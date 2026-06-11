//  TranceScriptDecodingTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

struct TranceScriptDecodingTests {

    static let sampleJSON = """
    {
      "schemaVersion": 1,
      "id": "deep-drift-01",
      "title": "Deep Drift",
      "theme": "relaxation",
      "supportedArcs": ["fullText", "handoff"],
      "language": "en",
      "source": { "kind": "bundled", "generator": "hand-authored", "reviewed": true },
      "segments": [
        { "phase": "induction",  "text": "Allow your eyes to rest.", "pacing": { "baseWPM": 140 } },
        { "phase": "deepening",  "text": "Deeper and deeper." },
        { "phase": "emergence",  "text": "Return now, refreshed.", "arcs": ["fullText"] },
        { "phase": "emergence",  "text": "Let your eyes close.", "arcs": ["handoff"], "triggersHandoff": true }
      ]
    }
    """

    @Test func decodesAllFields() throws {
        let data = Data(Self.sampleJSON.utf8)
        let script = try JSONDecoder().decode(TranceScript.self, from: data)

        #expect(script.id == "deep-drift-01")
        #expect(script.title == "Deep Drift")
        #expect(script.theme == .relaxation)
        #expect(script.supportedArcs == [.fullText, .handoff])
        #expect(script.source.reviewed == true)
        #expect(script.segments.count == 4)
        #expect(script.segments[0].phase == .induction)
        #expect(script.segments[0].pacing?.baseWPM == 140)
        #expect(script.segments[1].pacing == nil)
        #expect(script.segments[2].arcs == [.fullText])
        #expect(script.segments[3].triggersHandoff == true)
        #expect(script.segments[0].triggersHandoff == nil)
    }
}
