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

    struct BoundaryError: Sendable, Equatable {
        let mean: Double
        let median: Double
        let count: Int   // number of truth boundaries scored
    }

    /// For each internal truth transition, the distance from the nearest
    /// predicted boundary to the truth boundary (exact) or to the gray-zone
    /// gap (anchored: zero inside the gap, overshoot distance outside it).
    func boundaryError(
        truth: [PhaseTruthSpan],
        predicted: [PhaseTruthSpan],
        boundaryMode: CorpusBoundaryMode,
        duration: TimeInterval
    ) -> BoundaryError {
        let sortedTruth = truth.sorted { $0.start < $1.start }
        let predBoundaries = internalBoundaries(of: predicted)

        var distances: [Double] = []
        for i in 0..<max(0, sortedTruth.count - 1) {
            let prev = sortedTruth[i]
            let next = sortedTruth[i + 1]
            let target: (Double) -> Double
            switch boundaryMode {
            case .exact:
                // gap collapses to the shared boundary point
                let point = next.start
                target = { abs($0 - point) }
            case .anchored:
                // tolerance gap [prev.end, next.start]; 0 inside, overshoot outside
                let lo = prev.end, hi = next.start
                target = { p in p < lo ? lo - p : (p > hi ? p - hi : 0) }
            }
            // nearest predicted boundary to this truth transition
            guard let best = predBoundaries.map(target).min() else {
                distances.append(duration) // no predicted boundary at all = worst case
                continue
            }
            distances.append(best)
        }

        guard !distances.isEmpty else { return BoundaryError(mean: 0, median: 0, count: 0) }
        let mean = distances.reduce(0, +) / Double(distances.count)
        let median = medianOf(distances)
        return BoundaryError(mean: mean, median: median, count: distances.count)
    }

    /// Start times of every span after the first (the internal transitions).
    private func internalBoundaries(of spans: [PhaseTruthSpan]) -> [Double] {
        let sorted = spans.sorted { $0.start < $1.start }
        guard sorted.count > 1 else { return [] }
        return sorted.dropFirst().map(\.start)
    }

    private func medianOf(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
}
