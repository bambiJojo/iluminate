//
//  TrainingWorkflowControllerTests.swift
//  LumeLabelTests
//

import Foundation
import Testing
@testable import LumeLabel

@MainActor
struct TrainingWorkflowControllerTests {
    @Test
    func transcriptCoverageInspectorCountsMatchingCache() throws {
        let fixture = try makeDatasetFixture()
        let initialCoverage = try TrainingTranscriptCoverageInspector.inspect(dataset: fixture.dataset)

        #expect(initialCoverage.readyExampleCount == 0)
        #expect(initialCoverage.totalExampleCount == 1)
        #expect(initialCoverage.missingExamples.count == 1)

        try writeTranscriptCache(
            for: fixture.dataset.examples[0],
            to: fixture.dataset.transcriptCacheDirectory
        )

        let updatedCoverage = try TrainingTranscriptCoverageInspector.inspect(dataset: fixture.dataset)
        #expect(updatedCoverage.readyExampleCount == 1)
        #expect(updatedCoverage.missingExamples.isEmpty)
    }

    @Test
    func measureRunPreparesMissingTranscriptsAndCompletes() async throws {
        let fixture = try makeDatasetFixture()
        let tempDirectory = fixture.corpusDirectory.deletingLastPathComponent()
        let engine = FakeTrainingWorkflowEngine(
            dataset: fixture.dataset,
            initialCoverage: .init(
                readyExampleCount: 0,
                totalExampleCount: 1,
                missingExamples: fixture.dataset.examples
            ),
            postCoverage: .init(
                readyExampleCount: 1,
                totalExampleCount: 1,
                missingExamples: []
            ),
            measurementResult: try makeMeasurementResult(
                dataset: fixture.dataset,
                outputDirectory: tempDirectory,
                matchPercentage: 82.4
            ),
            optimizeResult: try makeOptimizeResult(
                dataset: fixture.dataset,
                outputDirectory: tempDirectory,
                matchPercentage: 83.1
            )
        )
        let finishedAt = Date(timeIntervalSince1970: 1_234)
        let controller = TrainingWorkflowController(engine: engine, now: { finishedAt })

        await controller.refreshSnapshot()
        #expect(controller.datasetSnapshot.validExampleCount == 1)
        #expect(controller.datasetSnapshot.readyTranscriptCount == 0)

        controller.startMeasure()
        await controller.waitForRunCompletion()

        #expect(engine.prepareCalls == 1)
        #expect(engine.measureCalls == 1)
        #expect(engine.optimizeCalls == 0)
        #expect(controller.datasetSnapshot.readyTranscriptCount == 1)

        switch controller.state {
        case .completed(let summary):
            #expect(summary.action == .measure)
            #expect(summary.finishedAt == finishedAt)
            #expect(summary.matchPercentage == 82.4)
        default:
            Issue.record("Expected the controller to finish in a completed state.")
        }
    }

    @Test
    func secondRunRequestIsIgnoredWhileWorkIsActive() async throws {
        let fixture = try makeDatasetFixture()
        let tempDirectory = fixture.corpusDirectory.deletingLastPathComponent()
        let engine = FakeTrainingWorkflowEngine(
            dataset: fixture.dataset,
            initialCoverage: .init(
                readyExampleCount: 1,
                totalExampleCount: 1,
                missingExamples: []
            ),
            postCoverage: .init(
                readyExampleCount: 1,
                totalExampleCount: 1,
                missingExamples: []
            ),
            measurementResult: try makeMeasurementResult(
                dataset: fixture.dataset,
                outputDirectory: tempDirectory,
                matchPercentage: 75.0
            ),
            optimizeResult: try makeOptimizeResult(
                dataset: fixture.dataset,
                outputDirectory: tempDirectory,
                matchPercentage: 76.0
            ),
            measureDelayNanoseconds: 100_000_000
        )
        let controller = TrainingWorkflowController(engine: engine)

        controller.startMeasure()
        controller.startOptimize()
        await controller.waitForRunCompletion()

        #expect(engine.measureCalls == 1)
        #expect(engine.optimizeCalls == 0)
    }

