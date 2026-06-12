//  BundledTranceScriptTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

struct BundledTranceScriptTests {

    /// Locate the source Scripts directory relative to this test file so the
    /// shipped JSON is validated regardless of test-bundle packaging.
    private static var scriptsDir: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()    // .../IlumionateTests/TextTrance
            .deletingLastPathComponent()    // .../IlumionateTests
            .deletingLastPathComponent()    // repo root
            .appending(path: "Ilumionate/TextTrance/Scripts")
    }

    // Non-exhaustive; covers the most common direct eyes-closure instructions.
    // Extend as new scripts are added.
    private static let eyesClosurePhrases = [
        "close your eyes", "eyes closed", "let your eyes close",
        "let your eyes drift", "eyes drift closed", "eyes gently closed"
    ]

    /// Loads the bundled scripts, failing loudly if the directory resolution
    /// breaks (otherwise the loop-based tests below would pass vacuously).
    private func loadedScripts(
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) -> [TranceScript] {
        let scripts = TranceScriptLibrary.loadAll(inDirectory: Self.scriptsDir)
        #expect(scripts.count >= 3,
                "loadAll returned \(scripts.count) scripts — check scriptsDir resolution",
                sourceLocation: sourceLocation)
        return scripts
    }

    @Test func everyBundledScriptParsesAndValidates() throws {
        let scripts = loadedScripts()
        let ids = Set(scripts.map(\.id))
        #expect(ids.isSuperset(of: ["deep-drift", "shoreline-sleep", "clear-signal"]))
    }

    @Test func everyScriptIsHumanReviewed() {
        let scripts = loadedScripts()
        #expect(scripts.allSatisfy { $0.source.reviewed })
    }

    @Test func eachSupportedArcProducesANonEmptySchedule() {
        for script in loadedScripts() {
            for arc in script.supportedArcs {
                let schedule = TextPacingEngine.schedule(
                    for: script, settings: .init(arc: arc, speed: .natural))
                #expect(!schedule.isEmpty, "\(script.id)/\(arc.rawValue) empty")
            }
        }
    }

    @Test func fullTextSchedulesContainNoEyesClosurePhrasing() {
        for script in loadedScripts()
            where script.supportedArcs.contains(.fullText) {
            let schedule = TextPacingEngine.schedule(
                for: script, settings: .init(arc: .fullText, speed: .natural))
            let joined = schedule.map(\.text).joined(separator: " ").lowercased()
            for phrase in Self.eyesClosurePhrases {
                #expect(!joined.contains(phrase),
                        "\(script.id) fullText contains '\(phrase)'")
            }
        }
    }

    @Test func handoffScriptsEndOnATriggerSegment() {
        for script in loadedScripts()
            where script.supportedArcs.contains(.handoff) {
            let hasTrigger = script.segments.contains {
                ($0.triggersHandoff == true) &&
                ($0.arcs?.contains(.handoff) ?? true)
            }
            #expect(hasTrigger, "\(script.id) handoff arc has no trigger segment")
        }
    }
}
