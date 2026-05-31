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
}
