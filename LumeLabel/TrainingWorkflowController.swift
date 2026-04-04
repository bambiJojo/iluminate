//
//  TrainingWorkflowController.swift
//  LumeLabel
//
//  Coordinates dataset-level analyzer measurement and optimization inside
//  the labeling utility.
//

import Foundation
import Observation

enum TrainingWorkflowAction: String, Sendable {
    case measure
    case optimize

    var title: String {
        switch self {
        case .measure: return "Measure"
        case .optimize: return "Optimize"
        }
    }

    var systemImage: String {
        switch self {
        case .measure: return "chart.bar.xaxis"
        case .optimize: return "slider.horizontal.3"
        }
    }
}

struct TrainingWorkflowSummary: Sendable {
    let action: TrainingWorkflowAction
    let finishedAt: Date
    let matchPercentage: Double
    let exampleCount: Int
    let outputDirectoryURL: URL
    let scorecardURL: URL
    let optimizedConfigURL: URL?
    let reportURL: URL?
}

enum TrainingWorkflowState: Sendable {
    case idle
    case preflighting
    case transcribing(current: Int, total: Int, filename: String)
    case measuring
    case optimizing(generation: Int?, message: String)
    case completed(TrainingWorkflowSummary)
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .idle, .completed, .failed:
            return false
        case .preflighting, .transcribing, .measuring, .optimizing:
            return true
        }
    }

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .preflighting:
            return "Preflighting Dataset"
        case .transcribing:
            return "Preparing Transcripts"
        case .measuring:
            return "Measuring Analyzer"
        case .optimizing:
            return "Optimizing Analyzer"
        case .completed(let summary):
            return "\(summary.action.title) Complete"
        case .failed:
            return "Run Failed"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "Measure or optimize the exported training dataset."
        case .preflighting:
            return "Checking the dataset, audio files, and transcript cache."
        case .transcribing(let current, let total, let filename):
            return "Generating transcript \(current) of \(max(total, 1)) for \(filename)."
        case .measuring:
            return "Evaluating the current analyzer config against the full corpus."
        case .optimizing(let generation, let message):
            if let generation {
                return "[Generation \(generation)] \(message)"
            }
            return message
        case .completed(let summary):
            return "\(summary.exampleCount) examples evaluated with \(summary.matchPercentage.formatted(.number.precision(.fractionLength(2))))% overall match."
        case .failed(let message):
            return message
        }
    }
}

struct TrainingTranscriptCoverage: Sendable {
    let readyExampleCount: Int
    let totalExampleCount: Int
    let missingExamples: [AnalyzerOptimizationDataset.Example]

    var missingExampleCount: Int { totalExampleCount - readyExampleCount }
}

struct TrainingWorkflowDatasetSnapshot: Sendable {
    let validExampleCount: Int
    let readyTranscriptCount: Int
    let totalTranscriptCount: Int
    let issueCount: Int
    let errorMessage: String?

    init(
        validExampleCount: Int,
        readyTranscriptCount: Int,
        totalTranscriptCount: Int,
        issueCount: Int,
        errorMessage: String?
    ) {
        self.validExampleCount = validExampleCount
        self.readyTranscriptCount = readyTranscriptCount
        self.totalTranscriptCount = totalTranscriptCount
        self.issueCount = issueCount
        self.errorMessage = errorMessage
    }

    static let empty = TrainingWorkflowDatasetSnapshot(
        validExampleCount: 0,
        readyTranscriptCount: 0,
        totalTranscriptCount: 0,
        issueCount: 0,
        errorMessage: nil
    )

    init(dataset: AnalyzerOptimizationDataset, coverage: TrainingTranscriptCoverage) {
        self.validExampleCount = dataset.examples.count
        self.readyTranscriptCount = coverage.readyExampleCount
        self.totalTranscriptCount = coverage.totalExampleCount
        self.issueCount = dataset.issues.count
        self.errorMessage = nil
    }

    init(errorMessage: String) {
        self.validExampleCount = 0
        self.readyTranscriptCount = 0
        self.totalTranscriptCount = 0
        self.issueCount = 0
        self.errorMessage = errorMessage
    }
}

