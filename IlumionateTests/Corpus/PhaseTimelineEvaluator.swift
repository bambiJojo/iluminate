//  PhaseTimelineEvaluator.swift
//  IlumionateTests
//
//  Timeline-aware phase metrics. Grades predictions against ground-truth
//  spans per second; supports exact and anchored (gray-zone) boundary modes.
//
import Foundation
@testable import Ilumionate

struct PhaseTimelineEvaluator: Sendable {

    /// One phase per second over [0, duration). `nil` = not covered by any span
    /// (a gray-zone gap, or beyond the labeled region).
    func perSecondTimeline(
        spans: [PhaseTruthSpan],
        duration: TimeInterval
    ) -> [HypnosisMetadata.Phase?] {
        let bucketCount = max(0, Int(ceil(duration)))
        var timeline = [HypnosisMetadata.Phase?](repeating: nil, count: bucketCount)
        for span in spans {
            let lo = max(0, Int(floor(span.start)))
            let hi = min(bucketCount, Int(ceil(span.end)))
            guard lo < hi else { continue }
            for i in lo..<hi { timeline[i] = span.phase }
        }
        return timeline
    }

    /// Fraction of truth-covered seconds where predicted phase == truth phase.
    /// Returns 0 when there are no graded seconds.
    func perSecondAgreement(
        truth: [PhaseTruthSpan],
        predicted: [PhaseTruthSpan],
        duration: TimeInterval
    ) -> Double {
        let truthTimeline = perSecondTimeline(spans: truth, duration: duration)
        let predTimeline = perSecondTimeline(spans: predicted, duration: duration)
        var graded = 0
        var correct = 0
        for i in truthTimeline.indices {
            guard let t = truthTimeline[i] else { continue } // skip gray/uncovered
            graded += 1
            if i < predTimeline.count, predTimeline[i] == t { correct += 1 }
        }
        return graded == 0 ? 0 : Double(correct) / Double(graded)
    }
}
