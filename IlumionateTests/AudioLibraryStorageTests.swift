//
//  AudioLibraryStorageTests.swift
//  IlumionateTests
//
//  The library outgrew `UserDefaults`. iOS caps a single value at 4 MiB and
//  rejects anything larger, and `UserDefaults.set` cannot report that — so a
//  97-file library on device was silently dropping every write. These pin the
//  file-backed store and the one-time migration onto it. See ERRORS.md ERR-005.
//

import Foundation
import Testing
@testable import Ilumionate

struct AudioLibraryStorageTests {

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AudioLibraryStorageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Big enough to be rejected outright by `UserDefaults`.
    private func oversizedLibrary() -> [AudioFile] {
        let transcript = String(repeating: "relax and breathe ", count: 3_000)
        return (0..<100).map { index in
            var file = AudioFile(
                filename: "Session \(index).mp3",
                duration: 1_800,
                fileSize: 40_000_000
            )
            file.transcription = transcript
            return file
        }
    }

    @Test("A library past the UserDefaults ceiling round-trips intact")
    func oversizedLibraryRoundTrips() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = AudioLibraryStorage(
            fileURL: root.appending(path: "library.json"),
            legacyDefaults: nil
        )
        let files = oversizedLibrary()

        // The test is only meaningful if this really is over the limit.
        let encodedSize = try JSONEncoder().encode(files).count
        #expect(
            encodedSize > 4 * 1024 * 1024,
            "Fixture is only \(encodedSize) bytes — it no longer exercises the ceiling"
        )

        let didSave = await AudioLibraryStore.save(files, storage: storage)
        #expect(didSave)

        let loaded = AudioLibraryStore.load(storage: storage)
        #expect(loaded.count == 100)
        #expect(loaded.first?.transcription?.isEmpty == false)
    }

    @Test("A library stored in UserDefaults migrates to the file on first load")
    func migratesLegacyLibrary() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "AudioLibraryStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let original = [AudioFile(filename: "Legacy.mp3", duration: 60, fileSize: 10)]
        defaults.set(
            try JSONEncoder().encode(original),
            forKey: AnalysisStateManager.audioFilesUserDefaultsKey
        )

        let fileURL = root.appending(path: "library.json")
        let storage = AudioLibraryStorage(fileURL: fileURL, legacyDefaults: defaults)

        let loaded = AudioLibraryStore.load(storage: storage)

        #expect(loaded.count == 1)
        #expect(loaded.first?.id == original[0].id)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        // The key is cleared only once the file is safely on disk, so the 4 MiB
        // ceiling can never be hit again for this library.
        #expect(defaults.data(forKey: AnalysisStateManager.audioFilesUserDefaultsKey) == nil)
    }

    // Clearing the key before the file is known to be written would destroy the
    // library outright. The old copy has to survive a failed migration.
    @Test("A failed migration leaves the UserDefaults copy in place")
    func failedMigrationKeepsLegacyCopy() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "AudioLibraryStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let original = [AudioFile(filename: "Legacy.mp3", duration: 60, fileSize: 10)]
        let encoded = try JSONEncoder().encode(original)
        defaults.set(encoded, forKey: AnalysisStateManager.audioFilesUserDefaultsKey)

        // A regular file where the store wants a directory: creating the
        // enclosing folder fails, so the write cannot succeed.
        let blocker = root.appending(path: "blocked")
        try Data("not a directory".utf8).write(to: blocker)
        let storage = AudioLibraryStorage(
            fileURL: blocker.appending(path: "library.json"),
            legacyDefaults: defaults
        )

        let loaded = AudioLibraryStore.load(storage: storage)

        #expect(loaded.count == 1, "The legacy copy should still be readable")
        #expect(defaults.data(forKey: AnalysisStateManager.audioFilesUserDefaultsKey) == encoded)
    }

    @Test("Migration runs once and does not reread UserDefaults afterwards")
    func migrationIsOneWay() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "AudioLibraryStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            try JSONEncoder().encode([AudioFile(filename: "Legacy.mp3", duration: 60, fileSize: 10)]),
            forKey: AnalysisStateManager.audioFilesUserDefaultsKey
        )

        let storage = AudioLibraryStorage(
            fileURL: root.appending(path: "library.json"),
            legacyDefaults: defaults
        )
        _ = AudioLibraryStore.load(storage: storage)

        // Something writes the old key again — a stale build, or a code path not
        // yet migrated. The file remains the source of truth.
        defaults.set(
            try JSONEncoder().encode([
                AudioFile(filename: "Stale A.mp3", duration: 1, fileSize: 1),
                AudioFile(filename: "Stale B.mp3", duration: 1, fileSize: 1)
            ]),
            forKey: AnalysisStateManager.audioFilesUserDefaultsKey
        )

        let reloaded = AudioLibraryStore.load(storage: storage)
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.filename == "Legacy.mp3")
    }

    @Test("An unwritable destination reports failure rather than claiming success")
    func unwritableSaveReportsFailure() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let blocker = root.appending(path: "blocked")
        try Data("not a directory".utf8).write(to: blocker)

        let storage = AudioLibraryStorage(
            fileURL: blocker.appending(path: "library.json"),
            legacyDefaults: nil
        )

        let didSave = await AudioLibraryStore.save(
            [AudioFile(filename: "A.mp3", duration: 1, fileSize: 1)],
            storage: storage
        )

        #expect(didSave == false)
    }

    @Test("An empty store loads as an empty library, not a failure")
    func missingFileLoadsEmpty() {
        let storage = AudioLibraryStorage(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: "does-not-exist-\(UUID().uuidString).json"),
            legacyDefaults: nil
        )

        #expect(AudioLibraryStore.load(storage: storage).isEmpty)
    }
}
