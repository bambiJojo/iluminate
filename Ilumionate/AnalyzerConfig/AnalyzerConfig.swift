//
//  AnalyzerConfig.swift
//  Ilumionate
//
//  Single JSON-driven configuration for all analyzer components.
//  The evolutionary pipeline mutates this to improve accuracy.
//

import Foundation

struct AnalyzerConfig: Codable, Sendable {

    var version: Int = 1
    var generation: Int = 0
    var fitness: Double = 0.0

    var keywordPipeline: KeywordPipeline
    var chunkedAnalyzer: ChunkedAnalyzer
    var prosody: Prosody
    var techniqueDetection: TechniqueDetection
    var sessionGeneration: SessionGeneration

    // MARK: - Keyword Pipeline

    struct KeywordPipeline: Codable, Sendable {
        /// Phase name (raw value) → keyword → weight
        var weights: [String: [String: Double]]
        var contextWindowSeconds: Int
        var smoothingWindowSize: Int
        var minimumPhaseDurationSeconds: Int
        var collapseThresholdFraction: Double

        func weightsForPhase(_ phase: HypnosisMetadata.Phase) -> [String: Double] {
            weights[phase.rawValue] ?? [:]
        }
    }

    // MARK: - Chunked Analyzer (Foundation Models)

    struct ChunkedAnalyzer: Codable, Sendable {
        var chunkDurationSeconds: Double
        var chunkOverlapSeconds: Double
        var minChunks: Int
        var maxChunks: Int
        var systemInstructions: String
        var fewShotExamples: [FewShotExample]

        struct FewShotExample: Codable, Sendable {
            var text: String
            var position: Double
            var correctPhase: String
        }
    }

    // MARK: - Prosody

    struct Prosody: Codable, Sendable {
        var speechRateWindowSeconds: Double
        var pauseThresholdSeconds: Double
        var deliberatePauseMinSeconds: Double
        var musicOnlyPauseMinSeconds: Double
    }

    // MARK: - Technique Detection

    struct TechniqueDetection: Codable, Sendable {
        var sensitivityThreshold: Double
        var minConfidence: Double
    }

    // MARK: - Session Generation

    struct SessionGeneration: Codable, Sendable {
        var frequencyBands: [String: FrequencyBand]
        var transitionSmoothingSeconds: Double
        var intensityCurve: String

        struct FrequencyBand: Codable, Sendable {
            var lower: Double
            var upper: Double

            var closedRange: ClosedRange<Double> { lower...upper }
        }

        func band(for contentType: AnalysisResult.ContentType) -> FrequencyBand {
            frequencyBands[contentType.rawValue] ?? FrequencyBand(lower: 8.0, upper: 12.0)
        }
    }
}
