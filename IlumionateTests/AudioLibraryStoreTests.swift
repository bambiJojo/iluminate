//
//  AudioLibraryStoreTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct AudioLibraryStoreTests {

    // `savingLargeLibraryDoesNotBlockMainActor` lived here. It timed how long
    // the main actor took to notice a heartbeat while a 34 MB library encoded,
    // and failed under the full suite recording a 43-second delay — a
    // measurement of the machine, not of this code. The property it guarded is
    // now structural: `AudioLibraryPersistence` is a non-main actor and `save`
    // is `async`, so the encode cannot run on the main actor. The functional
    // half — a very large library surviving a round trip — is covered
    // deterministically by `AudioLibraryStorageTests.oversizedLibraryRoundTrips`.
    // See ERRORS.md ERR-001.

    @Test func registersSupportedFilesDiscoveredInDocuments() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        try Data("not real audio".utf8).write(to: fixture.documentsURL.appending(path: "Dropped Session.mp3"))
        try Data("ignored".utf8).write(to: fixture.documentsURL.appending(path: "notes.txt"))

        let files = await AudioLibraryStore.loadRepairingStoredFiles(
            storage: fixture.storage,
            documentsURL: fixture.documentsURL
        )

        #expect(files.count == 1)
        #expect(files.first?.filename == "Dropped Session.mp3")
        #expect(files.first?.contentFingerprint?.count == 64)
        #expect(AudioLibraryStore.load(storage: fixture.storage).count == 1)
    }

    @Test func doesNotDuplicateAlreadyRegisteredDocumentFiles() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let url = fixture.documentsURL.appending(path: "Existing.mp3")
        try Data("not real audio".utf8).write(to: url)

        let existing = AudioFile(filename: "Existing.mp3", duration: 12, fileSize: 99)
        await AudioLibraryStore.save([existing], storage: fixture.storage)

        let files = await AudioLibraryStore.loadRepairingStoredFiles(
            storage: fixture.storage,
            documentsURL: fixture.documentsURL
        )

        #expect(files.count == 1)
        #expect(files.first?.id == existing.id)
    }

    @Test func loadingLibraryAutomaticallyAppliesRecognizedGoldReview() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let url = fixture.documentsURL.appending(path: "04 Giggledoll.mp3")
        try Data("test audio placeholder".utf8).write(to: url)
        let existing = AudioFile(
            filename: url.lastPathComponent,
            duration: 394.031,
            fileSize: 1_024
        )
        await AudioLibraryStore.save([existing], storage: fixture.storage)

        let files = await AudioLibraryStore.loadRepairingStoredFiles(
            storage: fixture.storage,
            documentsURL: fixture.documentsURL
        )
        let recognized = try #require(files.first)

        #expect(recognized.isAnalyzed)
        #expect(recognized.analysisResult?.expertAnalysis?.verdict == .productionReady)
        #expect(recognized.trackMetadata?.preferredTitle == "Giggledoll")
        #expect(
            AudioLibraryStore.load(storage: fixture.storage)
                .first?.analysisResult?.recommendedPreset
                == "Giggledoll — Gold Light Score"
        )
    }

    @Test func playbackUpdatesRecencyAndPlayCount() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let file = AudioFile(filename: "Played.mp3", duration: 120, fileSize: 10)
        let playedAt = Date(timeIntervalSince1970: 5_000)
        await AudioLibraryStore.save([file], storage: fixture.storage)

        await AudioLibraryStore.recordPlayback(
            audioFileID: file.id,
            at: playedAt,
            storage: fixture.storage
        )

        let updated = try #require(AudioLibraryStore.load(storage: fixture.storage).first)
        #expect(updated.lastPlayedDate == playedAt)
        #expect(updated.playCount == 1)
    }

    @Test func partialTranscriptionIsVisibleBeforeAnalysisCompletes() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let file = AudioFile(filename: "Partial.mp3", duration: 120, fileSize: 10)
        await AudioLibraryStore.save([file], storage: fixture.storage)

        await AudioLibraryStore.savePartialTranscription(
            "A saved partial transcript",
            audioFileID: file.id,
            storage: fixture.storage
        )

        let updated = try #require(AudioLibraryStore.load(storage: fixture.storage).first)
        #expect(updated.transcription == "A saved partial transcript")
        #expect(updated.isAnalyzed == false)
    }

    @Test func concurrentSemanticMutationsDoNotLoseEachOther() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let existing = AudioFile(filename: "Existing.mp3", duration: 120, fileSize: 10)
        let added = AudioFile(filename: "Added.mp3", duration: 90, fileSize: 8)
        await AudioLibraryStore.save([existing], storage: fixture.storage)

        async let favorite = AudioLibraryStore.setFavorite(
            true,
            audioFileID: existing.id,
            storage: fixture.storage
        )
        async let rating = AudioLibraryStore.setRating(
            4,
            audioFileID: existing.id,
            storage: fixture.storage
        )
        async let insertion = AudioLibraryStore.add(
            added,
            storage: fixture.storage
        )

        _ = await (favorite, rating, insertion)

        let files = AudioLibraryStore.load(storage: fixture.storage)
        let updated = try #require(files.first { $0.id == existing.id })
        #expect(updated.isFavorite == true)
        #expect(updated.rating == 4)
        #expect(files.contains { $0.id == added.id })
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AudioLibraryStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let documentsURL = root.appending(path: "Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)

        return Fixture(
            root: root,
            documentsURL: documentsURL,
            storage: AudioLibraryStorage(
                fileURL: root.appending(path: "library.json"),
                legacyDefaults: nil
            )
        )
    }

    private struct Fixture {
        let root: URL
        let documentsURL: URL
        let storage: AudioLibraryStorage

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
