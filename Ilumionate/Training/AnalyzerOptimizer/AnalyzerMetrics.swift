//
//  AnalyzerMetrics.swift
//  Ilumionate
//
//  Scoring helpers for analyzer optimizer runs.
//

import Foundation

struct AnalyzerOptimizationPhaseStats: Codable, Sendable {
    let phase: TrancePhase
    let precision: Double
    let recall: Double
    let f1: Double
    let truePositiveBuckets: Int
    let predictedBuckets: Int
    let truthBuckets: Int
}

struct AnalyzerOptimizationMetrics: Codable, Sendable {
    let timelineAccuracy: Double
    let macroPhaseF1: Double
    let boundaryScore: Double
    let meanBoundaryErrorSeconds: Double
    let transitionRecall: Double
    let orderValidity: Double
    let contentTypeAccuracy: Double
    let overallScore: Double
    let truthBoundaryCount: Int
    let predictedBoundaryCount: Int
    let matchedTruthBoundaryCount: Int
    let phaseStats: [AnalyzerOptimizationPhaseStats]
}

struct AnalyzerOptimizationAggregateMetrics: Codable, Sendable {
    let exampleCount: Int
    let timelineAccuracy: Double
    let macroPhaseF1: Double
    let boundaryScore: Double
    let meanBoundaryErrorSeconds: Double
    let transitionRecall: Double
    let orderValidity: Double
    let contentTypeAccuracy: Double
    let overallScore: Double

    static let zero = AnalyzerOptimizationAggregateMetrics(
        exampleCount: 0,
        timelineAccuracy: 0,
        macroPhaseF1: 0,
        boundaryScore: 0,
        meanBoundaryErrorSeconds: 0,
        transitionRecall: 0,
        orderValidity: 0,
        contentTypeAccuracy: 0,
        overallScore: 0
    )
}

enum AnalyzerMetrics {
    private static let scoredPhases: [TrancePhase] = [
        .preTalk, .induction, .deepening, .therapy,
        .suggestions, .conditioning, .emergence
    ]

    private static let canonicalOrder: [TrancePhase] = scoredPhases

    static func score(
        example: AnalyzerTrainingExample,
        predictedSegments: [PhaseSegment],
        predictedContentType: AudioContentType,
        boundaryToleranceSeconds: Double = 30.0
    ) -> AnalyzerOptimizationMetrics {
        let truthTimeline = example.labels.denseTimeline.isEmpty
            ? rebuildTruthTimeline(from: example.labels.phaseSegments, duration: example.audio.durationSeconds)
            : example.labels.denseTimeline

        let predictedTimeline = truthTimeline.map { bucket in
            predictedPhase(at: min(example.audio.durationSeconds, bucket.startTime + ((bucket.endTime - bucket.startTime) / 2)), in: predictedSegments)
        }
        let truthPhases = truthTimeline.map(\.phase)

        let phaseStats = scoredPhases.map { phase -> AnalyzerOptimizationPhaseStats in
            let tp = zip(truthPhases, predictedTimeline).filter { truth, predicted in
                truth == phase && predicted == phase
            }.count
            let predictedCount = predictedTimeline.filter { $0 == phase }.count
            let truthCount = truthPhases.filter { $0 == phase }.count
            let precision = predictedCount == 0 ? 0 : Double(tp) / Double(predictedCount)
            let recall = truthCount == 0 ? 0 : Double(tp) / Double(truthCount)
            let f1 = (precision + recall) == 0 ? 0 : (2 * precision * recall) / (precision + recall)
            return AnalyzerOptimizationPhaseStats(
                phase: phase,
                precision: precision,
                recall: recall,
                f1: f1,
                truePositiveBuckets: tp,
                predictedBuckets: predictedCount,
                truthBuckets: truthCount
            )
        }

        let activePhaseStats = phaseStats.filter { $0.predictedBuckets > 0 || $0.truthBuckets > 0 }
        let macroPhaseF1: Double
        if activePhaseStats.isEmpty {
            macroPhaseF1 = 1.0
        } else {
            macroPhaseF1 = activePhaseStats.map(\.f1).reduce(0, +) / Double(activePhaseStats.count)
        }

        let correctTimelineBuckets = zip(truthPhases, predictedTimeline).filter { $0 == $1 }.count
        let timelineAccuracy = truthPhases.isEmpty ? 1.0 : Double(correctTimelineBuckets) / Double(truthPhases.count)

        let truthBoundaries = Array(example.labels.phaseSegments.dropFirst()).map(\.startTime)
        let predictedBoundaries = Array(predictedSegments.dropFirst()).map(\.startTime)
        let boundaryEvaluation = evaluateBoundaries(
            truthBoundaries: truthBoundaries,
            predictedBoundaries: predictedBoundaries,
            tolerance: boundaryToleranceSeconds
        )

        let orderValidity = scorePhaseOrder(predictedSegments.map(\.phase))
        let contentTypeAccuracy = predictedContentType == example.labels.contentType ? 1.0 : 0.0
        let overallScore =
            (0.45 * macroPhaseF1) +
            (0.25 * boundaryEvaluation.boundaryScore) +
            (0.15 * boundaryEvaluation.transitionRecall) +
            (0.10 * orderValidity) +
            (0.05 * contentTypeAccuracy)

        return AnalyzerOptimizationMetrics(
            timelineAccuracy: timelineAccuracy,
            macroPhaseF1: macroPhaseF1,
            boundaryScore: boundaryEvaluation.boundaryScore,
            meanBoundaryErrorSeconds: boundaryEvaluation.meanErrorSeconds,
            transitionRecall: boundaryEvaluation.transitionRecall,
            orderValidity: orderValidity,
            contentTypeAccuracy: contentTypeAccuracy,
            overallScore: overallScore,
            truthBoundaryCount: truthBoundaries.count,
            predictedBoundaryCount: predictedBoundaries.count,
            matchedTruthBoundaryCount: boundaryEvaluation.matchedTruthBoundaryCount,
            phaseStats: phaseStats
        )
    }