    @Test
    func loadFailureSurfacesAsFailedRun() async throws {
        let fixture = try makeDatasetFixture()
        let tempDirectory = fixture.corpusDirectory.deletingLastPathComponent()
        let engine = FakeTrainingWorkflowEngine(
            dataset: fixture.dataset,
            initialCoverage: .init(
                readyExampleCount: 1,
                totalExampleCount: 1,
                missingExamples: []
            ),
            postCoverage: .init(
                readyExampleCount: 1,
                totalExampleCount: 1,
                missingExamples: []
            ),
            measurementResult: try makeMeasurementResult(
                dataset: fixture.dataset,
                outputDirectory: tempDirectory,
                matchPercentage: 70.0
            ),
            optimizeResult: try makeOptimizeResult(
                dataset: fixture.dataset,
                outputDirectory: tempDirectory,
                matchPercentage: 71.0
            )
        )
        engine.loadError = AnalyzerOptimizerError.datasetIndexMissing(
            fixture.corpusDirectory.appending(path: "AnalyzerDataset/dataset.jsonl")
        )

        let controller = TrainingWorkflowController(engine: engine)
        controller.startMeasure()
        await controller.waitForRunCompletion()

        switch controller.state {
        case .failed(let message):
            #expect(message.contains("Analyzer dataset index is missing"))
        default:
            Issue.record("Expected a failed workflow state.")
        }
    }
}

@MainActor
private final class FakeTrainingWorkflowEngine: TrainingWorkflowEngine {
    let dataset: AnalyzerOptimizationDataset
    let initialCoverage: TrainingTranscriptCoverage
    let postCoverage: TrainingTranscriptCoverage
    let measurementResult: AnalyzerOptimizer.MeasurementResult
    let optimizeResult: AnalyzerOptimizer.RunResult
    let measureDelayNanoseconds: UInt64

    var loadError: Error?
    var prepareCalls = 0
    var measureCalls = 0
    var optimizeCalls = 0

    init(
        dataset: AnalyzerOptimizationDataset,
        initialCoverage: TrainingTranscriptCoverage,
        postCoverage: TrainingTranscriptCoverage,
        measurementResult: AnalyzerOptimizer.MeasurementResult,
        optimizeResult: AnalyzerOptimizer.RunResult,
        measureDelayNanoseconds: UInt64 = 0
    ) {
        self.dataset = dataset
        self.initialCoverage = initialCoverage
        self.postCoverage = postCoverage
        self.measurementResult = measurementResult
        self.optimizeResult = optimizeResult
        self.measureDelayNanoseconds = measureDelayNanoseconds
    }

    func loadDataset() throws -> AnalyzerOptimizationDataset {
        if let loadError {
            throw loadError
        }
        return dataset
    }

    func inspectTranscriptCoverage(dataset: AnalyzerOptimizationDataset) throws -> TrainingTranscriptCoverage {
        prepareCalls > 0 ? postCoverage : initialCoverage
    }

    func prepareTranscripts(
        for dataset: AnalyzerOptimizationDataset,
        progress: @escaping @MainActor (Int, Int, String) -> Void
    ) async throws -> TrainingTranscriptCoverage {
        prepareCalls += 1
        if let example = initialCoverage.missingExamples.first {
            await progress(1, initialCoverage.totalExampleCount, example.originalFilename)
        }
        return postCoverage
    }

    func measure() async throws -> AnalyzerOptimizer.MeasurementResult {
        measureCalls += 1
        if measureDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: measureDelayNanoseconds)
        }
        return measurementResult
    }

    func optimize(
        onProgress: @escaping @Sendable (AnalyzerOptimizer.Progress) async -> Void
    ) async throws -> AnalyzerOptimizer.RunResult {
        optimizeCalls += 1
        await onProgress(.init(message: "Generation 0 complete", generation: 0))
        return optimizeResult
    }

    func cancelCurrentWork() async {}
}

private struct DatasetFixture {
    let corpusDirectory: URL
    let dataset: AnalyzerOptimizationDataset
}

