//
//  AnalyzerMutationEngine.swift
//  Ilumionate
//
//  Deterministic mutation/crossover helpers for analyzer optimization.
//

import Foundation

struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private(set) var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    init(state: UInt64) {
        self.state = state == 0 ? 0x9E37_79B9_7F4A_7C15 : state
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

struct AnalyzerMutationEngine: Sendable {
    private struct SearchAxes {
        let keywordPipeline: Bool
        let chunkedAnalyzer: Bool
        let hybridSelection: Bool
        let corpusLearning: Bool
        let boundaryRefinement: Bool
    }

    struct Parameters: Sendable {
        var keywordWeightSigma: Double = 0.18
        var contextWindowDelta: Int = 3
        var smoothingWindowDelta: Int = 2
        var minimumPhaseDurationDelta: Int = 12
        var collapseThresholdSigma: Double = 0.20
        var chunkDurationSigma: Double = 0.20
        var chunkOverlapSigma: Double = 0.25
        var chunkCountDelta: Int = 4
        var selectionSigma: Double = 0.22
        var corpusLearningSigma: Double = 0.20
        var boundarySigma: Double = 0.18
    }

    let parameters: Parameters

    init(parameters: Parameters = .init()) {
        self.parameters = parameters
    }

    func mutate(
        _ config: AnalyzerConfig,
        for mode: AnalyzerEvaluationMode = .hybridRuntime
    ) -> AnalyzerConfig {
        var rng = SystemRandomNumberGenerator()
        return mutate(config, for: mode, using: &rng)
    }

    func mutate<RNG: RandomNumberGenerator>(
        _ config: AnalyzerConfig,
        for mode: AnalyzerEvaluationMode = .hybridRuntime,
        using rng: inout RNG
    ) -> AnalyzerConfig {
        var mutated = config
        let axes = searchAxes(for: mode)

        if axes.keywordPipeline {
            for (phase, keywords) in mutated.keywordPipeline.weights {
                var nextKeywords = keywords
                for (keyword, weight) in keywords {
                    nextKeywords[keyword] = max(0.05, perturb(weight, sigma: parameters.keywordWeightSigma, using: &rng))
                }
                mutated.keywordPipeline.weights[phase] = nextKeywords
            }

            mutated.keywordPipeline.contextWindowSeconds = max(
                1,
                mutated.keywordPipeline.contextWindowSeconds + Int.random(in: -parameters.contextWindowDelta...parameters.contextWindowDelta, using: &rng)
            )
            mutated.keywordPipeline.smoothingWindowSize = max(
                1,
                mutated.keywordPipeline.smoothingWindowSize + Int.random(in: -parameters.smoothingWindowDelta...parameters.smoothingWindowDelta, using: &rng)
            )
            mutated.keywordPipeline.minimumPhaseDurationSeconds = max(
                5,
                mutated.keywordPipeline.minimumPhaseDurationSeconds + Int.random(in: -parameters.minimumPhaseDurationDelta...parameters.minimumPhaseDurationDelta, using: &rng)
            )
            mutated.keywordPipeline.collapseThresholdFraction = clamp(
                perturb(mutated.keywordPipeline.collapseThresholdFraction, sigma: parameters.collapseThresholdSigma, using: &rng),
                min: 0.01,
                max: 0.50
            )
        }

        if axes.chunkedAnalyzer {
            mutated.chunkedAnalyzer.chunkDurationSeconds = clamp(
                perturb(mutated.chunkedAnalyzer.chunkDurationSeconds, sigma: parameters.chunkDurationSigma, using: &rng),
                min: 8.0,
                max: 45.0
            )
            mutated.chunkedAnalyzer.chunkOverlapSeconds = clamp(
                perturb(mutated.chunkedAnalyzer.chunkOverlapSeconds, sigma: parameters.chunkOverlapSigma, using: &rng),
                min: 1.0,
                max: min(mutated.chunkedAnalyzer.chunkDurationSeconds * 0.75, 18.0)
            )
            mutated.chunkedAnalyzer.minChunks = max(
                2,
                mutated.chunkedAnalyzer.minChunks + Int.random(in: -parameters.chunkCountDelta...parameters.chunkCountDelta, using: &rng)
            )
            mutated.chunkedAnalyzer.maxChunks = max(
                mutated.chunkedAnalyzer.minChunks,
                mutated.chunkedAnalyzer.maxChunks + Int.random(in: -(parameters.chunkCountDelta * 2)...(parameters.chunkCountDelta * 2), using: &rng)
            )
        }

        if axes.hybridSelection {
            mutated.hybridSelection.techniqueAlignmentWeight = clamp(
                perturb(mutated.hybridSelection.techniqueAlignmentWeight, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.40
            )
            mutated.hybridSelection.chunkedClearWinMargin = clamp(
                perturb(mutated.hybridSelection.chunkedClearWinMargin, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.20
            )
            mutated.hybridSelection.chunkedCoverageWinMargin = clamp(
                perturb(mutated.hybridSelection.chunkedCoverageWinMargin, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.12
            )
            mutated.hybridSelection.keywordCollapsedMargin = clamp(
                perturb(mutated.hybridSelection.keywordCollapsedMargin, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.12
            )
            mutated.hybridSelection.ensembleCompetitiveMargin = clamp(
                perturb(mutated.hybridSelection.ensembleCompetitiveMargin, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.12
            )
            mutated.hybridSelection.ensembleDisagreementThreshold = clamp(
                perturb(mutated.hybridSelection.ensembleDisagreementThreshold, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.40
            )
            mutated.hybridSelection.ensembleChunkedSourceLead = clamp(
                perturb(mutated.hybridSelection.ensembleChunkedSourceLead, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.15
            )
            mutated.hybridSelection.transcriptSupportWeight = clamp(
                perturb(mutated.hybridSelection.transcriptSupportWeight, sigma: parameters.selectionSigma, using: &rng),
                min: 0.10,
                max: 1.20
            )
            mutated.hybridSelection.techniqueSupportWeight = clamp(
                perturb(mutated.hybridSelection.techniqueSupportWeight, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.60
            )
            mutated.hybridSelection.keywordVoteScale = clamp(
                perturb(mutated.hybridSelection.keywordVoteScale, sigma: parameters.selectionSigma, using: &rng),
                min: 0.05,
                max: 0.90
            )
            mutated.hybridSelection.keywordVoteBias = clamp(
                perturb(mutated.hybridSelection.keywordVoteBias, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.40
            )
            mutated.hybridSelection.consensusBonus = clamp(
                perturb(mutated.hybridSelection.consensusBonus, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.50
            )
            mutated.hybridSelection.continuityBonus = clamp(
                perturb(mutated.hybridSelection.continuityBonus, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.30
            )
            mutated.hybridSelection.backwardJumpPenalty = clamp(
                perturb(mutated.hybridSelection.backwardJumpPenalty, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.30
            )
            mutated.hybridSelection.transitionPriorWeight = clamp(
                perturb(mutated.hybridSelection.transitionPriorWeight, sigma: parameters.selectionSigma, using: &rng),
                min: 0.0,
                max: 0.40
            )
        }

        if axes.corpusLearning {
            mutated.corpusLearning.learnedKeywordWeightMultiplier = clamp(
                perturb(mutated.corpusLearning.learnedKeywordWeightMultiplier, sigma: parameters.corpusLearningSigma, using: &rng),
                min: 0.20,
                max: 3.0
            )
            mutated.corpusLearning.learnedPhraseWeightMultiplier = clamp(
                perturb(mutated.corpusLearning.learnedPhraseWeightMultiplier, sigma: parameters.corpusLearningSigma, using: &rng),
                min: 0.20,
                max: 3.0
            )
            mutated.corpusLearning.transitionPriorMultiplier = clamp(
                perturb(mutated.corpusLearning.transitionPriorMultiplier, sigma: parameters.corpusLearningSigma, using: &rng),
                min: 0.0,
                max: 3.0
            )
        }

        if axes.boundaryRefinement {
            mutated.boundaryRefinement.minimumSideDurationFactor = clamp(
                perturb(mutated.boundaryRefinement.minimumSideDurationFactor, sigma: parameters.boundarySigma, using: &rng),
                min: 0.15,
                max: 0.90
            )
            mutated.boundaryRefinement.searchRadiusFactor = clamp(
                perturb(mutated.boundaryRefinement.searchRadiusFactor, sigma: parameters.boundarySigma, using: &rng),
                min: 0.10,
                max: 0.80
            )
            mutated.boundaryRefinement.windowFactor = clamp(
                perturb(mutated.boundaryRefinement.windowFactor, sigma: parameters.boundarySigma, using: &rng),
                min: 0.20,
                max: 0.95
            )
            mutated.boundaryRefinement.phaseSupportWeight = clamp(
                perturb(mutated.boundaryRefinement.phaseSupportWeight, sigma: parameters.boundarySigma, using: &rng),
                min: 0.05,
                max: 0.70
            )
            mutated.boundaryRefinement.phaseSeparationWeight = clamp(
                perturb(mutated.boundaryRefinement.phaseSeparationWeight, sigma: parameters.boundarySigma, using: &rng),
                min: 0.0,
                max: 0.50
            )
            mutated.boundaryRefinement.paceShiftWeight = clamp(
                perturb(mutated.boundaryRefinement.paceShiftWeight, sigma: parameters.boundarySigma, using: &rng),
                min: 0.0,
                max: 0.30
            )
            mutated.boundaryRefinement.repetitionShiftWeight = clamp(
                perturb(mutated.boundaryRefinement.repetitionShiftWeight, sigma: parameters.boundarySigma, using: &rng),
                min: 0.0,
                max: 0.35
            )
            mutated.boundaryRefinement.lexicalShiftWeight = clamp(
                perturb(mutated.boundaryRefinement.lexicalShiftWeight, sigma: parameters.boundarySigma, using: &rng),
                min: 0.0,
                max: 0.25
            )
            mutated.boundaryRefinement.coverageShiftWeight = clamp(
                perturb(mutated.boundaryRefinement.coverageShiftWeight, sigma: parameters.boundarySigma, using: &rng),
                min: 0.0,
                max: 0.20
            )
            mutated.boundaryRefinement.distancePenaltyWeight = clamp(
                perturb(mutated.boundaryRefinement.distancePenaltyWeight, sigma: parameters.boundarySigma, using: &rng),
                min: 0.0,
                max: 0.10
            )
        }

        return mutated
    }

    func crossover(
        _ lhs: AnalyzerConfig,
        _ rhs: AnalyzerConfig,
        for mode: AnalyzerEvaluationMode = .hybridRuntime
    ) -> AnalyzerConfig {
        var rng = SystemRandomNumberGenerator()
        return crossover(lhs, rhs, for: mode, using: &rng)
    }

    func crossover<RNG: RandomNumberGenerator>(
        _ lhs: AnalyzerConfig,
        _ rhs: AnalyzerConfig,
        for mode: AnalyzerEvaluationMode = .hybridRuntime,
        using rng: inout RNG
    ) -> AnalyzerConfig {
        var child = lhs
        let axes = searchAxes(for: mode)

        if axes.keywordPipeline {
            child.keywordPipeline.weights = Bool.random(using: &rng) ? lhs.keywordPipeline.weights : rhs.keywordPipeline.weights
            child.keywordPipeline.contextWindowSeconds = Bool.random(using: &rng)
                ? lhs.keywordPipeline.contextWindowSeconds
                : rhs.keywordPipeline.contextWindowSeconds
            child.keywordPipeline.smoothingWindowSize = Bool.random(using: &rng)
                ? lhs.keywordPipeline.smoothingWindowSize
                : rhs.keywordPipeline.smoothingWindowSize
            child.keywordPipeline.minimumPhaseDurationSeconds = Bool.random(using: &rng)
                ? lhs.keywordPipeline.minimumPhaseDurationSeconds
                : rhs.keywordPipeline.minimumPhaseDurationSeconds
            child.keywordPipeline.collapseThresholdFraction = Bool.random(using: &rng)
                ? lhs.keywordPipeline.collapseThresholdFraction
                : rhs.keywordPipeline.collapseThresholdFraction
        }
        if axes.chunkedAnalyzer {
            child.chunkedAnalyzer = Bool.random(using: &rng) ? lhs.chunkedAnalyzer : rhs.chunkedAnalyzer
        }
        if axes.hybridSelection {
            child.hybridSelection = Bool.random(using: &rng) ? lhs.hybridSelection : rhs.hybridSelection
        }
        if axes.corpusLearning {
            child.corpusLearning = Bool.random(using: &rng) ? lhs.corpusLearning : rhs.corpusLearning
        }
        if axes.boundaryRefinement {
            child.boundaryRefinement = Bool.random(using: &rng) ? lhs.boundaryRefinement : rhs.boundaryRefinement
        }

        return child
    }

    private func searchAxes(for mode: AnalyzerEvaluationMode) -> SearchAxes {
        switch mode {
        case .keywordOnly:
            return SearchAxes(
                keywordPipeline: true,
                chunkedAnalyzer: false,
                hybridSelection: false,
                corpusLearning: true,
                boundaryRefinement: true
            )
        case .chunkedOnly:
            return SearchAxes(
                keywordPipeline: false,
                chunkedAnalyzer: true,
                hybridSelection: false,
                corpusLearning: true,
                boundaryRefinement: true
            )
        case .hybridRuntime:
            return SearchAxes(
                keywordPipeline: true,
                chunkedAnalyzer: true,
                hybridSelection: true,
                corpusLearning: true,
                boundaryRefinement: true
            )
        }
    }

    private func perturb<RNG: RandomNumberGenerator>(_ value: Double, sigma: Double, using rng: inout RNG) -> Double {
        let noise = gaussianRandom(using: &rng) * sigma
        return value * (1.0 + noise)
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private func gaussianRandom<RNG: RandomNumberGenerator>(using rng: inout RNG) -> Double {
        let u1 = Double.random(in: Double.ulpOfOne...1.0, using: &rng)
        let u2 = Double.random(in: 0.0...1.0, using: &rng)
        return (-2.0 * log(u1)).squareRoot() * cos(2.0 * .pi * u2)
    }
}
