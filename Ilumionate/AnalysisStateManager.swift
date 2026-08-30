//
//  AnalysisStateManager.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/24/26.
//

import os
import Foundation
import Observation

private nonisolated struct CachedAudioAnalysis: Codable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let cachedAt: Date
    let transcription: AudioTranscriptionResult?
    let analysis: AnalysisResult
    let trackMetadata: AudioTrackMetadata?

    init(
        transcription: AudioTranscriptionResult?,
        analysis: AnalysisResult,
        trackMetadata: AudioTrackMetadata?
    ) {
        schemaVersion = Self.currentSchemaVersion
        cachedAt = .now
        self.transcription = transcription
        self.analysis = analysis
        self.trackMetadata = trackMetadata
    }
}

private nonisolated struct CachedAnalysisLoad: Sendable {
    let results: [String: CachedAudioAnalysis]
    let migratedLegacyCache: Bool
}

/// Serializes complete cache snapshots away from MainActor. The cache can hold
/// full transcript statistics, so encoding it synchronously made every
/// completed file freeze the UI for roughly 400–450 ms on device.
private actor AnalysisCachePersistence {
    func save(_ results: [String: CachedAudioAnalysis], to url: URL) {
        let trace = PerformanceTrace.begin("Analysis Cache Persist")
        defer { PerformanceTrace.end(trace) }

        guard let data = try? JSONEncoder().encode(results) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Analysis Stage

nonisolated enum AnalysisStage: Sendable {
    case starting
    case transcribing
    case analyzing
    case generatingSession
    case complete
    case failed
}

/// Enhanced analysis manager with modern Swift 6 concurrency optimizations
@MainActor @Observable
class AnalysisStateManager {

    // MARK: - Singleton

    static let shared = AnalysisStateManager()

    // MARK: - State

    var currentAnalysis: ActiveAnalysis?
    var analysisQueue: [AudioFile] = []
    var completedAnalyses: [CompletedAnalysis] = []
    var failedAnalyses: [FailedAnalysis] = []
    private(set) var partialResultsRevision = 0
    var onAnalysisComplete: (@Sendable (AudioFile, CompletedAnalysis) -> Void)?

    // MARK: - Initialization

    /// Production singleton — uses the live ML-backed implementations.
    private init(
        progressStore: AnalysisProgressStore = .shared,
        preferences: AnalysisPreferences? = nil,
        cacheURL: URL = AnalysisStateManager.cacheURL
    ) {
        self.analysisCoordinator = AnalysisCoordinator()
        self.audioAnalyzer = AudioAnalyzer()
        self.aiAnalyzer = AIContentAnalyzer()
        self.progressStore = progressStore
        self.preferences = preferences ?? .shared
        self.analysisCacheURL = cacheURL
        self.scheduleBackgroundAnalysis = { audioFiles in
            BackgroundAnalysisScheduler.shared.schedule(for: audioFiles)
        }
        // Cache decoding is deliberately deferred until ContentView's task.
        // The production cache can contain full transcript statistics; loading
        // it here makes this singleton's first access part of SwiftUI's initial
        // frame and previously added ~231 ms to cold launch on device.
    }

    /// Testable initializer — inject mock services for unit testing.
    /// Not intended for production use; use `shared` instead.
    init(
        transcriber: any AudioTranscribingService,
        analyzer: any ContentAnalyzingService,
        progressStore: AnalysisProgressStore = .shared,
        preferences: AnalysisPreferences? = nil,
        cacheURL: URL = AnalysisStateManager.cacheURL,
        stageOverlapOverride: Bool? = nil,
        watchdogPolicy: AnalysisWatchdogPolicy = AnalysisWatchdogPolicy(),
        eagerlyLoadsCache: Bool = true,
        scheduleBackgroundAnalysis: @escaping @MainActor ([AudioFile]) -> Void = { audioFiles in
            BackgroundAnalysisScheduler.shared.schedule(for: audioFiles)
        }
    ) {
        self.analysisCoordinator = AnalysisCoordinator(
            stageOverlapOverride: stageOverlapOverride,
            watchdogPolicy: watchdogPolicy
        )
        self.audioAnalyzer = transcriber
        self.aiAnalyzer = analyzer
        self.progressStore = progressStore
        self.preferences = preferences ?? .shared
        self.analysisCacheURL = cacheURL
        self.scheduleBackgroundAnalysis = scheduleBackgroundAnalysis
        if eagerlyLoadsCache {
            loadCachedResultsSynchronously()
        }
    }

    // MARK: - Actor-Isolated State Management

    private let analysisCoordinator: AnalysisCoordinator
    private let audioAnalyzer: any AudioTranscribingService
    private let aiAnalyzer: any ContentAnalyzingService
    private let performanceOptimizer = PerformanceOptimizer.shared

    // Injected stores — default to the shared singletons; injectable for testing.
    private let progressStore: AnalysisProgressStore
    private let preferences: AnalysisPreferences
    private let analysisCacheURL: URL
    private let scheduleBackgroundAnalysis: @MainActor ([AudioFile]) -> Void
    private var automaticProcessingTask: Task<Void, Never>?
    @ObservationIgnored private var quarantinedAttemptID: UUID?
    @ObservationIgnored private var restartAfterCurrentProcessor = false
    /// Priority the queue is currently being drained at, so a resume after a
    /// stall keeps it. `endAnalysisResourceQuarantine` used the default
    /// `.background`, which silently demoted a user-initiated run for the rest
    /// of the queue — invisible on macOS, where `.background` is barely
    /// throttled, and a crawl on iOS, where it is.
    @ObservationIgnored private var activeProcessingPriority: TaskPriority = .background
    @ObservationIgnored private var cachedResultsLoadTask: Task<CachedAnalysisLoad, Never>?
    @ObservationIgnored private var hasLoadedCachedResults = false
    @ObservationIgnored private let cachePersistence = AnalysisCachePersistence()

    // MARK: - Queue Management

    /// Remove a file from the analysis queue
    /// Dismisses a failure occurrence: it leaves the pill and the attention
    /// tier but stays listed, and its checkpoint survives so a later retry
    /// still resumes from the saved transcript.
    ///
    /// An `.unavailable` failure has no checkpoint — that path clears it before
    /// the failure is recorded — so there is nothing durable to annotate and
    /// nothing that could restore it. Dismissing one succeeds immediately.
    @discardableResult
    func dismissFailure(fileID: UUID, failedAt: Date, retryState: AnalysisRetryState) async -> Bool {
        if retryState == .unavailable {
            failedAnalyses.removeAll { $0.audioFile.id == fileID }
            return true
        }
        guard await progressStore.dismiss(fileID: fileID, expectingFailedAt: failedAt) else {
            return false
        }
        failedAnalyses.removeAll { $0.audioFile.id == fileID }
        return true
    }

    /// Destructive: clears the checkpoint *and* the runtime entry. Discards any
    /// saved transcript or analysis. Mutating `failedAnalyses` matters — the
    /// next structural refresh would otherwise rebuild the row.
    @discardableResult
    func removeFailure(fileID: UUID, failedAt: Date, retryState: AnalysisRetryState) async -> Bool {
        if retryState == .unavailable {
            failedAnalyses.removeAll { $0.audioFile.id == fileID }
            return true
        }
        guard await progressStore.remove(fileID: fileID, expectingFailedAt: failedAt) else {
            return false
        }
        failedAnalyses.removeAll { $0.audioFile.id == fileID }
        return true
    }

    /// Re-runs the AI stage for files that were declined for a passing reason.
    ///
    /// Called when the app backgrounds, because that is where the model
    /// actually answers: the device recorded `foreground 0/16 used AI,
    /// background 3/7`. Each file re-runs from its saved transcript, so this
    /// costs a model call rather than a WhisperKit pass.
    ///
    /// Attempts are counted *before* running, so a crash or a jetsam mid-retry
    /// still consumes budget instead of leaving the file to loop.
    func retryDeferredAIAnalyses() async {
        let candidates = DeferredAIAnalysisPolicy.candidates(
            from: await progressStore.deferredAIRetryCheckpoints()
        )
        guard candidates.isEmpty == false else { return }

        Log.analysis.info("↺ Retrying AI for \(candidates.count) deferred file(s)")

        let library = AudioLibraryStore.load()
        for (index, candidate) in candidates.enumerated() {
            guard !Task.isCancelled else { break }
            guard let audioFile = library.first(where: { $0.id == candidate.audioFileID }) else {
                continue
            }

            // Spacing exists because a successful AI stage is followed by one
            // chunk request per 15 seconds of transcript. See the spec: the
            // interval that actually avoids rate limiting is unmeasured.
            if index > 0 {
                try? await Task.sleep(for: DeferredAIAnalysisPolicy.spacingBetweenAttempts)
                guard !Task.isCancelled else { break }
            }

            await progressStore.recordAIRetryAttempt(for: candidate.audioFileID)
            // Without eviction the cached keyword result is reused and the
            // retry is a no-op. `saveQueued` clears the deferral so the file
            // becomes ordinary pending work again.
            await evictCachedResult(for: audioFile)
            await queueForAnalysis(audioFile)
        }
    }

    /// Flattens the durable store into plain values for the task projection.
    /// Exists so `AnalysisCenterModel` never reaches into the private actor.
    func recoverySnapshot() async -> (
        checkpoints: [UUID: AnalysisCheckpointSnapshot],
        failures: [UUID: AnalysisFailureSnapshot]
    ) {
        let all = await progressStore.allCheckpoints()
        var checkpoints: [UUID: AnalysisCheckpointSnapshot] = [:]
        var failures: [UUID: AnalysisFailureSnapshot] = [:]
        for checkpoint in all {
            let id = checkpoint.audioFile.id
            checkpoints[id] = AnalysisTaskInputAssembler.checkpointSnapshot(from: checkpoint)
            if let failure = AnalysisTaskInputAssembler.failureSnapshot(from: checkpoint) {
                failures[id] = failure
            }
        }
        return (checkpoints, failures)
    }

    func removeFromQueue(audioFile: AudioFile) {
        analysisQueue.removeAll { $0.id == audioFile.id }
        Log.analysis.info("🗑 Removed \(audioFile.filename) from analysis queue")
    }

    /// Move a file up in the queue (closer to front)
    func moveUpInQueue(audioFile: AudioFile) {
        guard let currentIndex = analysisQueue.firstIndex(where: { $0.id == audioFile.id }),
              currentIndex > 0 else { return }

        analysisQueue.swapAt(currentIndex, currentIndex - 1)
        Log.analysis.info("⬆️ Moved \(audioFile.filename) up in queue")
    }

    /// Move a file down in the queue (further back)
    func moveDownInQueue(audioFile: AudioFile) {
        guard let currentIndex = analysisQueue.firstIndex(where: { $0.id == audioFile.id }),
              currentIndex < analysisQueue.count - 1 else { return }

        analysisQueue.swapAt(currentIndex, currentIndex + 1)
        Log.analysis.info("⬇️ Moved \(audioFile.filename) down in queue")
    }

    /// Get queue position for a file (1-indexed, 0 if not in queue)
    func queuePosition(for audioFile: AudioFile) -> Int {
        guard let index = analysisQueue.firstIndex(where: { $0.id == audioFile.id }) else { return 0 }
        return index + 1
    }

    /// Clear entire analysis queue
    func clearQueue() {
        analysisQueue.removeAll()
        Log.analysis.info("🧹 Cleared analysis queue")
    }

    /// Move a file to the front of the analysis queue for immediate processing
    func prioritizeInQueue(audioFile: AudioFile) {
        guard let index = analysisQueue.firstIndex(where: { $0.id == audioFile.id }),
              index > 0 else { return }
        let file = analysisQueue.remove(at: index)
        analysisQueue.insert(file, at: 0)
        Log.analysis.info("⚡ Prioritized \(audioFile.filename) to front of queue")
    }

    // MARK: - Analysis Control

    /// Add a single audio file to queue and start automatic background processing
    func queueForAnalysis(_ audioFile: AudioFile, priority: TaskPriority = .background) async {
        await prepareCachedResults()

        if await completeReviewedCatalogAnalysisIfAvailable(audioFile) {
            return
        }

        guard !isQueuedOrActive(audioFile) else {
            Log.analysis.info("📋 File already in queue: \(audioFile.filename)")
            // A queue can outlive its processor: once the automatic task ends or
            // is cancelled, entries are left with nothing draining them. Returning
            // here made every later retry a silent no-op — the file sat queued
            // forever, emitting no completion, no error, and no telemetry.
            // `startAutomaticProcessing` awaits any live task and no-ops on an
            // empty queue, so re-arming is always safe.
            await startAutomaticProcessing(priority: priority)
            return
        }

        await progressStore.saveQueued(audioFile)
        analysisQueue.append(audioFile)
        Log.analysis.info("📋 Added to queue: \(audioFile.filename) (position \(self.analysisQueue.count))")
        scheduleBackgroundAnalysis([audioFile])

        await startAutomaticProcessing(priority: priority)
    }

    /// Add multiple files to queue and start automatic background processing
    func queueForAnalysis(_ audioFiles: [AudioFile], priority: TaskPriority = .background) async {
        await prepareCachedResults()

        var newFilesAdded = 0

        // Add all files to queue (avoid duplicates)
        for audioFile in audioFiles {
            if await completeReviewedCatalogAnalysisIfAvailable(audioFile) {
                continue
            }
            if !isQueuedOrActive(audioFile) {
                await progressStore.saveQueued(audioFile)
                analysisQueue.append(audioFile)
                newFilesAdded += 1
            }
        }

        Log.analysis.info("📋 Added \(newFilesAdded) files to queue (total: \(self.analysisQueue.count))")
        if newFilesAdded > 0 {
            scheduleBackgroundAnalysis(audioFiles)
        }

        await startAutomaticProcessing(priority: priority)
    }

    /// Restores analyses that exhausted their automatic retry so recovery is
    /// still visible after a relaunch. These checkpoints are deliberately not
    /// added to the automatic queue.
    func restoreManualRecoveries() async {
        for checkpoint in await progressStore.manualRecoveryCheckpoints() {
            guard let recovery = checkpoint.manualRecovery else { continue }
            recordFailure(
                FailedAnalysis(
                    audioFile: checkpoint.audioFile,
                    technicalMessage: "Restored recoverable analysis failure",
                    failedAt: recovery.failedAt,
                    reason: recovery.reason,
                    failedStage: recovery.failedStage,
                    recoveryStage: checkpoint.recoveryStage,
                    retryState: .manual
                )
            )
        }
    }

    /// Explicit user recovery resets the bounded automatic-attempt counter but
    /// leaves saved transcription/analysis data in place for the coordinator.
    func retryFailedAnalysis(_ failure: FailedAnalysis) async {
        guard failure.presentation.canRetry else { return }
        UsageAnalytics.shared.audioAnalyzeRetryRequested(
            reason: failure.reason,
            recoveryStage: failure.recoveryStage
        )
        failedAnalyses.removeAll { $0.id == failure.id }
        await queueForAnalysis(failure.audioFile, priority: .userInitiated)
    }

    func recordFailure(_ failure: FailedAnalysis) {
        if let index = failedAnalyses.firstIndex(where: { $0.id == failure.id }) {
            failedAnalyses[index] = failure
        } else {
            failedAnalyses.append(failure)
        }
    }

    func persistPartialTranscription(
        _ transcription: AudioTranscriptionResult,
        for audioFile: AudioFile
    ) async {
        await AudioLibraryStore.savePartialTranscription(
            transcription.fullText,
            audioFileID: audioFile.id
        )
        partialResultsRevision += 1
    }

    /// Start automatic background processing of the queue
    private func startAutomaticProcessing(priority: TaskPriority = .background) async {
        guard quarantinedAttemptID == nil else {
            restartAfterCurrentProcessor = !analysisQueue.isEmpty
            return
        }

        if let automaticProcessingTask {
            await automaticProcessingTask.value
            return
        }

        guard currentAnalysis == nil && !analysisQueue.isEmpty else {
            return
        }

        activeProcessingPriority = priority

        let task = Task(priority: priority) { [weak self] in
            guard let self else { return }
            await analysisCoordinator.processQueueAutomatically(
                analysisManager: self,
                audioAnalyzer: audioAnalyzer,
                aiAnalyzer: aiAnalyzer,
                progressStore: progressStore,
                performanceOptimizer: performanceOptimizer,
                priority: priority
            ) { [weak self] audioFile, result in
                await self?.handleAnalysisComplete(audioFile: audioFile, result: result)
            }
        }
        automaticProcessingTask = task
        await task.value
        automaticProcessingTask = nil

        if restartAfterCurrentProcessor,
           quarantinedAttemptID == nil,
           !analysisQueue.isEmpty {
            restartAfterCurrentProcessor = false
            await startAutomaticProcessing(priority: priority)
            return
        }

        if await progressStore.allPending().isEmpty {
            await BackgroundAnalysisScheduler.shared.analysisFinished()
        }
    }

    /// Whether this file is waiting in the queue or currently being analyzed.
    /// Surfaced so pickers can show work already in flight instead of offering
    /// to start it again.
    func isQueuedOrActive(_ audioFile: AudioFile) -> Bool {
        analysisQueue.contains { $0.id == audioFile.id }
            || currentAnalysis?.audioFile.id == audioFile.id
    }

    /// Known files already carry a versioned, human-reviewed result. Completing
    /// them here keeps import, retry, and bulk-analysis paths from invoking the
    /// generic on-device language model or replacing the canonical score.
    private func completeReviewedCatalogAnalysisIfAvailable(
        _ audioFile: AudioFile
    ) async -> Bool {
        guard let completed = KnownAudioCatalog.shared.reviewedCompletion(
            for: audioFile
        ) else {
            return false
        }

        await progressStore.clear(for: audioFile)
        completedAnalyses.removeAll { $0.audioFile.id == audioFile.id }
        await handleAnalysisComplete(audioFile: audioFile, result: completed)
        Log.analysis.info("🏅 Applied reviewed catalog analysis: \(audioFile.filename)")
        return true
    }

    /// Legacy method for backward compatibility - now delegates to queueForAnalysis
    func startAnalysis(for audioFile: AudioFile, priority: TaskPriority = .background) async {
        await queueForAnalysis(audioFile, priority: priority)
    }

    /// Legacy method for backward compatibility - now delegates to queueForAnalysis
    func startAnalysis(for audioFiles: [AudioFile], priority: TaskPriority = .background) async {
        await queueForAnalysis(audioFiles, priority: priority)
    }

    /// Cancel the current analysis with proper cleanup
    func cancelCurrentAnalysis() {
        automaticProcessingTask?.cancel()
        Task {
            await audioAnalyzer.cancelTranscription()
            await aiAnalyzer.cancelAnalysis()
        }
        currentAnalysis = nil
    }

    /// Cancel all analyses with structured cleanup
    func cancelAllAnalyses() {
        automaticProcessingTask?.cancel()
        restartAfterCurrentProcessor = false
        Task {
            await audioAnalyzer.cancelTranscription()
            await aiAnalyzer.cancelAnalysis()
        }
        currentAnalysis = nil
        analysisQueue.removeAll()
    }

    /// Stops work at an iOS background-task expiration boundary while keeping
    /// the durable queue/checkpoints available for the next system launch.
    func expireBackgroundProcessing() {
        automaticProcessingTask?.cancel()
        Task {
            await audioAnalyzer.cancelTranscription()
            await aiAnalyzer.cancelAnalysis()
        }
    }

    /// Prevents another attempt from touching an on-device model while an
    /// operation that ignored cancellation is still unwinding.
    func beginAnalysisResourceQuarantine(for attemptID: UUID) {
        quarantinedAttemptID = attemptID
    }

    func endAnalysisResourceQuarantine(for attemptID: UUID) async {
        guard quarantinedAttemptID == attemptID else { return }
        await audioAnalyzer.releaseResources()
        quarantinedAttemptID = nil

        guard !analysisQueue.isEmpty else {
            restartAfterCurrentProcessor = false
            return
        }

        if automaticProcessingTask != nil {
            restartAfterCurrentProcessor = true
        } else {
            await startAutomaticProcessing(priority: activeProcessingPriority)
        }
    }

    var isAnalysisResourceQuarantined: Bool {
        quarantinedAttemptID != nil
    }

    /// Check if a file is in the queue
    func isInQueue(_ audioFile: AudioFile) -> Bool {
        analysisQueue.contains { $0.id == audioFile.id }
    }

    var overallProgress: Double {
        guard let analysis = currentAnalysis else { return 0.0 }
        return analysis.progress
    }

    // MARK: - Persistent Cache

    /// In-memory cache: content-addressed key -> complete reusable analysis payload.
    private var cachedResults: [String: CachedAudioAnalysis] = [:]

    // MARK: Content-Addressed Key

    /// Complete transcription-and-analysis pipeline version baked into every cache key.
    /// Incrementing this string automatically invalidates all existing entries
    /// and forces re-analysis after either the model or analyzer behavior changes.
    nonisolated static let currentModelVersion = "base-v5-analyzer-knowledge-v1"

    /// Returns a content-addressed cache key: SHA-256 of the complete audio file,
    /// followed by a colon and the model version string.
    ///
    /// Falls back to the file's UUID string when the audio file cannot be
    /// read (e.g., synthetic `AudioFile` objects in unit tests).
    nonisolated static func cacheKey(for audioFile: AudioFile) -> String {
        if let fingerprint = audioFile.contentFingerprint, !fingerprint.isEmpty {
            return "\(fingerprint):\(currentModelVersion)"
        }
        // Fingerprints are computed by the import worker. Never hash an entire
        // legacy audio file synchronously from this MainActor cache lookup.
        return "\(audioFile.id.uuidString):\(currentModelVersion)"
    }

    /// Computes SHA-256 of the complete contents of `url`.
    /// Returns `nil` when the file cannot be read.
    nonisolated static func contentAddressedKey(
        audioFileURL url: URL,
        modelVersion: String = currentModelVersion
    ) -> String? {
        guard let hex = AudioFingerprintService.computeFingerprint(for: url) else { return nil }
        return "\(hex):\(modelVersion)"
    }

    // MARK: Cache API

    /// Returns the cached analysis result for a file, or nil if none exists.
    func cachedResult(for audioFile: AudioFile) -> AnalysisResult? {
        cachedResults[Self.cacheKey(for: audioFile)]?.analysis
    }

    /// Returns true if a cached result already exists for this file,
    /// so callers can skip expensive re-analysis.
    func hasCachedResult(for audioFile: AudioFile) -> Bool {
        cachedResults[Self.cacheKey(for: audioFile)] != nil
    }

    /// Evicts the cached result for a single file (e.g., when the user re-analyzes manually).
    func evictCachedResult(for audioFile: AudioFile) async {
        cachedResults.removeValue(forKey: Self.cacheKey(for: audioFile))
        await saveCachedResults()
    }

    func cache(_ result: CompletedAnalysis, for audioFile: AudioFile) async {
        let embedded = result.audioFile.trackMetadata
            ?? audioFile.trackMetadata
            ?? AudioTrackMetadata()
        let metadata = embedded.mergingAnalyzed(result.analysis.discoveredMetadata)
        cachedResults[Self.cacheKey(for: audioFile)] = CachedAudioAnalysis(
            transcription: result.transcription,
            analysis: result.analysis,
            trackMetadata: metadata.isEmpty ? nil : metadata
        )
        await saveCachedResults()
    }

    /// Restores all reusable data while preserving metadata freshly read from the file.
    func restoringCachedData(in audioFile: AudioFile) -> AudioFile {
        guard let cached = cachedResults[Self.cacheKey(for: audioFile)] else { return audioFile }

        var restored = audioFile
        restored.analysisResult = cached.analysis
        restored.transcription = cached.transcription?.fullText
        let embedded = restored.trackMetadata ?? AudioTrackMetadata()
        restored.trackMetadata = embedded.mergingAnalyzed(
            cached.trackMetadata ?? cached.analysis.discoveredMetadata
        )
        return restored
    }

    func cachedCompletion(for audioFile: AudioFile) -> CompletedAnalysis? {
        guard let cached = cachedResults[Self.cacheKey(for: audioFile)] else { return nil }
        let transcription = cached.transcription
            ?? Self.reusableTranscriptionResult(for: audioFile)
            ?? AudioTranscriptionResult(
                fullText: "",
                segments: [],
                duration: audioFile.duration,
                detectedLanguage: "und"
            )

        var restoredFile = restoringCachedData(in: audioFile)
        restoredFile.analysisResult = cached.analysis
        return CompletedAnalysis(
            audioFile: restoredFile,
            transcription: transcription,
            analysis: cached.analysis,
            completedAt: cached.cachedAt
        )
    }

    /// Builds a transcription result from a saved transcript so re-analysis can
    /// use improved analyzer logic without paying the Whisper cost again.
    nonisolated static func reusableTranscriptionResult(for audioFile: AudioFile) -> AudioTranscriptionResult? {
        if let text = audioFile.transcription {
            let sanitized = AudioTranscriptionResult.sanitizedTranscriptText(text)
            if !sanitized.isEmpty {
                return AudioTranscriptionResult(
                    fullText: sanitized,
                    segments: [
                        AudioTranscriptionSegment(
                            text: sanitized,
                            timestamp: 0,
                            duration: max(audioFile.duration, 1),
                            confidence: 0.85
                        )
                    ],
                    duration: audioFile.duration,
                    detectedLanguage: "en"
                )
            }
        }

        return KnownAudioCatalog.shared.transcription(for: audioFile)
    }

    /// URL of the on-disk analysis cache. Internal so tests can verify the path.
    nonisolated static var cacheURL: URL {
        PrivateStorageMigration.migrateItemIfNeeded(
            from: URL.documentsDirectory.appending(path: "AnalysisCache.json"),
            to: AppStoragePaths.analysisCache
        )
    }

    /// Re-queues durable work and waits for the active processing loop. Used by
    /// both foreground activation and BackgroundTasks launch handlers.
    @discardableResult
    func resumeInterruptedAnalyses(priority: TaskPriority = .utility) async -> Bool {
        await prepareCachedResults()

        let pending = await progressStore.allPending()
        guard !pending.isEmpty else {
            await startAutomaticProcessing(priority: priority)
            return true
        }

        Log.analysis.info("🔁 Resuming \(pending.count) interrupted analysis/analyses…")
        var filesToResume: [AudioFile] = []
        for checkpoint in pending {
            if await completeReviewedCatalogAnalysisIfAvailable(checkpoint.audioFile) {
                continue
            } else if hasCachedResult(for: checkpoint.audioFile) {
                await progressStore.clear(for: checkpoint.audioFile)
            } else if !isQueuedOrActive(checkpoint.audioFile) {
                filesToResume.append(checkpoint.audioFile)
            }
        }

        if !filesToResume.isEmpty {
            analysisQueue.append(contentsOf: filesToResume)
        }

        await startAutomaticProcessing(priority: priority)
        return await progressStore.allPending().isEmpty
    }

    /// Makes the persistent cache available without putting its potentially
    /// large transcript payload on the caller's actor. Concurrent callers share
    /// one task, and all observable state is installed back on MainActor.
    func prepareCachedResults() async {
        guard hasLoadedCachedResults == false else { return }

        let task: Task<CachedAnalysisLoad, Never>
        if let cachedResultsLoadTask {
            task = cachedResultsLoadTask
        } else {
            task = Task(priority: .utility) { [analysisCacheURL] in
                await Self.loadCachedResults(from: analysisCacheURL)
            }
            cachedResultsLoadTask = task
        }

        let load = await task.value
        guard hasLoadedCachedResults == false else { return }
        installCachedResults(load)
        cachedResultsLoadTask = nil
    }

    /// The injected initializer remains eager by default so unit tests and
    /// isolated tools retain their deterministic synchronous construction.
    private func loadCachedResultsSynchronously() {
        installCachedResults(Self.decodeCachedResults(from: analysisCacheURL))
    }

    @concurrent
    nonisolated private static func loadCachedResults(
        from url: URL
    ) async -> CachedAnalysisLoad {
        let trace = PerformanceTrace.begin("Analysis Cache Decode")
        defer { PerformanceTrace.end(trace) }
        return decodeCachedResults(from: url)
    }

    nonisolated private static func decodeCachedResults(
        from url: URL
    ) -> CachedAnalysisLoad {
        guard let data = try? Data(contentsOf: url) else {
            return CachedAnalysisLoad(results: [:], migratedLegacyCache: false)
        }

        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([String: CachedAudioAnalysis].self, from: data) {
            return CachedAnalysisLoad(results: decoded, migratedLegacyCache: false)
        } else if let legacy = try? decoder.decode([String: AnalysisResult].self, from: data) {
            return CachedAnalysisLoad(
                results: legacy.mapValues {
                    CachedAudioAnalysis(
                        transcription: nil,
                        analysis: $0,
                        trackMetadata: $0.discoveredMetadata
                    )
                },
                migratedLegacyCache: true
            )
        }

        return CachedAnalysisLoad(results: [:], migratedLegacyCache: false)
    }

    private func installCachedResults(_ load: CachedAnalysisLoad) {
        cachedResults = load.results
        hasLoadedCachedResults = true

        if load.migratedLegacyCache {
            Task { await saveCachedResults() }
            Log.analysis.info("📂 Migrated \(load.results.count) legacy analysis cache result(s)")
        } else if load.results.isEmpty == false {
            Log.analysis.info("📂 Loaded \(load.results.count) cached analysis result(s)")
        }
    }

    private func saveCachedResults() async {
        let snapshot = cachedResults
        await cachePersistence.save(snapshot, to: analysisCacheURL)
    }

    // MARK: - Private Methods

    /// Handle analysis completion with proper actor isolation
    private func handleAnalysisComplete(audioFile: AudioFile, result: CompletedAnalysis) async {
        let embedded = audioFile.trackMetadata ?? AudioTrackMetadata()
        let analyzedMetadata = canonicalizedCreator(
            in: result.analysis.discoveredMetadata,
            excluding: audioFile.id
        )
        let metadata = embedded.mergingAnalyzed(analyzedMetadata)
        var completedFile = audioFile
        completedFile.analysisResult = result.analysis
        completedFile.transcription = result.transcription.fullText
        completedFile.trackMetadata = metadata.isEmpty ? nil : metadata
        let completed = CompletedAnalysis(
            audioFile: completedFile,
            transcription: result.transcription,
            analysis: result.analysis,
            completedAt: result.completedAt
        )

        completedAnalyses.append(completed)
        failedAnalyses.removeAll { $0.audioFile.id == audioFile.id }
        onAnalysisComplete?(completedFile, completed)

        // Persist the complete result, keyed by the audio's full content fingerprint.
        await cache(completed, for: audioFile)

        // Write results back to the stored library so all views see the file as
        // analyzed on next load.
        let didPersist = await AudioLibraryStore.saveAnalysis(
            completed.analysis,
            transcription: completed.transcription.fullText,
            trackMetadata: metadata.isEmpty ? nil : metadata,
            audioFileID: audioFile.id
        )
        if didPersist {
            Log.analysis.info("💾 Persisted analysis result to the stored library")
        } else {
            // Previously this was announced as a success regardless. A dropped
            // write is how a finished analysis disappeared without a trace.
            Log.analysis.error(
                "❌ Analysis for \(audioFile.filename, privacy: .public) was NOT persisted"
            )
        }

        // Remove from queue
        analysisQueue.removeAll { $0.id == audioFile.id }

        Log.analysis.info("✅ Analysis completed: \(audioFile.filename)")
    }

    private func canonicalizedCreator(
        in metadata: AudioTrackMetadata?,
        excluding audioFileID: UUID
    ) -> AudioTrackMetadata? {
        guard var metadata, let creator = metadata.creator else { return metadata }
        guard metadata.verificationSource == nil else { return metadata }
        // The shared snapshot is already primed during app launch. Decoding the
        // full persisted library here retained nothing useful and cost 270 ms
        // in the navigation-memory trace just to collect creator names.
        let cache = AudioLibraryCache.shared
        let files = cache.hasLoaded ? cache.files : AudioLibraryStore.load()
        let knownCreators = files
            .filter { $0.id != audioFileID }
            .compactMap(\.creatorDisplayName)
        if let match = AudioIntroductionMetadataExtractor.closestMatch(
            to: creator,
            among: knownCreators
        ) {
            metadata.creator = match
        }
        return metadata
    }

    // MARK: - AudioFile Persistence Bridge

    /// Key used by AudioLibraryView to store/load the audio file list.
    nonisolated static let audioFilesUserDefaultsKey = "audioFiles"

    /// Get completed analysis for a file
    func getCompletedAnalysis(for audioFile: AudioFile) -> CompletedAnalysis? {
        completedAnalyses.first { $0.audioFile.id == audioFile.id }
    }

    /// Remove completed analysis
    func removeCompletedAnalysis(for audioFile: AudioFile) {
        completedAnalyses.removeAll { $0.audioFile.id == audioFile.id }
    }

    /// Save generated light session to documents directory
    private func saveGeneratedSession(_ session: LightSession, for audioFile: AudioFile) async throws {
        try GeneratedSessionStore.shared.save(session, for: audioFile)
    }
}

// MARK: - Analysis Coordinator

private nonisolated struct ContentAnalysisStageResult: Sendable {
    let analysis: AnalysisResult
    let prosody: ProsodicProfile?
}

private enum AnalysisProcessingDisposition: Equatable {
    case continueQueue
    case haltForResourceCleanup
}

/// Main-actor coordinator for services whose observable state drives SwiftUI.
/// CPU-heavy transcription, prosody, and file work explicitly leave this actor.
@MainActor
final class AnalysisCoordinator {

    // MARK: - State

    private var isProcessing = false
    private let stageOverlapOverride: Bool?
    private let watchdogPolicy: AnalysisWatchdogPolicy

    init(
        stageOverlapOverride: Bool? = nil,
        watchdogPolicy: AnalysisWatchdogPolicy = AnalysisWatchdogPolicy()
    ) {
        self.stageOverlapOverride = stageOverlapOverride
        self.watchdogPolicy = watchdogPolicy
    }

    private func superviseOperation<Value: Sendable>(
        attemptID: UUID,
        stage: AnalyticsAnalysisStage,
        analysisManager: AnalysisStateManager,
        progress: @escaping @MainActor () -> Double,
        cancelOperation: @escaping @MainActor () async -> Void,
        operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        let race = AnalysisOperationRace<Value>()
        let operationTask = Task<Value, Error> {
            try await operation()
        }
        let completionTask = Task<Void, Never> {
            let result: Result<Value, any Error>
            do {
                result = .success(try await operationTask.value)
            } catch {
                result = .failure(error)
            }
            await race.resolve(.result(result))
        }

        let timing = watchdogPolicy.timing
        let monitorTask = Task<Void, Never> {
            var watchdog = AnalysisInactivityWatchdog(
                stage: stage,
                progress: progress(),
                startedAt: timing.elapsed(),
                timeout: watchdogPolicy.noProgressTimeout
            )

            while !Task.isCancelled {
                do {
                    try await timing.sleep(watchdogPolicy.pollInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                guard analysisManager.currentAnalysis?.attemptID == attemptID else {
                    await race.resolve(.cancelled)
                    return
                }

                let now = timing.elapsed()
                watchdog.observe(stage: stage, progress: progress(), at: now)
                if watchdog.hasTimedOut(at: now) {
                    await race.resolve(.stalled)
                    return
                }
            }
        }

        let outcome = await withTaskCancellationHandler {
            await race.value()
        } onCancel: {
            operationTask.cancel()
            monitorTask.cancel()
            Task { await race.resolve(.cancelled) }
        }

        switch outcome {
        case .result(let result):
            monitorTask.cancel()
            return try result.get()

        case .cancelled:
            operationTask.cancel()
            monitorTask.cancel()
            throw CancellationError()

        case .stalled:
            operationTask.cancel()
            monitorTask.cancel()
            analysisManager.beginAnalysisResourceQuarantine(for: attemptID)

            let cancellationTask = Task<Void, Never> {
                await cancelOperation()
            }
            // Do not await a model task that has already failed to respond.
            // Quarantine remains until both the operation and its explicit
            // cancellation path confirm that the resource has been released.
            Task<Void, Never> {
                await completionTask.value
                await cancellationTask.value
                await analysisManager.endAnalysisResourceQuarantine(for: attemptID)
            }
            throw AnalysisStalledError(stage: stage)
        }
    }

    private func enrichAnalysis(
        audioFile: AudioFile,
        analysis: AnalysisResult,
        transcription: AudioTranscriptionResult
    ) async -> AnalysisResult {
        let trace = PerformanceTrace.begin("Analysis Enrichment")
        defer { PerformanceTrace.end(trace) }

        let enricher = AudioAnalysisEnricher(analyzerConfig: AnalyzerConfigLoader.load())
        return await enricher.enrich(
            analysis,
            transcription: transcription,
            audioFile: audioFile
        )
    }

    private func generateLightSession(
        audioFile: AudioFile,
        analysis: AnalysisResult
    ) async throws -> LightSession {
        let trace = PerformanceTrace.begin("Session Generation")
        defer { PerformanceTrace.end(trace) }

        return await MainActor.run {
            let generator = SessionGenerator(config: AnalyzerConfigLoader.load().sessionGeneration)
            return generator.generateSession(
                from: audioFile,
                analysis: analysis,
                config: AnalysisPreferences.shared.generationConfig
            )
        }
    }

    private func saveLightSession(_ session: LightSession, for audioFile: AudioFile) async throws {
        let trace = PerformanceTrace.begin("Session Persist")
        defer { PerformanceTrace.end(trace) }

        try await MainActor.run {
            try GeneratedSessionStore.shared.save(session, for: audioFile)
        }
    }

    // MARK: - Automatic Queue Processing

    /// Processes the queue as a resource-aware pipeline. Whisper transcription
    /// and Foundation Models analysis remain mutually exclusive because they
    /// compete for constrained on-device ML resources.
    func processQueueAutomatically(
        analysisManager: AnalysisStateManager,
        audioAnalyzer: any AudioTranscribingService,
        aiAnalyzer: any ContentAnalyzingService,
        progressStore: AnalysisProgressStore,
        performanceOptimizer: PerformanceOptimizer,
        priority: TaskPriority,
        onComplete: @Sendable @escaping (AudioFile, CompletedAnalysis) async -> Void
    ) async {
        guard !isProcessing else {
            Log.analysis.info("⏸️ Queue processing already active")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        Log.analysis.info("🚀 Starting staged automatic queue processing...")

        while true {
            if Task.isCancelled { break }

            // Get next file from queue on main actor
            let nextFile: AudioFile? = await MainActor.run {
                guard !analysisManager.analysisQueue.isEmpty else { return nil }
                return analysisManager.analysisQueue.removeFirst()
            }

            // Break if queue is empty
            guard let audioFile = nextFile else {
                Log.analysis.info("✅ Queue processing complete - no more files")
                break
            }

            // Update current analysis state on main actor
            await MainActor.run {
                analysisManager.currentAnalysis = ActiveAnalysis(
                    audioFile: audioFile,
                    stage: .starting,
                    progress: 0.0
                )
            }

            let queuePosition = await MainActor.run { analysisManager.queuePosition(for: audioFile) }
            Log.analysis.info("🔄 Processing: \(audioFile.filename) (queue position: \(queuePosition))")

            guard let attemptID = analysisManager.currentAnalysis?.attemptID else {
                continue
            }

            let disposition = await performSingleAnalysisWithStateUpdates(
                audioFile: audioFile,
                attemptID: attemptID,
                analysisManager: analysisManager,
                audioAnalyzer: audioAnalyzer,
                aiAnalyzer: aiAnalyzer,
                progressStore: progressStore,
                performanceOptimizer: performanceOptimizer,
                onComplete: onComplete
            )

            if disposition == .haltForResourceCleanup {
                Log.analysis.info("⏸️ Queue paused while stalled model resources unwind")
                break
            }

            // Check for cancellation between files
            if Task.isCancelled {
                Log.analysis.info("🛑 Queue processing cancelled")
                await MainActor.run {
                    analysisManager.currentAnalysis = nil
                }
                break
            }
        }

        if !analysisManager.isAnalysisResourceQuarantined {
            await audioAnalyzer.releaseResources()
        }

        // Clear current analysis when done
        await MainActor.run {
            analysisManager.currentAnalysis = nil
        }

        Log.analysis.info("🏁 Automatic queue processing finished")
    }

    /// Perform single analysis with proper state updates, resuming from any saved checkpoint.
    private func performSingleAnalysisWithStateUpdates(
        audioFile: AudioFile,
        attemptID: UUID,
        analysisManager: AnalysisStateManager,
        audioAnalyzer: any AudioTranscribingService,
        aiAnalyzer: any ContentAnalyzingService,
        progressStore: AnalysisProgressStore,
        performanceOptimizer: PerformanceOptimizer,
        onComplete: @Sendable @escaping (AudioFile, CompletedAnalysis) async -> Void
    ) async -> AnalysisProcessingDisposition {
        let trace = PerformanceTrace.begin("Analyze File")
        defer { PerformanceTrace.end(trace) }

        // Load any checkpoint saved from a previous run.
        let checkpoint = await progressStore.checkpoint(for: audioFile)
        let attemptNumber = await progressStore.beginAttempt(for: audioFile)
        let resumingFrom = checkpoint?.resumeStage ?? .transcribing
        let telemetryContext = AudioAnalysisTelemetryContext(
            audioFile: audioFile,
            attempt: attemptNumber == 1 ? .first : .resumed
        )
        let telemetryStartedAt = Date()
        var telemetryStage = AnalyticsAnalysisStage.preparation
        var createGenerationStartedAt: Date?

        await MainActor.run {
            UsageAnalytics.shared.audioAnalyzeStarted(context: telemetryContext)
        }

        if checkpoint != nil {
            Log.analysis.info("🔁 Resuming \(audioFile.filename) from stage: \(String(describing: resumingFrom))")
        } else {
            Log.analysis.info("🔄 Starting analysis: \(audioFile.filename)")
        }

        do {
            if let cached = await MainActor.run(body: {
                analysisManager.cachedCompletion(for: audioFile)
            }) {
                telemetryStage = .generation
                createGenerationStartedAt = Date()
                Log.analysis.info("⚡ Restoring cached analysis: \(audioFile.filename)")
                await MainActor.run {
                    UsageAnalytics.shared.createStarted(.audioSession)
                    analysisManager.currentAnalysis?.stage = .generatingSession
                    analysisManager.currentAnalysis?.progress = 0.85
                }

                let lightSession = try await self.generateLightSession(
                    audioFile: cached.audioFile,
                    analysis: cached.analysis
                )
                try await self.saveLightSession(lightSession, for: cached.audioFile)
                if let createGenerationStartedAt {
                    await MainActor.run {
                        UsageAnalytics.shared.createCompleted(
                            .audioSession,
                            duration: ProcessingTimeBucket(
                                seconds: Date().timeIntervalSince(createGenerationStartedAt)
                            )
                        )
                    }
                }
                await progressStore.clear(for: audioFile)

                await MainActor.run {
                    analysisManager.currentAnalysis?.stage = .complete
                    analysisManager.currentAnalysis?.progress = 1.0
                    UsageAnalytics.shared.audioAnalyzeCompleted(
                        context: telemetryContext,
                        processingTime: ProcessingTimeBucket(
                            seconds: Date().timeIntervalSince(telemetryStartedAt)
                        )
                    )
                }
                await onComplete(audioFile, cached)
                return .continueQueue
            }

            try await performanceOptimizer.withBackgroundTask(name: "AudioAnalysis-\(audioFile.filename)") {

                // Start progress syncing loop
                let progressTracker = Task { @MainActor in
                    while !Task.isCancelled {
                        guard let current = analysisManager.currentAnalysis else { break }
                        let displayedProgress: Double?
                        switch current.stage {
                        case .transcribing:
                            displayedProgress = audioAnalyzer.progress * 0.4
                        case .analyzing:
                            displayedProgress = 0.4 + (aiAnalyzer.progress * 0.4)
                        case .generatingSession:
                            displayedProgress = 0.8
                        default:
                            displayedProgress = nil
                        }

                        // Observation invalidates every view that reads
                        // `currentAnalysis` even when the assigned value is
                        // unchanged. Avoiding no-op writes keeps the analysis
                        // screen idle while a stage reports steady progress.
                        if let displayedProgress,
                           displayedProgress != current.progress {
                            analysisManager.currentAnalysis?.progress = displayedProgress
                        }
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
                defer { progressTracker.cancel() }

                // Stage 1: Transcription (skip if checkpoint already has it)
                telemetryStage = .transcription
                let transcriptionResult: AudioTranscriptionResult
                if let saved = checkpoint?.transcription {
                    Log.analysis.info("⏭️ Skipping transcription (checkpoint found) for \(audioFile.filename)")
                    transcriptionResult = saved
                    await MainActor.run {
                        analysisManager.currentAnalysis?.stage = .analyzing
                        analysisManager.currentAnalysis?.progress = 0.4
                    }
                } else if let reusable = AnalysisStateManager.reusableTranscriptionResult(for: audioFile) {
                    Log.analysis.info("⏭️ Reusing saved transcript for \(audioFile.filename)")
                    transcriptionResult = reusable
                    await progressStore.saveTranscription(transcriptionResult, for: audioFile)
                    await MainActor.run {
                        analysisManager.currentAnalysis?.stage = .analyzing
                        analysisManager.currentAnalysis?.progress = 0.4
                    }
                } else {
                    await MainActor.run {
                        analysisManager.currentAnalysis?.stage = .transcribing
                    }
                    transcriptionResult = try await superviseOperation(
                        attemptID: attemptID,
                        stage: .transcription,
                        analysisManager: analysisManager,
                        progress: { audioAnalyzer.progress },
                        cancelOperation: { await audioAnalyzer.cancelTranscription() },
                        operation: { try await audioAnalyzer.transcribe(audioFile: audioFile) }
                    )
                    try Task.checkCancellation()
                    await progressStore.saveTranscription(transcriptionResult, for: audioFile)
                }

                await analysisManager.persistPartialTranscription(
                    transcriptionResult,
                    for: audioFile
                )

                // Stage 2: AI Analysis (skip if checkpoint already has it)
                telemetryStage = .contentAnalysis
                let analysisResult: AnalysisResult
                if let saved = checkpoint?.analysis {
                    Log.analysis.info("⏭️ Skipping AI analysis (checkpoint found) for \(audioFile.filename)")
                    analysisResult = try await superviseOperation(
                        attemptID: attemptID,
                        stage: .contentAnalysis,
                        analysisManager: analysisManager,
                        progress: { 0 },
                        cancelOperation: {},
                        operation: {
                            await self.enrichAnalysis(
                                audioFile: audioFile,
                                analysis: saved,
                                transcription: transcriptionResult
                            )
                        }
                    )
                    await progressStore.saveAnalysis(analysisResult, for: audioFile)
                    await MainActor.run {
                        analysisManager.currentAnalysis?.stage = .generatingSession
                        analysisManager.currentAnalysis?.progress = 0.8
                    }
                } else {
                    await MainActor.run {
                        analysisManager.currentAnalysis?.stage = .analyzing
                    }
                    // Prosody extraction is pure signal processing on the raw
                    // audio and independent of the AI stage — run both
                    // concurrently instead of paying for prosody afterwards.
                    let stageResult = try await superviseOperation(
                        attemptID: attemptID,
                        stage: .contentAnalysis,
                        analysisManager: analysisManager,
                        progress: { aiAnalyzer.progress },
                        cancelOperation: { await aiAnalyzer.cancelAnalysis() },
                        operation: {
                            let enricher = AudioAnalysisEnricher(
                                analyzerConfig: AnalyzerConfigLoader.load()
                            )
                            async let prosody = enricher.extractProsody(
                                audioFile: audioFile,
                                transcription: transcriptionResult
                            )
                            let rawAnalysis = try await aiAnalyzer.analyzeContent(
                                transcription: transcriptionResult,
                                audioFile: audioFile
                            )
                            return ContentAnalysisStageResult(
                                analysis: rawAnalysis,
                                prosody: await prosody
                            )
                        }
                    )
                    try Task.checkCancellation()
                    let enricher = AudioAnalysisEnricher(analyzerConfig: AnalyzerConfigLoader.load())
                    analysisResult = enricher.enrich(
                        stageResult.analysis,
                        transcription: transcriptionResult,
                        audioFile: audioFile,
                        prosody: stageResult.prosody
                    )
                    await progressStore.saveAnalysis(analysisResult, for: audioFile)
                }

                // Stage 3: Generate Light Session (always run — it's fast)
                telemetryStage = .generation
                createGenerationStartedAt = Date()
                await MainActor.run {
                    UsageAnalytics.shared.createStarted(.audioSession)
                    analysisManager.currentAnalysis?.stage = .generatingSession
                    analysisManager.currentAnalysis?.progress = 0.8
                }

                let lightSession = try await self.generateLightSession(
                    audioFile: audioFile,
                    analysis: analysisResult
                )
                try Task.checkCancellation()

                // Stage 4: Save Session
                telemetryStage = .persistence
                try await self.saveLightSession(lightSession, for: audioFile)
                if let createGenerationStartedAt {
                    await MainActor.run {
                        UsageAnalytics.shared.createCompleted(
                            .audioSession,
                            duration: ProcessingTimeBucket(
                                seconds: Date().timeIntervalSince(createGenerationStartedAt)
                            )
                        )
                    }
                }

                // Stage 5: Mark complete.
                //
                // A transient refusal keeps its checkpoint instead of clearing
                // it, so the AI stage can be tried again from the saved
                // transcript. Clearing here is what made "↺ Transient —
                // analysing this file again later should succeed" a promise
                // nothing could keep: the device recorded foreground 0/16, and
                // sixteen files were permanently downgraded by a condition that
                // was going to pass.
                //
                // The session has already been generated and saved above, so
                // the file is playable either way — deferring improves it
                // later rather than withholding it now.
                let deferredKind = analysisResult.aiFallbackKind
                if let deferredKind, DeferredAIAnalysisPolicy.retainsCheckpoint(after: deferredKind) {
                    await progressStore.markAwaitingAIRetry(for: audioFile, kind: deferredKind)
                } else {
                    await progressStore.clear(for: audioFile)
                }

                await MainActor.run {
                    analysisManager.currentAnalysis?.stage = .complete
                    analysisManager.currentAnalysis?.progress = 1.0
                }

                let completedAnalysis = CompletedAnalysis(
                    audioFile: audioFile,
                    transcription: transcriptionResult,
                    analysis: analysisResult,
                    completedAt: Date()
                )

                let processingTime = ProcessingTimeBucket(
                    seconds: Date().timeIntervalSince(telemetryStartedAt)
                )
                await MainActor.run {
                    UsageAnalytics.shared.audioAnalyzeCompleted(
                        context: telemetryContext,
                        processingTime: processingTime
                    )
                }
                await onComplete(audioFile, completedAnalysis)

            }
        } catch is CancellationError {
            // Keep the checkpoint — progress is preserved for next launch.
            Log.analysis.info("🛑 Analysis cancelled: \(audioFile.filename) — checkpoint preserved for resume")
            let finalStage = telemetryStage
            let processingTime = ProcessingTimeBucket(
                seconds: Date().timeIntervalSince(telemetryStartedAt)
            )
            await MainActor.run {
                if let createGenerationStartedAt {
                    UsageAnalytics.shared.createCancelled(
                        .audioSession,
                        duration: ProcessingTimeBucket(
                            seconds: Date().timeIntervalSince(createGenerationStartedAt)
                        )
                    )
                }
                UsageAnalytics.shared.audioAnalyzeCancelled(
                    context: telemetryContext,
                    stage: finalStage,
                    processingTime: processingTime
                )
                // Background expiration is a pause, not a user-visible
                // analysis failure. The checkpoint remains available to resume.
                analysisManager.currentAnalysis = nil
                analysisManager.removeFromQueue(audioFile: audioFile)
            }
        } catch {
            let msg = error.localizedDescription
            Log.analysis.info("❌ Analysis failed: \(audioFile.filename) - \(msg)")
            let finalStage = telemetryStage
            let processingTime = ProcessingTimeBucket(
                seconds: Date().timeIntervalSince(telemetryStartedAt)
            )
            let reason = AnalyticsAnalysisFailureReason(error: error, stage: finalStage)
            let failedAttemptNumber: Int
            if reason.supportsAutomaticRetry && reason != .stalled {
                failedAttemptNumber = await progressStore.recordFailedAttempt(for: audioFile)
            } else {
                failedAttemptNumber = 1
            }
            let shouldRetry = reason.supportsAutomaticRetry
                && reason != .stalled
                && failedAttemptNumber < 2
            let failedAt = Date()
            let retryState: AnalysisRetryState
            if reason == .stalled {
                retryState = .manual
                await progressStore.markRequiresManualRetry(
                    for: audioFile,
                    reason: reason,
                    failedStage: finalStage,
                    failedAt: failedAt
                )
                Log.analysis.info("⏸️ Stalled model attempt quarantined; manual retry available")
            } else if shouldRetry {
                retryState = .automatic
                Log.analysis.info("🔁 Preserving checkpoint for one retry: \(audioFile.filename)")
            } else if reason.supportsAutomaticRetry {
                retryState = .manual
                await progressStore.markRequiresManualRetry(
                    for: audioFile,
                    reason: reason,
                    failedStage: finalStage,
                    failedAt: failedAt
                )
                Log.analysis.info("⏸️ Automatic retry stopped; manual retry available for \(audioFile.filename)")
            } else {
                retryState = .unavailable
                await progressStore.clear(for: audioFile)
                Log.analysis.info("🛑 Automatic retry stopped for \(audioFile.filename)")
            }
            let recoveryStage = await progressStore.checkpoint(for: audioFile)?.recoveryStage ?? .none
            await MainActor.run {
                if let createGenerationStartedAt {
                    UsageAnalytics.shared.createGenerationFailed(
                        .audioSession,
                        duration: ProcessingTimeBucket(
                            seconds: Date().timeIntervalSince(createGenerationStartedAt)
                        ),
                        failure: finalStage == .persistence ? .persistence : .generation
                    )
                }
                UsageAnalytics.shared.audioAnalysisFailed(
                    context: telemetryContext,
                    stage: finalStage,
                    reason: reason,
                    processingTime: processingTime
                )
                analysisManager.currentAnalysis?.stage = .failed
                analysisManager.currentAnalysis?.errorMessage = msg
                analysisManager.removeFromQueue(audioFile: audioFile)
                if shouldRetry,
                   analysisManager.analysisQueue.contains(where: { $0.id == audioFile.id }) == false {
                    analysisManager.analysisQueue.append(audioFile)
                }
                analysisManager.recordFailure(
                    FailedAnalysis(
                        audioFile: audioFile,
                        technicalMessage: msg,
                        failedAt: failedAt,
                        reason: reason,
                        failedStage: finalStage,
                        recoveryStage: recoveryStage,
                        retryState: retryState
                    )
                )
            }
            if reason == .stalled {
                return .haltForResourceCleanup
            }
        }
        return .continueQueue
    }
}

private extension AnalyticsAnalysisFailureReason {
    /// Invalid or empty audio cannot become valid by repeating the same work.
    /// Stalls use manual recovery after resource quarantine; ordinary transient
    /// failures get one automatic recovery attempt, bounded by the coordinator.
    var supportsAutomaticRetry: Bool {
        switch self {
        case .invalidAudio, .noAudioData:
            false
        default:
            true
        }
    }
}

// MARK: - Active Analysis Model

/// Reference state keeps fast-changing progress granular. When this was a
/// value nested inside `AnalysisStateManager.currentAnalysis`, every progress
/// write was observed as a replacement of the whole optional and invalidated
/// unrelated screens and cards that only cared whether analysis was active.
@Observable final class ActiveAnalysis: Equatable {
    let audioFile: AudioFile
    var stage: AnalysisStage
    var progress: Double
    var errorMessage: String?
    /// When this analysis began — drives the "still working" reassurance copy.
    /// Excluded from `==` so elapsed time never causes spurious UI diffs.
    let startedAt: Date
    /// Identifies this attempt. Phase 2b uses it so a late result cannot
    /// overwrite a failure the watchdog already recorded; Phase 2c uses it to
    /// attribute a model download to the right attempt. Excluded from `==` for
    /// the same reason as `startedAt`: it never changes within an instance.
    let attemptID = UUID()

    /// Value snapshot for the Analysis Task Center projection.
    var snapshot: ActiveAnalysisSnapshot {
        ActiveAnalysisSnapshot(
            audioFileID: audioFile.id,
            attemptID: attemptID,
            stage: stage,
            progress: progress,
            startedAt: startedAt
        )
    }

    init(
        audioFile: AudioFile,
        stage: AnalysisStage,
        progress: Double,
        errorMessage: String? = nil,
        startedAt: Date = Date()
    ) {
        self.audioFile = audioFile
        self.stage = stage
        self.progress = progress
        self.errorMessage = errorMessage
        self.startedAt = startedAt
    }

    static func == (lhs: ActiveAnalysis, rhs: ActiveAnalysis) -> Bool {
        lhs.audioFile.id == rhs.audioFile.id &&
        lhs.stage == rhs.stage &&
        lhs.progress == rhs.progress &&
        lhs.errorMessage == rhs.errorMessage
    }
}

// MARK: - Completed Analysis Model

struct CompletedAnalysis: Identifiable, Sendable {
    let id = UUID()
    let audioFile: AudioFile
    let transcription: AudioTranscriptionResult
    let analysis: AnalysisResult
    let completedAt: Date
}
