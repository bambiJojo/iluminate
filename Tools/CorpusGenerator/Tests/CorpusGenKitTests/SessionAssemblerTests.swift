import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct SessionAssemblerTests {

    private func twoBlockPlan() -> PhasePlan {
        PhasePlan(archetype: "test", blocks: [
            PhasePlanBlock(phase: .induction, duration: 60),
            PhasePlanBlock(phase: .deepening, duration: 60),
        ])
    }

    @Test("Truth spans are contiguous, exact, and cover [0, totalDuration]")
    func contiguousTruth() async throws {
        let assembler = SessionAssembler(responder: StubResponder())
        let kase = try await assembler.assemble(
            plan: twoBlockPlan(), ambiguity: .low, idPrefix: "synth", model: nil, seedSetID: nil
        )
        #expect(kase.boundaryMode == .exact)
        #expect(kase.source == .synthetic)
        #expect(kase.duration == 120)
        #expect(kase.truth.count == 2)
        #expect(kase.truth[0].phase == .induction)
        #expect(kase.truth[0].start == 0)
        #expect(kase.truth[0].end == 60)
        #expect(kase.truth[1].phase == .deepening)
        #expect(kase.truth[1].start == 60)
        #expect(kase.truth[1].end == 120)
    }

    @Test("Segments are non-empty and stay within their block window")
    func segmentsWithinWindow() async throws {
        let assembler = SessionAssembler(responder: StubResponder())
        let kase = try await assembler.assemble(
            plan: twoBlockPlan(), ambiguity: .low, idPrefix: "synth", model: nil, seedSetID: nil
        )
        #expect(!kase.segments.isEmpty)
        for seg in kase.segments {
            #expect(seg.timestamp >= 0)
            #expect(seg.timestamp + seg.duration <= kase.duration + 0.001)
        }
        // Induction keyword lands in the first block window (before 60s).
        let early = kase.segments.filter { $0.timestamp < 60 }.map(\.text).joined(separator: " ")
        #expect(early.localizedCaseInsensitiveContains("close your eyes"))
    }

    @Test("Stamps generation provenance and ambiguity")
    func stampsProvenance() async throws {
        let assembler = SessionAssembler(responder: StubResponder())
        let kase = try await assembler.assemble(
            plan: twoBlockPlan(), ambiguity: .high, idPrefix: "synth", model: "claude-x", seedSetID: "seedset-1"
        )
        #expect(kase.ambiguityLevel == .high)
        #expect(kase.generation?.archetype == "test")
        #expect(kase.generation?.ambiguity == "high")
        #expect(kase.generation?.model == "claude-x")
        #expect(kase.generation?.seedSetID == "seedset-1")
        #expect(kase.id.hasPrefix("synth-"))
    }

    @Test("Accepts deterministic case id, generation seed, and createdAt")
    func deterministicProvenance() async throws {
        let assembler = SessionAssembler(responder: StubResponder())
        let createdAt = Date(timeIntervalSince1970: 42)

        let kase = try await assembler.assemble(
            plan: twoBlockPlan(),
            ambiguity: .low,
            idPrefix: "synth",
            model: nil,
            seedSetID: nil,
            caseID: "synth-test-seed4242-0001",
            generationSeed: 4242,
            createdAt: createdAt
        )

        #expect(kase.id == "synth-test-seed4242-0001")
        #expect(kase.generation?.seed == 4242)
        #expect(kase.generation?.createdAt == createdAt)
    }
}
