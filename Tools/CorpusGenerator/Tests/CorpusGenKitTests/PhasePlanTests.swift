import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct PhasePlanTests {

    @Test("Classic archetype has the canonical 4-phase order")
    func classicOrder() {
        var rng = SeededRNG(seed: 42)
        let plan = PhasePlan.classic(using: &rng)
        #expect(plan.blocks.map(\.phase) == [.induction, .deepening, .suggestions, .emergence])
    }

    @Test("Named archetypes produce their configured phase orders")
    func namedArchetypeOrders() {
        let cases: [(PhasePlan.Archetype, [TrancePhase])] = [
            (.classic, [.induction, .deepening, .suggestions, .emergence]),
            (.fractionationLadder, [.induction, .fractionation, .deepening, .suggestions, .emergence]),
            (.confusionTherapy, [.induction, .deepening, .confusion, .suggestions, .emergence]),
            (.suggestionConditioning, [.induction, .deepening, .suggestions, .emergence]),
            (.directSuggestion, [.induction, .suggestions, .emergence]),
        ]

        for (archetype, expectedOrder) in cases {
            var rng = SeededRNG(seed: 42)
            let plan = PhasePlan.make(archetype: archetype, using: &rng)
            #expect(plan.archetype == archetype.rawValue)
            #expect(plan.blocks.map(\.phase) == expectedOrder)
        }
    }

    @Test("Block durations are positive and within configured ranges")
    func durationsInRange() {
        for archetype in PhasePlan.Archetype.allCases {
            var rng = SeededRNG(seed: 7)
            let plan = PhasePlan.make(archetype: archetype, using: &rng)
            for block in plan.blocks {
                #expect(block.duration > 0)
                let range = PhasePlan.durationRange(for: block.phase)
                #expect(block.duration >= range.lowerBound)
                #expect(block.duration <= range.upperBound)
            }
        }
    }

    @Test("totalDuration equals the sum of block durations")
    func totalDuration() {
        var rng = SeededRNG(seed: 1)
        let plan = PhasePlan.classic(using: &rng)
        #expect(abs(plan.totalDuration - plan.blocks.reduce(0) { $0 + $1.duration }) < 0.0001)
    }

    @Test("Same seed reproduces the same plan")
    func deterministic() {
        var a = SeededRNG(seed: 99); var b = SeededRNG(seed: 99)
        let p1 = PhasePlan.classic(using: &a)
        let p2 = PhasePlan.classic(using: &b)
        #expect(p1.blocks.map(\.duration) == p2.blocks.map(\.duration))
    }
}
