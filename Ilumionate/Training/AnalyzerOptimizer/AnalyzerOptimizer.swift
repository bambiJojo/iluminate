//
//  AnalyzerOptimizer.swift
//  Ilumionate
//
//  Host-side optimizer that tunes analyzer config against exported training data.
//

import Foundation

struct AnalyzerOptimizer {
    struct Parameters: Sendable {
        var populationSize: Int = 8
        var maxGenerations: Int = 8
        var elitismCount: Int = 2
        var mutationRate: Double = 0.85
        var earlyStopPatience: Int = 4
        var trainFraction: Double = 0.7
        var validationFraction: Double = 0.15
        var evaluationMode: AnalyzerEvaluationMode = .keywordOnly
        var publishBestConfigToDocuments: Bool = false

        nonisolated init(
            populationSize: Int = 8,
            maxGenerations: Int = 8,
            elitismCount: Int = 2,
            mutationRate: Double = 0.85,
            earlyStopPatience: Int = 4,
            trainFraction: Double = 0.7,
            validationFraction: Double = 0.15,
            evaluationMode: AnalyzerEvaluationMode = .keywordOnly,
            publishBestConfigToDocuments: Bool = false
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
        }
    }

    struct Progress: Sendable {
        let message: String
        let generation: Int?
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

    private struct PopulationEntry {
        let config: AnalyzerConfig
        let trainingMetrics: AnalyzerOptimizationAggregateMetrics
        let validationMetrics: AnalyzerOptimizationAggregateMetrics
    }

    private let corpusDirectory: URL
    private let outputDirectory: URL
    private let mutationEngine: AnalyzerMutationEngine

