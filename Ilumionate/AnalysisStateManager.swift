//
//  AnalysisStateManager.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/24/26.
//

import CryptoKit
import Foundation
import Observation

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
class AnalysisStateManager: Sendable {

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
    private init() {
        self.audioAnalyzer = AudioAnalyzer()
        self.aiAnalyzer = AIContentAnalyzer()
        loadCachedResults()
        Task { await resumeInterruptedAnalyses() }
    }

    /// Testable initializer — inject mock services for unit testing.
    /// Not intended for production use; use `shared` instead.
    init(transcriber: any AudioTranscribingService, analyzer: any ContentAnalyzingService) {
        self.audioAnalyzer = transcriber
        self.aiAnalyzer = analyzer
        loadCachedResults()
    }

    // MARK: - Actor-Isolated State Management

    private let analysisCoordinator = AnalysisCoordinator()
    private let audioAnalyzer: any AudioTranscribingService
    private let aiAnalyzer: any ContentAnalyzingService
    private let performanceOptimizer = PerformanceOptimizer.shared

    // MARK: - Queue Management

    /// Remove a file from the analysis queue
    func removeFromQueue(audioFile: AudioFile) {
        analysisQueue.removeAll { $0.id == audioFile.id }
        print("🗑 Removed \(audioFile.filename) from analysis queue")
    }

    /// Move a file up in the queue (closer to front)
    func moveUpInQueue(audioFile: AudioFile) {
        guard let currentIndex = analysisQueue.firstIndex(where: { $0.id == audioFile.id }),
              currentIndex > 0 else { return }

        analysisQueue.swapAt(currentIndex, currentIndex - 1)
        print("⬆️ Moved \(audioFile.filename) up in queue")
    }

    /// Move a file down in the queue (further back)
    func moveDownInQueue(audioFile: AudioFile) {
        guard let currentIndex = analysisQueue.firstIndex(where: { $0.id == audioFile.id }),
              currentIndex < analysisQueue.count - 1 else { return }

        analysisQueue.swapAt(currentIndex, currentIndex + 1)
        print("⬇️ Moved \(audioFile.filename) down in queue")
    }

    /// Get queue position for a file (1-indexed, 0 if not in queue)
    func queuePosition(for audioFile: AudioFile) -> Int {
        guard let index = analysisQueue.firstIndex(where: { $0.id == audioFile.id }) else { return 0 }
        return index + 1
    }

    /// Clear entire analysis queue
    func clearQueue() {
        analysisQueue.removeAll()
        print("🧹 Cleared analysis queue")
    }

    /// Move a file to the front of the analysis queue for immediate processing
    func prioritizeInQueue(audioFile: AudioFile) {
        guard let index = analysisQueue.firstIndex(where: { $0.id == audioFile.id }),
              index > 0 else { return }
        let file = analysisQueue.remove(at: index)
        analysisQueue.insert(file, at: 0)
        print("⚡ Prioritized \(audioFile.filename) to front of queue")
    }

    // MARK: - Analysis Control

    /// Add a single audio file to queue and start automatic background processing
    func queueForAnalysis(_ audioFile: AudioFile, priority: TaskPriority = .background) async {
        // Add to queue if not already there
        guard !analysisQueue.contains(where: { $0.id == audioFile.id }) else {
            print("📋 File already in queue: \(audioFile.filename)")
            return
        }

        analysisQueue.append(audioFile)
        print("📋 Added to queue: \(audioFile.filename) (position \(analysisQueue.count))")

        // Start automatic processing if nothing is currently analyzing
        await startAutomaticProcessing(priority: priority)
    }

