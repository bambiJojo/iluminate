import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct CorpusWriterTests {

    @Test("Writes a decodable JSON file named after the case id")
    func writesDecodableFile() throws {
        let tmp = URL.temporaryDirectory.appending(path: "corpusgen-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let kase = CorpusCase(
            id: "synth-classic-deadbeef", source: .synthetic, boundaryMode: .exact,
            ambiguityLevel: .low, duration: 60,
            segments: [CorpusSegment(text: "relax", timestamp: 0, duration: 60, confidence: 1)],
            truth: [PhaseTruthSpan(phase: .induction, start: 0, end: 60)]
        )
        let url = try CorpusWriter.write(kase, to: tmp)
        #expect(url.lastPathComponent == "synth-classic-deadbeef.json")

        let back = try JSONDecoder().decode(CorpusCase.self, from: Data(contentsOf: url))
        #expect(back.id == kase.id)
        #expect(back.truth.first?.phase == .induction)
    }
}
