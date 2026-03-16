//
//  AIAnalysisManager+Parsing.swift
//  Ilumionate
//
//  Hypnosis metadata and temporal analysis helpers for AIAnalysisManager.
//  Kept separate to stay within SwiftLint file_length limits.
//

import Foundation

// MARK: - Metadata Parsing

extension AIAnalysisManager {

    func buildHypnosisMetadata(
        contentType: AnalysisResult.ContentType,
        phases: [AIPhaseSegment]
    ) -> HypnosisMetadata? {
        guard contentType == .hypnosis, !phases.isEmpty else { return nil }

        let phaseSegments = phases.compactMap { segment -> PhaseSegment? in
            guard let phase = HypnosisMetadata.Phase(rawValue: segment.phase) else { return nil }
            let confidence = parseConfidence(segment.confidenceLevel)
            return PhaseSegment(
                phase: phase,
                startTime: segment.startTime,
                endTime: segment.endTime,
                characteristics: segment.characteristics,
                tranceDepthEstimate: max(0, min(1, segment.tranceDepth)),
                confidenceLevel: confidence
            )
        }

        guard !phaseSegments.isEmpty else { return nil }

        return HypnosisMetadata(
            phases: phaseSegments,
            inductionStyle: nil,
            estimatedTranceDeph: estimateTranceDephFromPhases(phaseSegments),
            suggestionDensity: nil,
            languagePatterns: [],
            detectedTechniques: []
        )
    }

    func parseConfidence(_ raw: String) -> HypnosisMetadata.ConfidenceLevel {
        switch raw.lowercased() {
        case "high":   return .high
        case "low":    return .low
        default:       return .medium
        }
    }

    func estimateTranceDephFromPhases(_ phases: [PhaseSegment]) -> HypnosisMetadata.TranceDeph {
        let maxDepth = phases.map { $0.tranceDepthEstimate }.max() ?? 0.5
        switch maxDepth {
        case 0.8...:   return .somnambulism
        case 0.6...:   return .deep
        case 0.35...:  return .medium
        default:       return .light
        }
    }

    func buildTemporalAnalysis(
        curve: [Double],
        duration: TimeInterval
    ) -> TemporalAnalysis? {
        guard curve.count >= 3 else { return nil }
        let samplingInterval = duration / Double(curve.count)
        return TemporalAnalysis(
            tranceDepthCurve: curve,
            receptivityLevels: curve,
            emotionalArc: [],
            samplingInterval: samplingInterval
        )
    }
}
