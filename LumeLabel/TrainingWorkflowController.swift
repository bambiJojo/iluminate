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
    let evaluationMode: AnalyzerEvaluationMode
    let matchPercentage: Double
    let exampleCount: Int
    let outputDirectoryURL: URL
    let scorecardURL: URL
    let optimizedConfigURL: URL?
    let activeConfigURL: URL?
    let reportURL: URL?
}

struct TrainingWorkflowResumeSnapshot: Sendable {
    let savedAt: Date
    let generation: Int?
    let outputDirectoryURL: URL
    let checkpointURL: URL
    let detail: String
}

struct TrainingWorkflowProgressSnapshot: Sendable {
    let title: String
    let message: String
    let completedUnitCount: Int?
    let totalUnitCount: Int?
    let startedAt: Date
    let updatedAt: Date
    let isEstimatedTotal: Bool

    var fractionCompleted: Double? {
        guard let completedUnitCount, let totalUnitCount, totalUnitCount > 0 else { return nil }
        return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
    }

    var elapsedTime: TimeInterval {
        max(0, updatedAt.timeIntervalSince(startedAt))
    }

    var remainingTimeEstimate: TimeInterval? {
        guard
            let completedUnitCount,
            let totalUnitCount,
            totalUnitCount > 0,
            completedUnitCount > 0,
            completedUnitCount < totalUnitCount
        else {
            return nil
        }

        let unitsPerSecond = Double(completedUnitCount) / max(elapsedTime, 0.001)
        guard unitsPerSecond > 0 else { return nil }
        return Double(totalUnitCount - completedUnitCount) / unitsPerSecond
    }
}

enum TrainingWorkflowState: Sendable {
    case idle
    case preflighting
    case transcribing(current: Int, total: Int, filename: String)
    case measuring
    case optimizing(generation: Int?, message: String)
    case paused(TrainingWorkflowResumeSnapshot)
    case completed(TrainingWorkflowSummary)
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .idle, .paused, .completed, .failed:
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
        case .paused:
            return "Optimization Paused"
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
        case .paused(let snapshot):
            return snapshot.detail
        case .completed(let summary):
            return "\(summary.exampleCount) examples evaluated in \(summary.evaluationMode.displayName) mode with \(summary.matchPercentage.formatted(.number.precision(.fractionLength(2))))% overall match."
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

struct TrainingWorkflowPhaseBreakdown: Identifiable, Hashable, Sendable {
    let phase: TrancePhase
    let segmentCount: Int
    let durationSeconds: TimeInterval

    var id: String { phase.rawValue }
}

struct TrainingWorkflowDatasetSnapshot: Sendable {
    let validExampleCount: Int
    let readyTranscriptCount: Int
    let totalTranscriptCount: Int
    let issueCount: Int
    let handLabeledExampleCount: Int
    let silverLabeledExampleCount: Int
    let phaseBreakdown: [TrainingWorkflowPhaseBreakdown]
    let errorMessage: String?

    init(
        validExampleCount: Int,
        readyTranscriptCount: Int,
        totalTranscriptCount: Int,
        issueCount: Int,
        handLabeledExampleCount: Int,
        silverLabeledExampleCount: Int,
        phaseBreakdown: [TrainingWorkflowPhaseBreakdown],
        errorMessage: String?
    ) {
        self.validExampleCount = validExampleCount
        self.readyTranscriptCount = readyTranscriptCount
        self.totalTranscriptCount = totalTranscriptCount
        self.issueCount = issueCount
        self.handLabeledExampleCount = handLabeledExampleCount
        self.silverLabeledExampleCount = silverLabeledExampleCount
        self.phaseBreakdown = phaseBreakdown
        self.errorMessage = errorMessage
    }

    static let empty = TrainingWorkflowDatasetSnapshot(
        validExampleCount: 0,
        readyTranscriptCount: 0,
        totalTranscriptCount: 0,
        issueCount: 0,
        handLabeledExampleCount: 0,
        silverLabeledExampleCount: 0,
        phaseBreakdown: [],
        errorMessage: nil
    )

    init(dataset: AnalyzerOptimizationDataset, coverage: TrainingTranscriptCoverage) {
        self.validExampleCount = dataset.examples.count
        self.readyTranscriptCount = coverage.readyExampleCount
        self.totalTranscriptCount = coverage.totalExampleCount
        self.issueCount = dataset.issues.count
        self.handLabeledExampleCount = dataset.examples.filter { !Self.isSilverLabel($0) }.count
        self.silverLabeledExampleCount = dataset.examples.filter(Self.isSilverLabel).count
        self.phaseBreakdown = Self.makePhaseBreakdown(for: dataset.examples)
        self.errorMessage = nil
    }

