//
//  AnalyzerMutationEngine.swift
//  Ilumionate
//
//  Deterministic mutation/crossover helpers for analyzer optimization.
//

import Foundation

struct AnalyzerMutationEngine {
    struct Parameters: Sendable {
        var keywordWeightSigma: Double = 0.18
        var contextWindowDelta: Int = 3
        var smoothingWindowDelta: Int = 2
        var minimumPhaseDurationDelta: Int = 12
        var collapseThresholdSigma: Double = 0.20
    }

    let parameters: Parameters

    init(parameters: Parameters = .init()) {
        self.parameters = parameters
    }

    func mutate(_ config: AnalyzerConfig) -> AnalyzerConfig {
        var mutated = config

        for (phase, keywords) in mutated.keywordPipeline.weights {
            var nextKeywords = keywords
            for (keyword, weight) in keywords {
                nextKeywords[keyword] = max(0.05, perturb(weight, sigma: parameters.keywordWeightSigma))
            }
            mutated.keywordPipeline.weights[phase] = nextKeywords
        }

        mutated.keywordPipeline.contextWindowSeconds = max(
            1,
            mutated.keywordPipeline.contextWindowSeconds + Int.random(in: -parameters.contextWindowDelta...parameters.contextWindowDelta)
        )
        mutated.keywordPipeline.smoothingWindowSize = max(
            1,
            mutated.keywordPipeline.smoothingWindowSize + Int.random(in: -parameters.smoothingWindowDelta...parameters.smoothingWindowDelta)
        )
        mutated.keywordPipeline.minimumPhaseDurationSeconds = max(
            5,
            mutated.keywordPipeline.minimumPhaseDurationSeconds + Int.random(in: -parameters.minimumPhaseDurationDelta...parameters.minimumPhaseDurationDelta)
        )
        mutated.keywordPipeline.collapseThresholdFraction = clamp(
            perturb(mutated.keywordPipeline.collapseThresholdFraction, sigma: parameters.collapseThresholdSigma),
            min: 0.01,
            max: 0.50
        )

        return mutated
    }

    func crossover(_ lhs: AnalyzerConfig, _ rhs: AnalyzerConfig) -> AnalyzerConfig {
        var child = lhs

        child.keywordPipeline.weights = Bool.random() ? lhs.keywordPipeline.weights : rhs.keywordPipeline.weights
        child.keywordPipeline.contextWindowSeconds = Bool.random()
            ? lhs.keywordPipeline.contextWindowSeconds
            : rhs.keywordPipeline.contextWindowSeconds
        child.keywordPipeline.smoothingWindowSize = Bool.random()
            ? lhs.keywordPipeline.smoothingWindowSize
            : rhs.keywordPipeline.smoothingWindowSize
        child.keywordPipeline.minimumPhaseDurationSeconds = Bool.random()
            ? lhs.keywordPipeline.minimumPhaseDurationSeconds
            : rhs.keywordPipeline.minimumPhaseDurationSeconds
        child.keywordPipeline.collapseThresholdFraction = Bool.random()
            ? lhs.keywordPipeline.collapseThresholdFraction
            : rhs.keywordPipeline.collapseThresholdFraction

        return child
    }

    private func perturb(_ value: Double, sigma: Double) -> Double {
        let noise = gaussianRandom() * sigma
        return value * (1.0 + noise)
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private func gaussianRandom() -> Double {
        let u1 = Double.random(in: Double.ulpOfOne...1.0)
        let u2 = Double.random(in: 0.0...1.0)
        return (-2.0 * log(u1)).squareRoot() * cos(2.0 * .pi * u2)
    }
}
