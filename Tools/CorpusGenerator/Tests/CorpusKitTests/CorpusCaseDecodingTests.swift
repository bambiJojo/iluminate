import Testing
import Foundation
@testable import CorpusKit

struct CorpusCaseDecodingTests {

    @Test("Decodes an exact-mode synthetic case with truth spans")
    func decodesExactCase() throws {
        let json = """
        {
          "id": "synth-0001", "source": "synthetic", "boundaryMode": "exact",
          "ambiguityLevel": "high", "duration": 120.0,
          "segments": [{ "text": "close your eyes", "timestamp": 0.0, "duration": 10.0, "confidence": 1.0 }],
          "truth": [
            { "phase": "induction", "start": 0.0,  "end": 60.0 },
            { "phase": "deepening", "start": 60.0, "end": 120.0 }
          ]
        }
        """
        let kase = try JSONDecoder().decode(CorpusCase.self, from: Data(json.utf8))
        #expect(kase.id == "synth-0001")
        #expect(kase.source == .synthetic)
        #expect(kase.boundaryMode == .exact)
        #expect(kase.ambiguityLevel == .high)
        #expect(kase.truth.first?.phase == .induction)
        #expect(kase.truth.last?.end == 120.0)
    }

    @Test("Decodes a legacy case; content type stays raw, phase order parses")
    func decodesLegacyCase() throws {
        let json = """
        {
          "id": "legacy-1", "source": "real", "boundaryMode": "anchored",
          "ambiguityLevel": "unspecified", "duration": 60.0, "segments": [], "truth": [],
          "expectedContentType": "hypnosis",
          "expectedPhaseOrder": ["pre_talk", "induction"],
          "minimumPhaseCount": 1
        }
        """
        let kase = try JSONDecoder().decode(CorpusCase.self, from: Data(json.utf8))
        #expect(kase.truth.isEmpty)
        #expect(kase.expectedContentTypeRaw == "hypnosis")
        #expect(kase.expectedPhaseOrder == [.preTalk, .induction])
    }

    @Test("Round-trips through encode/decode")
    func roundTrips() throws {
        let original = CorpusCase(
            id: "rt", source: .synthetic, boundaryMode: .exact, ambiguityLevel: .low,
            duration: 30, segments: [CorpusSegment(text: "relax", timestamp: 0, duration: 30, confidence: 1)],
            truth: [PhaseTruthSpan(phase: .induction, start: 0, end: 30)]
        )
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(CorpusCase.self, from: data)
        #expect(back.id == "rt")
        #expect(back.truth.first?.phase == .induction)
        #expect(back.segments.first?.text == "relax")
    }
}
