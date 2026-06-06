//
//  AnalyzerOptimizer+Evaluation.swift
//  Ilumionate
//
//  Extracted from AnalyzerOptimizer.swift (structural decomposition):
//  measurement, population seeding/evaluation, and parallel mapping.
//

import Foundation
import CryptoKit

extension AnalyzerOptimizer {

    func measure(
        config: AnalyzerConfig? = nil,
        evaluationMode: AnalyzerEvaluationMode = .keywordOnly,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)? = nil,
        onProgress: (@Sendable (Progress) async -> Void)? = nil
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
        let concurrencyProfile = OptimizerConcurrencyProfile.for(mode: evaluationMode)
        let preparationUnitCount = dataset.examples.count
        let totalUnitCount = preparationUnitCount + dataset.examples.count

        await onProgress?(
            Progress(
                title: "Measuring Analyzer",
                message: "Loaded \(dataset.examples.count) analyzer examples.",
                generation: nil,
                completedUnitCount: 0,
                totalUnitCount: totalUnitCount,
                isEstimatedTotal: false
            )
        )

        try Task.checkCancellation()
        try await warmPreparedInputs(
            examples: dataset.examples,
            cache: cache,
            transcribe: transcribe,
            maxConcurrent: concurrencyProfile.cacheWarmLimit,
            progressBase: 0,
            totalUnitCount: totalUnitCount,
            title: "Measuring Analyzer",
            messagePrefix: "Preparing cached analyzer inputs",
            generation: nil,
            isEstimatedTotal: false,
            onProgress: onProgress
        )

        try Task.checkCancellation()
        let allResults = try await evaluate(
            config: activeConfig,
            examples: dataset.examples,
            cache: cache,
            engine: engine,
            transcribe: transcribe,
            maxConcurrent: concurrencyProfile.fileEvaluationLimit,
            progressBase: preparationUnitCount,
            progress: { example, completedUnitCount in
                let splitName = splitName(for: example.id, in: split)
                await onProgress?(
                    Progress(
                        title: "Measuring Analyzer",
                        message: "Evaluating the full corpus · \(splitName) · \(example.originalFilename)",
                        generation: nil,
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        isEstimatedTotal: false
                    )
                )
            }
        )
        let partitionedResults = partitionResults(allResults, by: split)

