//
//  BambiCloudPlaylistImporter.swift
//  Ilumionate
//

import Foundation

/// Conservatively matches shared playlist entries to local audio.
///
/// A duration match can strengthen a title match but is never sufficient by
/// itself. Each local file is automatically selected at most once.
struct BambiCloudPlaylistImporter {
    func makePlan(
        for playlist: BambiCloudPlaylist,
        availableAudioFiles: [AudioFile]
    ) -> BambiCloudPlaylistImportPlan {
        var automaticallyUsedIDs = Set<AudioFile.ID>()
        let rows = playlist.tracks.map { track in
            let candidates = rankedCandidates(
                for: track,
                availableAudioFiles: availableAudioFiles
            )
            let selectable = candidates.filter {
                !automaticallyUsedIDs.contains($0.audioFile.id)
            }
            let best = selectable.first
            let runnerUpScore = selectable.dropFirst().first?.score ?? 0
            let margin = (best?.score ?? 0) - runnerUpScore

            let status: BambiCloudPlaylistImportPlan.Row.Status
            let selectedID: AudioFile.ID?
            if let best, best.score >= 0.98, margin >= 0.04 {
                status = .exact
                selectedID = best.audioFile.id
            } else if let best, best.score >= 0.90, margin >= 0.08 {
                status = .probable
                selectedID = best.audioFile.id
            } else if let best, best.score >= 0.75 {
                status = .needsReview
                selectedID = nil
            } else {
                status = .missing
                selectedID = nil
            }

            if let selectedID {
                automaticallyUsedIDs.insert(selectedID)
            }

            return BambiCloudPlaylistImportPlan.Row(
                track: track,
                status: status,
                selectedAudioFileID: selectedID,
                suggestedAudioFileIDs: candidates.prefix(5).map(\.audioFile.id)
            )
        }

        return BambiCloudPlaylistImportPlan(
            sourcePlaylist: playlist,
            availableAudioFiles: availableAudioFiles,
            rows: rows
        )
    }

    func rankedAudioFiles(
        for track: BambiCloudPlaylist.Track,
        availableAudioFiles: [AudioFile]
    ) -> [AudioFile] {
        rankedCandidates(
            for: track,
            availableAudioFiles: availableAudioFiles
        )
        .map(\.audioFile)
    }

    private func rankedCandidates(
        for track: BambiCloudPlaylist.Track,
        availableAudioFiles: [AudioFile]
    ) -> [Candidate] {
        availableAudioFiles
            .compactMap { audioFile in
                let score = matchScore(track: track, audioFile: audioFile)
                guard score >= 0.55 else { return nil }
                return Candidate(audioFile: audioFile, score: score)
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.audioFile.displayName
                        .localizedStandardCompare($1.audioFile.displayName)
                        == .orderedAscending
                }
                return $0.score > $1.score
            }
    }

    private func matchScore(
        track: BambiCloudPlaylist.Track,
        audioFile: AudioFile
    ) -> Double {
        let remoteTitle = normalize(track.name)
        guard remoteTitle.count >= 4 else { return 0 }

        var localTitles = [
            audioFile.filename,
            audioFile.displayName,
            audioFile.userTitle,
            audioFile.trackMetadata?.embeddedTitle,
            audioFile.trackMetadata?.generatedTitle
        ]
        if let catalogTitle = KnownAudioCatalog.shared
            .match(audioFile: audioFile)?
            .entry.title {
            localTitles.append(catalogTitle)
        }

        let titleScore = localTitles
            .compactMap { $0 }
            .map(normalize)
            .map { titleSimilarity(remote: remoteTitle, local: $0) }
            .max() ?? 0
        guard titleScore >= 0.55 else { return 0 }

        let allowedDifference = max(3, track.duration * 0.01)
        let durationDifference = abs(track.duration - audioFile.duration)
        let durationBonus: Double
        if durationDifference <= allowedDifference {
            durationBonus = 0.06
        } else if durationDifference <= max(10, track.duration * 0.03) {
            durationBonus = 0.03
        } else {
            durationBonus = 0
        }

        return min(titleScore + durationBonus, 1)
    }

    /// Scores how much of the remote title survives in a local name.
    ///
    /// Coverage is measured against the remote title alone: library files are
    /// routinely saved with a series prefix or a trailing tag, and those extra
    /// words say nothing about whether the title matched. Requiring both sides
    /// to share three tokens used to reject every two-word title outright,
    /// which is most of a typical release.
    private func titleSimilarity(remote: String, local: String) -> Double {
        guard !remote.isEmpty, !local.isEmpty else { return 0 }
        if remote == local {
            return 0.94
        }

        let remoteTokens = Set(remote.split(separator: " ").map(String.init))
        let localTokens = Set(local.split(separator: " ").map(String.init))
        // A lone word is too weak to identify a track by anything but equality.
        guard remoteTokens.count >= 2 else { return 0 }

        // The whole remote title appearing inside a longer local name is the
        // prefix/suffix case, and is nearly as strong as an exact match.
        if remoteTokens.isSubset(of: localTokens) {
            return 0.90
        }

        let commonCount = remoteTokens.intersection(localTokens).count
        let coverage = Double(commonCount) / Double(remoteTokens.count)
        if coverage >= 0.8 {
            return 0.78
        }
        if coverage >= 0.65 {
            return 0.68
        }
        return 0
    }

    private func normalize(_ value: String) -> String {
        let filename = URL(filePath: value)
            .deletingPathExtension()
            .lastPathComponent
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        var tokens = filename
            .replacing(
                /[^a-z0-9]+/,
                with: " "
            )
            .split(separator: " ")
            .map(String.init)

        if let first = tokens.first,
           first.allSatisfy(\.isNumber),
           first.count <= 3 {
            tokens.removeFirst()
        }

        let disposableSuffixes: Set<String> = [
            "audio", "final", "hq", "official", "remastered",
            "mp3", "m4a", "wav", "aac", "flac", "v2", "320kbps"
        ]
        while let last = tokens.last, disposableSuffixes.contains(last) {
            tokens.removeLast()
        }

        return tokens.joined(separator: " ")
    }

    private struct Candidate {
        let audioFile: AudioFile
        let score: Double
    }
}
