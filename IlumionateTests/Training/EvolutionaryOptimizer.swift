//
//  EvolutionaryOptimizer.swift
//  IlumionateTests
//
//  Population management, selection, and generational evolution.
//

import Foundation
@testable import Ilumionate

struct EvolutionaryOptimizer {

    struct Parameters {
        var populationSize: Int = 10
        var maxGenerations: Int = 20
        var elitismCount: Int = 3
        var mutationRate: Double = 0.8
        var earlyStopPatience: Int = 5
    }

    struct GenerationResult {
        let generation: Int
        let bestFitness: Double
        let averageFitness: Double
        let bestConfig: AnalyzerConfig
    }

    let params: Parameters
    let labeledCorpus: [LabeledFile]

    /// Evaluates a single config against the entire labeled corpus.
    /// Uses keyword pipeline only (fast) — Foundation Models evaluation
    /// is handled separately in PipelineRunner when the flag is set.
    @MainActor
    func evaluateConfig(
        _ config: AnalyzerConfig
    ) -> Double {
        let keywordAnalyzer = HypnosisPhaseAnalyzer(config: config.keywordPipeline)
        let sessionGenerator = SessionGenerator(config: config.sessionGeneration)
        let fitnessEvaluator = FitnessEvaluator()

        var totalFitness: Double = 0

        for labeledFile in labeledCorpus {
            // Build a synthetic transcription from the labeled file
            let audioFile = AudioFile(
                filename: labeledFile.audioFilename,
                duration: labeledFile.audioDuration,
                fileSize: 0
            )

            // Run keyword analyzer with empty segments (keyword-only eval)
            let phases = keywordAnalyzer.analyze(
                segments: [],
                duration: labeledFile.audioDuration
            )

            let metadata = HypnosisMetadata(
                phases: phases,
                inductionStyle: .permissive,
                estimatedTranceDeph: .medium,
                suggestionDensity: nil,
                languagePatterns: [],
                detectedTechniques: []
            )

            let result = AnalysisResult(
                mood: .meditative,
                energyLevel: 0.3,
                suggestedFrequencyRange: config.sessionGeneration
                    .band(for: labeledFile.expectedContentType).closedRange,
                suggestedIntensity: 0.5,
                keyMoments: [],
                aiSummary: "",
                recommendedPreset: "",
                contentType: labeledFile.expectedContentType,
                hypnosisMetadata: metadata
            )

            let session = sessionGenerator.generateSession(from: audioFile, analysis: result)
            totalFitness += fitnessEvaluator.fitness(labeledFile: labeledFile, result: result, session: session)
        }

        return labeledCorpus.isEmpty ? 0 : totalFitness / Double(labeledCorpus.count)
    }

    @MainActor
    private func seedPopulation(from seed: AnalyzerConfig) -> [(config: AnalyzerConfig, fitness: Double)] {
        var population: [(config: AnalyzerConfig, fitness: Double)] = []
        population.append((seed, evaluateConfig(seed)))
        for _ in 1..<params.populationSize {
            let mutated = MutationOperators.mutate(seed, labeledCorpus: labeledCorpus)
            population.append((mutated, evaluateConfig(mutated)))
        }
        return population
    }

    @MainActor
    private func nextGeneration(
        from population: [(config: AnalyzerConfig, fitness: Double)],
        elites: [(config: AnalyzerConfig, fitness: Double)]
    ) -> [(config: AnalyzerConfig, fitness: Double)] {
        var nextGen = elites
        while nextGen.count < params.populationSize {
            let parent: AnalyzerConfig
            if nextGen.count < params.elitismCount + 2 && population.count >= 2 {
                parent = MutationOperators.crossover(population[0].config, population[1].config)
            } else {
                parent = elites.randomElement()!.config
            }
            let child = Double.random(in: 0...1) < params.mutationRate
                ? MutationOperators.mutate(parent, labeledCorpus: labeledCorpus)
                : parent
            nextGen.append((child, evaluateConfig(child)))
        }
        return nextGen
    }

    /// Runs the full evolutionary loop and returns generation history.
    @MainActor
    func run(
        seed: AnalyzerConfig,
        onGeneration: ((GenerationResult) -> Void)? = nil
    ) -> (bestConfig: AnalyzerConfig, history: [GenerationResult]) {
        var population = seedPopulation(from: seed)
        var history: [GenerationResult] = []
        var bestEverFitness: Double = 0
        var bestEverConfig = seed
        var stagnantGenerations = 0

        for gen in 0..<params.maxGenerations {
            // Sort by fitness descending
            population.sort { $0.fitness > $1.fitness }

            let bestFitness = population[0].fitness
            let avgFitness = population.map(\.fitness).reduce(0, +) / Double(population.count)

            var bestConfig = population[0].config
            bestConfig.generation = gen
            bestConfig.fitness = bestFitness

            let result = GenerationResult(
                generation: gen,
                bestFitness: bestFitness,
                averageFitness: avgFitness,
                bestConfig: bestConfig
            )
            history.append(result)
            onGeneration?(result)

            let bestStr = bestFitness.formatted(.number.precision(.fractionLength(4)))
            let avgStr = avgFitness.formatted(.number.precision(.fractionLength(4)))
            print("Gen \(gen): best=\(bestStr), avg=\(avgStr)")

            // Track best ever
            if bestFitness > bestEverFitness {
                bestEverFitness = bestFitness
                bestEverConfig = bestConfig
                stagnantGenerations = 0
            } else {
                stagnantGenerations += 1
            }

            // Early stopping
            if stagnantGenerations >= params.earlyStopPatience {
                print("🛑 Early stop: no improvement for \(params.earlyStopPatience) generations")
                break
            }

            let elites = Array(population.prefix(params.elitismCount))
            population = nextGeneration(from: population, elites: elites)
        }

        return (bestEverConfig, history)
    }
}
