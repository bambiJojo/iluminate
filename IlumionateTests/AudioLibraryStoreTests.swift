//
//  AudioLibraryStoreTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct AudioLibraryStoreTests {

    @Test @MainActor
    func savingLargeLibraryDoesNotBlockMainActor() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AudioLibraryStoreResponsiveness-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = AudioLibraryStorage(
            fileURL: root.appending(path: "library.json"),
            legacyDefaults: nil
        )

        let realisticTranscript = String(repeating: "relax and breathe ", count: 30_000)
        let files = (0..<64).map { index in
            var file = AudioFile(
                filename: "Session \(index).mp3",
                duration: 1_800,
                fileSize: 40_000_000
            )
            file.transcription = realisticTranscript
            return file
        }

        let clock = ContinuousClock()
        let startedAt = clock.now
        let heartbeat = Task.detached {
            try? await Task.sleep(for: .milliseconds(20))
            return await MainActor.run { clock.now }
        }

        await AudioLibraryStore.save(files, storage: storage)

        let heartbeatDelay = startedAt.duration(to: await heartbeat.value)
        #expect(
            heartbeatDelay < .milliseconds(150),
            "Post-import persistence blocked the main actor for \(heartbeatDelay)"
        )
    }

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