    init(errorMessage: String) {
        self.validExampleCount = 0
        self.readyTranscriptCount = 0
        self.totalTranscriptCount = 0
        self.issueCount = 0
        self.handLabeledExampleCount = 0
        self.silverLabeledExampleCount = 0
        self.phaseBreakdown = []
        self.errorMessage = errorMessage
    }

    var coveredPhaseCount: Int {
        phaseBreakdown.filter { $0.segmentCount > 0 }.count
    }

    var totalPhaseCount: Int {
        TrancePhase.orderedHypnosisPhases.count
    }

    var qualityWarning: String? {
        guard validExampleCount > 0 else { return nil }
        if silverLabeledExampleCount > handLabeledExampleCount, handLabeledExampleCount < 10 {
            return "Silver labels dominate this dataset (\(silverLabeledExampleCount)/\(validExampleCount))."
        }
        return nil
    }

    var compactPhaseCoverageText: String {
        let presentPhases = phaseBreakdown
            .filter { $0.segmentCount > 0 }
            .sorted {
                if $0.segmentCount == $1.segmentCount {
                    return Self.phaseSortIndex($0.phase) < Self.phaseSortIndex($1.phase)
                }
                return $0.segmentCount > $1.segmentCount
            }

        guard !presentPhases.isEmpty else { return "No phase coverage" }

        let leading = presentPhases.prefix(4)
            .map { "\($0.phase.displayName) \($0.segmentCount)" }
            .joined(separator: " · ")
        let remainingCount = presentPhases.count - min(presentPhases.count, 4)
        if remainingCount > 0 {
            return "\(leading) · +\(remainingCount) more"
        }
        return leading
    }

    private nonisolated static func makePhaseBreakdown(
        for examples: [AnalyzerOptimizationDataset.Example]
    ) -> [TrainingWorkflowPhaseBreakdown] {
        TrancePhase.orderedHypnosisPhases.map { phase in
            let segments = examples.flatMap(\.phaseSegments).filter { $0.phase == phase }
            return TrainingWorkflowPhaseBreakdown(
                phase: phase,
                segmentCount: segments.count,
                durationSeconds: segments.reduce(0) { $0 + $1.durationSeconds }
            )
        }
    }

    private nonisolated static func isSilverLabel(_ example: AnalyzerOptimizationDataset.Example) -> Bool {
        example.example.labels.labelerNotes
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("silver label:")
    }

    private nonisolated static func phaseSortIndex(_ phase: TrancePhase) -> Int {
        TrancePhase.orderedHypnosisPhases.firstIndex(of: phase) ?? Int.max
    }
}

@MainActor
protocol TrainingWorkflowEngine: AnyObject {
    func loadDataset() async throws -> AnalyzerOptimizationDataset
    func inspectTranscriptCoverage(dataset: AnalyzerOptimizationDataset) async throws -> TrainingTranscriptCoverage
    func loadOptimizationCheckpoint() throws -> AnalyzerOptimizer.Checkpoint?
    func prepareTranscripts(
        for dataset: AnalyzerOptimizationDataset,
        progress: @escaping @MainActor (_ current: Int, _ total: Int, _ filename: String) -> Void
    ) async throws -> TrainingTranscriptCoverage
    func measure(
        onProgress: @escaping @Sendable (AnalyzerOptimizer.Progress) async -> Void
    ) async throws -> AnalyzerOptimizer.MeasurementResult
    func optimize(
        resuming: Bool,
        onProgress: @escaping @Sendable (AnalyzerOptimizer.Progress) async -> Void
    ) async throws -> AnalyzerOptimizer.RunResult
    func requestPause() async
    func cancelCurrentWork() async
}

@MainActor
final class DefaultTrainingWorkflowEngine: TrainingWorkflowEngine {
    static let optimizationEvaluationMode: AnalyzerEvaluationMode = .keywordOnly
    static let liveEvaluationMode: AnalyzerEvaluationMode = .hybridRuntime
    static let hybridRefinementPopulationSize = 8
    static let hybridRefinementGenerationCount = 8
    static let hybridRefinementEarlyStopPatience = 4

