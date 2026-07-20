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

// MARK: - Analysis Stage

enum AnalysisStage: Sendable {
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
        loadCachedResults()
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
        scheduleBackgroundAnalysis: @escaping @MainActor ([AudioFile]) -> Void = { audioFiles in
            BackgroundAnalysisScheduler.shared.schedule(for: audioFiles)
        }
    ) {
        self.analysisCoordinator = AnalysisCoordinator(
            stageOverlapOverride: stageOverlapOverride
        )
        self.audioAnalyzer = transcriber
        self.aiAnalyzer = analyzer
        self.progressStore = progressStore
        self.preferences = preferences ?? .shared
        self.analysisCacheURL = cacheURL
        self.scheduleBackgroundAnalysis = scheduleBackgroundAnalysis
        loadCachedResults()
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

    // MARK: - Queue Management

    /// Remove a file from the analysis queue
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
        guard !isQueuedOrActive(audioFile) else {
            Log.analysis.info("📋 File already in queue: \(audioFile.filename)")
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
        var newFilesAdded = 0

        // Add all files to queue (avoid duplicates)
        for audioFile in audioFiles {
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

    /// Start automatic background processing of the queue
    private func startAutomaticProcessing(priority: TaskPriority = .background) async {
        if let automaticProcessingTask {
            await automaticProcessingTask.value
            return
        }

        guard currentAnalysis == nil && !analysisQueue.isEmpty else {
            return
        }

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

        if await progressStore.allPending().isEmpty {
            BackgroundAnalysisScheduler.shared.analysisFinished()
        }
    }

    private func isQueuedOrActive(_ audioFile: AudioFile) -> Bool {
        analysisQueue.contains { $0.id == audioFile.id }
            || currentAnalysis?.audioFile.id == audioFile.id
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
            await analysisCoordinator.cancelCurrentTask()
            await audioAnalyzer.cancelTranscription()
        }
        currentAnalysis = nil
    }

    /// Cancel all analyses with structured cleanup
    func cancelAllAnalyses() {
        automaticProcessingTask?.cancel()
        Task {
            await analysisCoordinator.cancelAllTasks()
            await audioAnalyzer.cancelTranscription()
        }
        currentAnalysis = nil
        analysisQueue.removeAll()
    }

    /// Stops work at an iOS background-task expiration boundary while keeping
    /// the durable queue/checkpoints available for the next system launch.
    func expireBackgroundProcessing() {
        automaticProcessingTask?.cancel()
        Task {
            await analysisCoordinator.cancelAllTasks()
            await audioAnalyzer.cancelTranscription()
        }
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

    /// WhisperKit model version baked into every cache key.
    /// Incrementing this string automatically invalidates all existing entries
    /// and forces re-analysis — do this after upgrading the WhisperKit model.
    nonisolated static let currentModelVersion = "base-v4-catalog-verification"

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
        return audioFile.id.uuidString
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
    func evictCachedResult(for audioFile: AudioFile) {
        cachedResults.removeValue(forKey: Self.cacheKey(for: audioFile))
        saveCachedResults()
    }

    func cache(_ result: CompletedAnalysis, for audioFile: AudioFile) {
        let embedded = result.audioFile.trackMetadata
            ?? audioFile.trackMetadata
            ?? AudioTrackMetadata()
        let metadata = embedded.mergingAnalyzed(result.analysis.discoveredMetadata)
        cachedResults[Self.cacheKey(for: audioFile)] = CachedAudioAnalysis(
            transcription: result.transcription,
            analysis: result.analysis,
            trackMetadata: metadata.isEmpty ? nil : metadata
        )
        saveCachedResults()
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
        guard let text = audioFile.transcription else { return nil }

        let sanitized = AudioTranscriptionResult.sanitizedTranscriptText(text)
        guard !sanitized.isEmpty else { return nil }

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

    /// URL of the on-disk analysis cache. Internal so tests can verify the path.
    nonisolated static var cacheURL: URL {
        URL.documentsDirectory.appending(path: "AnalysisCache.json")
    }

    /// Re-queues durable work and waits for the active processing loop. Used by
    /// both foreground activation and BackgroundTasks launch handlers.
    @discardableResult
    func resumeInterruptedAnalyses(priority: TaskPriority = .utility) async -> Bool {
        let pending = await progressStore.allPending()
        guard !pending.isEmpty else {
            await startAutomaticProcessing(priority: priority)
            return true
        }

        Log.analysis.info("🔁 Resuming \(pending.count) interrupted analysis/analyses…")
        var filesToResume: [AudioFile] = []
        for checkpoint in pending {
            if hasCachedResult(for: checkpoint.audioFile) {
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

    private func loadCachedResults() {
        guard let data = try? Data(contentsOf: analysisCacheURL) else { return }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([String: CachedAudioAnalysis].self, from: data) {
            cachedResults = decoded
            Log.analysis.info("📂 Loaded \(self.cachedResults.count) cached analysis result(s)")
        } else if let legacy = try? decoder.decode([String: AnalysisResult].self, from: data) {
            cachedResults = legacy.mapValues {
                CachedAudioAnalysis(
                    transcription: nil,
                    analysis: $0,
                    trackMetadata: $0.discoveredMetadata
                )
            }
            saveCachedResults()
            Log.analysis.info("📂 Migrated \(legacy.count) legacy analysis cache result(s)")
        }
    }

    private func saveCachedResults() {
        guard let data = try? JSONEncoder().encode(cachedResults) else { return }
        try? data.write(to: analysisCacheURL, options: .atomic)
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
        cache(completed, for: audioFile)

        // Write results back to the persisted AudioFile list in UserDefaults
        // so all views see the file as analyzed on next load.
        persistAnalysisToAudioFiles(
            audioFileID: audioFile.id,
            analysis: completed.analysis,
            transcription: completed.transcription.fullText,
            trackMetadata: metadata.isEmpty ? nil : metadata
        )

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
        let knownCreators = AudioLibraryStore.load()
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

    /// Updates the persisted AudioFile in UserDefaults with analysis results.
    /// This bridges AnalysisStateManager (which owns results) with the AudioFile
    /// persistence layer (UserDefaults) so every view sees the file as analyzed.
    private func persistAnalysisToAudioFiles(
        audioFileID: UUID,
        analysis: AnalysisResult,
        transcription: String,
        trackMetadata: AudioTrackMetadata?
    ) {
        guard let data = UserDefaults.standard.data(forKey: Self.audioFilesUserDefaultsKey),
              var files = try? JSONDecoder().decode([AudioFile].self, from: data) else {
            Log.analysis.info("⚠️ Could not load audio files from UserDefaults to persist analysis")
            return
        }

        guard let index = files.firstIndex(where: { $0.id == audioFileID }) else {
            Log.analysis.info("⚠️ AudioFile \(audioFileID) not found in persisted list")
            return
        }

        files[index].analysisResult = analysis
        files[index].transcription = transcription
        files[index].trackMetadata = trackMetadata

        if let encoded = try? JSONEncoder().encode(files) {
            UserDefaults.standard.set(encoded, forKey: Self.audioFilesUserDefaultsKey)
            Log.analysis.info("💾 Persisted analysis result to AudioFile in UserDefaults")
        }
    }

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

/// Main-actor coordinator for services whose observable state drives SwiftUI.
/// CPU-heavy transcription, prosody, and file work explicitly leave this actor.
@MainActor
final class AnalysisCoordinator {

    // MARK: - State

    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var isProcessing = false
    private let stageOverlapOverride: Bool?

    init(stageOverlapOverride: Bool? = nil) {
        self.stageOverlapOverride = stageOverlapOverride
    }

    // MARK: - Task Management

    func processQueue(
        audioFiles: [AudioFile],
        audioAnalyzer: any AudioTranscribingService,
        aiAnalyzer: any ContentAnalyzingService,
        performanceOptimizer: PerformanceOptimizer,
        priority: TaskPriority,
        onComplete: @Sendable @escaping (AudioFile, CompletedAnalysis) async -> Void
    ) async {
        guard !isProcessing else { return }
        isProcessing = true

        defer { isProcessing = false }

        // Get optimal concurrent limit
        let optimalLimit = await performanceOptimizer.getOptimalConcurrentLimit()

        // Use structured concurrency with TaskGroup
        await withTaskGroup(of: Void.self) { group in
            var fileIndex = 0

            while fileIndex < audioFiles.count {
                // Maintain optimal concurrent tasks
                while activeTasks.count >= optimalLimit && fileIndex < audioFiles.count {
                    // Wait briefly and clean up completed tasks
                    await Task.yield()
                    cleanupCompletedTasks()
                    try? await Task.sleep(for: .milliseconds(50))
                }

                guard fileIndex < audioFiles.count else { break }

                let audioFile = audioFiles[fileIndex]
                fileIndex += 1

                let taskId = UUID()
                let optimalPriority = await performanceOptimizer.getOptimalTaskPriority(
                    isUserInitiated: priority == .userInitiated
                )

                // Create and track task with proper actor inheritance
                let task = Task(priority: optimalPriority) {
                    await self.performSingleAnalysis(
                        audioFile: audioFile,
                        audioAnalyzer: audioAnalyzer,
                        aiAnalyzer: aiAnalyzer,
                        performanceOptimizer: performanceOptimizer,
                        onComplete: onComplete
                    )
                }

                activeTasks[taskId] = task

                // Add to group for structured concurrency
                group.addTask {
                    await task.value
                    await self.removeTask(taskId)
                }
            }
        }
        await audioAnalyzer.releaseResources()
    }

    private func performSingleAnalysis(
        audioFile: AudioFile,
        audioAnalyzer: any AudioTranscribingService,
        aiAnalyzer: any ContentAnalyzingService,
        performanceOptimizer: PerformanceOptimizer,
        onComplete: @Sendable @escaping (AudioFile, CompletedAnalysis) async -> Void
    ) async {
        let telemetryContext = AudioAnalysisTelemetryContext(audioFile: audioFile, attempt: .first)
        let telemetryStartedAt = Date()
        var telemetryStage = AnalyticsAnalysisStage.preparation
        await MainActor.run {
            UsageAnalytics.shared.audioAnalyzeStarted(context: telemetryContext)
        }

        do {
            Log.analysis.info("🔄 Starting analysis: \(audioFile.filename)")

            // Use background task registration for iOS background processing
            try await performanceOptimizer.withBackgroundTask(name: "AudioAnalysis-\(audioFile.filename)") {
                // Stage 1: Transcription
                telemetryStage = .transcription
                let transcriptionResult: AudioTranscriptionResult
                if let reusable = AnalysisStateManager.reusableTranscriptionResult(for: audioFile) {
                    Log.analysis.info("⏭️ Reusing saved transcript for \(audioFile.filename)")
                    transcriptionResult = reusable
                } else {
                    transcriptionResult = try await audioAnalyzer.transcribe(audioFile: audioFile)
                    try Task.checkCancellation()
                }

                // Stage 2: AI Analysis, with prosody extraction (independent
                // raw-audio DSP) running concurrently rather than afterwards.
                telemetryStage = .contentAnalysis
                let enricher = AudioAnalysisEnricher(analyzerConfig: AnalyzerConfigLoader.load())
                async let prosodyAsync = enricher.extractProsody(
                    audioFile: audioFile,
                    transcription: transcriptionResult
                )
                let analysisResult = try await aiAnalyzer.analyzeContent(
                    transcription: transcriptionResult,
                    audioFile: audioFile
                )
                try Task.checkCancellation()
                let enrichedAnalysis = enricher.enrich(
                    analysisResult,
                    transcription: transcriptionResult,
                    audioFile: audioFile,
                    prosody: await prosodyAsync
                )

                // Stage 3: Generate Light Session
                telemetryStage = .generation
                let lightSession = try await self.generateLightSession(
                    audioFile: audioFile,
                    analysis: enrichedAnalysis
                )
                try Task.checkCancellation()

                // Stage 4: Save Session
                telemetryStage = .persistence
                try await self.saveLightSession(lightSession, for: audioFile)

                // Complete
                let completedAnalysis = CompletedAnalysis(
                    audioFile: audioFile,
                    transcription: transcriptionResult,
                    analysis: enrichedAnalysis,
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
            Log.analysis.info("🛑 Analysis cancelled: \(audioFile.filename)")
            let finalStage = telemetryStage
            let processingTime = ProcessingTimeBucket(
                seconds: Date().timeIntervalSince(telemetryStartedAt)
            )
            await MainActor.run {
                UsageAnalytics.shared.audioAnalyzeCancelled(
                    context: telemetryContext,
                    stage: finalStage,
                    processingTime: processingTime
                )
            }
        } catch {
            Log.analysis.info("❌ Analysis failed: \(audioFile.filename) - \(error)")
            let finalStage = telemetryStage
            let processingTime = ProcessingTimeBucket(
                seconds: Date().timeIntervalSince(telemetryStartedAt)
            )
            let reason = AnalyticsAnalysisFailureReason(error: error, stage: finalStage)
            await MainActor.run {
                UsageAnalytics.shared.audioAnalysisFailed(
                    context: telemetryContext,
                    stage: finalStage,
                    reason: reason,
                    processingTime: processingTime
                )
            }
        }
    }

    private func enrichAnalysis(
        audioFile: AudioFile,
        analysis: AnalysisResult,
        transcription: AudioTranscriptionResult
    ) async -> AnalysisResult {
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
        await MainActor.run {
            let generator = SessionGenerator(config: AnalyzerConfigLoader.load().sessionGeneration)
            return generator.generateSession(
                from: audioFile,
                analysis: analysis,
                config: AnalysisPreferences.shared.generationConfig
            )
        }
    }

    private func saveLightSession(_ session: LightSession, for audioFile: AudioFile) async throws {
        try await MainActor.run {
            try GeneratedSessionStore.shared.save(session, for: audioFile)
        }
    }

    func cancelCurrentTask() async {
        guard let firstTask = activeTasks.values.first else { return }
        firstTask.cancel()
    }

    func cancelAllTasks() async {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }

    private func removeTask(_ taskId: UUID) {
        activeTasks.removeValue(forKey: taskId)
    }

    private func cleanupCompletedTasks() {
        let completedTaskIds = activeTasks.compactMap { (taskId, task) in
            task.isCancelled ? taskId : nil
        }
        for taskId in completedTaskIds {
            activeTasks.removeValue(forKey: taskId)
        }
    }

    // MARK: - Automatic Queue Processing

    /// Processes the queue as a two-stage pipeline. Content analysis remains
    /// single-file because `AIContentAnalyzer` owns one cancellable model
    /// session, while the next file may use the independent transcription lane.
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
        let stageConcurrencyLimit = await performanceOptimizer.getOptimalConcurrentLimit()

        struct TranscriptionPrefetch {
            let audioFileID: UUID
            let task: Task<Void, Never>
        }

        var transcriptionPrefetch: TranscriptionPrefetch?

        func awaitPrefetchedTranscriptionForNextFile() async {
            guard let prefetch = transcriptionPrefetch else { return }

            // Queue reordering remains authoritative. A speculative transcript
            // for a file that is no longer next should not delay the new leader.
            if analysisManager.analysisQueue.first?.id != prefetch.audioFileID {
                prefetch.task.cancel()
                await audioAnalyzer.cancelTranscription()
            }

            await prefetch.task.value
            transcriptionPrefetch = nil
        }

        func startPrefetchingNextTranscription() {
            let concurrencyAllowsPrefetch = stageOverlapOverride ?? (stageConcurrencyLimit > 1)
            guard concurrencyAllowsPrefetch,
                  transcriptionPrefetch == nil,
                  let nextFile = analysisManager.analysisQueue.first else {
                return
            }

            if stageOverlapOverride == nil {
                guard case .normal = performanceOptimizer.memoryPressure else { return }
            }

            Log.analysis.info("⏩ Prefetching transcription: \(nextFile.filename)")
            let task = Task(priority: priority) {
                await self.prefetchTranscription(
                    for: nextFile,
                    analysisManager: analysisManager,
                    audioAnalyzer: audioAnalyzer,
                    progressStore: progressStore
                )
            }
            transcriptionPrefetch = TranscriptionPrefetch(
                audioFileID: nextFile.id,
                task: task
            )
        }

        while true {
            // Do not promote a file into content analysis until its speculative
            // transcription has either completed or cleanly fallen back.
            await awaitPrefetchedTranscriptionForNextFile()
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

            // Stay structured: cancelling the queue task now propagates into
            // the current file instead of leaving an unstructured child alive.
            await performSingleAnalysisWithStateUpdates(
                audioFile: audioFile,
                analysisManager: analysisManager,
                audioAnalyzer: audioAnalyzer,
                aiAnalyzer: aiAnalyzer,
                progressStore: progressStore,
                performanceOptimizer: performanceOptimizer,
                onTranscriptionReady: startPrefetchingNextTranscription,
                onComplete: onComplete
            )

            // Check for cancellation between files
            if Task.isCancelled {
                Log.analysis.info("🛑 Queue processing cancelled")
                await MainActor.run {
                    analysisManager.currentAnalysis = nil
                }
                break
            }
        }

        if let transcriptionPrefetch {
            transcriptionPrefetch.task.cancel()
            await audioAnalyzer.cancelTranscription()
            await transcriptionPrefetch.task.value
        }

        await audioAnalyzer.releaseResources()

        // Clear current analysis when done
        await MainActor.run {
            analysisManager.currentAnalysis = nil
        }

        Log.analysis.info("🏁 Automatic queue processing finished")
    }

    /// Speculatively completes only the transcription stage for the next file.
    /// The normal checkpoint-aware pipeline still owns attempts, telemetry,
    /// retries, AI analysis, and finalization when the file reaches the front.
    private func prefetchTranscription(
        for audioFile: AudioFile,
        analysisManager: AnalysisStateManager,
        audioAnalyzer: any AudioTranscribingService,
        progressStore: AnalysisProgressStore
    ) async {
        do {
            try Task.checkCancellation()

            if let checkpoint = await progressStore.checkpoint(for: audioFile),
               checkpoint.transcription != nil || checkpoint.analysis != nil {
                Log.analysis.info("⏭️ Prefetch already checkpointed: \(audioFile.filename)")
                return
            }

            guard analysisManager.cachedCompletion(for: audioFile) == nil else {
                Log.analysis.info("⏭️ Prefetch skipped cached file: \(audioFile.filename)")
                return
            }

            let transcription: AudioTranscriptionResult
            if let reusable = AnalysisStateManager.reusableTranscriptionResult(for: audioFile) {
                transcription = reusable
            } else {
                transcription = try await audioAnalyzer.transcribe(audioFile: audioFile)
            }

            try Task.checkCancellation()
            await progressStore.saveTranscription(transcription, for: audioFile)
            Log.analysis.info("✅ Prefetched transcription: \(audioFile.filename)")
        } catch is CancellationError {
            Log.analysis.info("🛑 Transcription prefetch cancelled: \(audioFile.filename)")
        } catch {
            // Prefetch is opportunistic. The regular pipeline gets the normal
            // attempt and retry semantics when this file becomes current.
            Log.analysis.info(
                "⚠️ Transcription prefetch deferred for \(audioFile.filename): \(error.localizedDescription)"
            )
        }
    }

    /// Perform single analysis with proper state updates, resuming from any saved checkpoint.
    private func performSingleAnalysisWithStateUpdates(
        audioFile: AudioFile,
        analysisManager: AnalysisStateManager,
        audioAnalyzer: any AudioTranscribingService,
        aiAnalyzer: any ContentAnalyzingService,
        progressStore: AnalysisProgressStore,
        performanceOptimizer: PerformanceOptimizer,
        onTranscriptionReady: @MainActor () -> Void,
        onComplete: @Sendable @escaping (AudioFile, CompletedAnalysis) async -> Void
    ) async {
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
                Log.analysis.info("⚡ Restoring cached analysis: \(audioFile.filename)")
                onTranscriptionReady()
                await MainActor.run {
                    analysisManager.currentAnalysis?.stage = .generatingSession
                    analysisManager.currentAnalysis?.progress = 0.85
                }

                let lightSession = try await self.generateLightSession(
                    audioFile: cached.audioFile,
                    analysis: cached.analysis
                )
                try await self.saveLightSession(lightSession, for: cached.audioFile)
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
                return
            }

            try await performanceOptimizer.withBackgroundTask(name: "AudioAnalysis-\(audioFile.filename)") {

                // Start progress syncing loop
                let progressTracker = Task { @MainActor in
                    while !Task.isCancelled {
                        guard let current = analysisManager.currentAnalysis else { break }
                        switch current.stage {
                        case .transcribing:
                            analysisManager.currentAnalysis?.progress = audioAnalyzer.progress * 0.4
                        case .analyzing:
                            analysisManager.currentAnalysis?.progress = 0.4 + (aiAnalyzer.progress * 0.4)
                        case .generatingSession:
                            analysisManager.currentAnalysis?.progress = 0.8
                        default:
                            break
                        }
                        try? await Task.sleep(for: .milliseconds(100))
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
                    transcriptionResult = try await audioAnalyzer.transcribe(audioFile: audioFile)
                    try Task.checkCancellation()
                    await progressStore.saveTranscription(transcriptionResult, for: audioFile)
                }

                // The shared transcriber is now idle. Let the next queued file
                // occupy it while this file uses the AI/prosody lane.
                onTranscriptionReady()

                // Stage 2: AI Analysis (skip if checkpoint already has it)
                telemetryStage = .contentAnalysis
                let analysisResult: AnalysisResult
                if let saved = checkpoint?.analysis {
                    Log.analysis.info("⏭️ Skipping AI analysis (checkpoint found) for \(audioFile.filename)")
                    analysisResult = await self.enrichAnalysis(
                        audioFile: audioFile,
                        analysis: saved,
                        transcription: transcriptionResult
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
                    let enricher = AudioAnalysisEnricher(analyzerConfig: AnalyzerConfigLoader.load())
                    async let prosodyAsync = enricher.extractProsody(
                        audioFile: audioFile,
                        transcription: transcriptionResult
                    )
                    let rawAnalysis = try await aiAnalyzer.analyzeContent(
                        transcription: transcriptionResult,
                        audioFile: audioFile
                    )
                    try Task.checkCancellation()
                    analysisResult = enricher.enrich(
                        rawAnalysis,
                        transcription: transcriptionResult,
                        audioFile: audioFile,
                        prosody: await prosodyAsync
                    )
                    await progressStore.saveAnalysis(analysisResult, for: audioFile)
                }

                // Stage 3: Generate Light Session (always run — it's fast)
                telemetryStage = .generation
                await MainActor.run {
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

                // Stage 5: Mark complete and clear checkpoint
                await progressStore.clear(for: audioFile)

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
                UsageAnalytics.shared.audioAnalyzeCancelled(
                    context: telemetryContext,
                    stage: finalStage,
                    processingTime: processingTime
                )
                analysisManager.currentAnalysis?.stage = .failed
                analysisManager.currentAnalysis?.errorMessage = "Cancelled"
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
            let shouldRetry = reason.supportsAutomaticRetry && attemptNumber < 2
            let failedAt = Date()
            let retryState: AnalysisRetryState
            if shouldRetry {
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
                UsageAnalytics.shared.audioAnalysisFailed(
                    context: telemetryContext,
                    stage: finalStage,
                    reason: reason,
                    processingTime: processingTime
                )
                analysisManager.currentAnalysis?.stage = .failed
                analysisManager.currentAnalysis?.errorMessage = msg
                analysisManager.removeFromQueue(audioFile: audioFile)
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
        }
    }
}

private extension AnalyticsAnalysisFailureReason {
    /// Invalid or empty audio cannot become valid by repeating the same work.
    /// Other failures get one recovery attempt, bounded by the coordinator.
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

struct ActiveAnalysis: Equatable, Sendable {
    let audioFile: AudioFile
    var stage: AnalysisStage
    var progress: Double
    var errorMessage: String?
    /// When this analysis began — drives the "still working" reassurance copy.
    /// Excluded from `==` so elapsed time never causes spurious UI diffs.
    var startedAt: Date = Date()

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
