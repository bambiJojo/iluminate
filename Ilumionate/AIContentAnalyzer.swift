//
//  AIContentAnalyzer.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation
import FoundationModels

/// Uses Apple's on-device AI to analyze audio content with modern Swift concurrency
@MainActor @Observable
final class AIContentAnalyzer {

    // MARK: - Published State

    var isAnalyzing = false
    var progress: Double = 0.0
    var statusMessage: String = ""
    var modelAvailability: SystemLanguageModel.Availability = .unavailable(.modelNotReady)

    // MARK: - Actor-Isolated Components

    private let aiManager = AIAnalysisManager()
    private var currentTask: Task<AnalysisResult, Error>?
    private var analysisGeneration = 0

    // MARK: - Initialization

    init() {
        Task {
            modelAvailability = await aiManager.checkModelAvailability()
        }
    }

    // MARK: - Model Availability

    func checkModelAvailability() {
        Task {
            modelAvailability = await aiManager.checkModelAvailability()
        }
    }

    var isModelAvailable: Bool {
        if case .available = modelAvailability {
            return true
        }
        return false
    }

    // MARK: - Content Analysis

    /// Analyze transcribed audio content using modern async/await patterns
    func analyzeContent(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile
    ) async throws -> AnalysisResult {
        let trace = PerformanceTrace.begin("Content Analysis")
        defer { PerformanceTrace.end(trace) }

        currentTask?.cancel()
        analysisGeneration += 1
        let generation = analysisGeneration

        isAnalyzing = true
        progress = 0.0
        statusMessage = isModelAvailable
            ? "Analyzing content with AI..."
            : "Using built-in phase analysis..."

        let task = Task {
            var completed = false
            defer {
                if self.analysisGeneration == generation {
                    self.currentTask = nil
                    self.isAnalyzing = false
                    self.statusMessage = Task.isCancelled
                        ? "Analysis cancelled"
                        : (completed ? "Analysis complete" : "Analysis failed")
                }
            }

            let progressHandler: @Sendable (AIAnalysisManager.ProgressInfo) async -> Void = { info in
                await MainActor.run {
                    self.progress = info.progress
                    self.statusMessage = info.message
                }
            }

            let result = try await aiManager.analyzeContent(
                transcription: transcription,
                audioFile: audioFile,
                onProgress: progressHandler
            )
            completed = true
            return result
        }
        currentTask = task

        return try await task.value
    }

    /// Analyze audio without transcription using modern patterns
    func analyzeWithoutTranscription(
        audioFile: AudioFile,
        audioFeatures: AudioFeatures
    ) async throws -> AnalysisResult {
        let trace = PerformanceTrace.begin("Content Analysis No Transcript")
        defer { PerformanceTrace.end(trace) }

        guard isModelAvailable else {
            throw AIAnalyzerError.modelUnavailable
        }

        currentTask?.cancel()
        analysisGeneration += 1
        let generation = analysisGeneration

        isAnalyzing = true
        progress = 0.0
        statusMessage = "Analyzing audio characteristics..."

        let task = Task {
            var completed = false
            defer {
                if self.analysisGeneration == generation {
                    self.currentTask = nil
                    self.isAnalyzing = false
                    self.statusMessage = Task.isCancelled
                        ? "Analysis cancelled"
                        : (completed ? "Analysis complete" : "Analysis failed")
                }
            }

            let progressHandler: @Sendable (AIAnalysisManager.ProgressInfo) async -> Void = { info in
                await MainActor.run {
                    self.progress = info.progress
                    self.statusMessage = info.message
                }
            }

            let result = try await aiManager.analyzeWithoutTranscription(
                audioFile: audioFile,
                audioFeatures: audioFeatures,
                onProgress: progressHandler
            )
            completed = true
            return result
        }
        currentTask = task

        return try await task.value
    }

    func cancelAnalysis() async {
        analysisGeneration += 1
        currentTask?.cancel()
        currentTask = nil
        await aiManager.cancelAnalysis()
        isAnalyzing = false
        progress = 0
        statusMessage = "Analysis cancelled"
    }
}

// MARK: - Audio Features (for non-transcribed analysis)

struct AudioFeatures {
    let averageTempo: Double // BPM
    let averageEnergy: Double // 0.0 to 1.0
    let dynamicRange: String // "low", "medium", "high"
}

// MARK: - Errors

enum AIAnalyzerError: LocalizedError {
    case modelUnavailable
    case analysisFailed(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "AI model is not available on this device"
        case .analysisFailed(let error):
            return "Analysis failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "AI returned an invalid response"
        }
    }
}
