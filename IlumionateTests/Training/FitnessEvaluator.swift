//
//  FitnessEvaluator.swift
//  IlumionateTests
//
//  Extended scoring with phase boundary accuracy for the evolutionary pipeline.
//

import Foundation
@testable import Ilumionate

struct FitnessEvaluator {

    /// Tolerance in seconds for phase boundary matching.
    var boundaryToleranceSeconds: Double = 30.0

    /// Weighted fitness function per the spec.
    func fitness(
        labeledFile: LabeledFile,
        result: AnalysisResult,
        session: LightSession
    ) -> Double {
        let contentTypeScore: Double = result.contentType == labeledFile.expectedContentType ? 1.0 : 0.0
        let boundaryScore = scorePhaseBoundaries(labeledFile: labeledFile, result: result)
        let presenceScore = scorePhasePresence(labeledFile: labeledFile, result: result)
        let orderScore = scorePhaseOrder(result: result)
        let frequencyScore = scoreFrequencyRange(labeledFile: labeledFile, result: result)
        let sessionScore = scoreSessionValidity(session: session)

        return (0.25 * contentTypeScore)
             + (0.25 * boundaryScore)
             + (0.20 * presenceScore)
             + (0.10 * orderScore)
             + (0.10 * frequencyScore)
             + (0.10 * sessionScore)
    }

    // MARK: - Phase Boundary Score

    /// For each truth boundary, find the nearest detected boundary.
    /// Score = 1.0 - (avgErrorSeconds / toleranceSeconds), clamped to 0.
    func scorePhaseBoundaries(labeledFile: LabeledFile, result: AnalysisResult) -> Double {
        guard let meta = result.hypnosisMetadata, !meta.phases.isEmpty else {
            return labeledFile.phases.isEmpty ? 1.0 : 0.0
        }

        let truthBoundaries = labeledFile.phases.map(\.startTime) +
            [labeledFile.phases.last?.endTime ?? labeledFile.audioDuration]
        let detectedBoundaries = meta.phases.map(\.startTime) +
            [meta.phases.last?.endTime ?? 0]

        guard !truthBoundaries.isEmpty else { return 1.0 }

        var totalError: Double = 0
        for truth in truthBoundaries {
            let nearest = detectedBoundaries.min(by: { abs($0 - truth) < abs($1 - truth) }) ?? 0
            totalError += abs(nearest - truth)
        }

        let avgError = totalError / Double(truthBoundaries.count)
        return max(0, 1.0 - (avgError / boundaryToleranceSeconds))
    }

    // MARK: - Phase Presence

    func scorePhasePresence(labeledFile: LabeledFile, result: AnalysisResult) -> Double {
        guard !labeledFile.phases.isEmpty else { return 1.0 }
        guard let meta = result.hypnosisMetadata else { return 0.0 }
        let detected = Set(meta.phases.map(\.phase))
        let expected = Set(labeledFile.phases.map(\.phase))
        let hits = expected.intersection(detected).count
        return Double(hits) / Double(expected.count)
    }

    // MARK: - Phase Order

    private static let canonicalOrder: [HypnosisMetadata.Phase] = [
        .preTalk, .induction, .deepening, .therapy,
        .suggestions, .conditioning, .emergence
    ]

    func scorePhaseOrder(result: AnalysisResult) -> Double {
        guard let meta = result.hypnosisMetadata, !meta.phases.isEmpty else { return 1.0 }
        let detected = meta.phases.map(\.phase)
        var lastIndex = -1
        for phase in detected {
            if let idx = Self.canonicalOrder.firstIndex(of: phase) {
                if idx < lastIndex { return 0.0 }
                lastIndex = idx
            }
        }
        return 1.0
    }

    // MARK: - Frequency Range

    func scoreFrequencyRange(labeledFile: LabeledFile, result: AnalysisResult) -> Double {
        let detected = result.suggestedFrequencyRange
        let expected = labeledFile.expectedFrequencyBand.closedRange
        let overlaps = detected.lowerBound <= expected.upperBound && expected.lowerBound <= detected.upperBound
        return overlaps ? 1.0 : 0.0
    }

    // MARK: - Session Validity

    func scoreSessionValidity(session: LightSession) -> Double {
        guard !session.light_score.isEmpty else { return 0.0 }
        let validFreq = session.light_score.allSatisfy { $0.frequency >= 0.5 && $0.frequency <= 40.0 }
        let validAmp = session.light_score.allSatisfy { $0.intensity >= 0.0 && $0.intensity <= 1.0 }
        let sorted = session.light_score.map(\.time) == session.light_score.map(\.time).sorted()
        return (validFreq && validAmp && sorted) ? 1.0 : 0.0
    }
}