    /// Add multiple files to queue and start automatic background processing
    func queueForAnalysis(_ audioFiles: [AudioFile], priority: TaskPriority = .background) async {
        var newFilesAdded = 0

        // Add all files to queue (avoid duplicates)
        for audioFile in audioFiles {
            if !analysisQueue.contains(where: { $0.id == audioFile.id }) {
                analysisQueue.append(audioFile)
                newFilesAdded += 1
            }
        }

        print("📋 Added \(newFilesAdded) files to queue (total: \(analysisQueue.count))")

        // Start automatic processing if nothing is currently analyzing
        await startAutomaticProcessing(priority: priority)
    }

    /// Start automatic background processing of the queue
    private func startAutomaticProcessing(priority: TaskPriority = .background) async {
        // Don't start if already processing or queue is empty
        guard currentAnalysis == nil && !analysisQueue.isEmpty else {
            print("⏸️ Skipping auto-processing: analyzing=\(currentAnalysis != nil), queue=\(analysisQueue.count)")
            return
        }

        print("🚀 Starting automatic queue processing...")

        // Process queue continuously until empty
        await analysisCoordinator.processQueueAutomatically(
            analysisManager: self,
            audioAnalyzer: audioAnalyzer,
            aiAnalyzer: aiAnalyzer,
            performanceOptimizer: performanceOptimizer,
            priority: priority
        ) { [weak self] audioFile, result in
            await self?.handleAnalysisComplete(audioFile: audioFile, result: result)
        }
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
        Task {
            await analysisCoordinator.cancelCurrentTask()
            await audioAnalyzer.cancelTranscription()
        }
        currentAnalysis = nil
    }

    /// Cancel all analyses with structured cleanup
    func cancelAllAnalyses() {
        Task {
            await analysisCoordinator.cancelAllTasks()
            await audioAnalyzer.cancelTranscription()
        }
        currentAnalysis = nil
        analysisQueue.removeAll()
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

    /// In-memory cache: content-addressed key → AnalysisResult.
    private var cachedResults: [String: AnalysisResult] = [:]

    // MARK: Content-Addressed Key

    /// WhisperKit model version baked into every cache key.
    /// Incrementing this string automatically invalidates all existing entries
    /// and forces re-analysis — do this after upgrading the WhisperKit model.
    nonisolated static let currentModelVersion = "base-v1"

    /// Maximum bytes read from the audio file for fingerprinting.
    nonisolated private static let cacheKeyChunkBytes = 64 * 1024 // 64 KB

    /// Returns a content-addressed cache key: SHA-256 of the first 64 KB
    /// of the audio file, followed by a colon and the model version string.
    ///
    /// Falls back to the file's UUID string when the audio file cannot be
    /// read (e.g., synthetic `AudioFile` objects in unit tests).
    nonisolated static func cacheKey(for audioFile: AudioFile) -> String {
        contentAddressedKey(audioFileURL: audioFile.url) ?? audioFile.id.uuidString
    }

    /// Computes SHA-256 of the first `cacheKeyChunkBytes` of `url`.
    /// Returns `nil` when the file cannot be read.
    nonisolated static func contentAddressedKey(
        audioFileURL url: URL,
        modelVersion: String = currentModelVersion
    ) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = (try? handle.read(upToCount: cacheKeyChunkBytes)) ?? Data()
        guard !chunk.isEmpty else { return nil }
        let hex = SHA256.hash(data: chunk).map { String(format: "%02x", $0) }.joined()
        return "\(hex):\(modelVersion)"
    }

    // MARK: Cache API

