//
//  PlaylistPlayerControllerLibraryTests.swift
//  IlumionateTests
//
//  `PlaylistPlayerController` resolves every playlist item against the audio
//  library. When the library moved out of `UserDefaults` into a file the
//  controller kept reading the old key, which by then had been cleared by the
//  migration — so the lookup was empty, every item failed to resolve, and
//  `loadAndPlayItem` walked the whole playlist to its last index and stopped.
//  The user saw a playlist jump straight to the end reading 0:00 / 0:00.
//
//  See ERRORS.md ERR-011.
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct PlaylistPlayerControllerLibraryTests {

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(
                path: "PlaylistPlayerControllerLibraryTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeLibraryFile() -> AudioFile {
        AudioFile(filename: "Deep Induction.m4a", duration: 600, fileSize: 8_000_000)
    }

    private func makePlaylist(referencing file: AudioFile) -> (Playlist, PlaylistItem) {
        let item = PlaylistItem(
            audioFileId: file.id,
            filename: file.filename,
            duration: file.duration
        )
        return (Playlist(name: "Evening", items: [item]), item)
    }

    @Test("Playlist items resolve against the file-backed library")
    func resolvesItemsFromTheLibraryFile() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = AudioLibraryStorage(
            fileURL: root.appending(path: "library.json"),
            legacyDefaults: nil
        )
        let file = makeLibraryFile()
        #expect(await AudioLibraryStore.save([file], storage: storage))

        let (playlist, item) = makePlaylist(referencing: file)
        let controller = PlaylistPlayerController(
            playlist: playlist,
            engine: LightEngine(),
            storage: storage
        )
        await controller.loadAudioLibrary()

        #expect(controller.audioFile(for: item)?.id == file.id)
    }

    /// The exact upgrade path that broke: the library still sits in
    /// `UserDefaults` from an older build, and loading it migrates it to a file
    /// and clears the old key. A controller reading that key directly finds
    /// nothing.
    @Test("A library still in UserDefaults resolves through the migration")
    func resolvesItemsMigratedOutOfUserDefaults() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "PlaylistPlayerControllerLibraryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let file = makeLibraryFile()
        defaults.set(
            try JSONEncoder().encode([file]),
            forKey: AnalysisStateManager.audioFilesUserDefaultsKey
        )

        let storage = AudioLibraryStorage(
            fileURL: root.appending(path: "library.json"),
            legacyDefaults: defaults
        )

        let (playlist, item) = makePlaylist(referencing: file)
        let controller = PlaylistPlayerController(
            playlist: playlist,
            engine: LightEngine(),
            storage: storage
        )
        await controller.loadAudioLibrary()

        #expect(controller.audioFile(for: item)?.id == file.id)
        #expect(
            defaults.data(forKey: AnalysisStateManager.audioFilesUserDefaultsKey) == nil,
            "The migration should have cleared the legacy key"
        )
    }

    @Test("A playlist referencing audio the library no longer holds resolves to nil")
    func missingLibraryEntryResolvesToNil() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = AudioLibraryStorage(
            fileURL: root.appending(path: "library.json"),
            legacyDefaults: nil
        )
        #expect(await AudioLibraryStore.save([makeLibraryFile()], storage: storage))

        let (playlist, item) = makePlaylist(referencing: makeLibraryFile())
        let controller = PlaylistPlayerController(
            playlist: playlist,
            engine: LightEngine(),
            storage: storage
        )
        await controller.loadAudioLibrary()

        #expect(controller.audioFile(for: item) == nil)
    }

    @Test("A measured dead-time profile is written back to the library store")
    func persistsDeadTimeProfileToTheStore() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = AudioLibraryStorage(
            fileURL: root.appending(path: "library.json"),
            legacyDefaults: nil
        )
        let file = makeLibraryFile()
        #expect(await AudioLibraryStore.save([file], storage: storage))

        let profile = DeadTimeProfile(
            headDeadTime: 2.5,
            tailDeadTime: 11.0,
            headClassification: .silence,
            tailClassification: .binaural,
            analysisDate: Date()
        )
        #expect(
            await AudioLibraryStore.saveDeadTimeProfile(
                profile,
                audioFileID: file.id,
                storage: storage
            )
        )

        let reloaded = try #require(
            AudioLibraryStore.load(storage: storage).first { $0.id == file.id }
        )
        #expect(reloaded.deadTimeProfile?.tailDeadTime == 11.0)
        #expect(reloaded.deadTimeProfile?.headDeadTime == 2.5)
    }
}
