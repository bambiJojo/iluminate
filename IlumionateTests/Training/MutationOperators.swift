//
//  MutationOperators.swift
//  IlumionateTests
//
//  Per-parameter-type mutation strategies for the evolutionary optimizer.
//

import Foundation
@testable import Ilumionate

struct MutationOperators {

    /// Gaussian perturbation: multiply value by (1 + N(0, sigma)).
    static func perturbDouble(_ value: Double, sigma: Double) -> Double {
        let noise = gaussianRandom() * sigma
        return value * (1.0 + noise)
    }

    /// Integer perturbation: add random from [-delta, delta].
    static func perturbInt(_ value: Int, delta: Int) -> Int {
        value + Int.random(in: -delta...delta)
    }

    /// Shift a frequency band boundary by up to +/-maxShift Hz.
    static func perturbFrequencyBand(
        _ band: AnalyzerConfig.SessionGeneration.FrequencyBand,
        maxShift: Double = 1.0
    ) -> AnalyzerConfig.SessionGeneration.FrequencyBand {
        let newLower = max(0.5, band.lower + Double.random(in: -maxShift...maxShift))
        let newUpper = max(newLower + 0.5, band.upper + Double.random(in: -maxShift...maxShift))
        return .init(lower: newLower, upper: newUpper)
    }

    // MARK: - Keyword Weight Mutation

    /// Perturb all keyword weights by +/-20%.
    static func mutateKeywordWeights(
        _ weights: [String: [String: Double]]
    ) -> [String: [String: Double]] {
        var result = weights
        for (phase, keywords) in weights {
            var mutated = keywords
            for (keyword, weight) in keywords {
                mutated[keyword] = max(0.1, perturbDouble(weight, sigma: 0.20))
            }
            result[phase] = mutated
        }
        return result
    }

    // MARK: - Section Mutators

    static func mutateKeywordPipeline(
        _ pipeline: AnalyzerConfig.KeywordPipeline
    ) -> AnalyzerConfig.KeywordPipeline {
        var p = pipeline
        p.weights = mutateKeywordWeights(p.weights)
        p.contextWindowSeconds = max(1, perturbInt(p.contextWindowSeconds, delta: 2))
        p.smoothingWindowSize = max(1, perturbInt(p.smoothingWindowSize, delta: 2))
        p.minimumPhaseDurationSeconds = max(10, perturbInt(p.minimumPhaseDurationSeconds, delta: 10))
        p.collapseThresholdFraction = max(0.01, perturbDouble(p.collapseThresholdFraction, sigma: 0.30))
        return p
    }

    static func mutateChunkedAnalyzer(
        _ chunked: AnalyzerConfig.ChunkedAnalyzer,
        labeledCorpus: [LabeledFile]
    ) -> AnalyzerConfig.ChunkedAnalyzer {
        var c = chunked
        c.chunkDurationSeconds = max(5.0, perturbDouble(c.chunkDurationSeconds, sigma: 0.30))
        c.chunkOverlapSeconds = max(1.0, perturbDouble(c.chunkOverlapSeconds, sigma: 0.30))
        c.minChunks = max(2, perturbInt(c.minChunks, delta: 2))
        c.maxChunks = max(c.minChunks + 1, perturbInt(c.maxChunks, delta: 5))

        // Few-shot mutation: add/remove/replace from labeled corpus
        if !labeledCorpus.isEmpty && Bool.random() {
            c.fewShotExamples = generateFewShotExamples(from: labeledCorpus, count: Int.random(in: 1...3))
        }

        return c
    }

    static func mutateProsody(
        _ prosody: AnalyzerConfig.Prosody
    ) -> AnalyzerConfig.Prosody {
        var p = prosody
        p.speechRateWindowSeconds = max(1.0, perturbDouble(p.speechRateWindowSeconds, sigma: 0.30))
        p.pauseThresholdSeconds = max(0.3, perturbDouble(p.pauseThresholdSeconds, sigma: 0.30))
        p.deliberatePauseMinSeconds = max(1.0, perturbDouble(p.deliberatePauseMinSeconds, sigma: 0.30))
        p.musicOnlyPauseMinSeconds = max(2.0, perturbDouble(p.musicOnlyPauseMinSeconds, sigma: 0.30))
        return p
    }

    static func mutateTechniqueDetection(
        _ td: AnalyzerConfig.TechniqueDetection
    ) -> AnalyzerConfig.TechniqueDetection {
        var t = td
        t.sensitivityThreshold = max(0.1, min(1.0, perturbDouble(t.sensitivityThreshold, sigma: 0.15)))
        t.minConfidence = max(0.1, min(1.0, perturbDouble(t.minConfidence, sigma: 0.15)))
        return t
    }

    static func mutateSessionGeneration(
        _ sg: AnalyzerConfig.SessionGeneration
    ) -> AnalyzerConfig.SessionGeneration {
        var s = sg
        for (key, band) in s.frequencyBands {
            s.frequencyBands[key] = perturbFrequencyBand(band)
        }
        s.transitionSmoothingSeconds = max(1.0, perturbDouble(s.transitionSmoothingSeconds, sigma: 0.30))
        return s
    }

    // MARK: - Full Config Mutation

    static func mutate(
        _ config: AnalyzerConfig,
        labeledCorpus: [LabeledFile]
    ) -> AnalyzerConfig {
        var c = config
        c.keywordPipeline = mutateKeywordPipeline(c.keywordPipeline)
        c.chunkedAnalyzer = mutateChunkedAnalyzer(c.chunkedAnalyzer, labeledCorpus: labeledCorpus)
        c.prosody = mutateProsody(c.prosody)
        c.techniqueDetection = mutateTechniqueDetection(c.techniqueDetection)
        c.sessionGeneration = mutateSessionGeneration(c.sessionGeneration)
        return c
    }

    // MARK: - Crossover

    /// Section-level crossover: each section randomly picked from one parent.
    static func crossover(_ a: AnalyzerConfig, _ b: AnalyzerConfig) -> AnalyzerConfig {
        var child = a
        child.keywordPipeline = Bool.random() ? a.keywordPipeline : b.keywordPipeline
        child.chunkedAnalyzer = Bool.random() ? a.chunkedAnalyzer : b.chunkedAnalyzer
        child.prosody = Bool.random() ? a.prosody : b.prosody
        child.techniqueDetection = Bool.random() ? a.techniqueDetection : b.techniqueDetection
        child.sessionGeneration = Bool.random() ? a.sessionGeneration : b.sessionGeneration
        return child
    }

    // MARK: - Few-Shot Generation

    static func generateFewShotExamples(
        from corpus: [LabeledFile],
        count: Int
    ) -> [AnalyzerConfig.ChunkedAnalyzer.FewShotExample] {
        var examples: [AnalyzerConfig.ChunkedAnalyzer.FewShotExample] = []
        for _ in 0..<count {
            guard let file = corpus.randomElement(),
                  let phase = file.phases.randomElement() else { continue }
            let position = phase.startTime / max(file.audioDuration, 1)
            examples.append(.init(
                text: "[\(phase.phase.displayName) segment at \(Int(position * 100))%]",
                position: position,
                correctPhase: phase.phase.rawValue
            ))
        }
        return examples
    }

    // MARK: - Gaussian Random

    /// Box-Muller transform for normal distribution.
    private static func gaussianRandom() -> Double {
        let u1 = Double.random(in: Double.ulpOfOne...1.0)
        let u2 = Double.random(in: 0.0...1.0)
        return (-2.0 * log(u1)).squareRoot() * cos(2.0 * .pi * u2)
    }
}