    /// Returns the cached analysis result for a file, or nil if none exists.
    func cachedResult(for audioFile: AudioFile) -> AnalysisResult? {
        cachedResults[Self.cacheKey(for: audioFile)]
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

    /// URL of the on-disk analysis cache. Internal so tests can verify the path.
    static var cacheURL: URL {
        URL.documentsDirectory.appending(path: "AnalysisCache.json")
    }

    /// Re-queues any audio files whose analysis was interrupted before completion.
    private func resumeInterruptedAnalyses() async {
        let pending = await AnalysisProgressStore.shared.allPending()
        guard !pending.isEmpty else { return }

        print("🔁 Resuming \(pending.count) interrupted analysis/analyses…")
        let filesToResume = pending
            .filter { !hasCachedResult(for: $0.audioFile) }
            .map(\.audioFile)

        guard !filesToResume.isEmpty else {
            // All checkpoints already have finished results — clean up stale entries
            await AnalysisProgressStore.shared.clearAll()
            return
        }

        await queueForAnalysis(filesToResume)
    }

    private func loadCachedResults() {
        guard let data = try? Data(contentsOf: Self.cacheURL) else { return }
        if let decoded = try? JSONDecoder().decode([String: AnalysisResult].self, from: data) {
            cachedResults = decoded
            print("📂 Loaded \(cachedResults.count) cached analysis result(s)")
        }
    }

    private func saveCachedResults() {
        guard let data = try? JSONEncoder().encode(cachedResults) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    // MARK: - Private Methods

    /// Handle analysis completion with proper actor isolation
    private func handleAnalysisComplete(audioFile: AudioFile, result: CompletedAnalysis) async {
        completedAnalyses.append(result)
        onAnalysisComplete?(audioFile, result)

        // Persist the analysis result, keyed by content fingerprint
        cachedResults[Self.cacheKey(for: audioFile)] = result.analysis
        saveCachedResults()

        // Remove from queue
        analysisQueue.removeAll { $0.id == audioFile.id }

        print("✅ Analysis completed: \(audioFile.filename)")
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
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionsURL = documentsURL.appendingPathComponent("GeneratedSessions", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: sessionsURL.path) {
            try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        }

        // Create filename from audio file
        let baseName = audioFile.filename
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".m4a", with: "")
            .replacingOccurrences(of: ".wav", with: "")
        let filename = "\(baseName)_session.json"
        let fileURL = sessionsURL.appendingPathComponent(filename)

        // Encode and save
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: fileURL)

        print("💾 Saved generated session: \(filename)")
        print("📍 Location: \(fileURL.path)")
    }
}

// MARK: - Analysis Coordinator Actor