    init(
        corpusDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus"),
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

    func run(
        seedConfig: AnalyzerConfig? = nil,
        params: Parameters = .init(),
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)? = nil,
        onProgress: (@Sendable (Progress) async -> Void)? = nil
    ) async throws -> RunResult {
        try Task.checkCancellation()
        let dataset = try loadDataset()
        guard !dataset.examples.isEmpty else {
            throw AnalyzerOptimizerError.emptyDataset
        }

        await onProgress?(Progress(message: "Loaded \(dataset.examples.count) analyzer examples.", generation: nil))

        let split = split(dataset.examples, trainFraction: params.trainFraction, validationFraction: params.validationFraction)
        let cache = AnalyzerTranscriptCache(cacheDirectory: dataset.transcriptCacheDirectory)
        let engine = AnalyzerEvaluationEngine(mode: params.evaluationMode)
        let baseConfig = seedConfig ?? AnalyzerConfigLoader.load()

        try Task.checkCancellation()
        let baselineTrainingResults = try await evaluate(
            config: baseConfig,
            examples: split.train,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )
        try Task.checkCancellation()
        let baselineValidationResults = try await evaluate(
            config: baseConfig,
            examples: split.validation,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )
        try Task.checkCancellation()
        let baselineAllResults = try await evaluate(
            config: baseConfig,
            examples: dataset.examples,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )

        var population = try await seedPopulation(
            seed: baseConfig,
            params: params,
            split: split,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )

        var history: [AnalyzerOptimizationReport.GenerationSnapshot] = []
        var stagnantGenerations = 0

        let initialBest = population.max(by: { selectionScore(for: $0) < selectionScore(for: $1) })!
        var bestEntry = initialBest
        var bestGeneration = 0
        var bestSelectionScore = selectionScore(for: initialBest)

        for generation in 0..<params.maxGenerations {
            try Task.checkCancellation()
            population.sort { $0.trainingMetrics.overallScore > $1.trainingMetrics.overallScore }

            let bestTrainingScore = population.first?.trainingMetrics.overallScore ?? 0
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
                    message: "Generation \(generation) complete. train=\(bestTrainingScore.formatted(.number.precision(.fractionLength(4)))) val=\(bestValidationScore.formatted(.number.precision(.fractionLength(4))))",
                    generation: generation
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

            if stagnantGenerations >= params.earlyStopPatience {
                break
            }

            let elites = Array(population.prefix(max(1, min(params.elitismCount, population.count))))
            var nextGeneration = elites

            while nextGeneration.count < max(1, params.populationSize) {
                try Task.checkCancellation()
                let parentA = elites.randomElement() ?? population[0]
                let parentB = elites.randomElement() ?? population[0]
                let base = mutationEngine.crossover(parentA.config, parentB.config)
                let child = Double.random(in: 0...1) < params.mutationRate
                    ? mutationEngine.mutate(base)
                    : base
                let entry = try await evaluatePopulationEntry(
                    config: child,
                    split: split,
                    cache: cache,
                    engine: engine,
                    transcribe: transcribe
                )
                nextGeneration.append(entry)
            }

            population = nextGeneration
        }

        var selectedConfig = bestEntry.config
        selectedConfig.generation = bestGeneration
        selectedConfig.fitness = bestSelectionScore

        try Task.checkCancellation()
        let testResults = try await evaluate(
            config: selectedConfig,
            examples: split.test,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )
        try Task.checkCancellation()
        let selectedAllResults = try await evaluate(
            config: selectedConfig,
            examples: dataset.examples,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )
        let diagnostics = buildDiagnostics(from: selectedAllResults)
        let baselineOverallMetrics = AnalyzerMetrics.aggregate(baselineAllResults.map(\.metrics))
        let selectedOverallMetrics = AnalyzerMetrics.aggregate(selectedAllResults.map(\.metrics))
        try Task.checkCancellation()
        let scorecard = buildScorecard(
            config: selectedConfig,
            dataset: dataset,
            evaluationMode: params.evaluationMode,
            split: split,
            trainResults: try await evaluate(
                config: selectedConfig,
                examples: split.train,
                cache: cache,
                engine: engine,
                transcribe: transcribe
            ),
            validationResults: try await evaluate(
                config: selectedConfig,
                examples: split.validation,
                cache: cache,
                engine: engine,
                transcribe: transcribe
            ),
            testResults: testResults,
            allResults: selectedAllResults
        )
        let report = AnalyzerOptimizationReport(
            generatedAt: Date(),
            optimizerVersion: 1,
            evaluationMode: params.evaluationMode,
            dataset: dataset.summary,
            outputDirectory: outputDirectory.path(),
            trainCount: split.train.count,
            validationCount: split.validation.count,
            testCount: split.test.count,
            baselineTrainingMetrics: AnalyzerMetrics.aggregate(baselineTrainingResults.map(\.metrics)),
            baselineValidationMetrics: AnalyzerMetrics.aggregate(baselineValidationResults.map(\.metrics)),
            bestTrainingMetrics: bestEntry.trainingMetrics,
            bestValidationMetrics: bestEntry.validationMetrics,
            testMetrics: AnalyzerMetrics.aggregate(testResults.map(\.metrics)),
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
        if params.publishBestConfigToDocuments {
            try AnalyzerConfigLoader.save(selectedConfig)
        }

        return RunResult(
            bestConfig: selectedConfig,
            report: report,
            scorecard: scorecard,
            outputFiles: outputFiles
        )
    }

    func measure(
        config: AnalyzerConfig? = nil,
        evaluationMode: AnalyzerEvaluationMode = .keywordOnly,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)? = nil
    ) async throws -> MeasurementResult {
        try Task.checkCancellation()
        let dataset = try loadDataset()
        guard !dataset.examples.isEmpty else {
            throw AnalyzerOptimizerError.emptyDataset
        }

        let activeConfig = config ?? AnalyzerConfigLoader.load()
        let split = split(dataset.examples, trainFraction: 0.7, validationFraction: 0.15)
        let cache = AnalyzerTranscriptCache(cacheDirectory: dataset.transcriptCacheDirectory)
        let engine = AnalyzerEvaluationEngine(mode: evaluationMode)

        try Task.checkCancellation()
        let trainResults = try await evaluate(
            config: activeConfig,
            examples: split.train,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )
        try Task.checkCancellation()
        let validationResults = try await evaluate(
            config: activeConfig,
            examples: split.validation,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )
        try Task.checkCancellation()
        let testResults = try await evaluate(
            config: activeConfig,
            examples: split.test,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )
        try Task.checkCancellation()
        let allResults = try await evaluate(
            config: activeConfig,
            examples: dataset.examples,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )

        let scorecard = buildScorecard(
            config: activeConfig,
            dataset: dataset,
            evaluationMode: evaluationMode,
            split: split,
            trainResults: trainResults,
            validationResults: validationResults,
            testResults: testResults,
            allResults: allResults
        )
        try Task.checkCancellation()
        let outputURL = try writeScorecard(scorecard)
        let historyURL = try appendScorecardHistory(scorecard)
        return MeasurementResult(scorecard: scorecard, outputURL: outputURL, historyURL: historyURL)
    }

