//
//  AnalyzerOptimizer.swift
//  Ilumionate
//
//  Host-side optimizer that tunes analyzer config against exported training data.
//

import Foundation
import CryptoKit

actor OptimizerProgressCounter {
    var completedUnitCount: Int

    init(initialValue: Int) {
        self.completedUnitCount = initialValue
    }

    func next() -> Int {
        completedUnitCount += 1
        return completedUnitCount
    }
}

struct OptimizerConcurrencyProfile: Sendable {
    let cacheWarmLimit: Int
    let candidateEvaluationLimit: Int
    let fileEvaluationLimit: Int

    static func `for`(
        mode: AnalyzerEvaluationMode,
        processorCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> OptimizerConcurrencyProfile {
        let availableProcessors = max(1, processorCount)

        switch mode {
        case .keywordOnly:
            let totalBudget = max(2, availableProcessors)
            let candidateLimit = max(1, min(4, totalBudget / 2))
            let fileLimit = max(1, min(4, totalBudget / max(candidateLimit, 1)))
            let cacheLimit = max(fileLimit, min(6, totalBudget))
            return OptimizerConcurrencyProfile(
                cacheWarmLimit: cacheLimit,
                candidateEvaluationLimit: candidateLimit,
                fileEvaluationLimit: fileLimit
            )
        case .chunkedOnly:
            return OptimizerConcurrencyProfile(
                cacheWarmLimit: max(1, min(4, availableProcessors / 2)),
                candidateEvaluationLimit: max(1, min(2, availableProcessors / 4)),
                fileEvaluationLimit: max(1, min(2, availableProcessors / 3))
            )
        case .hybridRuntime:
            return OptimizerConcurrencyProfile(
                cacheWarmLimit: max(1, min(4, availableProcessors / 2)),
                candidateEvaluationLimit: 1,
                fileEvaluationLimit: max(1, min(2, availableProcessors / 4))
            )
        }
    }
}

struct AnalyzerOptimizer: Sendable {
    struct Parameters: Codable, Sendable {
        nonisolated static let defaultRandomSeed: UInt64 = 0xA13C_5EED_7F4A_7C15

        var populationSize: Int = 8
        var maxGenerations: Int = 8
        var elitismCount: Int = 2
        var mutationRate: Double = 0.85
        var earlyStopPatience: Int = 4
        var trainFraction: Double = 0.7
        var validationFraction: Double = 0.15
        var evaluationMode: AnalyzerEvaluationMode = .keywordOnly
        var publishBestConfigToDocuments: Bool = false
        var randomSeed: UInt64?

        var effectiveRandomSeed: UInt64 {
            randomSeed ?? Self.defaultRandomSeed
        }

        nonisolated init(
            populationSize: Int = 8,
            maxGenerations: Int = 8,
            elitismCount: Int = 2,
            mutationRate: Double = 0.85,
            earlyStopPatience: Int = 4,
            trainFraction: Double = 0.7,
            validationFraction: Double = 0.15,
            evaluationMode: AnalyzerEvaluationMode = .keywordOnly,
            publishBestConfigToDocuments: Bool = false,
            randomSeed: UInt64? = AnalyzerOptimizer.Parameters.defaultRandomSeed
        ) {
            self.populationSize = populationSize
            self.maxGenerations = maxGenerations
            self.elitismCount = elitismCount
            self.mutationRate = mutationRate
            self.earlyStopPatience = earlyStopPatience
            self.trainFraction = trainFraction
            self.validationFraction = validationFraction
            self.evaluationMode = evaluationMode
            self.publishBestConfigToDocuments = publishBestConfigToDocuments
            self.randomSeed = randomSeed
        }
    }

    struct Progress: Sendable {
        let title: String
        let message: String
        let generation: Int?
        let completedUnitCount: Int?
        let totalUnitCount: Int?
        let isEstimatedTotal: Bool
    }

    struct OutputFiles: Sendable {
        let configURL: URL
        let reportURL: URL
        let diagnosticsURL: URL
        let historyURL: URL
        let scorecardURL: URL
        let scorecardHistoryURL: URL
    }

    struct RunResult: Sendable {
        let bestConfig: AnalyzerConfig
        let report: AnalyzerOptimizationReport
        let scorecard: AnalyzerTrainingMatchScorecard
        let outputFiles: OutputFiles
    }

    struct MeasurementResult: Sendable {
        let scorecard: AnalyzerTrainingMatchScorecard
        let outputURL: URL
        let historyURL: URL
    }

    enum CheckpointStage: String, Codable, Sendable {
        case generationLoop
        case finalization
    }

    struct Checkpoint: Codable, Sendable {
        struct PopulationEntrySnapshot: Codable, Sendable {
            let config: AnalyzerConfig
            let trainingMetrics: AnalyzerOptimizationAggregateMetrics
            let validationMetrics: AnalyzerOptimizationAggregateMetrics
        }

