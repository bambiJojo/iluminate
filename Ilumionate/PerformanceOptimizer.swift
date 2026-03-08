//
//  PerformanceOptimizer.swift
//  Ilumionate
//
//  Performance optimization utilities for audio processing and background tasks
//

import Foundation
import AVFoundation
import Observation
import UIKit

/// Memory and performance optimization utilities with modern Swift concurrency
@MainActor @Observable
class PerformanceOptimizer: Sendable {

    // MARK: - Memory Management

    static let shared = PerformanceOptimizer()

    /// Current memory usage in MB
    var currentMemoryUsage: Double = 0.0

    /// Memory pressure level
    var memoryPressure: MemoryPressureLevel = .normal

    // MARK: - Actor-Isolated Monitoring

    private let memoryMonitor = MemoryMonitor()

    private init() {
        Task {
            await startMemoryMonitoring()
        }
    }

    // MARK: - Memory Monitoring

    enum MemoryPressureLevel {
        case normal
        case warning  // > 200MB
        case critical // > 400MB
    }

    private func startMemoryMonitoring() async {
        await memoryMonitor.startMonitoring { [weak self] memoryInfo in
            await self?.updateMemoryStats(memoryInfo)
        }
    }

    private func updateMemoryStats(_ memoryInfo: MemoryMonitor.MemoryInfo) {
        currentMemoryUsage = memoryInfo.usage
        memoryPressure = memoryInfo.pressureLevel

        switch memoryPressure {
        case .critical:
            print("🔥 CRITICAL memory usage: \(Int(memoryInfo.usage))MB")
            Task {
                await memoryMonitor.performAggressiveCleanup()
            }
        case .warning:
            print("⚠️ High memory usage: \(Int(memoryInfo.usage))MB")
            Task {
                await memoryMonitor.performModerateCleanup()
            }
        case .normal:
            break
        }
    }

    // MARK: - Public Interface Methods

    func getOptimalConcurrentLimit() async -> Int {
        return await memoryMonitor.getOptimalConcurrentLimit()
    }

    func getOptimalTaskPriority(isUserInitiated: Bool) async -> TaskPriority {
        return await memoryMonitor.getOptimalTaskPriority(isUserInitiated: isUserInitiated)
    }

    func shouldChunkAudioFile(_ audioFile: AudioFile) async -> Bool {
        return await memoryMonitor.shouldChunkAudioFile(audioFile)
    }

    func getOptimalChunkSize(for audioFile: AudioFile) async -> TimeInterval {
        return await memoryMonitor.getOptimalChunkSize(memoryPressure: memoryPressure)
    }

    // MARK: - Background Task Management

    /// Register a background task with automatic cleanup
    func withBackgroundTask<T>(
        name: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await memoryMonitor.withBackgroundTask(name: name, operation: operation)
    }
    /// Process large audio file in memory-efficient chunks
    func processAudioInChunks<T>(
        audioFile: AudioFile,
        chunkSize: TimeInterval,
        processor: (AVURLAsset, CMTimeRange) async throws -> T
    ) async throws -> [T] {
        return try await memoryMonitor.processAudioInChunks(
            audioFile: audioFile,
            chunkSize: chunkSize,
            processor: processor
        )
    }
}

// MARK: - Memory Monitor Actor

/// Actor-isolated memory monitoring and management
actor MemoryMonitor {

    // MARK: - State

    private var monitoringTask: Task<Void, Never>?

    // MARK: - Memory Info

    struct MemoryInfo: Sendable {
        let usage: Double
        let pressureLevel: PerformanceOptimizer.MemoryPressureLevel
    }

    // MARK: - Monitoring

    func startMonitoring(
        onUpdate: @Sendable @escaping (MemoryInfo) async -> Void
    ) async {
        monitoringTask?.cancel()

        monitoringTask = Task {
            while !Task.isCancelled {
                let usage = await getCurrentMemoryUsage()
                let pressureLevel = determinePressureLevel(usage: usage)

                let memoryInfo = MemoryInfo(usage: usage, pressureLevel: pressureLevel)
                await onUpdate(memoryInfo)

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func getCurrentMemoryUsage() async -> Double {
        let MACH_TASK_BASIC_INFO_COUNT = MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size

        let name = mach_task_self_
        let flavor = task_flavor_t(MACH_TASK_BASIC_INFO)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MACH_TASK_BASIC_INFO_COUNT)

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(name, flavor, $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
        }

        return 0.0
    }

    private func determinePressureLevel(usage: Double) -> PerformanceOptimizer.MemoryPressureLevel {
        if usage > 400 {
            return .critical
        } else if usage > 200 {
            return .warning
        } else {
            return .normal
        }
    }

    // MARK: - Optimization Methods

    func getOptimalConcurrentLimit() -> Int {
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        // Conservative approach for better stability
        return max(1, min(processorCount / 3, 2))
    }

    func getOptimalTaskPriority(isUserInitiated: Bool) -> TaskPriority {
        if isUserInitiated {
            return .userInitiated
        }
        return .background
    }

    func shouldChunkAudioFile(_ audioFile: AudioFile) async -> Bool {
        // Chunk files longer than 10 minutes for better memory management
        return audioFile.duration > 600
    }

    func getOptimalChunkSize(memoryPressure: PerformanceOptimizer.MemoryPressureLevel) -> TimeInterval {
        switch memoryPressure {
        case .normal:
            return 300 // 5 minutes
        case .warning:
            return 180 // 3 minutes
        case .critical:
            return 60  // 1 minute
        }
    }

    // MARK: - Cleanup Operations

    func performModerateCleanup() async {
        print("🧹 Performing moderate memory cleanup...")
        await MainActor.run {
            URLCache.shared.removeAllCachedResponses()
        }
    }

    func performAggressiveCleanup() async {
        print("🔥 Performing aggressive memory cleanup...")
        await performModerateCleanup()

        await MainActor.run {
            NotificationCenter.default.post(
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: nil
            )
        }
    }

    // MARK: - Background Task Management

    func withBackgroundTask<T>(
        name: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let taskID = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: name) {
                print("⏰ Background task '\(name)' expired")
            }
        }

        defer {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }

        return try await operation()
    }

    // MARK: - Audio Processing

    func processAudioInChunks<T>(
        audioFile: AudioFile,
        chunkSize: TimeInterval,
        processor: (AVURLAsset, CMTimeRange) async throws -> T
    ) async throws -> [T] {
        let asset = AVURLAsset(url: audioFile.url)
        let duration = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(duration)

        var results: [T] = []
        var currentTime: TimeInterval = 0

        while currentTime < totalDuration {
            let chunkDuration = min(chunkSize, totalDuration - currentTime)
            let startTime = CMTime(seconds: currentTime, preferredTimescale: 44100)
            let chunkCMDuration = CMTime(seconds: chunkDuration, preferredTimescale: 44100)
            let timeRange = CMTimeRange(start: startTime, duration: chunkCMDuration)

            print("📦 Processing chunk: \(Int(currentTime))s - \(Int(currentTime + chunkDuration))s")

            let result = try await processor(asset, timeRange)
            results.append(result)

            currentTime += chunkDuration

            // Allow other tasks to run
            await Task.yield()

            // Check memory pressure and pause if needed
            let currentUsage = await getCurrentMemoryUsage()
            if currentUsage > 400 {
                print("⏸ Pausing due to critical memory pressure")
                try await Task.sleep(for: .seconds(1))
            }
        }

        return results
    }

    deinit {
        monitoringTask?.cancel()
    }
}