    static func aggregate(_ metrics: [AnalyzerOptimizationMetrics]) -> AnalyzerOptimizationAggregateMetrics {
        guard !metrics.isEmpty else { return .zero }

        func average(_ keyPath: KeyPath<AnalyzerOptimizationMetrics, Double>) -> Double {
            metrics.map { $0[keyPath: keyPath] }.reduce(0, +) / Double(metrics.count)
        }

        return AnalyzerOptimizationAggregateMetrics(
            exampleCount: metrics.count,
            timelineAccuracy: average(\.timelineAccuracy),
            macroPhaseF1: average(\.macroPhaseF1),
            boundaryScore: average(\.boundaryScore),
            meanBoundaryErrorSeconds: average(\.meanBoundaryErrorSeconds),
            transitionRecall: average(\.transitionRecall),
            orderValidity: average(\.orderValidity),
            contentTypeAccuracy: average(\.contentTypeAccuracy),
            overallScore: average(\.overallScore)
        )
    }

    private static func predictedPhase(
        at time: TimeInterval,
        in segments: [PhaseSegment]
    ) -> TrancePhase? {
        segments.first(where: { segment in
            time >= segment.startTime && time < segment.endTime
        })?.phase
        ?? segments.last(where: { time == $0.endTime })?.phase
    }

    private static func rebuildTruthTimeline(
        from segments: [AnalyzerTrainingExample.PhaseSegment],
        duration: TimeInterval,
        resolutionSeconds: TimeInterval = 1
    ) -> [AnalyzerTrainingExample.TimelineBucket] {
        guard duration > 0 else { return [] }

        let bucketCount = max(1, Int(ceil(duration / resolutionSeconds)))
        return (0..<bucketCount).map { index in
            let start = Double(index) * resolutionSeconds
            let end = min(duration, start + resolutionSeconds)
            let midpoint = min(duration, start + ((end - start) / 2))
            let phase = segments.first(where: { midpoint >= $0.startTime && midpoint < $0.endTime })?.phase
            return AnalyzerTrainingExample.TimelineBucket(
                secondIndex: index,
                startTime: start,
                endTime: end,
                phase: phase
            )
        }
    }

    private static func evaluateBoundaries(
        truthBoundaries: [TimeInterval],
        predictedBoundaries: [TimeInterval],
        tolerance: Double
    ) -> (boundaryScore: Double, meanErrorSeconds: Double, transitionRecall: Double, matchedTruthBoundaryCount: Int) {
        guard !truthBoundaries.isEmpty else {
            return (
                predictedBoundaries.isEmpty ? 1.0 : 0.0,
                0.0,
                predictedBoundaries.isEmpty ? 1.0 : 0.0,
                predictedBoundaries.isEmpty ? 0 : 0
            )
        }

        var totalError: Double = 0
        var matchedCount = 0

        for truth in truthBoundaries {
            let nearest = predictedBoundaries.min(by: { abs($0 - truth) < abs($1 - truth) })
            let error = nearest.map { abs($0 - truth) } ?? tolerance
            totalError += error
            if error <= tolerance {
                matchedCount += 1
            }
        }

        let meanError = totalError / Double(truthBoundaries.count)
        let boundaryScore = max(0, 1.0 - (meanError / tolerance))
        let transitionRecall = Double(matchedCount) / Double(truthBoundaries.count)
        return (boundaryScore, meanError, transitionRecall, matchedCount)
    }

    private static func scorePhaseOrder(_ phases: [TrancePhase]) -> Double {
        guard !phases.isEmpty else { return 1.0 }

        var lastIndex = -1
        for phase in phases {
            guard phase != .transitional else { continue }
            guard let index = canonicalOrder.firstIndex(of: phase) else { continue }
            if index < lastIndex {
                return 0.0
            }
            lastIndex = index
        }
        return 1.0
    }
}
