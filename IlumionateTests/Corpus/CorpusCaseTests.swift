//  CorpusCaseTests.swift
import Testing
import Foundation
@testable import Ilumionate

struct CorpusCaseTests {

    @Test("Decodes an exact-mode synthetic case with truth spans")
    func decodesExactCase() throws {
        let json = """
        {
          "id": "synth-0001",
          "source": "synthetic",
          "boundaryMode": "exact",
          "ambiguityLevel": "high",
          "duration": 120.0,
          "segments": [
            { "text": "close your eyes", "timestamp": 0.0, "duration": 10.0, "confidence": 1.0 }
          ],
          "truth": [
            { "phase": "induction", "start": 0.0,  "end": 60.0 },
            { "phase": "deepening", "start": 60.0, "end": 120.0 }
          ]
        }
        """
        let data = Data(json.utf8)
        let kase = try JSONDecoder().decode(CorpusCase.self, from: data)

        #expect(kase.id == "synth-0001")
        #expect(kase.source == .synthetic)
        #expect(kase.boundaryMode == .exact)
        #expect(kase.ambiguityLevel == .high)
        #expect(kase.duration == 120.0)
        #expect(kase.segments.count == 1)
        #expect(kase.segments.first?.text == "close your eyes")
        #expect(kase.truth.count == 2)
        #expect(kase.truth.first?.phase == .induction)
        #expect(kase.truth.last?.end == 120.0)
    }

    @Test("Decodes a legacy case with no truth spans and optional expectations")
    func decodesLegacyCase() throws {
        let json = """
        {
          "id": "legacy-1",
          "source": "real",
          "boundaryMode": "anchored",
          "ambiguityLevel": "unspecified",
          "duration": 60.0,
          "segments": [],
          "truth": [],
          "expectedContentType": "hypnosis",
          "expectedPhaseOrder": ["pre_talk", "induction"],
          "minimumPhaseCount": 1
        }
        """
        let kase = try JSONDecoder().decode(CorpusCase.self, from: Data(json.utf8))
        #expect(kase.truth.isEmpty)
        #expect(kase.expectedPhaseOrder == [.preTalk, .induction])
        #expect(kase.expectedContentType == .hypnosis)
    }

    @Test("Converts to AudioTranscriptionSegment array")
    func convertsSegments() throws {
        let kase = CorpusCase(
            id: "x", source: .synthetic, boundaryMode: .exact,
            ambiguityLevel: .low, duration: 20,
            segments: [CorpusSegment(text: "hi", timestamp: 1, duration: 2, confidence: 0.9)],
            truth: []
        )
        let segs = kase.transcriptionSegments
        #expect(segs.count == 1)
        #expect(segs.first?.text == "hi")
        #expect(segs.first?.timestamp == 1)
        #expect(segs.first?.duration == 2)
    }
}