        let schemaVersion: Int
        let savedAt: Date
        let datasetHash: String
        let params: Parameters
        let baseConfig: AnalyzerConfig
        let stage: CheckpointStage
        let nextGeneration: Int
        let progressBase: Int
        let childGenerationCount: Int
        let stagnantGenerations: Int
        let baselineTrainingMetrics: AnalyzerOptimizationAggregateMetrics
        let baselineValidationMetrics: AnalyzerOptimizationAggregateMetrics
        let baselineOverallMetrics: AnalyzerOptimizationAggregateMetrics
        let population: [PopulationEntrySnapshot]
        let bestEntry: PopulationEntrySnapshot
        let bestGeneration: Int
        let bestSelectionScore: Double
        let generationHistory: [AnalyzerOptimizationReport.GenerationSnapshot]
        let randomState: UInt64?
    }

    struct PopulationEntry: Sendable {
        let config: AnalyzerConfig
        let trainingMetrics: AnalyzerOptimizationAggregateMetrics
        let validationMetrics: AnalyzerOptimizationAggregateMetrics
    }

    struct PopulationEvaluationJob: Sendable {
        let config: AnalyzerConfig
        let progressLabel: String
    }

    private enum SplitBucketID: Int, CaseIterable, Sendable {
        case train
        case validation
        case test
    }

    private struct SplitBucket: Sendable {
        let id: SplitBucketID
        let targetCount: Int
        var examples: [AnalyzerOptimizationDataset.Example] = []
        var phaseCounts: [TrancePhase: Int] = [:]

        var remainingCapacity: Int {
            max(0, targetCount - examples.count)
        }

        var hasCapacity: Bool {
            remainingCapacity > 0
        }

        mutating func append(_ example: AnalyzerOptimizationDataset.Example) {
            examples.append(example)
            for phase in AnalyzerOptimizer.phaseSet(for: example) {
                phaseCounts[phase, default: 0] += 1
            }
        }
    }

    let corpusDirectory: URL
    let outputDirectory: URL
    let mutationEngine: AnalyzerMutationEngine

    init(
        corpusDirectory: URL = TrainingCorpusLocation.defaultURL(),
        outputDirectory: URL = URL.documentsDirectory.appending(path: "TrainingOutput"),
        mutationEngine: AnalyzerMutationEngine = .init()
    ) {
        self.corpusDirectory = corpusDirectory
        self.outputDirectory = outputDirectory
        self.mutationEngine = mutationEngine
    }

    func loadDataset() throws -> AnalyzerOptimizationDataset {
        try AnalyzerOptimizationDataset.load(from: corpusDirectory)
    }

    func loadCheckpoint() throws -> Checkpoint? {
        let url = checkpointURL()
        guard FileManager.default.fileExists(atPath: url.path()) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Checkpoint.self, from: Data(contentsOf: url))
    }

