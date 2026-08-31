//
//  PlaylistImporter.swift
//  Ilumionate
//

import Foundation

/// Conservatively matches shared playlist entries to local audio.
///
/// A duration match can strengthen a title match but is never sufficient by
/// itself. Each local file is automatically selected at most once.
struct PlaylistImporter {
    func makePlan(
        for playlist: SourcePlaylist,
        availableAudioFiles: [AudioFile]
    ) -> PlaylistImportPlan {
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

            let status: PlaylistImportPlan.Row.Status
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

            return PlaylistImportPlan.Row(
                track: track,
                status: status,
                selectedAudioFileID: selectedID,
                suggestedAudioFileIDs: candidates.prefix(5).map(\.audioFile.id)
            )
        }

        return PlaylistImportPlan(
            sourcePlaylist: playlist,
            availableAudioFiles: availableAudioFiles,
            rows: rows
        )
    }

    func rankedAudioFiles(
        for track: SourcePlaylistTrack,
        availableAudioFiles: [AudioFile]
    ) -> [AudioFile] {
        rankedCandidates(
            for: track,
            availableAudioFiles: availableAudioFiles
        )
        .map(\.audioFile)
    }

    private func rankedCandidates(
        for track: SourcePlaylistTrack,
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
        track: SourcePlaylistTrack,
        audioFile: AudioFile
    ) -> Double {
        let remoteTitle = AudioTitleNormalizer.normalize(track.title)
        guard remoteTitle.count >= 4 else { return 0 }
        guard !hasTrackNumberConflict(track: track, audioFile: audioFile) else { return 0 }

        // The publisher names the track twice: once for people, once in the URL
        // it serves the audio from. A file fetched from that URL carries the
        // second name, which is often nothing like the first — an abbreviated
        // slug the title's own words cannot be recovered from. Both are scored,
        // and the better one wins.
        let remoteTitles = [
            remoteTitle,
            track.audioURL.map { AudioTitleNormalizer.normalize($0.lastPathComponent) }
        ]
        .compactMap { $0 }
        .filter { $0.count >= 4 }

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

        let normalizedLocalTitles = localTitles
            .compactMap { $0 }
            .map(AudioTitleNormalizer.normalize)

        let titleScore = remoteTitles
            .flatMap { remote in
                normalizedLocalTitles.map { titleSimilarity(remote: remote, local: $0) }
            }
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

    /// True when both *names* open with a track position and they disagree.
    ///
    /// A numbered series is otherwise near-indistinguishable: every entry
    /// shares the same words, so title similarity alone ranks the wrong file
    /// as highly as the right one, and `automaticallyUsedIDs` then pushes the
    /// loser to `.missing` — where it gets downloaded as a duplicate.
    ///
    /// Only leading digits on both sides are compared. `track.trackNumber` is
    /// deliberately not consulted: sources disagree about whether the first
    /// track is 0 or 1, and treating a zero-based position as the printed
    /// number made every `01 …` file conflict with the track it belongs to,
    /// rejecting an entire numbered library at once.
    private func hasTrackNumberConflict(
        track: SourcePlaylistTrack,
        audioFile: AudioFile
    ) -> Bool {
        let localNumber = AudioTitleNormalizer.leadingTrackNumber(audioFile.filename)
            ?? AudioTitleNormalizer.leadingTrackNumber(audioFile.displayName)
        guard let localNumber,
              let remoteNumber = AudioTitleNormalizer.leadingTrackNumber(track.title) else {
            return false
        }

        return localNumber != remoteNumber
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
            return 0.94
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

    private struct Candidate {
        let audioFile: AudioFile
        let score: Double
    }
}