@MainActor
protocol TrainingWorkflowEngine: AnyObject {
    func loadDataset() throws -> AnalyzerOptimizationDataset
    func inspectTranscriptCoverage(dataset: AnalyzerOptimizationDataset) throws -> TrainingTranscriptCoverage
    func prepareTranscripts(
        for dataset: AnalyzerOptimizationDataset,
        progress: @escaping @MainActor (_ current: Int, _ total: Int, _ filename: String) -> Void
    ) async throws -> TrainingTranscriptCoverage
    func measure() async throws -> AnalyzerOptimizer.MeasurementResult
    func optimize(
        onProgress: @escaping @Sendable (AnalyzerOptimizer.Progress) async -> Void
    ) async throws -> AnalyzerOptimizer.RunResult
    func cancelCurrentWork() async
}

@MainActor
final class DefaultTrainingWorkflowEngine: TrainingWorkflowEngine {
    private let optimizer: AnalyzerOptimizer
    private let audioAnalyzer: AudioAnalyzer

    init(
        corpusDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus"),
        outputDirectory: URL = URL.documentsDirectory.appending(path: "TrainingOutput"),
        audioAnalyzer: AudioAnalyzer? = nil
    ) {
        self.optimizer = AnalyzerOptimizer(
            corpusDirectory: corpusDirectory,
            outputDirectory: outputDirectory
        )
        self.audioAnalyzer = audioAnalyzer ?? AudioAnalyzer()
    }

    func loadDataset() throws -> AnalyzerOptimizationDataset {
        try optimizer.loadDataset()
    }

    func inspectTranscriptCoverage(dataset: AnalyzerOptimizationDataset) throws -> TrainingTranscriptCoverage {
        try TrainingTranscriptCoverageInspector.inspect(dataset: dataset)
    }

    func prepareTranscripts(
        for dataset: AnalyzerOptimizationDataset,
        progress: @escaping @MainActor (_ current: Int, _ total: Int, _ filename: String) -> Void
    ) async throws -> TrainingTranscriptCoverage {
        let coverage = try inspectTranscriptCoverage(dataset: dataset)
        guard !coverage.missingExamples.isEmpty else {
            return coverage
        }

        let cache = AnalyzerTranscriptCache(cacheDirectory: dataset.transcriptCacheDirectory)
        let total = coverage.missingExamples.count

        for (index, example) in coverage.missingExamples.enumerated() {
            try Task.checkCancellation()
            progress(index + 1, total, example.originalFilename)
            _ = try await cache.transcription(for: example) { [audioAnalyzer] example in
                try Task.checkCancellation()
                let audioFile = try await MainActor.run {
                    try example.makeAudioFileForDocumentsBackedCorpus()
                }
                return try await audioAnalyzer.transcribe(audioFile: audioFile)
            }
        }

        try Task.checkCancellation()
        return try inspectTranscriptCoverage(dataset: dataset)
    }

    func measure() async throws -> AnalyzerOptimizer.MeasurementResult {
        try Task.checkCancellation()
        return try await optimizer.measure(
            config: AnalyzerConfigLoader.load(),
            evaluationMode: .keywordOnly
        )
    }

    func optimize(
        onProgress: @escaping @Sendable (AnalyzerOptimizer.Progress) async -> Void
    ) async throws -> AnalyzerOptimizer.RunResult {
        try Task.checkCancellation()
        return try await optimizer.run(
            seedConfig: AnalyzerConfigLoader.load(),
            params: .init(evaluationMode: .keywordOnly),
            onProgress: onProgress
        )
    }

    func cancelCurrentWork() async {
        await audioAnalyzer.cancelTranscription()
    }
}

enum TrainingTranscriptCoverageInspector {
    private struct CachedTranscription: Codable {
        let schemaVersion: Int
        let cachedAt: Date
        let exampleID: UUID
        let audioSHA256: String
        let transcription: AudioTranscriptionResult
    }

    static func inspect(dataset: AnalyzerOptimizationDataset) throws -> TrainingTranscriptCoverage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var readyCount = 0
        var missing: [AnalyzerOptimizationDataset.Example] = []
        missing.reserveCapacity(dataset.examples.count)

        for example in dataset.examples {
            let cacheURL = dataset.transcriptCacheDirectory.appending(path: "\(example.example.audio.sha256).json")
            guard FileManager.default.fileExists(atPath: cacheURL.path()) else {
                missing.append(example)
                continue
            }

            do {
                let data = try Data(contentsOf: cacheURL)
                let cached = try decoder.decode(CachedTranscription.self, from: data)
                if cached.audioSHA256 == example.example.audio.sha256 {
                    readyCount += 1
                } else {
                    missing.append(example)
                }
            } catch {
                missing.append(example)
            }
        }

