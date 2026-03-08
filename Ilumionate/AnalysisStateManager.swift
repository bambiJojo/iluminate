//
//  AnalysisStateManager.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/24/26.
//

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
    var onAnalysisComplete: (@Sendable (AudioFile, CompletedAnalysis) -> Void)?

    // MARK: - Initialization

    private init() {
        // Private initializer to enforce singleton usage
    }

    // MARK: - Actor-Isolated State Management

    private let analysisCoordinator = AnalysisCoordinator()
    private let audioAnalyzer = AudioAnalyzer()
    private let aiAnalyzer = AIContentAnalyzer()
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

    // MARK: - Private Methods

    /// Handle analysis completion with proper actor isolation
    private func handleAnalysisComplete(audioFile: AudioFile, result: CompletedAnalysis) async {
        completedAnalyses.append(result)
        onAnalysisComplete?(audioFile, result)

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
        audioAnalyzer: AudioAnalyzer,
        aiAnalyzer: AIContentAnalyzer,
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

                // Create and track task
                let task = Task.detached(priority: optimalPriority) {
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
        audioAnalyzer: AudioAnalyzer,
        aiAnalyzer: AIContentAnalyzer,
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
        // File I/O on utility priority
        try await Task.detached(priority: .utility) {
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
        audioAnalyzer: AudioAnalyzer,
        aiAnalyzer: AIContentAnalyzer,
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

            // Create task for single file processing
            let task = Task.detached(priority: optimalPriority) {
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

    /// Perform single analysis with proper state updates
    private func performSingleAnalysisWithStateUpdates(
        audioFile: AudioFile,
        analysisManager: AnalysisStateManager,
        audioAnalyzer: AudioAnalyzer,
        aiAnalyzer: AIContentAnalyzer,
        performanceOptimizer: PerformanceOptimizer,
        onComplete: @Sendable @escaping (AudioFile, CompletedAnalysis) async -> Void
    ) async {
        do {
            print("🔄 Starting analysis: \(audioFile.filename)")

            // Use background task registration for iOS background processing
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

                // Stage 1: Transcription
                await MainActor.run {
                    analysisManager.currentAnalysis?.stage = .transcribing
                }

                let transcriptionResult = try await audioAnalyzer.transcribe(audioFile: audioFile)
                try Task.checkCancellation()

                // Stage 2: AI Analysis
                await MainActor.run {
                    analysisManager.currentAnalysis?.stage = .analyzing
                }

                let analysisResult = try await aiAnalyzer.analyzeContent(
                    transcription: transcriptionResult,
                    audioFile: audioFile
                )
                try Task.checkCancellation()

                // Stage 3: Generate Light Session
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

                // Stage 5: Mark complete
                await MainActor.run {
                    analysisManager.currentAnalysis?.stage = .complete
                    analysisManager.currentAnalysis?.progress = 1.0
                }

                // Complete
                let completedAnalysis = CompletedAnalysis(
                    audioFile: audioFile,
                    transcription: transcriptionResult,
                    analysis: analysisResult,
                    completedAt: Date()
                )

                // Call completion handler
                await onComplete(audioFile, completedAnalysis)

                print("✅ Analysis completed: \(audioFile.filename)")
            }
        } catch is CancellationError {
            print("🛑 Analysis cancelled: \(audioFile.filename)")
            await MainActor.run {
                analysisManager.currentAnalysis?.stage = .failed
                analysisManager.currentAnalysis?.errorMessage = "Cancelled"
                analysisManager.removeFromQueue(audioFile: audioFile)
            }
        } catch {
            print("❌ Analysis failed: \(audioFile.filename) - \(error)")
            await MainActor.run {
                analysisManager.currentAnalysis?.stage = .failed
                analysisManager.currentAnalysis?.errorMessage = error.localizedDescription
                analysisManager.removeFromQueue(audioFile: audioFile)
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