/// Actor-isolated coordinator for managing concurrent analysis tasks
actor AnalysisCoordinator {

    // MARK: - State

    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var isProcessing = false

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
    }

    private func performSingleAnalysis(
        audioFile: AudioFile,
        audioAnalyzer: any AudioTranscribingService,
        aiAnalyzer: any ContentAnalyzingService,
        performanceOptimizer: PerformanceOptimizer,
        onComplete: @Sendable @escaping (AudioFile, CompletedAnalysis) async -> Void
    ) async {
        do {
            print("🔄 Starting analysis: \(audioFile.filename)")

            // Use background task registration for iOS background processing
            try await performanceOptimizer.withBackgroundTask(name: "AudioAnalysis-\(audioFile.filename)") {
                // Stage 1: Transcription
                let transcriptionResult = try await audioAnalyzer.transcribe(audioFile: audioFile)
                try Task.checkCancellation()

                // Stage 2: AI Analysis
                let analysisResult = try await aiAnalyzer.analyzeContent(
                    transcription: transcriptionResult,
                    audioFile: audioFile
                )
                try Task.checkCancellation()

                // Stage 3: Generate Light Session
                let lightSession = try await self.generateLightSession(
                    audioFile: audioFile,
                    analysis: analysisResult,
                    transcription: transcriptionResult
                )
                try Task.checkCancellation()

                // Stage 4: Save Session
                try await self.saveLightSession(lightSession, for: audioFile)

                // Complete
                let completedAnalysis = CompletedAnalysis(
                    audioFile: audioFile,
                    transcription: transcriptionResult,
                    analysis: analysisResult,
                    completedAt: Date()
                )

                await onComplete(audioFile, completedAnalysis)
            }
        } catch is CancellationError {
            print("🛑 Analysis cancelled: \(audioFile.filename)")
        } catch {
            print("❌ Analysis failed: \(audioFile.filename) - \(error)")
        }
    }

    private func generateLightSession(
        audioFile: AudioFile,
        analysis: AnalysisResult,
        transcription: AudioTranscriptionResult
    ) async throws -> LightSession {
        // This should be done on a background actor to avoid blocking
        return await MainActor.run {
            let generator = AudioLightScoreGenerator()
            return generator.generateLightScore(
                from: audioFile,
                analysis: analysis,
                transcription: transcription
            )
        }
    }

    private func saveLightSession(_ session: LightSession, for audioFile: AudioFile) async throws {
        // File I/O with proper concurrency handling
        try await Task(priority: .utility) {
            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let sessionsURL = documentsURL.appendingPathComponent("GeneratedSessions", isDirectory: true)

            // Create directory if needed
            if !fileManager.fileExists(atPath: sessionsURL.path) {
                try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
            }

            // Create filename
            let baseName = audioFile.filename
                .replacingOccurrences(of: ".mp3", with: "")
                .replacingOccurrences(of: ".m4a", with: "")
                .replacingOccurrences(of: ".wav", with: "")
            let filename = "\(baseName)_session.json"
            let fileURL = sessionsURL.appendingPathComponent(filename)

            // Encode and save using a safe encoding context
            let data = try await MainActor.run {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return try encoder.encode(session)
            }
            try data.write(to: fileURL)

            print("💾 Saved generated session: \(filename)")
        }.value
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

    /// Process files one at a time from the queue until empty
    func processQueueAutomatically(
        analysisManager: AnalysisStateManager,
        audioAnalyzer: any AudioTranscribingService,
        aiAnalyzer: any ContentAnalyzingService,
        performanceOptimizer: PerformanceOptimizer,
        priority: TaskPriority,
        onComplete: @Sendable @escaping (AudioFile, CompletedAnalysis) async -> Void
    ) async {
        guard !isProcessing else {
            print("⏸️ Queue processing already active")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        print("🚀 Starting automatic queue processing...")

        // Process files one at a time until queue is empty
        while true {
            // Get next file from queue on main actor
            let nextFile: AudioFile? = await MainActor.run {
                guard !analysisManager.analysisQueue.isEmpty else { return nil }
                return analysisManager.analysisQueue.removeFirst()
            }

            // Break if queue is empty
            guard let audioFile = nextFile else {
                print("✅ Queue processing complete - no more files")
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

            print("🔄 Processing: \(audioFile.filename) (queue position: \(await MainActor.run { analysisManager.queuePosition(for: audioFile) }))")

            // Process the current file
            let taskId = UUID()
            let optimalPriority = await performanceOptimizer.getOptimalTaskPriority(
                isUserInitiated: priority == .userInitiated
            )

            // Create task for single file processing with proper concurrency
            let task = Task(priority: optimalPriority) {
                await self.performSingleAnalysisWithStateUpdates(
                    audioFile: audioFile,
                    analysisManager: analysisManager,
                    audioAnalyzer: audioAnalyzer,
                    aiAnalyzer: aiAnalyzer,
                    performanceOptimizer: performanceOptimizer,
                    onComplete: onComplete
                )
            }

            activeTasks[taskId] = task

            // Wait for completion and clean up
            await task.value
            activeTasks.removeValue(forKey: taskId)

            // Check for cancellation between files
            if Task.isCancelled {
                print("🛑 Queue processing cancelled")
                await MainActor.run {
                    analysisManager.currentAnalysis = nil
                }
                break
            }
        }

        // Clear current analysis when done
        await MainActor.run {
            analysisManager.currentAnalysis = nil
        }

        print("🏁 Automatic queue processing finished")
    }

    /// Perform single analysis with proper state updates, resuming from any saved checkpoint.
    private func performSingleAnalysisWithStateUpdates(
        audioFile: AudioFile,
        analysisManager: AnalysisStateManager,
        audioAnalyzer: any AudioTranscribingService,
        aiAnalyzer: any ContentAnalyzingService,
        performanceOptimizer: PerformanceOptimizer,
        onComplete: @Sendable @escaping (AudioFile, CompletedAnalysis) async -> Void
    ) async {
        // Load any checkpoint saved from a previous run.
        let checkpoint = await AnalysisProgressStore.shared.checkpoint(for: audioFile)
        let resumingFrom = checkpoint?.resumeStage ?? .transcribing

        if checkpoint != nil {
            print("🔁 Resuming \(audioFile.filename) from stage: \(resumingFrom)")
        } else {
            print("🔄 Starting analysis: \(audioFile.filename)")
        }

        do {
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
                let transcriptionResult: AudioTranscriptionResult
                if let saved = checkpoint?.transcription {
                    print("⏭️ Skipping transcription (checkpoint found) for \(audioFile.filename)")
                    transcriptionResult = saved
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
                    await AnalysisProgressStore.shared.saveTranscription(transcriptionResult, for: audioFile)
                }

                // Stage 2: AI Analysis (skip if checkpoint already has it)
                let analysisResult: AnalysisResult
                if let saved = checkpoint?.analysis {
                    print("⏭️ Skipping AI analysis (checkpoint found) for \(audioFile.filename)")
                    analysisResult = saved
                    await MainActor.run {
                        analysisManager.currentAnalysis?.stage = .generatingSession
                        analysisManager.currentAnalysis?.progress = 0.8
                    }
                } else {
                    await MainActor.run {
                        analysisManager.currentAnalysis?.stage = .analyzing
                    }
                    analysisResult = try await aiAnalyzer.analyzeContent(
                        transcription: transcriptionResult,
                        audioFile: audioFile
                    )
                    try Task.checkCancellation()
                    await AnalysisProgressStore.shared.saveAnalysis(analysisResult, for: audioFile)
                }

                // Stage 3: Generate Light Session (always run — it's fast)
                await MainActor.run {
                    analysisManager.currentAnalysis?.stage = .generatingSession
                    analysisManager.currentAnalysis?.progress = 0.8
                }

                let lightSession = try await self.generateLightSession(
                    audioFile: audioFile,
                    analysis: analysisResult,
                    transcription: transcriptionResult
                )
                try Task.checkCancellation()

                // Stage 4: Save Session
                try await self.saveLightSession(lightSession, for: audioFile)

                // Stage 5: Mark complete and clear checkpoint
                await AnalysisProgressStore.shared.clear(for: audioFile)

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

                await onComplete(audioFile, completedAnalysis)

                print("✅ Analysis completed: \(audioFile.filename)")
            }
        } catch is CancellationError {
            // Keep the checkpoint — progress is preserved for next launch.
            print("🛑 Analysis cancelled: \(audioFile.filename) — checkpoint preserved for resume")
            await MainActor.run {
                analysisManager.currentAnalysis?.stage = .failed
                analysisManager.currentAnalysis?.errorMessage = "Cancelled"
                analysisManager.removeFromQueue(audioFile: audioFile)
            }
        } catch {
            let msg = error.localizedDescription
            print("❌ Analysis failed: \(audioFile.filename) - \(msg)")
            // Keep checkpoint on transient errors; it will be retried on next launch.
            await MainActor.run {
                analysisManager.currentAnalysis?.stage = .failed
                analysisManager.currentAnalysis?.errorMessage = msg
                analysisManager.removeFromQueue(audioFile: audioFile)
                analysisManager.failedAnalyses.append(
                    FailedAnalysis(audioFile: audioFile, errorMessage: msg, failedAt: Date())
                )
            }
        }
    }
}

// MARK: - Active Analysis Model

struct ActiveAnalysis: Equatable, Sendable {
    let audioFile: AudioFile
    var stage: AnalysisStage
    var progress: Double
    var errorMessage: String?

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
