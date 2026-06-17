import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct ClaudeRequestBuilderTests {

    @Test("System prefix embeds seed excerpts and is marked cacheable")
    func systemPrefixHasSeeds() {
        let builder = ClaudeRequestBuilder(model: "claude-x")
        let seeds = [PhaseSeed(phase: .induction, excerpt: "close your eyes")]
        let body = builder.body(
            for: BlockRequest(phase: .deepening, durationSec: 90, ambiguity: .medium, seeds: seeds, priorPhases: [.induction])
        )
        let system = body["system"] as? [[String: Any]]
        let joined = (system ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        #expect(joined.localizedCaseInsensitiveContains("close your eyes"))
        // Cache control present on the (large, stable) seed block.
        #expect((system ?? []).contains { ($0["cache_control"] as? [String: Any]) != nil })
    }

    @Test("User message names the target phase and duration")
    func userMessageTargets() {
        let builder = ClaudeRequestBuilder(model: "claude-x")
        let body = builder.body(
            for: BlockRequest(phase: .emergence, durationSec: 45, ambiguity: .high, seeds: [], priorPhases: [.suggestions])
        )
        let messages = body["messages"] as? [[String: Any]]
        let text = (messages?.first?["content"] as? String) ?? ""
        #expect(text.localizedCaseInsensitiveContains("emergence"))
        #expect(text.contains("45"))
        #expect(body["model"] as? String == "claude-x")
    }
}
