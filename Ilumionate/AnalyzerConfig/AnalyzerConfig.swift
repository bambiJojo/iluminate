//
//  AnalyzerConfig.swift
//  Ilumionate
//
//  Single JSON-driven configuration for all analyzer components.
//  The evolutionary pipeline mutates this to improve accuracy.
//

import Foundation

enum CorpusSourceProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case general
    case therapeutic
    case eroticConditioning
    case sourceDiagnostic

    static let userDefaultsKey = "analysisPref_corpusSourceProfile"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general:
            return "General"
        case .therapeutic:
            return "Therapeutic"
        case .eroticConditioning:
            return "Erotic / Conditioning"
        case .sourceDiagnostic:
            return "Source Diagnostic"
        }
    }

    var description: String {
        switch self {
        case .general:
            return "Keeps adult source packs present but damped for broad hypnosis analysis."
        case .therapeutic:
            return "Suppresses adult source packs for meditation, therapeutic, and general wellness content."
        case .eroticConditioning:
            return "Boosts adult conditioning source packs for erotic hypnosis and post-hypnotic language."
        case .sourceDiagnostic:
            return "Uses source packs at full strength so learned corpus effects are easier to inspect."
        }
    }

    var sfSymbol: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .therapeutic:
            return "cross.case.fill"
        case .eroticConditioning:
            return "sparkles"
        case .sourceDiagnostic:
            return "waveform.path.ecg"
        }
    }

    static func storedSelection(defaults: UserDefaults = .standard) -> CorpusSourceProfile? {
        guard defaults.object(forKey: userDefaultsKey) != nil else { return nil }
        return CorpusSourceProfile(rawValue: defaults.string(forKey: userDefaultsKey) ?? "")
    }

    nonisolated func multiplier(for sourcePackID: String, phase: HypnosisMetadata.Phase) -> Double {
        switch (self, sourcePackID) {
        case (.therapeutic, "bambi"):
            return 0.0
        case (.general, "bambi"):
            return 0.35
        case (.eroticConditioning, "bambi"):
            switch phase.labelingPhase {
            case .brainwashing, .conditioning, .suggestions, .eroticSuggestions:
                return 1.25
            case .deepening, .induction:
                return 0.80
            default:
                return 0.60
            }
        case (.sourceDiagnostic, "bambi"):
            return 1.0
        default:
            return 1.0
        }
    }
}

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
            let canonicalPhase = phase.labelingPhase
            var phaseWeights = weights[canonicalPhase.rawValue] ?? [:]
            for alias in mergedAliasPhases(for: canonicalPhase) {
                for (keyword, weight) in weights[alias.rawValue] ?? [:] {
                    phaseWeights[keyword] = max(phaseWeights[keyword] ?? 0.0, weight)
                }
            }
            return phaseWeights
        }

        private func mergedAliasPhases(for canonicalPhase: HypnosisMetadata.Phase) -> [HypnosisMetadata.Phase] {
            switch canonicalPhase {
            case .induction:
                return [.preTalk]
            case .deepening:
                return [.fractionation, .confusion]
            default:
                return []
            }
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
            var sourcePackID: String? = nil
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
        var sourceProfile: CorpusSourceProfile = .general
        var sourcePackWeightMultipliers: [String: Double] = [:]

        nonisolated init(
            learnedKeywordWeightMultiplier: Double = 1.0,
            learnedPhraseWeightMultiplier: Double = 1.0,
            transitionPriorMultiplier: Double = 1.0,
            sourceProfile: CorpusSourceProfile = .general,
            sourcePackWeightMultipliers: [String: Double] = [:]
        ) {
            self.learnedKeywordWeightMultiplier = learnedKeywordWeightMultiplier
            self.learnedPhraseWeightMultiplier = learnedPhraseWeightMultiplier
            self.transitionPriorMultiplier = transitionPriorMultiplier
            self.sourceProfile = sourceProfile
            self.sourcePackWeightMultipliers = sourcePackWeightMultipliers
        }

        nonisolated func sourceMultiplier(
            for sourcePackIDs: Set<String>,
            phase: HypnosisMetadata.Phase
        ) -> Double {
            guard !sourcePackIDs.isEmpty else { return 1.0 }

            return sourcePackIDs
                .map { sourcePackID in
                    let profileMultiplier = sourceProfile.multiplier(
                        for: sourcePackID,
                        phase: phase
                    )
                    if let configuredMultiplier = sourcePackWeightMultipliers[sourcePackID] {
                        return configuredMultiplier * profileMultiplier
                    }
                    return profileMultiplier
                }
                .max() ?? 1.0
        }

        private enum CodingKeys: String, CodingKey {
            case learnedKeywordWeightMultiplier
            case learnedPhraseWeightMultiplier
            case transitionPriorMultiplier
            case sourceProfile
            case sourcePackWeightMultipliers
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            learnedKeywordWeightMultiplier = try container.decodeIfPresent(
                Double.self,
                forKey: .learnedKeywordWeightMultiplier
            ) ?? 1.0
            learnedPhraseWeightMultiplier = try container.decodeIfPresent(
                Double.self,
                forKey: .learnedPhraseWeightMultiplier
            ) ?? 1.0
            transitionPriorMultiplier = try container.decodeIfPresent(
                Double.self,
                forKey: .transitionPriorMultiplier
            ) ?? 1.0
            sourceProfile = try container.decodeIfPresent(
                CorpusSourceProfile.self,
                forKey: .sourceProfile
            ) ?? .general
            sourcePackWeightMultipliers = try container.decodeIfPresent(
                [String: Double].self,
                forKey: .sourcePackWeightMultipliers
            ) ?? [:]
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(learnedKeywordWeightMultiplier, forKey: .learnedKeywordWeightMultiplier)
            try container.encode(learnedPhraseWeightMultiplier, forKey: .learnedPhraseWeightMultiplier)
            try container.encode(transitionPriorMultiplier, forKey: .transitionPriorMultiplier)
            try container.encode(sourceProfile, forKey: .sourceProfile)
            try container.encode(sourcePackWeightMultipliers, forKey: .sourcePackWeightMultipliers)
        }
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
            let canonicalPhase = phase.labelingPhase
            return phaseFrequencyBands[canonicalPhase.rawValue]
                ?? phaseFrequencyBands[phase.rawValue]
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
