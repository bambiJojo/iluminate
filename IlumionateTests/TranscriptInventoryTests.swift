//
//  TranscriptInventoryTests.swift
//  IlumionateTests
//
//  Transcribing a corpus is a long unattended job, so the parts that decide
//  *what* to do are separated from the part that does it. Those decisions —
//  which files still need a transcript, and what order to show them in — are
//  worth testing; driving WhisperKit is not.
//

import Testing
import Foundation
import CorpusKit
@testable import Ilumionate

private func file(_ name: String, sha: String) -> LabeledFile {
    LabeledFile(
        originalFilename: name,
        storedAudioFilename: name,
        audioDuration: 600,
        audioSHA256: sha,
        expectedContentType: .hypnosis,
        expectedFrequencyBand: .init(lower: 0.5, upper: 10),
        phases: [],
        techniques: [],
        labeledAt: Date(timeIntervalSince1970: 0),
        labelerNotes: ""
    )
}

struct TranscriptInventoryTests {

    private func temporaryDirectory() -> URL {
        let url = URL.temporaryDirectory.appending(path: "TranscriptInventory-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A cached transcript is found by its audio hash")
    func presenceIsDetectedByHash() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TranscriptInventory.cacheDirectory(in: directory)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: cache.appending(path: "abc.json"))

        let available = TranscriptInventory.availableHashes(in: directory)

        #expect(available == ["abc"])
    }

    @Test("A corpus with no cache directory reports none rather than failing")
    func missingCacheIsEmpty() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(TranscriptInventory.availableHashes(in: directory).isEmpty)
    }

    /// The point of the feature: leave it running and it works through the gap.
    @Test("Only files without a transcript are queued")
    func pendingSkipsWhatIsCached() {
        let files = [
            file("a.mp3", sha: "aaa"),
            file("b.mp3", sha: "bbb"),
            file("c.mp3", sha: "ccc")
        ]

        let pending = TranscriptInventory.pending(files, transcribed: ["bbb"])

        #expect(pending.map(\.audioFilename) == ["a.mp3", "c.mp3"])
    }

    /// Two corpus entries can point at the same audio. Transcribing it twice
    /// would waste the slowest step in the job.
    @Test("A hash appearing twice is queued once")
    func duplicateHashesAreQueuedOnce() {
        let files = [
            file("original.mp3", sha: "same"),
            file("copy.mp3", sha: "same")
        ]

        #expect(TranscriptInventory.pending(files, transcribed: []).count == 1)
    }

    @Test("A file with no hash cannot be located and is skipped")
    func filesWithoutHashesAreSkipped() {
        #expect(TranscriptInventory.pending([file("x.mp3", sha: "")], transcribed: []).isEmpty)
    }

    @Test("Sorting by name is alphabetical and case-insensitive")
    func nameOrderIsAlphabetical() {
        let files = [file("beta.mp3", sha: "b"), file("Alpha.mp3", sha: "a")]

        let sorted = TranscriptInventory.sorted(files, by: .name, transcribed: [])

        #expect(sorted.map(\.audioFilename) == ["Alpha.mp3", "beta.mp3"])
    }

    @Test("Transcribed files can be brought to the top")
    func transcribedFirstGroupsThem() {
        let files = [
            file("a.mp3", sha: "aaa"),
            file("b.mp3", sha: "bbb"),
            file("c.mp3", sha: "ccc")
        ]

        let sorted = TranscriptInventory.sorted(files, by: .transcribedFirst, transcribed: ["bbb"])

        #expect(sorted.first?.audioFilename == "b.mp3")
    }

    /// The order that matters while labelling: the files that are ready to work
    /// on last, so the ones still waiting are visible.
    @Test("Untranscribed files can be brought to the top")
    func untranscribedFirstGroupsThem() {
        let files = [
            file("a.mp3", sha: "aaa"),
            file("b.mp3", sha: "bbb")
        ]

        let sorted = TranscriptInventory.sorted(files, by: .untranscribedFirst, transcribed: ["aaa"])

        #expect(sorted.first?.audioFilename == "b.mp3")
    }

    @Test("Ties inside a group stay alphabetical")
    func groupsAreStableByName() {
        let files = [
            file("zeta.mp3", sha: "z"),
            file("alpha.mp3", sha: "a"),
            file("mid.mp3", sha: "m")
        ]

        let sorted = TranscriptInventory.sorted(files, by: .transcribedFirst, transcribed: ["z", "a"])

        #expect(sorted.map(\.audioFilename) == ["alpha.mp3", "zeta.mp3", "mid.mp3"])
    }

    @Test("Sorting an empty corpus yields an empty list")
    func emptyCorpusSortsToEmpty() {
        #expect(TranscriptInventory.sorted([], by: .name, transcribed: []).isEmpty)
    }
}
