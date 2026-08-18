//
//  ChunkedPhaseCircuitBreakerTests.swift
//  IlumionateTests
//
//  A guardrail refusal is about the content, so a transcript the model refused
//  whole is refused chunk by chunk too. Each refusal is a real model
//  round-trip, and the analyzer used to grind through every chunk regardless —
//  on device that consumed the whole background window and left the Dynamic
//  Island reading "Analyzing audio · Task failed".
//

import Testing
import Foundation
import FoundationModels
@testable import Ilumionate

@MainActor
private final class ClassifyCounter {
    private(set) var calls = 0
    func increment() { calls += 1 }
}

struct ChunkedPhaseCircuitBreakerTests {

    private func jobs(_ count: Int) -> [ChunkedPhaseAnalyzer.ChunkJob] {
        (0..<count).map { index in
            ChunkedPhaseAnalyzer.ChunkJob(
                index: index,
                start: Double(index) * 10,
                end: Double(index) * 10 + 15,
                // Non-empty: an empty chunk is skipped without a model call, so
                // it would not exercise the breaker.
                text: "segment \(index) of transcript text",
                positionPct: min(99, index)
            )
        }
    }

    @MainActor
    @Test("A run of refusals stops the pass instead of grinding through every chunk")
    func refusalsAbortThePass() async throws {
        let counter = ClassifyCounter()
        let total = 400

        _ = try await ChunkedPhaseAnalyzer.runPass(
            jobs: jobs(total),
            previousResults: nil,
            totalDuration: 4_000,
            model: SystemLanguageModel.default,
            systemInstructions: "instructions",
            knowledge: CorpusPhaseKnowledge(),
            fewShotSeedExamples: [],
            classify: { _, _, _ in
                await counter.increment()
                // What a guardrail-refused chunk yields today.
                return []
            }
        )

        let calls = await counter.calls
        #expect(calls < total)
        // Generous headroom over the limit for in-flight concurrency, but far
        // short of the 400 the old loop would have spent.
        #expect(calls <= ChunkedPhaseAnalyzer.consecutiveUnusableChunkLimit * 3)
    }

    @MainActor
    @Test("A pass that keeps classifying runs to completion")
    func usefulResultsDoNotTripTheBreaker() async throws {
        let counter = ClassifyCounter()
        let total = 40

        let results = try await ChunkedPhaseAnalyzer.runPass(
            jobs: jobs(total),
            previousResults: nil,
            totalDuration: 400,
            model: SystemLanguageModel.default,
            systemInstructions: "instructions",
            knowledge: CorpusPhaseKnowledge(),
            fewShotSeedExamples: [],
            classify: { request, _, _ in
                await counter.increment()
                return [ChunkedPhaseAnalyzer.TimedClassification(
                    start: request.startTime,
                    end: request.endTime,
                    phase: .deepening
                )]
            }
        )

        #expect(await counter.calls == total)
        #expect(results.count == total)
    }

    /// The breaker must tolerate an unusable stretch that recovers — a quiet
    /// opening should not cost the rest of the file.
    @MainActor
    @Test("An unusable stretch that recovers does not abort the pass")
    func recoveringStretchDoesNotAbort() async throws {
        let counter = ClassifyCounter()
        let total = 60
        let quiet = ChunkedPhaseAnalyzer.consecutiveUnusableChunkLimit - 2

        _ = try await ChunkedPhaseAnalyzer.runPass(
            jobs: jobs(total),
            previousResults: nil,
            totalDuration: 600,
            model: SystemLanguageModel.default,
            systemInstructions: "instructions",
            knowledge: CorpusPhaseKnowledge(),
            fewShotSeedExamples: [],
            classify: { request, _, _ in
                await counter.increment()
                guard request.startTime >= Double(quiet) * 10 else { return [] }
                return [ChunkedPhaseAnalyzer.TimedClassification(
                    start: request.startTime,
                    end: request.endTime,
                    phase: .induction
                )]
            }
        )

        #expect(await counter.calls == total)
    }
}