    actor RunControl {
        private var pauseRequested = false

        func requestPause() {
            pauseRequested = true
        }

        func shouldPause() -> Bool {
            pauseRequested
        }

        func reset() {
            pauseRequested = false
        }
    }

    private let optimizer: AnalyzerOptimizer
    private let corpusDirectory: URL
    private let audioAnalyzer: AudioAnalyzer
    private let runControl = RunControl()

    init(
        corpusDirectory: URL = TrainingCorpusLocation.defaultURL(),
        outputDirectory: URL = URL.documentsDirectory.appending(path: "TrainingOutput"),
        audioAnalyzer: AudioAnalyzer? = nil
    ) {
        self.corpusDirectory = corpusDirectory
        self.optimizer = AnalyzerOptimizer(
            corpusDirectory: corpusDirectory,
            outputDirectory: outputDirectory
        )
        self.audioAnalyzer = audioAnalyzer ?? AudioAnalyzer()
    }

    func loadDataset() async throws -> AnalyzerOptimizationDataset {
        let corpusDirectory = corpusDirectory
        return try await Task.detached(priority: .userInitiated) {
            try AnalyzerOptimizationDataset.load(from: corpusDirectory)
        }.value
    }

    func inspectTranscriptCoverage(
        dataset: AnalyzerOptimizationDataset
    ) async throws -> TrainingTranscriptCoverage {
        try await Task.detached(priority: .utility) {
            try TrainingTranscriptCoverageInspector.inspect(dataset: dataset)
        }.value
    }

    func loadOptimizationCheckpoint() throws -> AnalyzerOptimizer.Checkpoint? {
        try optimizer.loadCheckpoint()
    }

    func prepareTranscripts(
        for dataset: AnalyzerOptimizationDataset,
        progress: @escaping @MainActor (_ current: Int, _ total: Int, _ filename: String) -> Void
    ) async throws -> TrainingTranscriptCoverage {
        let coverage = try await inspectTranscriptCoverage(dataset: dataset)
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
        return try await inspectTranscriptCoverage(dataset: dataset)
    }

    func measure(
        onProgress: @escaping @Sendable (AnalyzerOptimizer.Progress) async -> Void
    ) async throws -> AnalyzerOptimizer.MeasurementResult {
        try Task.checkCancellation()
        return try await optimizer.measure(
            config: AnalyzerConfigLoader.load(),
            evaluationMode: Self.liveEvaluationMode,
            onProgress: onProgress
        )
    }

    func optimize(
        resuming: Bool,
        onProgress: @escaping @Sendable (AnalyzerOptimizer.Progress) async -> Void
    ) async throws -> AnalyzerOptimizer.RunResult {
        try Task.checkCancellation()
        await runControl.reset()
        let checkpoint = resuming ? try optimizer.loadCheckpoint() : nil
        let checkpointMode = checkpoint?.params.evaluationMode
        if !resuming {
            try? optimizer.clearCheckpoint()
        }

        defer {
            Task {
                await runControl.reset()
            }
        }

        let pauseRequested: @Sendable () async -> Bool = { [runControl] in
            await runControl.shouldPause()
        }

        let keywordParams = AnalyzerOptimizer.Parameters(
            evaluationMode: Self.optimizationEvaluationMode,
            publishBestConfigToDocuments: false
        )
        let hybridParams = AnalyzerOptimizer.Parameters(
            populationSize: Self.hybridRefinementPopulationSize,
            maxGenerations: Self.hybridRefinementGenerationCount,
            elitismCount: 1,
            mutationRate: 0.80,
            earlyStopPatience: Self.hybridRefinementEarlyStopPatience,
            evaluationMode: Self.liveEvaluationMode,
            publishBestConfigToDocuments: true
        )

        if checkpointMode == Self.liveEvaluationMode {
            return try await optimizer.run(
                params: hybridParams,
                resumeFrom: checkpoint,
                onProgress: onProgress,
                pauseRequested: pauseRequested
            )
        }

        let keywordResult = try await optimizer.run(
            seedConfig: AnalyzerConfigLoader.load(),
            params: keywordParams,
            resumeFrom: checkpointMode == Self.optimizationEvaluationMode ? checkpoint : nil,
            onProgress: onProgress,
            pauseRequested: pauseRequested
        )

        await onProgress(
            AnalyzerOptimizer.Progress(
                title: "Optimizing Analyzer",
                message: "Keyword optimization complete. Starting \(Self.liveEvaluationMode.displayName) refinement.",
                generation: nil,
                completedUnitCount: nil,
                totalUnitCount: nil,
                isEstimatedTotal: true
            )
        )

        return try await optimizer.run(
            seedConfig: keywordResult.bestConfig,
            params: hybridParams,
            onProgress: onProgress,
            pauseRequested: pauseRequested
        )
    }

