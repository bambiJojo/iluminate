//
//  CableFileImportTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct CableFileImportTests {
    @Test("A stable audio drop is admitted to private storage and the library")
    func importsStableAudioDrop() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.inboxURL.appending(path: "Session.mp3")
        try fixture.validMP3Data.write(to: sourceURL)

        let result = await fixture.makeService().importAvailableFiles()

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

    @Test("A duplicate drop is kept in Needs Review instead of copied or deleted")
    func preservesDuplicateForReview() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.inboxURL.appending(path: "Session.mp3")
        try fixture.validMP3Data.write(to: sourceURL)
        let service = fixture.makeService()
        let first = await service.importAvailableFiles()
        let imported = try #require(first.imported.first)

        try fixture.validMP3Data.write(to: sourceURL)
        let second = await service.importAvailableFiles()

        #expect(second.imported.isEmpty)
        #expect(second.duplicates == ["Session.mp3"])
        #expect(AudioLibraryStore.load(storage: fixture.libraryStorage).count == 1)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
        #expect(FileManager.default.fileExists(
            atPath: fixture.inboxURL
                .appending(path: "_Needs Review/Duplicates/Session.mp3")
                .path
        ))
        #expect(FileManager.default.fileExists(
            atPath: fixture.managedAudioURL.appending(path: imported.filename).path
        ))
    }

    @Test("Invalid and unsupported drops are separated for Finder review")
    func preservesRejectedFilesByReason() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        try Data("<html>not audio</html>".utf8).write(
            to: fixture.inboxURL.appending(path: "Bad.mp3")
        )
        try Data("notes".utf8).write(
            to: fixture.inboxURL.appending(path: "Notes.txt")
        )

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.imported.isEmpty)
        #expect(result.rejected == ["Bad.mp3", "Notes.txt"])
        #expect(FileManager.default.fileExists(
            atPath: fixture.inboxURL
                .appending(path: "_Needs Review/Invalid Audio/Bad.mp3")
                .path
        ))
        #expect(FileManager.default.fileExists(
            atPath: fixture.inboxURL
                .appending(path: "_Needs Review/Unsupported Files/Notes.txt")
                .path
        ))
    }

    @Test("A file that changes during the stability window stays pending")
    func leavesInProgressTransferAlone() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.inboxURL.appending(path: "Still Copying.mp3")
        try fixture.validMP3Data.write(to: sourceURL)
        let service = fixture.makeService { _ in
            let handle = try FileHandle(forWritingTo: sourceURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data([0x01]))
            try handle.close()
        }

        let result = await service.importAvailableFiles()

        #expect(result.pending == ["Still Copying.mp3"])
        #expect(result.imported.isEmpty)
        #expect(AudioLibraryStore.load(storage: fixture.libraryStorage).isEmpty)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test("A library write failure rolls the moved audio back into the inbox")
    func rollsBackWhenLibraryCannotPersist() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.inboxURL.appending(path: "Keep Me.mp3")
        try fixture.validMP3Data.write(to: sourceURL)
        let blocker = fixture.rootURL.appending(path: "Not a Directory")
        try Data("blocker".utf8).write(to: blocker)
        let brokenStorage = AudioLibraryStorage(
            fileURL: blocker.appending(path: "library.json"),
            legacyDefaults: nil
        )
        let service = CableFileImportService(
            rootInboxURL: fixture.rootIntakeURL,
            dedicatedInboxURL: fixture.inboxURL,
            reviewURL: fixture.inboxURL.appending(
                path: "_Needs Review",
                directoryHint: .isDirectory
            ),
            managedAudioURL: fixture.managedAudioURL,
            libraryStorage: brokenStorage,
            stabilityDelay: .zero,
            minimumSettleAge: .zero,
            wait: { _ in }
        )

        let result = await service.importAvailableFiles()

        #expect(result.imported.isEmpty)
        #expect(result.failures.map(\.filename) == ["Keep Me.mp3"])
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(try FileManager.default.contentsOfDirectory(
            at: fixture.managedAudioURL,
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test("Identical files in one cable batch produce one library entry")
    func deduplicatesWithinOneBatch() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        try fixture.validMP3Data.write(
            to: fixture.inboxURL.appending(path: "A.mp3")
        )
        try fixture.validMP3Data.write(
            to: fixture.inboxURL.appending(path: "B.mp3")
        )

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.imported.map(\.filename) == ["A.mp3"])
        #expect(result.duplicates == ["B.mp3"])
        #expect(AudioLibraryStore.load(storage: fixture.libraryStorage).count == 1)
        #expect(FileManager.default.fileExists(
            atPath: fixture.inboxURL
                .appending(path: "_Needs Review/Duplicates/B.mp3")
                .path
        ))
    }
}

private struct CableImportFixture {
    let rootURL: URL
    /// A separate directory standing in for Documents root, kept apart from
    /// `rootURL` so fixture scaffolding is never treated as intake.
    let rootIntakeURL: URL
    let inboxURL: URL
    let textInboxURL: URL
    let importedURL: URL
    let managedAudioURL: URL
    let libraryStorage: AudioLibraryStorage

    let validMP3Data = Data([
        0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ])

    init() throws {
        rootURL = URL.temporaryDirectory.appending(
            path: "CableFileImportTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        rootIntakeURL = rootURL.appending(path: "Root Intake", directoryHint: .isDirectory)
        inboxURL = rootURL.appending(path: "Incoming Audio", directoryHint: .isDirectory)
        textInboxURL = rootURL.appending(path: "Incoming Text", directoryHint: .isDirectory)
        importedURL = rootIntakeURL.appending(path: "_Imported", directoryHint: .isDirectory)
        managedAudioURL = rootURL.appending(path: "Managed Audio", directoryHint: .isDirectory)
        libraryStorage = AudioLibraryStorage(
            fileURL: rootURL.appending(path: "library.json"),
            legacyDefaults: nil
        )

        try FileManager.default.createDirectory(
            at: rootIntakeURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: textInboxURL,
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

    func makeService(
        wait: @escaping CableImportWait = { _ in }
    ) -> CableFileImportService {
        CableFileImportService(
            rootInboxURL: rootIntakeURL,
            dedicatedInboxURL: inboxURL,
            textInboxURL: textInboxURL,
            reviewURL: inboxURL.appending(path: "_Needs Review", directoryHint: .isDirectory),
            importedURL: importedURL,
            managedAudioURL: managedAudioURL,
            libraryStorage: libraryStorage,
            stabilityDelay: .zero,
            minimumSettleAge: .zero,
            wait: wait
        )
    }
}