    func clearCheckpoint() throws {
        let url = checkpointURL()
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func run(
        seedConfig: AnalyzerConfig? = nil,
        params: Parameters = .init(),
        resumeFrom checkpoint: Checkpoint? = nil,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)? = nil,
        onProgress: (@Sendable (Progress) async -> Void)? = nil,
        pauseRequested: (@Sendable () async -> Bool)? = nil
    ) async throws -> RunResult {
        try Task.checkCancellation()
        let dataset = try loadDataset()
        guard !dataset.examples.isEmpty else {
            throw AnalyzerOptimizerError.emptyDataset
        }

        if checkpoint == nil {
            try? clearCheckpoint()
        }

        let resolvedParams = checkpoint?.params ?? params
        var randomGenerator = SeededRandomNumberGenerator(
            state: checkpoint?.randomState ?? resolvedParams.effectiveRandomSeed
        )
        if let checkpoint, checkpoint.datasetHash != dataset.datasetHash {
            throw AnalyzerOptimizerError.invalidCheckpoint("The saved optimizer checkpoint no longer matches the current analyzer dataset.")
        }

        let split = split(
            dataset.examples,
            trainFraction: resolvedParams.trainFraction,
            validationFraction: resolvedParams.validationFraction
        )
        let concurrencyProfile = OptimizerConcurrencyProfile.for(mode: resolvedParams.evaluationMode)
        let cache = AnalyzerTranscriptCache(cacheDirectory: dataset.transcriptCacheDirectory)
        let engine = AnalyzerEvaluationEngine(mode: resolvedParams.evaluationMode)
        let baseConfig = checkpoint?.baseConfig ?? seedConfig ?? AnalyzerConfigLoader.load()
        let populationSize = max(1, resolvedParams.populationSize)
        let eliteCount = max(1, min(resolvedParams.elitismCount, populationSize))
        let perCandidateUnitCount = split.train.count + split.validation.count
        let preparationUnitCount = dataset.examples.count
        let baselineUnitCount = dataset.examples.count
        let seedPopulationUnitCount = populationSize * perCandidateUnitCount
        let childCountPerGeneration = max(0, populationSize - eliteCount)
        let finalizationUnitCount = dataset.examples.count
        let estimatedTotalUnitCount = preparationUnitCount
            + baselineUnitCount
            + seedPopulationUnitCount
            + (resolvedParams.maxGenerations * childCountPerGeneration * perCandidateUnitCount)
            + finalizationUnitCount
        var childGenerationCount = checkpoint?.childGenerationCount ?? 0
        var progressBase = checkpoint?.progressBase ?? 0
        var baselineTrainingMetrics: AnalyzerOptimizationAggregateMetrics
        var baselineValidationMetrics: AnalyzerOptimizationAggregateMetrics
        var baselineOverallMetrics: AnalyzerOptimizationAggregateMetrics
        var population: [PopulationEntry]
        var history: [AnalyzerOptimizationReport.GenerationSnapshot]
        var stagnantGenerations: Int
        var bestEntry: PopulationEntry
        var bestGeneration: Int
        var bestSelectionScore: Double
        var startGeneration: Int
        let resumeStage = checkpoint?.stage ?? .generationLoop

        if let checkpoint {
            baselineTrainingMetrics = checkpoint.baselineTrainingMetrics
            baselineValidationMetrics = checkpoint.baselineValidationMetrics
            baselineOverallMetrics = checkpoint.baselineOverallMetrics
            population = checkpoint.population.map(populationEntry(from:))
            history = checkpoint.generationHistory
            stagnantGenerations = checkpoint.stagnantGenerations
            bestEntry = populationEntry(from: checkpoint.bestEntry)
            bestGeneration = checkpoint.bestGeneration
            bestSelectionScore = checkpoint.bestSelectionScore
            startGeneration = checkpoint.nextGeneration

            await onProgress?(
                Progress(
                    title: "Optimizing Analyzer",
                    message: "Resuming saved optimizer run from generation \(startGeneration).",
                    generation: startGeneration,
                    completedUnitCount: progressBase,
                    totalUnitCount: estimatedTotalUnitCount,
                    isEstimatedTotal: true
                )
            )
        } else {
            await onProgress?(
                Progress(
                    title: "Optimizing Analyzer",
                    message: "Loaded \(dataset.examples.count) analyzer examples.",
                    generation: nil,
                    completedUnitCount: 0,
                    totalUnitCount: estimatedTotalUnitCount,
                    isEstimatedTotal: true
                )
            )

            try Task.checkCancellation()
            try await warmPreparedInputs(
                examples: dataset.examples,
                cache: cache,
                transcribe: transcribe,
                maxConcurrent: concurrencyProfile.cacheWarmLimit,
                progressBase: progressBase,
                totalUnitCount: estimatedTotalUnitCount,
                title: "Optimizing Analyzer",
                messagePrefix: "Preparing cached analyzer inputs",
                generation: nil,
                isEstimatedTotal: true,
                onProgress: onProgress
            )
            progressBase += preparationUnitCount

            try Task.checkCancellation()
            let baselineAllResults = try await evaluate(
                config: baseConfig,
                examples: dataset.examples,
                cache: cache,
                engine: engine,
                transcribe: transcribe,
                maxConcurrent: concurrencyProfile.fileEvaluationLimit,
                progressBase: progressBase,
                progress: { example, completedUnitCount in
                    let splitName = splitName(for: example.id, in: split)
                    await onProgress?(
                        Progress(
                            title: "Optimizing Analyzer",
                            message: "Scoring baseline across the full corpus · \(splitName) · \(example.originalFilename)",
                            generation: nil,
                            completedUnitCount: completedUnitCount,
                            totalUnitCount: estimatedTotalUnitCount,
                            isEstimatedTotal: true
                        )
                    )
                }
            )
            progressBase += dataset.examples.count
            let baselinePartition = partitionResults(baselineAllResults, by: split)

            let seededPopulation = try await seedPopulation(
                seed: baseConfig,
                params: resolvedParams,
                evaluationMode: resolvedParams.evaluationMode,
                split: split,
                cache: cache,
                engine: engine,
                concurrencyProfile: concurrencyProfile,
                transcribe: transcribe,
                randomState: randomGenerator.state,
                progressBase: progressBase,
                totalUnitCount: estimatedTotalUnitCount,
                onProgress: onProgress
            )
            population = seededPopulation.entries
            randomGenerator = SeededRandomNumberGenerator(state: seededPopulation.randomState)
            progressBase += seedPopulationUnitCount

            baselineTrainingMetrics = AnalyzerMetrics.aggregate(baselinePartition.train.map(\.metrics))
            baselineValidationMetrics = AnalyzerMetrics.aggregate(baselinePartition.validation.map(\.metrics))
            baselineOverallMetrics = AnalyzerMetrics.aggregate(baselineAllResults.map(\.metrics))
            history = []
            stagnantGenerations = 0

            let initialBest = population.max(by: { selectionScore(for: $0) < selectionScore(for: $1) })!
            bestEntry = initialBest
            bestGeneration = 0
            bestSelectionScore = selectionScore(for: initialBest)
            startGeneration = 0

            try await pauseIfRequested(
                pauseRequested,
                dataset: dataset,
                params: resolvedParams,
                baseConfig: baseConfig,
                stage: .generationLoop,
                nextGeneration: startGeneration,
                progressBase: progressBase,
                childGenerationCount: childGenerationCount,
                stagnantGenerations: stagnantGenerations,
                baselineTrainingMetrics: baselineTrainingMetrics,
                baselineValidationMetrics: baselineValidationMetrics,
                baselineOverallMetrics: baselineOverallMetrics,
                population: population,
                bestEntry: bestEntry,
                bestGeneration: bestGeneration,
                bestSelectionScore: bestSelectionScore,
                history: history,
                randomState: randomGenerator.state
            )
        }

        if resumeStage == .generationLoop {
            for generation in startGeneration..<resolvedParams.maxGenerations {
                try Task.checkCancellation()
                population.sort { selectionScore(for: $0) > selectionScore(for: $1) }

            let bestTrainingScore = population.map(\.trainingMetrics.overallScore).max() ?? 0
            let bestValidationScore = population.map(selectionScore(for:)).max() ?? 0
            let averageTrainingScore = population.map(\.trainingMetrics.overallScore).reduce(0, +) / Double(population.count)
            let averageValidationScore = population.map { selectionScore(for: $0) }.reduce(0, +) / Double(population.count)

            history.append(
                .init(
                    generation: generation,
                    bestTrainingScore: bestTrainingScore,
                    bestValidationScore: bestValidationScore,
                    averageTrainingScore: averageTrainingScore,
                    averageValidationScore: averageValidationScore
                )
            )

            await onProgress?(
                Progress(
                    title: "Optimizing Analyzer",
                    message: "Generation \(generation) complete. train=\(bestTrainingScore.formatted(.number.precision(.fractionLength(4)))) val=\(bestValidationScore.formatted(.number.precision(.fractionLength(4))))",
                    generation: generation,
                    completedUnitCount: progressBase,
                    totalUnitCount: estimatedTotalUnitCount,
                    isEstimatedTotal: true
                )
            )

            if let currentBest = population.max(by: { selectionScore(for: $0) < selectionScore(for: $1) }) {
                let currentScore = selectionScore(for: currentBest)
                if currentScore > bestSelectionScore {
                    bestSelectionScore = currentScore
                    bestEntry = currentBest
                    bestGeneration = generation
                    stagnantGenerations = 0
                } else {
                    stagnantGenerations += 1
                }
            }

                if stagnantGenerations >= resolvedParams.earlyStopPatience {
                    break
                }

                let elites = Array(population.prefix(max(1, min(resolvedParams.elitismCount, population.count))))
                let plannedChildren = max(0, populationSize - elites.count)
                var childJobs: [PopulationEvaluationJob] = []
                childJobs.reserveCapacity(plannedChildren)

                while childJobs.count < plannedChildren {
                    try Task.checkCancellation()
                    let parentA = elites.randomElement(using: &randomGenerator) ?? population[0]
                    let parentB = elites.randomElement(using: &randomGenerator) ?? population[0]
                    let base = mutationEngine.crossover(
                        parentA.config,
                        parentB.config,
                        for: resolvedParams.evaluationMode,
                        using: &randomGenerator
                    )
                    let child = Double.random(in: 0...1, using: &randomGenerator) < resolvedParams.mutationRate
                        ? mutationEngine.mutate(base, for: resolvedParams.evaluationMode, using: &randomGenerator)
                        : base
                    childJobs.append(
                        PopulationEvaluationJob(
                            config: child,
                            progressLabel: "Evaluating generation \(generation + 1) candidate \(childJobs.count + 1) of \(max(plannedChildren, 1))"
                        )
                    )
                }

                let evaluatedChildren = try await evaluatePopulationEntries(
                    jobs: childJobs,
                    split: split,
                    cache: cache,
                    engine: engine,
                    concurrencyProfile: concurrencyProfile,
                    transcribe: transcribe,
                    progressBase: progressBase,
                    totalUnitCount: estimatedTotalUnitCount,
                    title: "Optimizing Analyzer",
                    generation: generation + 1,
                    isEstimatedTotal: true,
                    onProgress: onProgress
                )
                var nextGeneration = elites
                nextGeneration.append(contentsOf: evaluatedChildren)

                population = nextGeneration
                progressBase += plannedChildren * perCandidateUnitCount
                childGenerationCount += 1

                try await pauseIfRequested(
                    pauseRequested,
                    dataset: dataset,
                    params: resolvedParams,
                    baseConfig: baseConfig,
                    stage: .generationLoop,
                    nextGeneration: generation + 1,
                    progressBase: progressBase,
                    childGenerationCount: childGenerationCount,
                    stagnantGenerations: stagnantGenerations,
                    baselineTrainingMetrics: baselineTrainingMetrics,
                    baselineValidationMetrics: baselineValidationMetrics,
                    baselineOverallMetrics: baselineOverallMetrics,
                    population: population,
                    bestEntry: bestEntry,
                    bestGeneration: bestGeneration,
                    bestSelectionScore: bestSelectionScore,
                    history: history,
                    randomState: randomGenerator.state
                )
            }
        }

        var selectedConfig = bestEntry.config
        selectedConfig.generation = bestGeneration
        selectedConfig.fitness = bestSelectionScore
        let finalizedTotalUnitCount = preparationUnitCount
            + baselineUnitCount
            + seedPopulationUnitCount
            + (childGenerationCount * childCountPerGeneration * perCandidateUnitCount)
            + finalizationUnitCount

        try await pauseIfRequested(
            pauseRequested,
            dataset: dataset,
            params: resolvedParams,
            baseConfig: baseConfig,
            stage: .finalization,
            nextGeneration: resolvedParams.maxGenerations,
            progressBase: progressBase,
            childGenerationCount: childGenerationCount,
            stagnantGenerations: stagnantGenerations,
            baselineTrainingMetrics: baselineTrainingMetrics,
            baselineValidationMetrics: baselineValidationMetrics,
            baselineOverallMetrics: baselineOverallMetrics,
            population: population,
            bestEntry: bestEntry,
            bestGeneration: bestGeneration,
            bestSelectionScore: bestSelectionScore,
            history: history,
            randomState: randomGenerator.state
        )

        try Task.checkCancellation()
        let selectedBestGeneration = bestGeneration
        let selectedAllResults = try await evaluate(
            config: selectedConfig,
            examples: dataset.examples,
            cache: cache,
            engine: engine,
            transcribe: transcribe,
            maxConcurrent: concurrencyProfile.fileEvaluationLimit,
            progressBase: progressBase,
            progress: { example, completedUnitCount in
                let splitName = splitName(for: example.id, in: split)
                await onProgress?(
                    Progress(
                        title: "Optimizing Analyzer",
                        message: "Scoring selected config across the full corpus · \(splitName) · \(example.originalFilename)",
                        generation: selectedBestGeneration,
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: finalizedTotalUnitCount,
                        isEstimatedTotal: false
                    )
                )
            }
        )
        progressBase += dataset.examples.count
        let selectedPartition = partitionResults(selectedAllResults, by: split)
        let diagnostics = buildDiagnostics(from: selectedAllResults)
        let selectedOverallMetrics = AnalyzerMetrics.aggregate(selectedAllResults.map(\.metrics))
        try Task.checkCancellation()
        let scorecard = buildScorecard(
            config: selectedConfig,
            dataset: dataset,
            evaluationMode: resolvedParams.evaluationMode,
            split: split,
            trainResults: selectedPartition.train,
            validationResults: selectedPartition.validation,
            testResults: selectedPartition.test,
            allResults: selectedAllResults
        )
        let report = AnalyzerOptimizationReport(
            generatedAt: Date(),
            optimizerVersion: 1,
            evaluationMode: resolvedParams.evaluationMode,
            dataset: dataset.summary,
            outputDirectory: outputDirectory.path(),
            trainCount: split.train.count,
            validationCount: split.validation.count,
            testCount: split.test.count,
            baselineTrainingMetrics: baselineTrainingMetrics,
            baselineValidationMetrics: baselineValidationMetrics,
            bestTrainingMetrics: bestEntry.trainingMetrics,
            bestValidationMetrics: bestEntry.validationMetrics,
            testMetrics: AnalyzerMetrics.aggregate(selectedPartition.test.map(\.metrics)),
            baselineOverallMetrics: baselineOverallMetrics,
            selectedOverallMetrics: selectedOverallMetrics,
            overallImprovement: selectedOverallMetrics.overallScore - baselineOverallMetrics.overallScore,
            selectedConfigGeneration: bestGeneration,
            selectedConfigFitness: bestSelectionScore,
            generationHistory: history,
            issues: dataset.issues,
            diagnostics: diagnostics
        )

        try Task.checkCancellation()
        let outputFiles = try writeOutputs(config: selectedConfig, report: report, scorecard: scorecard)
        if resolvedParams.publishBestConfigToDocuments {
            try AnalyzerConfigLoader.save(selectedConfig)
        }
        try? clearCheckpoint()
        await onProgress?(
            Progress(
                title: "Optimizing Analyzer",
                message: "Writing optimized outputs.",
                generation: bestGeneration,
                completedUnitCount: finalizedTotalUnitCount,
                totalUnitCount: finalizedTotalUnitCount,
                isEstimatedTotal: false
            )
        )

        return RunResult(
            bestConfig: selectedConfig,
            report: report,
            scorecard: scorecard,
            outputFiles: outputFiles
        )
    }

