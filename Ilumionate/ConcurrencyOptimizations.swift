//
//  ConcurrencyOptimizations.swift
//  Ilumionate
//
//  Swift concurrency enhancements and advanced patterns
//

import Foundation
import AVFoundation

// MARK: - Async Sequence for Real-time Audio Processing

/// High-performance async sequence for real-time audio monitoring
@MainActor
struct AudioLevelSequence: AsyncSequence {
    typealias Element = (leftLevel: Float, rightLevel: Float)

    private let audioEngine: AVAudioEngine
    private let updateInterval: TimeInterval

    init(audioEngine: AVAudioEngine, updateInterval: TimeInterval = 0.01) {
        self.audioEngine = audioEngine
        self.updateInterval = updateInterval
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(audioEngine: audioEngine, updateInterval: updateInterval)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private let audioEngine: AVAudioEngine
        private let updateInterval: TimeInterval
        private var cancelled = false

        init(audioEngine: AVAudioEngine, updateInterval: TimeInterval) {
            self.audioEngine = audioEngine
            self.updateInterval = updateInterval
        }

        mutating func next() async throws -> Element? {
            guard !cancelled else { return nil }

            try await Task.sleep(for: .seconds(updateInterval))

            // Get real-time audio levels
            guard let playerNode = audioEngine.mainMixerNode as AVAudioMixerNode? else {
                return nil
            }

            // Simulated audio levels - in production would be real audio analysis
            let leftLevel = Float.random(in: 0...1)
            let rightLevel = Float.random(in: 0...1)

            return (leftLevel: leftLevel, rightLevel: rightLevel)
        }

        mutating func cancel() {
            cancelled = true
        }
    }
}

// MARK: - Actor-Isolated Audio Pipeline

/// Thread-safe audio processing pipeline using actors
actor AudioPipeline {

    // MARK: - State

    private var processors: [UUID: AudioProcessor] = [:]
    private let maxConcurrentProcessors = 3

    // MARK: - Audio Processor

    private struct AudioProcessor {
        let id: UUID
        let task: Task<AudioAnalysisResult, Error>
        let priority: TaskPriority
    }

    // MARK: - Pipeline Operations

    func addAudioForProcessing(
        audioFile: AudioFile,
        priority: TaskPriority = .userInitiated
    ) async -> UUID {
        let processorId = UUID()

        // Remove completed processors first
        await cleanupCompletedProcessors()

        // Wait if at capacity
        while processors.count >= maxConcurrentProcessors {
            try? await Task.sleep(for: .milliseconds(100))
            await cleanupCompletedProcessors()
        }

        // Create processor task
        let task = Task(priority: priority) {
            return try await self.processAudio(audioFile: audioFile)
        }

        let processor = AudioProcessor(
            id: processorId,
            task: task,
            priority: priority
        )

        processors[processorId] = processor
        return processorId
    }

    func getProcessingResult(for processorId: UUID) async throws -> AudioAnalysisResult? {
        guard let processor = processors[processorId] else { return nil }

        let result = try await processor.task.value
        processors.removeValue(forKey: processorId)

        return result
    }

    private func processAudio(audioFile: AudioFile) async throws -> AudioAnalysisResult {
        // Simulated audio processing - would be real in production
        try await Task.sleep(for: .seconds(Double.random(in: 1...5)))

        return AudioAnalysisResult(
            audioFile: audioFile,
            features: AudioFeatures(
                averageTempo: Double.random(in: 60...140),
                averageEnergy: Double.random(in: 0.1...0.9),
                dynamicRange: ["low", "medium", "high"].randomElement()!
            ),
            processedAt: Date()
        )
    }

    private func cleanupCompletedProcessors() {
        let completedProcessorIds = processors.compactMap { (id, processor) in
            processor.task.isCancelled ? id : nil
        }

        for id in completedProcessorIds {
            processors.removeValue(forKey: id)
        }
    }

    func cancelProcessor(id: UUID) {
        processors[id]?.task.cancel()
        processors.removeValue(forKey: id)
    }

    func cancelAllProcessors() {
        for processor in processors.values {
            processor.task.cancel()
        }
        processors.removeAll()
    }

    var activeProcessorCount: Int {
        processors.count
    }
}

// MARK: - Supporting Types

struct AudioAnalysisResult: Sendable {
    let audioFile: AudioFile
    let features: AudioFeatures
    let processedAt: Date
}

// MARK: - Sendable Compliant Timer Manager

/// Thread-safe timer management with modern Swift concurrency
@MainActor
@Observable
class ConcurrencyTimer: Sendable {

    // MARK: - State

    private(set) var isRunning = false
    private(set) var elapsedTime: TimeInterval = 0
    private var startTime: Date?
    private var updateTask: Task<Void, Never>?

    // MARK: - Timer Operations

