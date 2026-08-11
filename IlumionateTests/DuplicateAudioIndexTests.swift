//
//  DuplicateAudioIndexTests.swift
//  IlumionateTests
//
//  The rules that decide whether the library already holds a file are pinned
//  here — including the negatives, which are what keep a false positive from
//  silently binding a playlist to the wrong audio.
//

import Foundation
import Testing
@testable import Ilumionate

struct DuplicateAudioIndexTests {

    private func makeFile(
        filename: String = "Deep Relaxation.mp3",
        duration: TimeInterval = 600,
        fileSize: Int64 = 5_000_000,
        fingerprint: String? = nil,
        remoteSource: RemoteAudioSource? = nil,
        transcribed: Bool = false
    ) -> AudioFile {
        var file = AudioFile(
            filename: filename,
            duration: duration,
            fileSize: fileSize,
            contentFingerprint: fingerprint,
            remoteSource: remoteSource
        )
        if transcribed {
            file.transcription = "seeded"
        }
        return file
    }

    private func bambiSource(_ trackID: String) -> RemoteAudioSource {
        RemoteAudioSource(
            service: RemoteAudioSource.bambiCloudService,
            trackID: trackID,
            url: URL(string: "https://cdn.bambicloud.com/\(trackID).mp3")!
        )
    }

    // MARK: - Identical

    @Test("Same publisher track is identical, with no bytes fetched")
    func samePublisherTrackIsIdentical() {
        let source = bambiSource("track-1")
        let existing = makeFile(remoteSource: source)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                remoteSource: source,
                duration: 600,
                title: "Something Else Entirely"
            )
        )

        #expect(verdict == .identical(existing: existing.id))
    }

    @Test("A different publisher with the same track id does not match")
    func differentServiceDoesNotMatch() {
        let existing = makeFile(remoteSource: bambiSource("track-1"))
        let index = DuplicateAudioIndex([existing])

        let other = RemoteAudioSource(
            service: "someotherservice",
            trackID: "track-1",
            url: URL(string: "https://example.com/a.mp3")!
        )
        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                remoteSource: other,
                duration: 90,
                title: "Unrelated"
            )
        )

        #expect(verdict == .distinct)
    }

    @Test("Same fingerprint is identical, case-insensitively")
    func sameFingerprintIsIdentical() {
        let existing = makeFile(fingerprint: "ABCDEF123456")
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                contentFingerprint: "abcdef123456",
                duration: 12,
                title: "Renamed Completely"
            )
        )

        #expect(verdict == .identical(existing: existing.id))
    }

    // MARK: - Likely

    @Test("Byte-identical size with matching duration is a likely duplicate")
    func sameSizeAndDurationIsLikely() {
        let existing = makeFile(duration: 600, fileSize: 5_000_000)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 5_000_000,
                duration: 600.4,
                title: "Totally Different Name"
            )
        )

        #expect(verdict == .likely(existing: existing.id, reason: .sizeAndDuration))
    }

    @Test("Same normalized title with matching duration is a likely duplicate")
    func sameTitleAndDurationIsLikely() {
        let existing = makeFile(filename: "Deep Relaxation.mp3", duration: 600)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 9_999,
                duration: 601.5,
                title: "deep_relaxation"
            )
        )

        #expect(verdict == .likely(existing: existing.id, reason: .titleAndDuration))
    }

    // MARK: - Negatives

    @Test("Equal duration alone is not a duplicate")
    func equalDurationAloneIsDistinct() {
        let existing = makeFile(filename: "Morning Calm.mp3", duration: 600, fileSize: 1)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 2,
                duration: 600,
                title: "Evening Descent"
            )
        )

        #expect(verdict == .distinct)
    }

    @Test("Equal title with a clearly different duration is not a duplicate")
    func equalTitleDifferentDurationIsDistinct() {
        let existing = makeFile(filename: "Deep Relaxation.mp3", duration: 600, fileSize: 1)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 2,
                duration: 1_800,
                title: "Deep Relaxation"
            )
        )

        #expect(verdict == .distinct)
    }

    @Test("Numbered series entries are not duplicates of each other")
    func numberedSeriesAreDistinct() {
        let existing = makeFile(filename: "01 Bambi Sleep.mp3", duration: 600, fileSize: 1)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 2,
                duration: 600,
                title: "02 Bambi Sleep"
            )
        )

        #expect(verdict == .distinct)
    }

    @Test("An unreadable file with no fingerprint degrades rather than matching")
    func missingFingerprintDoesNotMatch() {
        let existing = makeFile(filename: "A.mp3", fingerprint: nil)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                contentFingerprint: nil,
                fileSize: 1,
                duration: 3,
                title: "B"
            )
        )

        #expect(verdict == .distinct)
    }

    @Test("A zero file size never matches on size")
    func zeroSizeDoesNotMatchOnSize() {
        let existing = makeFile(filename: "A.mp3", duration: 600, fileSize: 0)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 0,
                duration: 600,
                title: "B"
            )
        )

        #expect(verdict == .distinct)
    }

    // MARK: - Determinism

    // Two stored entries can hold the same audio — that is the mess this
    // feature exists to clean up. Resolving to the richer copy matches how
    // `PlaylistTrackBinding` heals an orphaned playlist item.
    @Test("With two matches, the transcribed copy wins")
    func prefersTheRicherCopy() {
        let plain = makeFile(filename: "A.mp3", fingerprint: "aa", transcribed: false)
        let transcribed = makeFile(filename: "A (1).mp3", fingerprint: "aa", transcribed: true)
        let index = DuplicateAudioIndex([plain, transcribed])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(contentFingerprint: "aa", duration: 600, title: "A")
        )

        #expect(verdict == .identical(existing: transcribed.id))
    }

    // ERR-003: the Files-picker path cannot know the source duration before it
    // copies, and used to pass zero. That silently disabled both duration
    // signals while reading as though all four ran.
    @Test("An unknown duration skips the signals that need one")
    func unknownDurationSkipsDurationSignals() {
        let existing = makeFile(filename: "Deep Relaxation.mp3", duration: 600, fileSize: 5_000_000)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 5_000_000,
                duration: nil,
                title: "Deep Relaxation"
            )
        )

        #expect(verdict == .distinct)
    }

    @Test("An unknown duration still resolves an exact fingerprint match")
    func unknownDurationStillMatchesOnFingerprint() {
        let existing = makeFile(fingerprint: "abc123")
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                contentFingerprint: "abc123",
                fileSize: 1,
                duration: nil,
                title: "Anything At All"
            )
        )

        #expect(verdict == .identical(existing: existing.id))
    }
}
