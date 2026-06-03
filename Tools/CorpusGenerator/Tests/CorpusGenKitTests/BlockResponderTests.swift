import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct BlockResponderTests {

    @Test("Stub returns non-empty, phase-appropriate keyword text")
    func stubText() async throws {
        let responder = StubResponder()
        let inductionReq = BlockRequest(phase: .induction, durationSec: 120, ambiguity: .low, seeds: [], priorPhases: [])
        let text = try await responder.text(for: inductionReq)
        #expect(!text.isEmpty)
        // Induction stub contains a canonical induction cue.
        #expect(text.localizedCaseInsensitiveContains("close your eyes"))
    }

    @Test("Stub covers every TrancePhase without crashing")
    func stubAllPhases() async throws {
        let responder = StubResponder()
        for phase in TrancePhase.allCases {
            let req = BlockRequest(phase: phase, durationSec: 60, ambiguity: .low, seeds: [], priorPhases: [])
            let text = try await responder.text(for: req)
            #expect(!text.isEmpty)
        }
    }
}
