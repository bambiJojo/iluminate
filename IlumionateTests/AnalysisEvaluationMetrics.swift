//
//  AnalysisEvaluationMetrics.swift
//  IlumionateTests
//
//  Quality-scoring types for the analysis evaluation harness.
//  Scores are deterministic when run with keyword-fallback or fixture data,
//  so they can run in CI without Apple Intelligence.
//

import Foundation
@testable import Ilumionate

// MARK: - Quality Score

/// A structured quality assessment for a single analysis result.
struct AnalysisQualityScore: Sendable {

    /// True when the detected content type matches the ground-truth label.
    let contentTypeCorrect: Bool

    /// Fraction of expected phases that are present in the result (0.0–1.0).
    let phasePresenceScore: Double

    /// 1.0 if detected phase spans are chronological and non-overlapping.
    /// Sustained returns to an earlier structural phase are valid hypnosis structure.
    let phaseOrderScore: Double

    /// 1.0 if `suggestedFrequencyRange` overlaps the expected band; 0.0 otherwise.
    let frequencyRangeScore: Double

    /// 1.0 if the generated `LightSession` passes all structural invariants; 0.0 otherwise.
    let sessionValidityScore: Double

    /// Weighted average of the four numeric scores (content type not included in the mean).
    var overallScore: Double {
        (phasePresenceScore + phaseOrderScore + frequencyRangeScore + sessionValidityScore) / 4.0
    }
}

// MARK: - Evaluation Case

/// A labelled ground-truth case used by the evaluation harness.
struct EvaluationCase: Sendable {
    let name: String
    let transcript: AudioTranscriptionResult
    let audioFile: AudioFile
    let expectedContentType: AnalysisResult.ContentType
    /// Phases that must appear, in this order, for a perfect phase-presence score.
    let expectedPhaseOrder: [HypnosisMetadata.Phase]
    /// Acceptable Hz range for `suggestedFrequencyRange`.
    let expectedFrequencyBand: ClosedRange<Double>
}

// MARK: - Evaluator

/// Computes an `AnalysisQualityScore` given a ground-truth case and pipeline outputs.
struct AnalysisEvaluator {

    func score(
        evalCase: EvaluationCase,
        result: AnalysisResult,
        session: LightSession
    ) -> AnalysisQualityScore {
        AnalysisQualityScore(
            contentTypeCorrect:  scoreContentType(result: result, evalCase: evalCase),
            phasePresenceScore:  scorePhasePresence(result: result, evalCase: evalCase),
            phaseOrderScore:     scorePhaseOrder(result: result),
            frequencyRangeScore: scoreFrequencyRange(result: result, evalCase: evalCase),
            sessionValidityScore: scoreSessionValidity(session: session)
        )
    }

    // MARK: - Individual Scorers

    private func scoreContentType(result: AnalysisResult, evalCase: EvaluationCase) -> Bool {
        result.contentType == evalCase.expectedContentType
    }

    private func scorePhasePresence(result: AnalysisResult, evalCase: EvaluationCase) -> Double {
        guard !evalCase.expectedPhaseOrder.isEmpty else { return 1.0 }
        guard let meta = result.hypnosisMetadata else { return 0.0 }
        let detected = Set(meta.phases.map(\.phase))
        let hits = evalCase.expectedPhaseOrder.filter { detected.contains($0) }.count
        return Double(hits) / Double(evalCase.expectedPhaseOrder.count)
    }

    private func scorePhaseOrder(result: AnalysisResult) -> Double {
        guard let meta = result.hypnosisMetadata, !meta.phases.isEmpty else { return 1.0 }
        var previousEnd = -Double.infinity
        for segment in meta.phases {
            guard
                segment.startTime.isFinite,
                segment.endTime.isFinite,
                segment.startTime >= previousEnd - 0.001,
                segment.endTime > segment.startTime
            else {
                return 0.0
            }
            previousEnd = segment.endTime
        }
        return 1.0
    }

    private func scoreFrequencyRange(result: AnalysisResult, evalCase: EvaluationCase) -> Double {
        let detected  = result.suggestedFrequencyRange
        let expected  = evalCase.expectedFrequencyBand
        // Ranges overlap if neither is entirely above or below the other
        let overlaps  = detected.lowerBound <= expected.upperBound &&
                        expected.lowerBound <= detected.upperBound
        return overlaps ? 1.0 : 0.0
    }

    private func scoreSessionValidity(session: LightSession) -> Double {
        guard !session.light_score.isEmpty else { return 0.0 }
        let validFrequencies = session.light_score.allSatisfy { $0.frequency >= 0.5 && $0.frequency <= 40.0 }
        let validIntensities = session.light_score.allSatisfy { $0.intensity >= 0.0 && $0.intensity <= 1.0 }
        let sortedTimes      = session.light_score.map(\.time) == session.light_score.map(\.time).sorted()
        return (validFrequencies && validIntensities && sortedTimes) ? 1.0 : 0.0
    }
}