    func pauseIfRequested(
        _ pauseRequested: (@Sendable () async -> Bool)?,
        dataset: AnalyzerOptimizationDataset,
        params: Parameters,
        baseConfig: AnalyzerConfig,
        stage: CheckpointStage,
        nextGeneration: Int,
        progressBase: Int,
        childGenerationCount: Int,
        stagnantGenerations: Int,
        baselineTrainingMetrics: AnalyzerOptimizationAggregateMetrics,
        baselineValidationMetrics: AnalyzerOptimizationAggregateMetrics,
        baselineOverallMetrics: AnalyzerOptimizationAggregateMetrics,
        population: [PopulationEntry],
        bestEntry: PopulationEntry,
        bestGeneration: Int,
        bestSelectionScore: Double,
        history: [AnalyzerOptimizationReport.GenerationSnapshot],
        randomState: UInt64
    ) async throws {
        guard let pauseRequested, await pauseRequested() else { return }

        let checkpoint = Checkpoint(
            schemaVersion: 1,
            savedAt: Date(),
            datasetHash: dataset.datasetHash,
            params: params,
            baseConfig: baseConfig,
            stage: stage,
            nextGeneration: nextGeneration,
            progressBase: progressBase,
            childGenerationCount: childGenerationCount,
            stagnantGenerations: stagnantGenerations,
            baselineTrainingMetrics: baselineTrainingMetrics,
            baselineValidationMetrics: baselineValidationMetrics,
            baselineOverallMetrics: baselineOverallMetrics,
            population: population.map(checkpointEntry(from:)),
            bestEntry: checkpointEntry(from: bestEntry),
            bestGeneration: bestGeneration,
            bestSelectionScore: bestSelectionScore,
            generationHistory: history,
            randomState: randomState
        )
        try writeCheckpoint(checkpoint)
        throw AnalyzerOptimizerError.paused(checkpointURL())
    }

