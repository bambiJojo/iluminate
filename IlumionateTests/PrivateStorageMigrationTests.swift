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

    private func makeRoot() throws -> URL {
        let root = URL.temporaryDirectory.appending(
            path: "PrivateStorageMigrationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
