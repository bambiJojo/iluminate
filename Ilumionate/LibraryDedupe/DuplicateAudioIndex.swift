//
//  DuplicateAudioIndex.swift
//  Ilumionate
//
//  Answers one question: does the library already hold this audio?
//
//  A pure value over a library snapshot — no actor, no file access, no network.
//  Everything expensive (hashing, HEAD requests) happens in the caller, which
//  is what lets the cheap signals run before a download rather than after.
//

import Foundation

nonisolated struct DuplicateAudioIndex: Sendable {

    /// How far two durations may drift and still describe the same recording.
    /// Tighter for the size rule, because an exact byte-count match is already
    /// nearly conclusive and the duration only guards against coincidence.
    private static let sizeMatchDurationTolerance: TimeInterval = 1
    private static let titleMatchDurationTolerance: TimeInterval = 2

    private let entries: [Entry]

    init(_ files: [AudioFile]) {
        entries = files.map(Entry.init)
    }

    func verdict(for candidate: DuplicateAudioCandidate) -> DuplicateAudioVerdict {
        if let source = candidate.remoteSource,
           let match = best(where: { $0.file.remoteSource == source }) {
            return .identical(existing: match.file.id)
        }

        if let fingerprint = candidate.contentFingerprint?.lowercased(),
           !fingerprint.isEmpty,
           let match = best(where: { $0.fingerprint == fingerprint }) {
            return .identical(existing: match.file.id)
        }

        if let size = candidate.fileSize,
           size > 0,
           let match = best(where: {
               $0.file.fileSize == size
                   && abs($0.file.duration - candidate.duration) <= Self.sizeMatchDurationTolerance
           }) {
            return .likely(existing: match.file.id, reason: .sizeAndDuration)
        }

        let title = AudioTitleNormalizer.normalize(candidate.title)
        if !title.isEmpty,
           let match = best(where: {
               $0.title == title
                   && abs($0.file.duration - candidate.duration) <= Self.titleMatchDurationTolerance
           }) {
            return .likely(existing: match.file.id, reason: .titleAndDuration)
        }

        return .distinct
    }

    /// The richest entry satisfying `predicate`.
    ///
    /// The library can legitimately hold two rows for one recording — that is
    /// the state this feature cleans up — so a match must resolve the same way
    /// every time. Preferring the analyzed copy matches how
    /// `PlaylistTrackBinding.resolve` heals an orphaned playlist item, and
    /// keeps a rebind from landing on the copy with no light session.
    private func best(where predicate: (Entry) -> Bool) -> Entry? {
        entries
            .filter(predicate)
            .min { lhs, rhs in
                if lhs.file.isAnalyzed != rhs.file.isAnalyzed {
                    return lhs.file.isAnalyzed
                }
                if lhs.file.hasTranscription != rhs.file.hasTranscription {
                    return lhs.file.hasTranscription
                }
                return lhs.file.createdDate < rhs.file.createdDate
            }
    }

    /// Normalisation is done once per library entry rather than once per
    /// comparison — a playlist import queries this for every unmatched row.
    private struct Entry {
        let file: AudioFile
        let fingerprint: String?
        let title: String

        init(_ file: AudioFile) {
            self.file = file
            fingerprint = file.contentFingerprint?.lowercased()
            title = AudioTitleNormalizer.normalize(file.filename)
        }
    }
}
