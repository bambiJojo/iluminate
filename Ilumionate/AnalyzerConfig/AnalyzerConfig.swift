//
//  AnalyzerConfig.swift
//  Ilumionate
//
//  Single JSON-driven configuration for all analyzer components.
//  The evolutionary pipeline mutates this to improve accuracy.
//

import Foundation

struct AnalyzerConfig: Codable, Sendable {

    var version: Int = 2
    var generation: Int = 0
    var fitness: Double = 0.0

    var keywordPipeline: KeywordPipeline
    var chunkedAnalyzer: ChunkedAnalyzer
    var prosody: Prosody
    var techniqueDetection: TechniqueDetection
    var hybridSelection: HybridSelection
    var corpusLearning: CorpusLearning
    var boundaryRefinement: BoundaryRefinement
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

    // MARK: - Hybrid Selection

    struct HybridSelection: Codable, Sendable {
        var techniqueAlignmentWeight: Double = 0.12
        var chunkedClearWinMargin: Double = 0.05
        var chunkedCoverageWinMargin: Double = 0.015
        var keywordCollapsedMargin: Double = 0.02
        var ensembleCompetitiveMargin: Double = 0.03
        var ensembleDisagreementThreshold: Double = 0.12
        var ensembleChunkedSourceLead: Double = 0.03
        var transcriptSupportWeight: Double = 0.55
        var techniqueSupportWeight: Double = 0.22
        var keywordVoteScale: Double = 0.45
        var keywordVoteBias: Double = 0.15
        var consensusBonus: Double = 0.18
        var continuityBonus: Double = 0.08
        var backwardJumpPenalty: Double = 0.05
        var transitionPriorWeight: Double = 0.12
    }

    // MARK: - Corpus Learning

    struct CorpusLearning: Codable, Sendable {
        var learnedKeywordWeightMultiplier: Double = 1.0
        var learnedPhraseWeightMultiplier: Double = 1.0
        var transitionPriorMultiplier: Double = 1.0
    }

    // MARK: - Boundary Refinement

    struct BoundaryRefinement: Codable, Sendable {
        var minimumSideDurationFactor: Double = 0.45
        var minimumSideDurationFloor: Double = 6.0
        var minimumSideDurationCeiling: Double = 10.0
        var searchRadiusFactor: Double = 0.35
        var minimumSearchRadiusSeconds: Double = 6.0
        var maximumSearchRadiusSeconds: Double = 18.0
        var windowFactor: Double = 0.55
        var minimumWindowSeconds: Double = 10.0
        var maximumWindowSeconds: Double = 20.0
        var phaseSupportWeight: Double = 0.34
        var phaseSeparationWeight: Double = 0.18
        var paceShiftWeight: Double = 0.12
        var repetitionShiftWeight: Double = 0.16
        var lexicalShiftWeight: Double = 0.10
        var coverageShiftWeight: Double = 0.06
        var distancePenaltyWeight: Double = 0.015
    }

    // MARK: - Session Generation

    struct SessionGeneration: Codable, Sendable {
        var frequencyBands: [String: FrequencyBand]
        /// Per-hypnosis-phase frequency bands keyed by `HypnosisMetadata.Phase.rawValue`.
        var phaseFrequencyBands: [String: FrequencyBand]
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

        func phaseBand(for phase: HypnosisMetadata.Phase) -> FrequencyBand? {
            phaseFrequencyBands[phase.rawValue]
        }
    }

    init(
        version: Int = 2,
        generation: Int = 0,
        fitness: Double = 0.0,
        keywordPipeline: KeywordPipeline,
        chunkedAnalyzer: ChunkedAnalyzer,
        prosody: Prosody,
        techniqueDetection: TechniqueDetection,
        hybridSelection: HybridSelection = .init(),
        corpusLearning: CorpusLearning = .init(),
        boundaryRefinement: BoundaryRefinement = .init(),
        sessionGeneration: SessionGeneration
    ) {
        self.version = version
        self.generation = generation
        self.fitness = fitness
        self.keywordPipeline = keywordPipeline
        self.chunkedAnalyzer = chunkedAnalyzer
        self.prosody = prosody
        self.techniqueDetection = techniqueDetection
        self.hybridSelection = hybridSelection
        self.corpusLearning = corpusLearning
        self.boundaryRefinement = boundaryRefinement
        self.sessionGeneration = sessionGeneration
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case generation
        case fitness
        case keywordPipeline
        case chunkedAnalyzer
        case prosody
        case techniqueDetection
        case hybridSelection
        case corpusLearning
        case boundaryRefinement
        case sessionGeneration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        generation = try container.decodeIfPresent(Int.self, forKey: .generation) ?? 0
        fitness = try container.decodeIfPresent(Double.self, forKey: .fitness) ?? 0.0
        keywordPipeline = try container.decode(KeywordPipeline.self, forKey: .keywordPipeline)
        chunkedAnalyzer = try container.decode(ChunkedAnalyzer.self, forKey: .chunkedAnalyzer)
        prosody = try container.decode(Prosody.self, forKey: .prosody)
        techniqueDetection = try container.decode(TechniqueDetection.self, forKey: .techniqueDetection)
        hybridSelection = try container.decodeIfPresent(HybridSelection.self, forKey: .hybridSelection) ?? .init()
        corpusLearning = try container.decodeIfPresent(CorpusLearning.self, forKey: .corpusLearning) ?? .init()
        boundaryRefinement = try container.decodeIfPresent(BoundaryRefinement.self, forKey: .boundaryRefinement) ?? .init()
        sessionGeneration = try container.decode(SessionGeneration.self, forKey: .sessionGeneration)
    }
}