    func start() async {
        guard !isRunning else { return }

        isRunning = true
        startTime = Date()
        elapsedTime = 0

        updateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self, let startTime = self.startTime else { break }

                self.elapsedTime = Date().timeIntervalSince(startTime)

                try? await Task.sleep(for: .milliseconds(16)) // ~60fps updates
            }
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
        isRunning = false
        startTime = nil
    }

    func reset() {
        stop()
        elapsedTime = 0
    }

    // MARK: - Formatted Output

    var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let milliseconds = Int((elapsedTime - floor(elapsedTime)) * 100)

        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

// MARK: - Task Group Audio Batch Processing

/// High-performance batch audio processing with structured concurrency
struct AudioBatchProcessor: Sendable {

    private let maxConcurrency: Int

    init(maxConcurrency: Int = 3) {
        self.maxConcurrency = maxConcurrency
    }

    /// Process multiple audio files concurrently with optimal resource usage
    func processBatch(
        audioFiles: [AudioFile],
        priority: TaskPriority = .userInitiated,
        onProgress: @Sendable @escaping (Int, Int) async -> Void = { _, _ in }
    ) async -> [AudioAnalysisResult] {

        return await withTaskGroup(of: AudioAnalysisResult?.self, returning: [AudioAnalysisResult].self) { group in
            var results: [AudioAnalysisResult] = []
            var fileIndex = 0
            var completedCount = 0
            let totalFiles = audioFiles.count

            // Add initial batch of tasks up to concurrency limit
            for _ in 0..<min(maxConcurrency, audioFiles.count) {
                guard fileIndex < audioFiles.count else { break }

                let audioFile = audioFiles[fileIndex]
                fileIndex += 1

                group.addTask(priority: priority) {
                    return try? await self.processSingleAudioFile(audioFile: audioFile)
                }
            }

            // Process results and add new tasks as needed
            for await result in group {
                completedCount += 1

                if let result = result {
                    results.append(result)
                }

                // Report progress
                await onProgress(completedCount, totalFiles)

                // Add next file if available
                if fileIndex < audioFiles.count {
                    let audioFile = audioFiles[fileIndex]
                    fileIndex += 1

                    group.addTask(priority: priority) {
                        return try? await self.processSingleAudioFile(audioFile: audioFile)
                    }
                }
            }

            return results
        }
    }

    private func processSingleAudioFile(audioFile: AudioFile) async throws -> AudioAnalysisResult {
        // Simulated processing time based on file size
        let processingTime = min(max(Double(audioFile.fileSize) / 1_000_000, 0.5), 10.0)
        try await Task.sleep(for: .seconds(processingTime))

        return AudioAnalysisResult(
            audioFile: audioFile,
            features: AudioFeatures(
                averageTempo: Double.random(in: 60...140),
                averageEnergy: Double.random(in: 0.1...0.9),
                dynamicRange: ["low", "medium", "high"].randomElement()!
            ),
            processedAt: Date()
        )
    }
}

// MARK: - Memory-Safe Audio Level Monitor

/// Real-time audio level monitoring with automatic memory management
@MainActor
@Observable
class AudioLevelMonitor: Sendable {

    // MARK: - State

    private(set) var isMonitoring = false
    private(set) var currentLevels: (left: Float, right: Float) = (0, 0)
    private(set) var peakLevels: (left: Float, right: Float) = (0, 0)

    private var monitoringTask: Task<Void, Never>?
    private let levelDecayRate: Float = 0.95

    // MARK: - Monitoring Control

    func startMonitoring(audioEngine: AVAudioEngine) async {
        guard !isMonitoring else { return }

        isMonitoring = true
        peakLevels = (0, 0)

        monitoringTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            let audioSequence = AudioLevelSequence(audioEngine: audioEngine)

            do {
                for try await levels in audioSequence {
                    guard !Task.isCancelled else { break }

                    self.updateLevels(levels)
                }
            } catch {
                print("❌ Audio monitoring error: \(error)")
            }

            await self.stopMonitoring()
        }
    }

    func stopMonitoring() async {
        monitoringTask?.cancel()
        monitoringTask = nil
        isMonitoring = false
        currentLevels = (0, 0)
    }

    // MARK: - Level Processing

    private func updateLevels(_ levels: (leftLevel: Float, rightLevel: Float)) {
        currentLevels = (left: levels.leftLevel, right: levels.rightLevel)

        // Update peak levels with decay
        peakLevels.left = max(levels.leftLevel, peakLevels.left * levelDecayRate)
        peakLevels.right = max(levels.rightLevel, peakLevels.right * levelDecayRate)
    }

    // MARK: - Computed Properties

    var averageLevel: Float {
        (currentLevels.left + currentLevels.right) / 2.0
    }

    var stereoWidth: Float {
        abs(currentLevels.left - currentLevels.right)
    }
}

// AudioFile already conforms to Sendable in AudioFile.swift (value type).
// URL is a stdlib value type and already implicitly Sendable.