    func requestPause() async {
        await runControl.requestPause()
    }

    func cancelCurrentWork() async {
        await runControl.reset()
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

    nonisolated static func inspect(
        dataset: AnalyzerOptimizationDataset
    ) throws -> TrainingTranscriptCoverage {
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
    var resumableOptimization: TrainingWorkflowResumeSnapshot?
    var progressSnapshot: TrainingWorkflowProgressSnapshot?
    var isSheetPresented = false
    var isPauseRequested = false

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
            let dataset = try await engine.loadDataset()
            let coverage = try await engine.inspectTranscriptCoverage(dataset: dataset)
            datasetSnapshot = TrainingWorkflowDatasetSnapshot(dataset: dataset, coverage: coverage)
            if let checkpoint = try engine.loadOptimizationCheckpoint(),
               checkpoint.datasetHash == dataset.datasetHash {
                resumableOptimization = makeResumeSnapshot(from: checkpoint)
                if case .idle = state {
                    state = .paused(makeResumeSnapshot(from: checkpoint))
                }
            } else {
                resumableOptimization = nil
                if case .paused = state {
                    state = .idle
                }
            }
        } catch {
            datasetSnapshot = TrainingWorkflowDatasetSnapshot(errorMessage: error.localizedDescription)
            resumableOptimization = nil
        }
    }

    func startMeasure() {
        start(.measure)
    }

    func startOptimize() {
        start(.optimize, resume: resumableOptimization != nil)
    }

    func resumeOptimize() {
        guard resumableOptimization != nil else {
            startOptimize()
            return
        }
        start(.optimize, resume: true)
    }

    func requestPause() async {
        guard case .optimizing = state else { return }
        isPauseRequested = true
        state = .optimizing(
            generation: currentOptimizationGeneration,
            message: "Pause requested. Saving after the current generation finishes..."
        )
        await engine.requestPause()
    }

    func cancel() async {
        runTask?.cancel()
        await engine.cancelCurrentWork()
    }

    func waitForRunCompletion() async {
        await runTask?.value
    }

    private func start(_ action: TrainingWorkflowAction, resume: Bool = false) {
        guard runTask == nil else {
            isSheetPresented = true
            return
        }

        isSheetPresented = true
        runTask = Task { @MainActor in
            await execute(action, resume: resume)
        }
    }

    private func execute(_ action: TrainingWorkflowAction, resume: Bool) async {
        defer { runTask = nil }

        do {
            isPauseRequested = false
            state = .preflighting
            updateProgress(
                title: state.title,
                message: state.detail,
                completedUnitCount: nil,
                totalUnitCount: nil,
                isEstimatedTotal: false
            )
            try Task.checkCancellation()

            let dataset = try await engine.loadDataset()
            let coverage = try await engine.inspectTranscriptCoverage(dataset: dataset)
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
                    self.updateProgress(
                        title: self.state.title,
                        message: "Working on \(filename)",
                        completedUnitCount: current,
                        totalUnitCount: total,
                        isEstimatedTotal: false
                    )
                }
                datasetSnapshot = TrainingWorkflowDatasetSnapshot(dataset: dataset, coverage: updatedCoverage)
            }

            try Task.checkCancellation()

