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

    @Test("Per-second agreement grades only truth-covered seconds")
    func perSecondAgreement() {
        let eval = PhaseTimelineEvaluator()
        let truth = [span(.induction, 0, 4), span(.deepening, 6, 10)] // 4,5 = gray gap
        let predicted = [span(.induction, 0, 5), span(.deepening, 5, 10)]
        // Graded seconds: 0,1,2,3 (induction) + 6,7,8,9 (deepening) = 8 graded.
        //   sec 0,1,2,3 -> induction == induction (4 correct)
        //   sec 6,7,8,9 -> deepening == deepening (4 correct)
        // gray seconds 4,5 ignored.
        let agreement = eval.perSecondAgreement(
            truth: truth, predicted: predicted, duration: 10
        )
        #expect(agreement == 1.0)
    }

    @Test("Agreement is zero when predictions miss every graded second")
    func agreementZero() {
        let eval = PhaseTimelineEvaluator()
        let truth = [span(.induction, 0, 4)]
        let predicted = [span(.emergence, 0, 4)]
        #expect(eval.perSecondAgreement(truth: truth, predicted: predicted, duration: 4) == 0.0)
    }

    @Test("Exact-mode boundary error is distance to nearest predicted boundary")
    func boundaryErrorExact() {
        let eval = PhaseTimelineEvaluator()
        let truth = [span(.induction, 0, 60), span(.deepening, 60, 120)] // boundary at 60
        let predicted = [span(.induction, 0, 68), span(.deepening, 68, 120)] // boundary at 68
        let result = eval.boundaryError(
            truth: truth, predicted: predicted, boundaryMode: .exact, duration: 120
        )
        #expect(result.mean == 8.0)
        #expect(result.median == 8.0)
    }

    @Test("Anchored-mode boundary inside the gray gap scores zero error")
    func boundaryErrorAnchoredInsideGap() {
        let eval = PhaseTimelineEvaluator()
        // anchors: induction ends at 50, deepening starts at 70 -> gray gap [50,70]
        let truth = [span(.induction, 0, 50), span(.deepening, 70, 120)]
        let predicted = [span(.induction, 0, 60), span(.deepening, 60, 120)] // boundary 60 in [50,70]
        let result = eval.boundaryError(
            truth: truth, predicted: predicted, boundaryMode: .anchored, duration: 120
        )
        #expect(result.mean == 0.0)
    }

    @Test("Anchored-mode boundary spilling past the gap is penalized by overshoot")
    func boundaryErrorAnchoredSpill() {
        let eval = PhaseTimelineEvaluator()
        let truth = [span(.induction, 0, 50), span(.deepening, 70, 120)] // gap [50,70]
        let predicted = [span(.induction, 0, 80), span(.deepening, 80, 120)] // boundary 80 > 70 by 10
        let result = eval.boundaryError(
            truth: truth, predicted: predicted, boundaryMode: .anchored, duration: 120
        )
        #expect(result.mean == 10.0)
    }

    @Test("Confusion matrix counts truth->predicted over graded seconds")
    func confusionMatrix() {
        let eval = PhaseTimelineEvaluator()
        let truth = [span(.induction, 0, 4)]                  // 4 graded secs, all induction
        let predicted = [span(.induction, 0, 2), span(.deepening, 2, 4)] // 2 ind, 2 deep
        let cm = eval.confusionMatrix(truth: truth, predicted: predicted, duration: 4)
        #expect(cm.count(truth: .induction, predicted: .induction) == 2)
        #expect(cm.count(truth: .induction, predicted: .deepening) == 2)
    }

    @Test("Precision/recall/F1 derive from the confusion matrix")
    func precisionRecallF1() {
        let eval = PhaseTimelineEvaluator()
        let truth = [span(.induction, 0, 4), span(.deepening, 4, 6)]
        let predicted = [span(.induction, 0, 3), span(.deepening, 3, 6)]
        let cm = eval.confusionMatrix(truth: truth, predicted: predicted, duration: 6)
        let stats = cm.stats(for: .induction)
        // induction: TP=3 (secs0-2), FN=1 (sec3 predicted deepening), FP=0
        #expect(stats.precision == 1.0)
        #expect(abs(stats.recall - 0.75) < 0.0001)
        #expect(abs(stats.f1 - (2 * 1.0 * 0.75 / 1.75)) < 0.0001)
    }

    @Test("Scores one case end to end")
    func scoresCase() {
        let eval = PhaseTimelineEvaluator()
        let kase = CorpusCase(
            id: "c1", source: .synthetic, boundaryMode: .exact,
            ambiguityLevel: .high, duration: 120,
            segments: [],
            truth: [span(.induction, 0, 60), span(.deepening, 60, 120)]
        )
        let predicted = [span(.induction, 0, 60), span(.deepening, 60, 120)]
        let score = eval.score(case: kase, predicted: predicted)
        #expect(score.caseID == "c1")
        #expect(score.ambiguityLevel == .high)
        #expect(score.agreement == 1.0)
        #expect(score.boundaryError.mean == 0.0)
    }

    @Test("Aggregates a corpus report grouped by ambiguity")
    func aggregatesReport() {
        let eval = PhaseTimelineEvaluator()
        let low = CorpusCase(
            id: "lo", source: .synthetic, boundaryMode: .exact, ambiguityLevel: .low,
            duration: 10, segments: [], truth: [span(.induction, 0, 10)]
        )
        let high = CorpusCase(
            id: "hi", source: .synthetic, boundaryMode: .exact, ambiguityLevel: .high,
            duration: 10, segments: [], truth: [span(.induction, 0, 10)]
        )
        let perfect = [span(.induction, 0, 10)]
        let wrong = [span(.emergence, 0, 10)]
        let report = eval.report(scores: [
            eval.score(case: low, predicted: perfect),
            eval.score(case: high, predicted: wrong)
        ])
        #expect(abs(report.overallAgreement - 0.5) < 0.0001)
        #expect(report.agreementByAmbiguity[.low] == 1.0)
        #expect(report.agreementByAmbiguity[.high] == 0.0)
    }
}
