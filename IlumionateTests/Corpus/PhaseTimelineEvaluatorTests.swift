//  PhaseTimelineEvaluatorTests.swift
//  IlumionateTests
//
//  Unit tests for the timeline-aware phase metrics.
//
import Foundation
import Testing
@testable import Ilumionate

struct PhaseTimelineEvaluatorTests {

    // Helper: build spans quickly.
    private func span(_ phase: HypnosisMetadata.Phase, _ start: Double, _ end: Double) -> PhaseTruthSpan {
        PhaseTruthSpan(phase: phase, start: start, end: end)
    }

    @Test("Builds a per-second timeline; uncovered seconds are nil")
    func buildsTimeline() {
        let eval = PhaseTimelineEvaluator()
        let spans = [span(.induction, 0, 3), span(.deepening, 5, 8)]
        let timeline = eval.perSecondTimeline(spans: spans, duration: 8)
        // seconds 0,1,2 = induction ; 3,4 = nil (gap) ; 5,6,7 = deepening
        #expect(timeline.count == 8)
        #expect(timeline[0] == .induction)
        #expect(timeline[2] == .induction)
        #expect(timeline[3] == nil)
        #expect(timeline[4] == nil)
        #expect(timeline[5] == .deepening)
        #expect(timeline[7] == .deepening)
    }
}
