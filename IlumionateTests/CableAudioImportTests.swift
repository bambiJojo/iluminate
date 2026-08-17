//
//  CableAudioImportTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct CableAudioImportTests {
    @Test("A stable audio drop is admitted to private storage and the library")
    func importsStableAudioDrop() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.inboxURL.appending(path: "Session.mp3")
        try Data([0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
            .write(to: sourceURL)

        let service = CableAudioImportService(
            inboxURL: fixture.inboxURL,
            managedAudioURL: fixture.managedAudioURL,
            libraryStorage: fixture.libraryStorage,
            stabilityDelay: .zero,
            wait: { _ in }
        )

        let result = await service.importAvailableFiles()

        let imported = try #require(result.imported.first)
        #expect(result.imported.count == 1)
        #expect(result.failures.isEmpty)
        #expect(imported.storageLocation == .managed)
        #expect(FileManager.default.fileExists(
            atPath: fixture.managedAudioURL.appending(path: imported.filename).path
        ))
        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)

        let stored = AudioLibraryStore.load(storage: fixture.libraryStorage)
        #expect(stored.map(\.id) == [imported.id])
    }
}

private struct CableImportFixture {
    let rootURL: URL
    let inboxURL: URL
    let managedAudioURL: URL
    let libraryStorage: AudioLibraryStorage

    init() throws {
        rootURL = URL.temporaryDirectory.appending(
            path: "CableAudioImportTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        inboxURL = rootURL.appending(path: "Incoming Audio", directoryHint: .isDirectory)
        managedAudioURL = rootURL.appending(path: "Managed Audio", directoryHint: .isDirectory)
        libraryStorage = AudioLibraryStorage(
            fileURL: rootURL.appending(path: "library.json"),
            legacyDefaults: nil
        )

        try FileManager.default.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: managedAudioURL,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