        return TrainingTranscriptCoverage(
            readyExampleCount: readyCount,
            totalExampleCount: dataset.examples.count,
            missingExamples: missing
        )
    }
}

@MainActor
@Observable
final class TrainingWorkflowController {
    private let engine: any TrainingWorkflowEngine
    private let now: @Sendable () -> Date

    private var runTask: Task<Void, Never>?

    var state: TrainingWorkflowState = .idle
    var datasetSnapshot: TrainingWorkflowDatasetSnapshot = .empty
    var lastRunSummary: TrainingWorkflowSummary?
    var isSheetPresented = false

    init(
        engine: (any TrainingWorkflowEngine)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.engine = engine ?? DefaultTrainingWorkflowEngine()
        self.now = now
    }

    var isRunning: Bool { state.isRunning }

    func refreshSnapshot() async {
        do {
            let dataset = try engine.loadDataset()
            let coverage = try engine.inspectTranscriptCoverage(dataset: dataset)
            datasetSnapshot = TrainingWorkflowDatasetSnapshot(dataset: dataset, coverage: coverage)
        } catch {
            datasetSnapshot = TrainingWorkflowDatasetSnapshot(errorMessage: error.localizedDescription)
        }
    }

    func startMeasure() {
        start(.measure)
    }

    func startOptimize() {
        start(.optimize)
    }

    func cancel() async {
        runTask?.cancel()
        await engine.cancelCurrentWork()
    }

    func waitForRunCompletion() async {
        await runTask?.value
    }

    private func start(_ action: TrainingWorkflowAction) {
        guard runTask == nil else {
            isSheetPresented = true
            return
        }

        isSheetPresented = true
        runTask = Task { @MainActor in
            await execute(action)
        }
    }

    private func execute(_ action: TrainingWorkflowAction) async {
        defer { runTask = nil }

        do {
            state = .preflighting
            try Task.checkCancellation()

            let dataset = try engine.loadDataset()
            let coverage = try engine.inspectTranscriptCoverage(dataset: dataset)
            datasetSnapshot = TrainingWorkflowDatasetSnapshot(dataset: dataset, coverage: coverage)

            guard !dataset.examples.isEmpty else {
                throw AnalyzerOptimizerError.emptyDataset
            }

            if !coverage.missingExamples.isEmpty {
                state = .transcribing(
                    current: 0,
                    total: coverage.missingExamples.count,
                    filename: coverage.missingExamples.first?.originalFilename ?? "audio"
                )
                let updatedCoverage = try await engine.prepareTranscripts(for: dataset) { current, total, filename in
                    self.state = .transcribing(current: current, total: total, filename: filename)
                }
                datasetSnapshot = TrainingWorkflowDatasetSnapshot(dataset: dataset, coverage: updatedCoverage)
            }

            try Task.checkCancellation()

            let summary: TrainingWorkflowSummary
            switch action {
            case .measure:
                state = .measuring
                let result = try await engine.measure()
                summary = TrainingWorkflowSummary(
                    action: .measure,
                    finishedAt: now(),
                    matchPercentage: result.scorecard.matchPercentage,
                    exampleCount: result.scorecard.evaluatedExampleCount,
                    outputDirectoryURL: result.outputURL.deletingLastPathComponent(),
                    scorecardURL: result.outputURL,
                    optimizedConfigURL: nil,
                    reportURL: nil
                )
            case .optimize:
                state = .optimizing(generation: nil, message: "Preparing optimizer...")
                let result = try await engine.optimize { progress in
                    await MainActor.run {
                        self.state = .optimizing(
                            generation: progress.generation,
                            message: progress.message
                        )
                    }
                }
                summary = TrainingWorkflowSummary(
                    action: .optimize,
                    finishedAt: now(),
                    matchPercentage: result.scorecard.matchPercentage,
                    exampleCount: result.scorecard.evaluatedExampleCount,
                    outputDirectoryURL: result.outputFiles.scorecardURL.deletingLastPathComponent(),
                    scorecardURL: result.outputFiles.scorecardURL,
                    optimizedConfigURL: result.outputFiles.configURL,
                    reportURL: result.outputFiles.reportURL
                )
            }

            lastRunSummary = summary
            state = .completed(summary)
            await refreshSnapshot()
        } catch is CancellationError {
            state = .failed("Run cancelled.")
            await refreshSnapshot()
        } catch {
            state = .failed(error.localizedDescription)
            await refreshSnapshot()
        }
    }
}