            let summary: TrainingWorkflowSummary
            switch action {
            case .measure:
                state = .measuring
                updateProgress(
                    title: state.title,
                    message: state.detail,
                    completedUnitCount: nil,
                    totalUnitCount: nil,
                    isEstimatedTotal: false
                )
                let result = try await engine.measure { progress in
                    await MainActor.run {
                        self.updateProgress(from: progress)
                    }
                }
                summary = TrainingWorkflowSummary(
                    action: .measure,
                    finishedAt: now(),
                    evaluationMode: result.scorecard.evaluationMode,
                    matchPercentage: result.scorecard.matchPercentage,
                    exampleCount: result.scorecard.evaluatedExampleCount,
                    outputDirectoryURL: result.outputURL.deletingLastPathComponent(),
                    scorecardURL: result.outputURL,
                    optimizedConfigURL: nil,
                    activeConfigURL: nil,
                    reportURL: nil
                )
            case .optimize:
                let preparationMessage = resume ? "Resuming optimizer..." : "Preparing optimizer..."
                state = .optimizing(generation: nil, message: preparationMessage)
                updateProgress(
                    title: state.title,
                    message: state.detail,
                    completedUnitCount: nil,
                    totalUnitCount: nil,
                    isEstimatedTotal: true
                )
                let result = try await engine.optimize(resuming: resume) { progress in
                    await MainActor.run {
                        self.state = .optimizing(
                            generation: progress.generation,
                            message: progress.message
                        )
                        self.updateProgress(from: progress)
                    }
                }
                summary = TrainingWorkflowSummary(
                    action: .optimize,
                    finishedAt: now(),
                    evaluationMode: result.scorecard.evaluationMode,
                    matchPercentage: result.scorecard.matchPercentage,
                    exampleCount: result.scorecard.evaluatedExampleCount,
                    outputDirectoryURL: result.outputFiles.scorecardURL.deletingLastPathComponent(),
                    scorecardURL: result.outputFiles.scorecardURL,
                    optimizedConfigURL: result.outputFiles.configURL,
                    activeConfigURL: AnalyzerConfigLoader.documentsConfigURL,
                    reportURL: result.outputFiles.reportURL
                )
            }

            resumableOptimization = nil
            lastRunSummary = summary
            progressSnapshot = nil
            isPauseRequested = false
            state = .completed(summary)
            await refreshSnapshot()
        } catch AnalyzerOptimizerError.paused {
            progressSnapshot = nil
            isPauseRequested = false
            do {
                if let checkpoint = try engine.loadOptimizationCheckpoint() {
                    let snapshot = makeResumeSnapshot(from: checkpoint)
                    resumableOptimization = snapshot
                    state = .paused(snapshot)
                } else {
                    state = .failed("The optimizer paused, but no resumable checkpoint could be found.")
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
            await refreshSnapshot()
        } catch is CancellationError {
            progressSnapshot = nil
            isPauseRequested = false
            state = .failed("Run cancelled.")
            await refreshSnapshot()
        } catch {
            progressSnapshot = nil
            isPauseRequested = false
            state = .failed(error.localizedDescription)
            await refreshSnapshot()
        }
    }

    private func updateProgress(from progress: AnalyzerOptimizer.Progress) {
        updateProgress(
            title: progress.title,
            message: progress.message,
            completedUnitCount: progress.completedUnitCount,
            totalUnitCount: progress.totalUnitCount,
            isEstimatedTotal: progress.isEstimatedTotal
        )
    }

    private func updateProgress(
        title: String,
        message: String,
        completedUnitCount: Int?,
        totalUnitCount: Int?,
        isEstimatedTotal: Bool
    ) {
        let timestamp = now()
        let startedAt: Date
        if let progressSnapshot, progressSnapshot.title == title {
            startedAt = progressSnapshot.startedAt
        } else {
            startedAt = timestamp
        }

        progressSnapshot = TrainingWorkflowProgressSnapshot(
            title: title,
            message: message,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            startedAt: startedAt,
            updatedAt: timestamp,
            isEstimatedTotal: isEstimatedTotal
        )
    }

    private var currentOptimizationGeneration: Int? {
        if case .optimizing(let generation, _) = state {
            return generation
        }
        return nil
    }

    private func makeResumeSnapshot(from checkpoint: AnalyzerOptimizer.Checkpoint) -> TrainingWorkflowResumeSnapshot {
        let generation = checkpoint.stage == .generationLoop ? checkpoint.nextGeneration : checkpoint.bestGeneration
        let detail: String
        switch checkpoint.stage {
        case .generationLoop:
            detail = "Saved after generation \(max(generation, 0)). Resume when you're ready."
        case .finalization:
            detail = "Saved before final scorecard generation. Resume to finish writing the optimized results."
        }

        return TrainingWorkflowResumeSnapshot(
            savedAt: checkpoint.savedAt,
            generation: generation,
            outputDirectoryURL: URL.documentsDirectory.appending(path: "TrainingOutput"),
            checkpointURL: URL.documentsDirectory.appending(path: "TrainingOutput/AnalyzerOptimizationCheckpoint.json"),
            detail: detail
        )
    }
}
