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
        guard isModelAvailable else {
            throw AIAnalyzerError.modelUnavailable
        }

        currentTask?.cancel()

        isAnalyzing = true
        progress = 0.0
        statusMessage = "Analyzing content with AI..."

        let task = Task {
            defer {
                self.isAnalyzing = false
                self.statusMessage = "Analysis complete"
            }

            let progressHandler: @Sendable (AIAnalysisManager.ProgressInfo) async -> Void = { info in
                await MainActor.run {
                    self.progress = info.progress
                    self.statusMessage = info.message
                }
            }

            return try await aiManager.analyzeContent(
                transcription: transcription,
                audioFile: audioFile,
                onProgress: progressHandler
            )
        }
        currentTask = task

        return try await task.value
    }

    /// Analyze audio without transcription using modern patterns
    func analyzeWithoutTranscription(
        audioFile: AudioFile,
        audioFeatures: AudioFeatures
    ) async throws -> AnalysisResult {
        guard isModelAvailable else {
            throw AIAnalyzerError.modelUnavailable
        }

        currentTask?.cancel()

        isAnalyzing = true
        progress = 0.0
        statusMessage = "Analyzing audio characteristics..."

        let task = Task {
            defer {
                self.isAnalyzing = false
                self.statusMessage = "Analysis complete"
            }

            let progressHandler: @Sendable (AIAnalysisManager.ProgressInfo) async -> Void = { info in
                await MainActor.run {
                    self.progress = info.progress
                    self.statusMessage = info.message
                }
            }

            return try await aiManager.analyzeWithoutTranscription(
                audioFile: audioFile,
                audioFeatures: audioFeatures,
                onProgress: progressHandler
            )
        }
        currentTask = task

        return try await task.value
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
