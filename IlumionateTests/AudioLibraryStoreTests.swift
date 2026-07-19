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
        let suiteName = "AudioLibraryStoreResponsivenessTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

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

        await AudioLibraryStore.save(files, defaults: defaults)

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
            defaults: fixture.defaults,
            documentsURL: fixture.documentsURL
        )

        #expect(files.count == 1)
        #expect(files.first?.filename == "Dropped Session.mp3")
        #expect(files.first?.contentFingerprint?.count == 64)
        #expect(AudioLibraryStore.load(defaults: fixture.defaults).count == 1)
    }

    @Test func doesNotDuplicateAlreadyRegisteredDocumentFiles() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let url = fixture.documentsURL.appending(path: "Existing.mp3")
        try Data("not real audio".utf8).write(to: url)

        let existing = AudioFile(filename: "Existing.mp3", duration: 12, fileSize: 99)
        await AudioLibraryStore.save([existing], defaults: fixture.defaults)

        let files = await AudioLibraryStore.loadRepairingStoredFiles(
            defaults: fixture.defaults,
            documentsURL: fixture.documentsURL
        )

        #expect(files.count == 1)
        #expect(files.first?.id == existing.id)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AudioLibraryStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let documentsURL = root.appending(path: "Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)

        let suiteName = "AudioLibraryStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        return Fixture(root: root, documentsURL: documentsURL, defaults: defaults, suiteName: suiteName)
    }

    private struct Fixture {
        let root: URL
        let documentsURL: URL
        let defaults: UserDefaults
        let suiteName: String

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
