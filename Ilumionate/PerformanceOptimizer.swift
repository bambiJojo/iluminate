//
//  PerformanceOptimizer.swift
//  Ilumionate
//
//  Performance optimization utilities for audio processing and background tasks
//

import Foundation
import os
import AVFoundation
import Observation

#if canImport(UIKit)
import UIKit
#endif

nonisolated enum BackgroundTaskPolicy {
    /// UIKit background assertions are short-lived and are not appropriate for
    /// transcription. The analysis checkpoint store resumes interrupted work.
    static func shouldRegisterForLongAnalysis() -> Bool {
        false
    }
}

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

    nonisolated enum MemoryPressureLevel: Sendable {
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

        switch memoryInfo.cleanupAction {
        case .aggressive:
            Log.general.info("🔥 CRITICAL memory usage: \(Int(memoryInfo.usage))MB")
        case .moderate:
            Log.general.info("⚠️ High memory usage: \(Int(memoryInfo.usage))MB")
        case nil:
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
        operation: () async throws -> T
    ) async throws -> T {
        _ = name
        return try await operation()
    }
    /// Process large audio file in memory-efficient chunks
    func processAudioInChunks<T: Sendable>(
        audioFile: AudioFile,
        chunkSize: TimeInterval,
        processor: @Sendable (AVURLAsset, CMTimeRange) async throws -> T
    ) async throws -> [T] {
        return try await memoryMonitor.processAudioInChunks(
            audioFile: audioFile,
            chunkSize: chunkSize,
            processor: processor
        )
    }
}

/// Suppresses repeated cleanup while the process remains in the same pressure
/// episode. Cleanup is rearmed only after memory returns to the normal band.
nonisolated struct MemoryCleanupPolicy: Sendable {
    nonisolated enum Action: Equatable, Sendable {
        case moderate
        case aggressive
    }

    private var highestHandledLevel: PerformanceOptimizer.MemoryPressureLevel = .normal

    mutating func action(
        for pressureLevel: PerformanceOptimizer.MemoryPressureLevel
    ) -> Action? {
        switch pressureLevel {
        case .normal:
            highestHandledLevel = .normal
            return nil
        case .warning:
            guard highestHandledLevel == .normal else { return nil }
            highestHandledLevel = .warning
            return .moderate
        case .critical:
            guard highestHandledLevel != .critical else { return nil }
            highestHandledLevel = .critical
            return .aggressive
        }
    }
}

// MARK: - Memory Monitor Actor

/// Actor-isolated memory monitoring and management
actor MemoryMonitor {

    // MARK: - State

    private var monitoringTask: Task<Void, Never>?
    private var cleanupPolicy = MemoryCleanupPolicy()

    // MARK: - Memory Info

    struct MemoryInfo: Sendable {
        let usage: Double
        let pressureLevel: PerformanceOptimizer.MemoryPressureLevel
        let cleanupAction: MemoryCleanupPolicy.Action?
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
                let cleanupAction = cleanupPolicy.action(for: pressureLevel)

                let memoryInfo = MemoryInfo(
                    usage: usage,
                    pressureLevel: pressureLevel,
                    cleanupAction: cleanupAction
                )
                await onUpdate(memoryInfo)

                switch cleanupAction {
                case .moderate:
                    await performModerateCleanup()
                case .aggressive:
                    await performAggressiveCleanup()
                case nil:
                    break
                }

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
        // `.utility` instead of `.background`: analysis is work the user is
        // actively waiting on behind a progress bar. Background QoS is
        // restricted to efficiency cores and aggressively throttled by iOS,
        // which multiplies wall-clock analysis time for zero benefit.
        return .utility
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
        Log.general.info("🧹 Performing moderate memory cleanup...")
        await MainActor.run {
            URLCache.shared.removeAllCachedResponses()
        }
    }

    func performAggressiveCleanup() async {
        Log.general.info("🔥 Performing aggressive memory cleanup...")
        await performModerateCleanup()

        await MainActor.run {
            #if canImport(UIKit)
            NotificationCenter.default.post(
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: nil
            )
            #endif
        }
    }

    // MARK: - Background Task Management

    func withBackgroundTask<T: Sendable>(
        name: String,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        _ = name
        return try await operation()
    }

    // MARK: - Audio Processing

    func processAudioInChunks<T: Sendable>(
        audioFile: AudioFile,
        chunkSize: TimeInterval,
        processor: @Sendable (AVURLAsset, CMTimeRange) async throws -> T
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

            Log.general.info("📦 Processing chunk: \(Int(currentTime))s - \(Int(currentTime + chunkDuration))s")

            let result = try await processor(asset, timeRange)
            results.append(result)

            currentTime += chunkDuration

            // Allow other tasks to run
            await Task.yield()

            // Check memory pressure and pause if needed
            let currentUsage = await getCurrentMemoryUsage()
            if currentUsage > 400 {
                Log.general.info("⏸ Pausing due to critical memory pressure")
                try await Task.sleep(for: .seconds(1))
            }
        }

        return results
    }

    deinit {
        monitoringTask?.cancel()
    }
}
