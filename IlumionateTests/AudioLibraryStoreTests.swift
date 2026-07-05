//
//  AudioLibraryStoreTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct AudioLibraryStoreTests {

    @Test func registersSupportedFilesDiscoveredInDocuments() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        try Data("not real audio".utf8).write(to: fixture.documentsURL.appending(path: "Dropped Session.mp3"))
        try Data("ignored".utf8).write(to: fixture.documentsURL.appending(path: "notes.txt"))

        let files = AudioLibraryStore.loadRepairingStoredFiles(
            defaults: fixture.defaults,
            documentsURL: fixture.documentsURL
        )

        #expect(files.count == 1)
        #expect(files.first?.filename == "Dropped Session.mp3")
        #expect(AudioLibraryStore.load(defaults: fixture.defaults).count == 1)
    }

    @Test func doesNotDuplicateAlreadyRegisteredDocumentFiles() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let url = fixture.documentsURL.appending(path: "Existing.mp3")
        try Data("not real audio".utf8).write(to: url)

        let existing = AudioFile(filename: "Existing.mp3", duration: 12, fileSize: 99)
        AudioLibraryStore.save([existing], defaults: fixture.defaults)

        let files = AudioLibraryStore.loadRepairingStoredFiles(
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