    func checkpointEntry(from entry: PopulationEntry) -> Checkpoint.PopulationEntrySnapshot {
        Checkpoint.PopulationEntrySnapshot(
            config: entry.config,
            trainingMetrics: entry.trainingMetrics,
            validationMetrics: entry.validationMetrics
        )
    }

    func populationEntry(from snapshot: Checkpoint.PopulationEntrySnapshot) -> PopulationEntry {
        PopulationEntry(
            config: snapshot.config,
            trainingMetrics: snapshot.trainingMetrics,
            validationMetrics: snapshot.validationMetrics
        )
    }

    func checkpointURL() -> URL {
        outputDirectory.appending(path: "AnalyzerOptimizationCheckpoint.json")
    }

    func writeCheckpoint(_ checkpoint: Checkpoint) throws {
        try ensureOutputDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let url = checkpointURL()
        do {
            try encoder.encode(checkpoint).write(to: url, options: .atomic)
        } catch {
            throw AnalyzerOptimizerError.outputWriteFailed(url, underlying: error.localizedDescription)
        }
    }

    nonisolated func splitName(
        for exampleID: UUID,
        in split: (
            train: [AnalyzerOptimizationDataset.Example],
            validation: [AnalyzerOptimizationDataset.Example],
            test: [AnalyzerOptimizationDataset.Example]
        )
    ) -> String {
        if split.train.contains(where: { $0.id == exampleID }) {
            return "train"
        }
        if split.validation.contains(where: { $0.id == exampleID }) {
            return "validation"
        }
        if split.test.contains(where: { $0.id == exampleID }) {
            return "test"
        }
        return "unassigned"
    }