        let scorecard = buildScorecard(
            config: activeConfig,
            dataset: dataset,
            evaluationMode: evaluationMode,
            split: split,
            trainResults: partitionedResults.train,
            validationResults: partitionedResults.validation,
            testResults: partitionedResults.test,
            allResults: allResults
        )
        try Task.checkCancellation()
        let outputURL = try writeScorecard(scorecard)
        let historyURL = try appendScorecardHistory(scorecard)
        await onProgress?(
            Progress(
                title: "Measuring Analyzer",
                message: "Writing scorecard outputs.",
                generation: nil,
                completedUnitCount: totalUnitCount,
                totalUnitCount: totalUnitCount,
                isEstimatedTotal: false
            )
        )
        return MeasurementResult(scorecard: scorecard, outputURL: outputURL, historyURL: historyURL)
    }

    func seedPopulation(
        seed: AnalyzerConfig,
        params: Parameters,
        evaluationMode: AnalyzerEvaluationMode,
        split: (train: [AnalyzerOptimizationDataset.Example], validation: [AnalyzerOptimizationDataset.Example], test: [AnalyzerOptimizationDataset.Example]),
        cache: AnalyzerTranscriptCache,
        engine: AnalyzerEvaluationEngine,
        concurrencyProfile: OptimizerConcurrencyProfile,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)?,
        progressBase: Int,
        totalUnitCount: Int,
        onProgress: (@Sendable (Progress) async -> Void)?
    ) async throws -> [PopulationEntry] {
        let targetSize = max(1, params.populationSize)
        var jobs: [PopulationEvaluationJob] = [
            PopulationEvaluationJob(
                config: seed,
                progressLabel: "Seeding candidate 1 of \(targetSize)"
            )
        ]
        jobs.reserveCapacity(targetSize)

        while jobs.count < targetSize {
            try Task.checkCancellation()
            jobs.append(
                PopulationEvaluationJob(
                    config: mutationEngine.mutate(seed, for: evaluationMode),
                    progressLabel: "Seeding candidate \(jobs.count + 1) of \(targetSize)"
                )
            )
        }

        try Task.checkCancellation()
        return try await evaluatePopulationEntries(
            jobs: jobs,
            split: split,
            cache: cache,
            engine: engine,
            concurrencyProfile: concurrencyProfile,
            transcribe: transcribe,
            progressBase: progressBase,
            totalUnitCount: totalUnitCount,
            title: "Optimizing Analyzer",
            generation: nil,
            isEstimatedTotal: true,
            onProgress: onProgress
        )
    }

    func evaluatePopulationEntries(
        jobs: [PopulationEvaluationJob],
        split: (train: [AnalyzerOptimizationDataset.Example], validation: [AnalyzerOptimizationDataset.Example], test: [AnalyzerOptimizationDataset.Example]),
        cache: AnalyzerTranscriptCache,
        engine: AnalyzerEvaluationEngine,
        concurrencyProfile: OptimizerConcurrencyProfile,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)?,
        progressBase: Int,
        totalUnitCount: Int,
        title: String,
        generation: Int?,
        isEstimatedTotal: Bool,
        onProgress: (@Sendable (Progress) async -> Void)?
    ) async throws -> [PopulationEntry] {
        let progressCounter = OptimizerProgressCounter(initialValue: progressBase)
        return try await parallelMap(
            jobs,
            maxConcurrent: concurrencyProfile.candidateEvaluationLimit
        ) { _, job in
            try await evaluatePopulationEntry(
                config: job.config,
                split: split,
                cache: cache,
                engine: engine,
                fileEvaluationLimit: concurrencyProfile.fileEvaluationLimit,
                transcribe: transcribe,
                totalUnitCount: totalUnitCount,
                title: title,
                generation: generation,
                messagePrefix: job.progressLabel,
                isEstimatedTotal: isEstimatedTotal,
                progressCounter: progressCounter,
                onProgress: onProgress
            )
        }
    }

    func evaluatePopulationEntry(
        config: AnalyzerConfig,
        split: (train: [AnalyzerOptimizationDataset.Example], validation: [AnalyzerOptimizationDataset.Example], test: [AnalyzerOptimizationDataset.Example]),
        cache: AnalyzerTranscriptCache,
        engine: AnalyzerEvaluationEngine,
        fileEvaluationLimit: Int,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)?,
        totalUnitCount: Int,
        title: String,
        generation: Int?,
        messagePrefix: String,
        isEstimatedTotal: Bool,
        progressCounter: OptimizerProgressCounter,
        onProgress: (@Sendable (Progress) async -> Void)?
    ) async throws -> PopulationEntry {
        let trainingResults = try await evaluate(
            config: config,
            examples: split.train,
            cache: cache,
            engine: engine,
            transcribe: transcribe,
            maxConcurrent: fileEvaluationLimit,
            progressCounter: progressCounter,
            progress: { example, completedUnitCount in
                await onProgress?(
                    Progress(
                        title: title,
                        message: "\(messagePrefix) · train · \(example.originalFilename)",
                        generation: generation,
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        isEstimatedTotal: isEstimatedTotal
                    )
                )
            }
        )
        let validationResults = try await evaluate(
            config: config,
            examples: split.validation,
            cache: cache,
            engine: engine,
            transcribe: transcribe,
            maxConcurrent: fileEvaluationLimit,
            progressCounter: progressCounter,
            progress: { example, completedUnitCount in
                await onProgress?(
                    Progress(
                        title: title,
                        message: "\(messagePrefix) · validation · \(example.originalFilename)",
                        generation: generation,
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        isEstimatedTotal: isEstimatedTotal
                    )
                )
            }
        )

        return PopulationEntry(
            config: config,
            trainingMetrics: AnalyzerMetrics.aggregate(trainingResults.map(\.metrics)),
            validationMetrics: AnalyzerMetrics.aggregate(validationResults.map(\.metrics))
        )
    }

    func evaluate(
        config: AnalyzerConfig,
        examples: [AnalyzerOptimizationDataset.Example],
        cache: AnalyzerTranscriptCache,
        engine: AnalyzerEvaluationEngine,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)?,
        maxConcurrent: Int,
        progressBase: Int = 0,
        progressCounter externalProgressCounter: OptimizerProgressCounter? = nil,
        progress: (@Sendable (_ example: AnalyzerOptimizationDataset.Example, _ completedUnitCount: Int) async -> Void)? = nil
    ) async throws -> [AnalyzerEvaluationResult] {
        let progressCounter = externalProgressCounter ?? OptimizerProgressCounter(initialValue: progressBase)
        return try await parallelMap(examples, maxConcurrent: maxConcurrent) { _, example in
            try Task.checkCancellation()
            let preparedTranscription = try await cache.preparedTranscription(for: example, transcribe: transcribe)
            let result = await engine.evaluate(
                config: config,
                example: example,
                preparedTranscription: preparedTranscription
            )
            if let progress {
                let completedUnitCount = await progressCounter.next()
                await progress(example, completedUnitCount)
            }
            return result
        }
    }

    func warmPreparedInputs(
        examples: [AnalyzerOptimizationDataset.Example],
        cache: AnalyzerTranscriptCache,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)?,
        maxConcurrent: Int,
        progressBase: Int,
        totalUnitCount: Int,
        title: String,
        messagePrefix: String,
        generation: Int?,
        isEstimatedTotal: Bool,
        onProgress: (@Sendable (Progress) async -> Void)?
    ) async throws {
        let progressCounter = OptimizerProgressCounter(initialValue: progressBase)
        _ = try await parallelMap(examples, maxConcurrent: maxConcurrent) { _, example in
            try Task.checkCancellation()
            _ = try await cache.preparedTranscription(for: example, transcribe: transcribe)
            if let onProgress {
                let completedUnitCount = await progressCounter.next()
                await onProgress(
                    Progress(
                        title: title,
                        message: "\(messagePrefix) · \(example.originalFilename)",
                        generation: generation,
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        isEstimatedTotal: isEstimatedTotal
                    )
                )
            }
            return example.id
        }
    }

    func parallelMap<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maxConcurrent: Int,
        operation: @escaping @Sendable (Int, Input) async throws -> Output
    ) async throws -> [Output] {
        guard !inputs.isEmpty else { return [] }

        let concurrencyLimit = max(1, min(maxConcurrent, inputs.count))
        if concurrencyLimit == 1 {
            var outputs: [Output] = []
            outputs.reserveCapacity(inputs.count)

            for (index, input) in inputs.enumerated() {
                try Task.checkCancellation()
                outputs.append(try await operation(index, input))
            }

            return outputs
        }

        return try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            var nextInputIndex = 0
            var orderedOutputs = Array<Output?>(repeating: nil, count: inputs.count)

            func enqueueNextTask() {
                guard nextInputIndex < inputs.count else { return }
                let inputIndex = nextInputIndex
                let input = inputs[inputIndex]
                nextInputIndex += 1
                group.addTask {
                    (inputIndex, try await operation(inputIndex, input))
                }
            }

            for _ in 0..<concurrencyLimit {
                enqueueNextTask()
            }

            while let (index, output) = try await group.next() {
                orderedOutputs[index] = output
                enqueueNextTask()
            }

            return orderedOutputs.compactMap { $0 }
        }
    }

    func selectionScore(for entry: PopulationEntry) -> Double {
        let trainingScore = entry.trainingMetrics.overallScore
        guard entry.validationMetrics.exampleCount > 0 else {
            return trainingScore
        }

        let validationScore = entry.validationMetrics.overallScore
        let validationWeight = entry.validationMetrics.exampleCount >= 4 ? 0.75 : 0.60
        let blendedScore = (validationWeight * validationScore) + ((1 - validationWeight) * trainingScore)
        let overfitPenalty = max(0, trainingScore - validationScore) * 0.10
        return blendedScore - overfitPenalty
    }

    func partitionResults(
        _ results: [AnalyzerEvaluationResult],
        by split: (
            train: [AnalyzerOptimizationDataset.Example],
            validation: [AnalyzerOptimizationDataset.Example],
            test: [AnalyzerOptimizationDataset.Example]
        )
    ) -> (
        train: [AnalyzerEvaluationResult],
        validation: [AnalyzerEvaluationResult],
        test: [AnalyzerEvaluationResult]
    ) {
        let resultByID = Dictionary(uniqueKeysWithValues: results.map { ($0.exampleID, $0) })
        return (
            train: split.train.compactMap { resultByID[$0.id] },
            validation: split.validation.compactMap { resultByID[$0.id] },
            test: split.test.compactMap { resultByID[$0.id] }
        )
    }
}
