//
//  PrivateStorageMigrationTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct PrivateStorageMigrationTests {
    @Test("A legacy implementation file moves out of Documents once")
    func migratesLegacyFile() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appending(path: "Documents/AnalysisCache.json")
        let destination = root.appending(path: "Application Support/Analysis/AnalysisCache.json")
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("checkpoint".utf8).write(to: legacy)

        let resolved = PrivateStorageMigration.migrateItemIfNeeded(
            from: legacy,
            to: destination
        )

        #expect(resolved == destination)
        #expect(try Data(contentsOf: destination) == Data("checkpoint".utf8))
        #expect(FileManager.default.fileExists(atPath: legacy.path) == false)
    }

    @Test("A failed migration keeps using the untouched legacy file")
    func migrationFailureFallsBackWithoutDataLoss() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appending(path: "AnalysisProgress.json")
        try Data("progress".utf8).write(to: legacy)
        let blocker = root.appending(path: "blocker")
        try Data("not a directory".utf8).write(to: blocker)
        let destination = blocker.appending(path: "AnalysisProgress.json")

        let resolved = PrivateStorageMigration.migrateItemIfNeeded(
            from: legacy,
            to: destination
        )

        #expect(resolved == legacy)
        #expect(try Data(contentsOf: legacy) == Data("progress".utf8))
    }

    /// The whole point of this migration is that the legacy copy stops being
    /// readable over file sharing. Returning the destination while leaving the
    /// legacy item sitting in Documents defeats that — and it is reachable, since
    /// a directory can be recreated after a previous migration ran.
    /// See ERRORS.md ERR-024.
    @Test("A legacy item is not left in Documents when the destination already exists")
    func clearsLegacyItemWhenDestinationAlreadyExists() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyURL = root.appending(path: "Documents/Guardrail Feedback", directoryHint: .isDirectory)
        let destinationURL = root.appending(path: "Support/Guardrail Feedback", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: legacyURL.appending(path: "old.json"))
        try Data("current".utf8).write(to: destinationURL.appending(path: "new.json"))

        let resolved = PrivateStorageMigration.migrateItemIfNeeded(
            from: legacyURL,
            to: destinationURL
        )

        #expect(resolved == destinationURL)
        // Gone from Documents...
        #expect(FileManager.default.fileExists(atPath: legacyURL.path) == false)
        // ...but not destroyed, and the destination is untouched.
        #expect(FileManager.default.fileExists(atPath: destinationURL.appending(path: "new.json").path))

        let recovered = try FileManager.default.contentsOfDirectory(
            at: destinationURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        #expect(recovered.contains { $0.lastPathComponent.contains("Recovered") })
    }

    private func makeRoot() throws -> URL {
        let root = URL.temporaryDirectory.appending(
            path: "PrivateStorageMigrationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