    private func seedPopulation(
        seed: AnalyzerConfig,
        params: Parameters,
        split: (train: [AnalyzerOptimizationDataset.Example], validation: [AnalyzerOptimizationDataset.Example], test: [AnalyzerOptimizationDataset.Example]),
        cache: AnalyzerTranscriptCache,
        engine: AnalyzerEvaluationEngine,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)?
    ) async throws -> [PopulationEntry] {
        var population: [PopulationEntry] = []
        try Task.checkCancellation()
        population.append(
            try await evaluatePopulationEntry(
                config: seed,
                split: split,
                cache: cache,
                engine: engine,
                transcribe: transcribe
            )
        )

        let targetSize = max(1, params.populationSize)
        while population.count < targetSize {
            try Task.checkCancellation()
            let mutated = mutationEngine.mutate(seed)
            population.append(
                try await evaluatePopulationEntry(
                    config: mutated,
                    split: split,
                    cache: cache,
                    engine: engine,
                    transcribe: transcribe
                )
            )
        }

        return population
    }

    private func evaluatePopulationEntry(
        config: AnalyzerConfig,
        split: (train: [AnalyzerOptimizationDataset.Example], validation: [AnalyzerOptimizationDataset.Example], test: [AnalyzerOptimizationDataset.Example]),
        cache: AnalyzerTranscriptCache,
        engine: AnalyzerEvaluationEngine,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)?
    ) async throws -> PopulationEntry {
        let trainingResults = try await evaluate(
            config: config,
            examples: split.train,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )
        let validationResults = try await evaluate(
            config: config,
            examples: split.validation,
            cache: cache,
            engine: engine,
            transcribe: transcribe
        )

        return PopulationEntry(
            config: config,
            trainingMetrics: AnalyzerMetrics.aggregate(trainingResults.map(\.metrics)),
            validationMetrics: AnalyzerMetrics.aggregate(validationResults.map(\.metrics))
        )
    }

    private func evaluate(
        config: AnalyzerConfig,
        examples: [AnalyzerOptimizationDataset.Example],
        cache: AnalyzerTranscriptCache,
        engine: AnalyzerEvaluationEngine,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)?
    ) async throws -> [AnalyzerEvaluationResult] {
        var results: [AnalyzerEvaluationResult] = []
        results.reserveCapacity(examples.count)

        for example in examples {
            try Task.checkCancellation()
            let transcription = try await cache.transcription(for: example, transcribe: transcribe)
            let result = await engine.evaluate(config: config, example: example, transcription: transcription)
            results.append(result)
        }

        return results
    }

    private func selectionScore(for entry: PopulationEntry) -> Double {
        entry.validationMetrics.exampleCount > 0
            ? entry.validationMetrics.overallScore
            : entry.trainingMetrics.overallScore
    }

    private func split(
        _ examples: [AnalyzerOptimizationDataset.Example],
        trainFraction: Double,
        validationFraction: Double
    ) -> (train: [AnalyzerOptimizationDataset.Example], validation: [AnalyzerOptimizationDataset.Example], test: [AnalyzerOptimizationDataset.Example]) {
        let sorted = examples.sorted { $0.id.uuidString < $1.id.uuidString }
        guard sorted.count > 1 else {
            return (sorted, [], [])
        }

        let count = sorted.count
        let trainCount = max(1, Int(Double(count) * trainFraction))
        let validationCount = count >= 3 ? max(1, Int(Double(count) * validationFraction)) : 0
        let clampedTrainCount = min(trainCount, count)
        let remainingAfterTrain = max(0, count - clampedTrainCount)
        let clampedValidationCount = min(validationCount, remainingAfterTrain)

        let train = Array(sorted.prefix(clampedTrainCount))
        let validation = Array(sorted.dropFirst(clampedTrainCount).prefix(clampedValidationCount))
        let test = Array(sorted.dropFirst(clampedTrainCount + clampedValidationCount))
        return (train, validation, test)
    }

    private func buildDiagnostics(from results: [AnalyzerEvaluationResult]) -> [AnalyzerOptimizationReport.FileDiagnostic] {
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

    private func writeOutputs(
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

    private func writeScorecard(_ scorecard: AnalyzerTrainingMatchScorecard) throws -> URL {
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

    private func appendScorecardHistory(_ scorecard: AnalyzerTrainingMatchScorecard) throws -> URL {
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

    private func ensureOutputDirectory() throws {
        guard !FileManager.default.fileExists(atPath: outputDirectory.path()) else { return }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    private func buildScorecard(
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