private func makeDatasetFixture() throws -> DatasetFixture {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let corpusDirectory = root.appending(path: "TrainingCorpus", directoryHint: .isDirectory)
    let datasetDirectory = corpusDirectory.appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
    let audioDirectory = datasetDirectory.appending(path: "audio", directoryHint: .isDirectory)

    try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

    let audioURL = audioDirectory.appending(path: "sample.m4a")
    try Data("audio".utf8).write(to: audioURL, options: .atomic)

    let example = AnalyzerTrainingExample(
        schemaVersion: AnalyzerTrainingExample.currentSchemaVersion,
        exportedAt: Date(timeIntervalSince1970: 0),
        exampleID: UUID(),
        source: .init(
            corpusFileID: UUID(),
            corpusLabelFilename: "sample.json",
            datasetRelativeExamplePath: "examples/sample.json",
            originalFilename: "sample.m4a",
            labeledAt: Date(timeIntervalSince1970: 0)
        ),
        audio: .init(
            datasetRelativePath: "audio/sample.m4a",
            storedAudioFilename: "sample.m4a",
            originalFilename: "sample.m4a",
            fileExtension: "m4a",
            sha256: "abc123",
            durationSeconds: 60
        ),
        labels: .init(
            contentType: .hypnosis,
            expectedFrequencyBand: .init(lower: 0.5, upper: 8.0),
            status: .refined,
            labelerNotes: "fixture",
            hasPhaseLabels: true,
            hasCompletePhaseCoverage: true,
            phaseOrder: [.preTalk],
            phasePoints: [
                .init(id: UUID(), timeSeconds: 0, phase: .preTalk, notes: nil)
            ],
            phaseSegments: [
                .init(
                    id: UUID(),
                    phase: .preTalk,
                    startTime: 0,
                    endTime: 60,
                    durationSeconds: 60,
                    notes: nil
                )
            ],
            denseTimeline: [
                .init(secondIndex: 0, startTime: 0, endTime: 1, phase: .preTalk)
            ],
            techniques: []
        )
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try Data((String(data: try encoder.encode(example), encoding: .utf8)! + "\n").utf8)
        .write(to: datasetDirectory.appending(path: "dataset.jsonl"), options: .atomic)

    let dataset = try AnalyzerOptimizationDataset.load(from: corpusDirectory)
    return DatasetFixture(corpusDirectory: corpusDirectory, dataset: dataset)
}

private func writeTranscriptCache(
    for example: AnalyzerOptimizationDataset.Example,
    to cacheDirectory: URL
) throws {
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

    let payload = CachedTranscriptionFixture(
        schemaVersion: 1,
        cachedAt: Date(timeIntervalSince1970: 0),
        exampleID: example.id,
        audioSHA256: example.example.audio.sha256,
        transcription: .init(
            fullText: "Hello",
            segments: [],
            duration: example.duration,
            detectedLanguage: "en"
        )
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(payload).write(
        to: cacheDirectory.appending(path: "\(example.example.audio.sha256).json"),
        options: .atomic
    )
}

private struct CachedTranscriptionFixture: Codable {
    let schemaVersion: Int
    let cachedAt: Date
    let exampleID: UUID
    let audioSHA256: String
    let transcription: AudioTranscriptionResult
}

private func makeMeasurementResult(
    dataset: AnalyzerOptimizationDataset,
    outputDirectory: URL,
    matchPercentage: Double
) throws -> AnalyzerOptimizer.MeasurementResult {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let scorecardURL = outputDirectory.appending(path: "scorecard.json")
    let historyURL = outputDirectory.appending(path: "history.json")
    try Data().write(to: scorecardURL, options: .atomic)
    try Data().write(to: historyURL, options: .atomic)

    return AnalyzerOptimizer.MeasurementResult(
        scorecard: makeScorecard(dataset: dataset, matchPercentage: matchPercentage),
        outputURL: scorecardURL,
        historyURL: historyURL
    )
}

private func makeOptimizeResult(
    dataset: AnalyzerOptimizationDataset,
    outputDirectory: URL,
    matchPercentage: Double
) throws -> AnalyzerOptimizer.RunResult {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let configURL = outputDirectory.appending(path: "AnalyzerConfig_optimized.json")
    let reportURL = outputDirectory.appending(path: "AnalyzerOptimizationReport.json")
    let diagnosticsURL = outputDirectory.appending(path: "AnalyzerPerFileDiagnostics.json")
    let historyURL = outputDirectory.appending(path: "AnalyzerOptimizationHistory.json")
    let scorecardURL = outputDirectory.appending(path: "AnalyzerTrainingMatchScorecard.json")
    let scorecardHistoryURL = outputDirectory.appending(path: "AnalyzerTrainingMatchHistory.json")

    for url in [configURL, reportURL, diagnosticsURL, historyURL, scorecardURL, scorecardHistoryURL] {
        try Data().write(to: url, options: .atomic)
    }

    let scorecard = makeScorecard(dataset: dataset, matchPercentage: matchPercentage)
    let report = AnalyzerOptimizationReport(
        generatedAt: Date(timeIntervalSince1970: 0),
        optimizerVersion: 1,
        evaluationMode: .keywordOnly,
        dataset: dataset.summary,
        outputDirectory: outputDirectory.path(),
        trainCount: dataset.examples.count,
        validationCount: 0,
        testCount: 0,
        baselineTrainingMetrics: makeAggregateMetrics(overallScore: 0.50, exampleCount: dataset.examples.count),
        baselineValidationMetrics: .zero,
        bestTrainingMetrics: makeAggregateMetrics(overallScore: 0.60, exampleCount: dataset.examples.count),
        bestValidationMetrics: .zero,
        testMetrics: .zero,
        baselineOverallMetrics: makeAggregateMetrics(overallScore: 0.50, exampleCount: dataset.examples.count),
        selectedOverallMetrics: makeAggregateMetrics(overallScore: matchPercentage / 100.0, exampleCount: dataset.examples.count),
        overallImprovement: 0.10,
        selectedConfigGeneration: 0,
        selectedConfigFitness: matchPercentage / 100.0,
        generationHistory: [],
        issues: dataset.issues,
        diagnostics: []
    )

    return AnalyzerOptimizer.RunResult(
        bestConfig: makeAnalyzerConfig(),
        report: report,
        scorecard: scorecard,
        outputFiles: .init(
            configURL: configURL,
            reportURL: reportURL,
            diagnosticsURL: diagnosticsURL,
            historyURL: historyURL,
            scorecardURL: scorecardURL,
            scorecardHistoryURL: scorecardHistoryURL
        )
    )
}

private func makeScorecard(
    dataset: AnalyzerOptimizationDataset,
    matchPercentage: Double
) -> AnalyzerTrainingMatchScorecard {
    let metrics = makeAggregateMetrics(
        overallScore: matchPercentage / 100.0,
        exampleCount: dataset.examples.count
    )

    return AnalyzerTrainingMatchScorecard(
        generatedAt: Date(timeIntervalSince1970: 0),
        optimizerVersion: 1,
        evaluationMode: .keywordOnly,
        dataset: dataset.summary,
        configGeneration: 0,
        configFitness: metrics.overallScore,
        evaluatedExampleCount: dataset.examples.count,
        overallMetrics: metrics,
        matchPercentage: matchPercentage,
        splitSummaries: [],
        worstMatches: []
    )
}

private func makeAggregateMetrics(
    overallScore: Double,
    exampleCount: Int
) -> AnalyzerOptimizationAggregateMetrics {
    AnalyzerOptimizationAggregateMetrics(
        exampleCount: exampleCount,
        timelineAccuracy: overallScore,
        macroPhaseF1: overallScore,
        boundaryScore: overallScore,
        meanBoundaryErrorSeconds: 0,
        transitionRecall: overallScore,
        orderValidity: overallScore,
        contentTypeAccuracy: overallScore,
        overallScore: overallScore
    )
}

private func makeAnalyzerConfig() -> AnalyzerConfig {
    AnalyzerConfig(
        keywordPipeline: .init(
            weights: [:],
            contextWindowSeconds: 5,
            smoothingWindowSize: 5,
            minimumPhaseDurationSeconds: 20,
            collapseThresholdFraction: 0.035
        ),
        chunkedAnalyzer: .init(
            chunkDurationSeconds: 15,
            chunkOverlapSeconds: 5,
            minChunks: 1,
            maxChunks: 6,
            systemInstructions: "",
            fewShotExamples: []
        ),
        prosody: .init(
            speechRateWindowSeconds: 3,
            pauseThresholdSeconds: 1,
            deliberatePauseMinSeconds: 3,
            musicOnlyPauseMinSeconds: 5
        ),
        techniqueDetection: .init(
            sensitivityThreshold: 0.6,
            minConfidence: 0.3
        ),
        sessionGeneration: .init(
            frequencyBands: [:],
            phaseFrequencyBands: [:],
            transitionSmoothingSeconds: 5,
            intensityCurve: "gradual"
        )
    )
}
