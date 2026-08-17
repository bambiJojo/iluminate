//
//  DuplicateAudioGroup.swift
//  Ilumionate
//
//  Library entries holding the same audio, and the policy for collapsing them.
//
//  Grouping is fingerprint-only on purpose. The circumstantial signals the
//  index uses at import time are appropriate when a human is about to confirm
//  them; a bulk cleanup that merges on "same size and duration" would fold two
//  genuinely different recordings together and lose one of them.
//

import Foundation

nonisolated struct DuplicateAudioGroup: Identifiable, Sendable {
    let id: UUID
    /// The entry that survives, carrying the merged history.
    let keeper: AudioFile
    /// Entries whose files are removed once their history is folded in.
    let redundant: [AudioFile]

    init(id: UUID = UUID(), keeper: AudioFile, redundant: [AudioFile]) {
        self.id = id
        self.keeper = keeper
        self.redundant = redundant
    }

    /// Groups of two or more entries sharing a content fingerprint.
    static func groups(in files: [AudioFile]) -> [DuplicateAudioGroup] {
        let byFingerprint = Dictionary(grouping: files) { file in
            file.contentFingerprint?.lowercased()
        }

        return byFingerprint
            .compactMap { fingerprint, matches -> DuplicateAudioGroup? in
                // A file whose bytes could not be read has no identity to
                // group by, and must not be pooled with every other such file.
                guard fingerprint != nil, matches.count > 1 else { return nil }

                let ranked = matches.sorted(by: isRicher)
                guard let keeper = ranked.first else { return nil }
                return DuplicateAudioGroup(
                    keeper: keeper,
                    redundant: Array(ranked.dropFirst())
                )
            }
            .sorted {
                $0.keeper.displayName.localizedStandardCompare($1.keeper.displayName)
                    == .orderedAscending
            }
    }

    /// Redundant identifier → keeper identifier, across every group.
    static func remap(for groups: [DuplicateAudioGroup]) -> [AudioFile.ID: AudioFile.ID] {
        groups.reduce(into: [:]) { remap, group in
            for file in group.redundant {
                remap[file.id] = group.keeper.id
            }
        }
    }

    /// The keeper with every redundant copy's history folded in.
    ///
    /// The keeper's own values always win — it was chosen for being the richest
    /// entry, and a merge must not downgrade it. Only fields it lacks are
    /// filled, except for the counters, which accumulate.
    func merged() -> AudioFile {
        var result = keeper

        for other in redundant {
            result.analysisResult = result.analysisResult ?? other.analysisResult
            result.transcription = result.transcription ?? other.transcription
            result.deadTimeProfile = result.deadTimeProfile ?? other.deadTimeProfile
            result.trackMetadata = result.trackMetadata ?? other.trackMetadata
            result.userTitle = result.userTitle ?? other.userTitle
            result.creator = result.creator ?? other.creator
            result.rating = result.rating ?? other.rating
            result.detailedRating = result.detailedRating ?? other.detailedRating
            result.tags = result.tags ?? other.tags
            result.sessionNotes = result.sessionNotes ?? other.sessionNotes
            result.remoteSource = result.remoteSource ?? other.remoteSource
            result.contentFingerprint = result.contentFingerprint ?? other.contentFingerprint

            result.playCount = (result.playCount ?? 0) + (other.playCount ?? 0)
            result.isFavorite = (result.isFavorite ?? false) || (other.isFavorite ?? false)
            if let otherPlayed = other.lastPlayedDate {
                result.lastPlayedDate = max(result.lastPlayedDate ?? otherPlayed, otherPlayed)
            }
        }

        return result
    }

    /// Analysis first, then a transcript, then listening history, then age.
    private static func isRicher(_ lhs: AudioFile, _ rhs: AudioFile) -> Bool {
        if lhs.isAnalyzed != rhs.isAnalyzed { return lhs.isAnalyzed }
        if lhs.hasTranscription != rhs.hasTranscription { return lhs.hasTranscription }
        if (lhs.playCount ?? 0) != (rhs.playCount ?? 0) {
            return (lhs.playCount ?? 0) > (rhs.playCount ?? 0)
        }
        return lhs.createdDate < rhs.createdDate
    }
}
