//  ImportedTranceScriptStoreTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct ImportedTranceScriptStoreTests {

    @Test func savePersistsImportedScriptAcrossStoreReloads() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ImportedTranceScriptStore(directoryURL: directory)
        try store.save(script(id: "imported-one", title: "Imported One"))

        let reloaded = ImportedTranceScriptStore(directoryURL: directory)
        #expect(reloaded.importedScripts.map(\.id) == ["imported-one"])
        #expect(reloaded.importedScripts.first?.title == "Imported One")
    }

    @Test func savingSameImportedSourceReplacesPreviousCopy() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ImportedTranceScriptStore(directoryURL: directory)
        try store.save(script(id: "first-copy", title: "First Copy", generator: "https://example.com/script"))
        try store.save(script(id: "second-copy", title: "Second Copy", generator: "https://example.com/script"))

        #expect(store.importedScripts.map(\.id) == ["second-copy"])
        #expect(store.importedScripts.first?.title == "Second Copy")
    }

    @Test func failedSaveDoesNotChangeInMemoryScripts() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockedDirectory = directory.appending(path: "not-a-directory")
        try Data("occupied".utf8).write(to: blockedDirectory)
        let store = ImportedTranceScriptStore(directoryURL: blockedDirectory)

        do {
            try store.save(script(id: "failed-import", title: "Failed Import"))
            Issue.record("Expected persistence to fail when the storage directory is a file")
        } catch {
            #expect(store.importedScripts.isEmpty)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "imported-script-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func script(id: String,
                        title: String,
                        generator: String = "https://example.com/imported") -> TranceScript {
        TranceScript(
            schemaVersion: 1,
            id: id,
            title: title,
            theme: .relaxation,
            supportedArcs: [.fullText],
            language: "en",
            source: ScriptSource(kind: .importedWeb, generator: generator, reviewed: false),
            segments: [
                TranceScriptSegment(
                    phase: .induction,
                    text: "Settle your gaze and breathe slowly.",
                    pacing: SegmentPacing(baseWPM: 120),
                    arcs: nil,
                    triggersHandoff: nil
                )
            ]
        )
    }
}