    func split(
        _ examples: [AnalyzerOptimizationDataset.Example],
        trainFraction: Double,
        validationFraction: Double
    ) -> (train: [AnalyzerOptimizationDataset.Example], validation: [AnalyzerOptimizationDataset.Example], test: [AnalyzerOptimizationDataset.Example]) {
        let sorted = examples.sorted { stableOrderingKey(for: $0) < stableOrderingKey(for: $1) }
        guard sorted.count > 1 else {
            return (sorted, [], [])
        }

        let count = sorted.count
        let minimumValidationCount = count >= 6 ? 2 : (count >= 3 ? 1 : 0)
        let minimumTestCount = count >= 6 ? 2 : (count >= 4 ? 1 : 0)

        var validationCount = count >= 3
            ? max(minimumValidationCount, Int(Double(count) * validationFraction))
            : 0
        validationCount = min(validationCount, max(0, count - 1 - minimumTestCount))

        var trainCount = max(1, Int(Double(count) * trainFraction))
        trainCount = min(trainCount, max(1, count - validationCount - minimumTestCount))

        var testCount = max(0, count - trainCount - validationCount)
        if testCount < minimumTestCount {
            let deficit = minimumTestCount - testCount
            trainCount = max(1, trainCount - deficit)
            testCount = max(0, count - trainCount - validationCount)
        }

        let stratified = stratifiedSplit(
            sorted,
            trainCount: trainCount,
            validationCount: validationCount,
            testCount: testCount
        )
        let train = stratified.train
        let validation = stratified.validation
        let test = stratified.test
        return (train, validation, test)
    }

    private func stratifiedSplit(
        _ sorted: [AnalyzerOptimizationDataset.Example],
        trainCount: Int,
        validationCount: Int,
        testCount: Int
    ) -> (train: [AnalyzerOptimizationDataset.Example], validation: [AnalyzerOptimizationDataset.Example], test: [AnalyzerOptimizationDataset.Example]) {
        var buckets = [
            SplitBucket(id: .train, targetCount: trainCount),
            SplitBucket(id: .validation, targetCount: validationCount),
            SplitBucket(id: .test, targetCount: testCount)
        ]
        var unassigned = sorted
        let phaseTotals = phaseExampleCounts(sorted)
        let spreadablePhases = phaseTotals
            .filter { $0.value >= 3 }
            .sorted {
                if $0.value == $1.value {
                    return $0.key.rawValue < $1.key.rawValue
                }
                return $0.value < $1.value
            }
            .map(\.key)

        for phase in spreadablePhases {
            for bucketID in [SplitBucketID.validation, .test, .train] {
                guard let bucketIndex = buckets.firstIndex(where: { $0.id == bucketID }),
                      buckets[bucketIndex].hasCapacity,
                      buckets[bucketIndex].phaseCounts[phase, default: 0] == 0,
                      let exampleIndex = bestUnassignedExampleIndex(
                        containing: phase,
                        for: buckets[bucketIndex],
                        in: unassigned,
                        phaseTotals: phaseTotals
                      )
                else {
                    continue
                }
                buckets[bucketIndex].append(unassigned.remove(at: exampleIndex))
            }
        }

        while !unassigned.isEmpty {
            let example = unassigned.removeFirst()
            guard let bucketIndex = bestBucketIndex(
                for: example,
                in: buckets,
                phaseTotals: phaseTotals
            ) else {
                break
            }
            buckets[bucketIndex].append(example)
        }

        let train = buckets.first { $0.id == .train }?.examples ?? []
        let validation = buckets.first { $0.id == .validation }?.examples ?? []
        let test = buckets.first { $0.id == .test }?.examples ?? []
        return (train, validation, test)
    }

