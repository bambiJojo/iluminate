//  TranceScriptLibraryTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

struct TranceScriptLibraryTests {

    private let valid = Data(TranceScriptDecodingTests.sampleJSON.utf8)

    @Test func parseAcceptsValidScript() throws {
        let script = try TranceScriptLibrary.parse(valid)
        #expect(script.id == "deep-drift-01")
    }

    @Test func validateRejectsEmptySegments() {
        let script = TranceScript(
            schemaVersion: 1, id: "x", title: "X", theme: .focus,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [])
        #expect(throws: TranceScriptLibrary.LibraryError.self) {
            try TranceScriptLibrary.validate(script)
        }
    }

    @Test func validateRejectsUnknownSchemaVersion() {
        let script = TranceScript(
            schemaVersion: 99, id: "x", title: "X", theme: .focus,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [TranceScriptSegment(phase: .induction, text: "hi",
                pacing: nil, arcs: nil, triggersHandoff: nil)])
        #expect(throws: TranceScriptLibrary.LibraryError.self) {
            try TranceScriptLibrary.validate(script)
        }
    }

    @Test func validateRejectsNonPositiveWPMHint() {
        let script = TranceScript(
            schemaVersion: 1, id: "x", title: "X", theme: .focus,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [TranceScriptSegment(phase: .induction, text: "hi",
                pacing: SegmentPacing(baseWPM: 0), arcs: nil, triggersHandoff: nil)])
        #expect(throws: TranceScriptLibrary.LibraryError.self) {
            try TranceScriptLibrary.validate(script)
        }
    }

    @Test func loadAllSkipsInvalidFilesAndKeepsValidOnes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "tt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try valid.write(to: dir.appending(path: "good.json"))
        try Data("{ not a script }".utf8).write(to: dir.appending(path: "bad.json"))

        let scripts = TranceScriptLibrary.loadAll(inDirectory: dir)
        #expect(scripts.map(\.id) == ["deep-drift-01"])
    }
}