    private func bestUnassignedExampleIndex(
        containing phase: TrancePhase,
        for bucket: SplitBucket,
        in examples: [AnalyzerOptimizationDataset.Example],
        phaseTotals: [TrancePhase: Int]
    ) -> Int? {
        var bestIndex: Int?
        var bestScore = -Double.infinity

        for (index, example) in examples.enumerated() where Self.phaseSet(for: example).contains(phase) {
            let score = bucketScore(for: example, bucket: bucket, phaseTotals: phaseTotals)
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestIndex
    }

    private func bestBucketIndex(
        for example: AnalyzerOptimizationDataset.Example,
        in buckets: [SplitBucket],
        phaseTotals: [TrancePhase: Int]
    ) -> Int? {
        var bestIndex: Int?
        var bestScore = -Double.infinity

        for (index, bucket) in buckets.enumerated() where bucket.hasCapacity {
            let score = bucketScore(for: example, bucket: bucket, phaseTotals: phaseTotals)
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestIndex
    }

    private func bucketScore(
        for example: AnalyzerOptimizationDataset.Example,
        bucket: SplitBucket,
        phaseTotals: [TrancePhase: Int]
    ) -> Double {
        let phases = Self.phaseSet(for: example)
        let missingPhaseScore = phases.reduce(0.0) { partial, phase in
            guard bucket.phaseCounts[phase, default: 0] == 0 else { return partial }
            let total = max(1, phaseTotals[phase, default: 1])
            return partial + (20.0 / Double(total))
        }
        let capacityScore = Double(bucket.remainingCapacity) / Double(max(bucket.targetCount, 1))
        return missingPhaseScore + capacityScore
    }

    private func phaseExampleCounts(
        _ examples: [AnalyzerOptimizationDataset.Example]
    ) -> [TrancePhase: Int] {
        var counts: [TrancePhase: Int] = [:]
        for example in examples {
            for phase in Self.phaseSet(for: example) {
                counts[phase, default: 0] += 1
            }
        }
        return counts
    }

    private static func phaseSet(for example: AnalyzerOptimizationDataset.Example) -> Set<TrancePhase> {
        Set(example.phaseSegments.map(\.phase))
    }

    func stableOrderingKey(for example: AnalyzerOptimizationDataset.Example) -> String {
        let fingerprint = [
            example.id.uuidString,
            example.originalFilename,
            String(format: "%.3f", example.duration),
            example.phaseSegments.map(\.phase.rawValue).joined(separator: ",")
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func buildDiagnostics(from results: [AnalyzerEvaluationResult]) -> [AnalyzerOptimizationReport.FileDiagnostic] {
        results.map { result in
            AnalyzerOptimizationReport.FileDiagnostic(
                exampleID: result.exampleID,
                filename: result.originalFilename,
                overallScore: result.metrics.overallScore,
                timelineAccuracy: result.metrics.timelineAccuracy,
                macroPhaseF1: result.metrics.macroPhaseF1,
                boundaryScore: result.metrics.boundaryScore,
                meanBoundaryErrorSeconds: result.metrics.meanBoundaryErrorSeconds,
                transitionRecall: result.metrics.transitionRecall,
                orderValidity: result.metrics.orderValidity
            )
        }
        .sorted { $0.overallScore < $1.overallScore }
    }

    func writeOutputs(
        config: AnalyzerConfig,
        report: AnalyzerOptimizationReport,
        scorecard: AnalyzerTrainingMatchScorecard
    ) throws -> OutputFiles {
        try ensureOutputDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let configURL = outputDirectory.appending(path: "AnalyzerConfig_optimized.json")
        let reportURL = outputDirectory.appending(path: "AnalyzerOptimizationReport.json")
        let diagnosticsURL = outputDirectory.appending(path: "AnalyzerPerFileDiagnostics.json")
        let historyURL = outputDirectory.appending(path: "AnalyzerOptimizationHistory.json")
        let scorecardURL = outputDirectory.appending(path: "AnalyzerTrainingMatchScorecard.json")
        let scorecardHistoryURL = outputDirectory.appending(path: "AnalyzerTrainingMatchHistory.json")

        do {
            try encoder.encode(config).write(to: configURL, options: .atomic)
            try encoder.encode(report).write(to: reportURL, options: .atomic)
            try encoder.encode(report.diagnostics).write(to: diagnosticsURL, options: .atomic)
            try encoder.encode(report.generationHistory).write(to: historyURL, options: .atomic)
            try encoder.encode(scorecard).write(to: scorecardURL, options: .atomic)
            _ = try appendScorecardHistory(scorecard)
        } catch {
            throw AnalyzerOptimizerError.outputWriteFailed(outputDirectory, underlying: error.localizedDescription)
        }

        return OutputFiles(
            configURL: configURL,
            reportURL: reportURL,
            diagnosticsURL: diagnosticsURL,
            historyURL: historyURL,
            scorecardURL: scorecardURL,
            scorecardHistoryURL: scorecardHistoryURL
        )
    }

    func writeScorecard(_ scorecard: AnalyzerTrainingMatchScorecard) throws -> URL {
        try ensureOutputDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let scorecardURL = outputDirectory.appending(path: "AnalyzerTrainingMatchScorecard.json")
        do {
            try encoder.encode(scorecard).write(to: scorecardURL, options: .atomic)
        } catch {
            throw AnalyzerOptimizerError.outputWriteFailed(scorecardURL, underlying: error.localizedDescription)
        }
        return scorecardURL
    }

    func appendScorecardHistory(_ scorecard: AnalyzerTrainingMatchScorecard) throws -> URL {
        try ensureOutputDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let historyURL = outputDirectory.appending(path: "AnalyzerTrainingMatchHistory.json")
        let existingEntries: [AnalyzerTrainingMatchHistory.Entry]
        if FileManager.default.fileExists(atPath: historyURL.path()) {
            do {
                let data = try Data(contentsOf: historyURL)
                existingEntries = try decoder.decode(AnalyzerTrainingMatchHistory.self, from: data).entries
            } catch {
                throw AnalyzerOptimizerError.outputWriteFailed(historyURL, underlying: error.localizedDescription)
            }
        } else {
            existingEntries = []
        }

        var entries = existingEntries
        entries.append(
            AnalyzerTrainingMatchHistory.Entry(
                generatedAt: scorecard.generatedAt,
                evaluationMode: scorecard.evaluationMode,
                datasetHash: scorecard.dataset.datasetHash,
                evaluatedExampleCount: scorecard.evaluatedExampleCount,
                configGeneration: scorecard.configGeneration,
                configFitness: scorecard.configFitness,
                matchPercentage: scorecard.matchPercentage,
                overallMetrics: scorecard.overallMetrics
            )
        )
        entries.sort { $0.generatedAt < $1.generatedAt }

        do {
            let history = AnalyzerTrainingMatchHistory(
                updatedAt: Date(),
                entries: entries
            )
            try encoder.encode(history).write(to: historyURL, options: .atomic)
        } catch {
            throw AnalyzerOptimizerError.outputWriteFailed(historyURL, underlying: error.localizedDescription)
        }

        return historyURL
    }

    func ensureOutputDirectory() throws {
        guard !FileManager.default.fileExists(atPath: outputDirectory.path()) else { return }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    func buildScorecard(
        config: AnalyzerConfig,
        dataset: AnalyzerOptimizationDataset,
        evaluationMode: AnalyzerEvaluationMode,
        split: (train: [AnalyzerOptimizationDataset.Example], validation: [AnalyzerOptimizationDataset.Example], test: [AnalyzerOptimizationDataset.Example]),
        trainResults: [AnalyzerEvaluationResult],
        validationResults: [AnalyzerEvaluationResult],
        testResults: [AnalyzerEvaluationResult],
        allResults: [AnalyzerEvaluationResult]
    ) -> AnalyzerTrainingMatchScorecard {
        let overallMetrics = AnalyzerMetrics.aggregate(allResults.map(\.metrics))
        let trainMetrics = AnalyzerMetrics.aggregate(trainResults.map(\.metrics))
        let validationMetrics = AnalyzerMetrics.aggregate(validationResults.map(\.metrics))
        let testMetrics = AnalyzerMetrics.aggregate(testResults.map(\.metrics))
        let splitSummaries: [AnalyzerTrainingMatchScorecard.SplitSummary] = [
            .init(
                name: "train",
                exampleCount: split.train.count,
                metrics: trainMetrics,
                matchPercentage: trainMetrics.overallScore * 100
            ),
            .init(
                name: "validation",
                exampleCount: split.validation.count,
                metrics: validationMetrics,
                matchPercentage: validationMetrics.overallScore * 100
            ),
            .init(
                name: "test",
                exampleCount: split.test.count,
                metrics: testMetrics,
                matchPercentage: testMetrics.overallScore * 100
            ),
            .init(
                name: "all",
                exampleCount: dataset.examples.count,
                metrics: overallMetrics,
                matchPercentage: overallMetrics.overallScore * 100
            )
        ]

        return AnalyzerTrainingMatchScorecard(
            generatedAt: Date(),
            optimizerVersion: 1,
            evaluationMode: evaluationMode,
            dataset: dataset.summary,
            configGeneration: config.generation,
            configFitness: config.fitness,
            evaluatedExampleCount: allResults.count,
            overallMetrics: overallMetrics,
            matchPercentage: overallMetrics.overallScore * 100,
            splitSummaries: splitSummaries,
            worstMatches: Array(buildDiagnostics(from: allResults).prefix(10))
        )
    }
}
