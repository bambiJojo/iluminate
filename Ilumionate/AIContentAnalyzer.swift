//
//  AIContentAnalyzer.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation
import FoundationModels
import Combine

/// Uses Apple's on-device AI to analyze audio content with modern Swift concurrency
@MainActor @Observable
class AIContentAnalyzer: Sendable {

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
    func analyzeContent(transcription: AudioTranscriptionResult, audioFile: AudioFile) async throws -> AnalysisResult {
        guard isModelAvailable else {
            throw AIAnalyzerError.modelUnavailable
        }

        // Cancel any existing analysis
        currentTask?.cancel()

        isAnalyzing = true
        progress = 0.0
        statusMessage = "Analyzing content with AI..."

        // Create cancellable task
        currentTask = Task {
            defer {
                Task { @MainActor in
                    self.isAnalyzing = false
                    self.statusMessage = "Analysis complete"
                }
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

        return try await currentTask!.value
    }

    /// Analyze audio without transcription using modern patterns
    func analyzeWithoutTranscription(audioFile: AudioFile, audioFeatures: AudioFeatures) async throws -> AnalysisResult {
        guard isModelAvailable else {
            throw AIAnalyzerError.modelUnavailable
        }

        currentTask?.cancel()

        isAnalyzing = true
        progress = 0.0
        statusMessage = "Analyzing audio characteristics..."

        currentTask = Task {
            defer {
                Task { @MainActor in
                    self.isAnalyzing = false
                    self.statusMessage = "Analysis complete"
                }
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

        return try await currentTask!.value
    }

}

// MARK: - AI Analysis Manager Actor

/// Actor-isolated AI analysis manager for thread-safe operations
actor AIAnalysisManager {

    // MARK: - State

    private let model = SystemLanguageModel.default
    private var session: LanguageModelSession?
    private var currentTask: Task<LanguageModelSession.Response<AIAnalysisResponse>, Error>?

    // MARK: - Progress Info

    struct ProgressInfo: Sendable {
        let progress: Double
        let message: String
    }

    // MARK: - Model Availability

    func checkModelAvailability() async -> SystemLanguageModel.Availability {
        let availability = model.availability
        switch availability {
        case .available:
            print("✅ Foundation Models available")
        case .unavailable(let reason):
            print("❌ Foundation Models unavailable: \(reason)")
        }
        return availability
    }

    // MARK: - Analysis Methods

    func analyzeContent(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile,
        onProgress: @Sendable @escaping (ProgressInfo) async -> Void
    ) async throws -> AnalysisResult {
        await onProgress(ProgressInfo(progress: 0.1, message: "Setting up AI session..."))

        // Create analysis session
        let instructions = """
        You are an expert in light therapy, neuroscience, and brainwave entrainment.
        Your role is to analyze audio content (meditation, music, spoken word) and recommend
        optimal light therapy parameters that complement and enhance the audio experience.

        Consider:
        - The overall mood and emotional tone
        - Energy level (calming vs. energizing)
        - Pacing and rhythm
        - Key transitions or climactic moments
        - The intended purpose (relaxation, focus, sleep, energy)

        Provide specific, actionable recommendations for:
        - Light frequency ranges (in Hz) based on brainwave states
        - Intensity levels (0.0 to 1.0)
        - Color temperature in Kelvin (2000K warm to 6500K cool)
        - Key moments where parameters should change

        Be concise and focus on what will create the best synergistic effect.
        """

        session = LanguageModelSession(instructions: instructions)

        await onProgress(ProgressInfo(progress: 0.3, message: "Building analysis prompt..."))

        // Build analysis prompt
        let prompt = buildAnalysisPrompt(transcription: transcription, duration: audioFile.duration)

        await onProgress(ProgressInfo(progress: 0.5, message: "Generating AI recommendations..."))

        // Create analysis task
        currentTask = Task {
            return try await session!.respond(to: prompt, generating: AIAnalysisResponse.self)
        }

        let response = try await currentTask!.value
        currentTask = nil

        await onProgress(ProgressInfo(progress: 0.9, message: "Processing recommendations..."))

        let result = convertToAnalysisResult(aiResponse: response.content, duration: audioFile.duration)

        print("✅ AI Analysis completed")
        print("📊 Mood: \(result.mood.rawValue), Energy: \(result.energyLevel)")
        print("💡 Frequency range: \(result.suggestedFrequencyRange)")
        print("🎯 Key moments: \(result.keyMoments.count)")

        return result
    }

    func analyzeWithoutTranscription(
        audioFile: AudioFile,
        audioFeatures: AudioFeatures,
        onProgress: @Sendable @escaping (ProgressInfo) async -> Void
    ) async throws -> AnalysisResult {
        await onProgress(ProgressInfo(progress: 0.1, message: "Setting up audio analysis..."))

        let instructions = """
        You are an expert in audio analysis and light therapy for music and instrumental audio.
        Based on audio characteristics, recommend light therapy parameters.
        """

        session = LanguageModelSession(instructions: instructions)

        let prompt = """
        Analyze this audio file and recommend light therapy parameters:

        Audio Characteristics:
        - Duration: \(formatDuration(audioFile.duration))
        - Average Tempo: \(audioFeatures.averageTempo) BPM
        - Average Energy: \(String(format: "%.1f%%", audioFeatures.averageEnergy * 100))
        - Dynamic Range: \(audioFeatures.dynamicRange)

        Provide recommendations for:
        1. Overall mood classification
        2. Suggested light frequency range (Hz)
        3. Intensity level (0.0-1.0)
        4. Color temperature preference
        5. How parameters should evolve over time
        """

        await onProgress(ProgressInfo(progress: 0.5, message: "Analyzing audio features..."))

        currentTask = Task {
            return try await session!.respond(to: prompt, generating: AIAnalysisResponse.self)
        }

        let response = try await currentTask!.value
        currentTask = nil

        let result = convertToAnalysisResult(aiResponse: response.content, duration: audioFile.duration)
        return result
    }

    // MARK: - Helper Methods

    private func buildAnalysisPrompt(transcription: AudioTranscriptionResult, duration: TimeInterval) -> String {
        var prompt = ""
        prompt.reserveCapacity(1000)

        // Safe access to transcription properties
        let wordCount = transcription.fullText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        let textPreview = String(transcription.fullText.prefix(500))
        let durationStr = formatDuration(duration)
        let avgConfidence = transcription.segments.isEmpty ? 0.0 : transcription.segments.map { $0.confidence }.reduce(0, +) / Double(transcription.segments.count)
        let confidenceStr = String(format: "%.1f%%", avgConfidence * 100)

        prompt += "Analyze this audio content and recommend light therapy parameters:\n\n"
        prompt += "Audio Information:\n"
        prompt += "- Duration: \(durationStr)\n"
        prompt += "- Word Count: \(wordCount)\n"
        prompt += "- Average Confidence: \(confidenceStr)\n\n"
        prompt += "Transcription (first 500 characters):\n\"\(textPreview)...\""

        prompt += "\n\nPlease provide a structured analysis with:\n"
        prompt += "1. Overall mood (relaxing, energizing, neutral, meditative, uplifting, or melancholic)\n"
        prompt += "2. Energy level (0.0 = very calm, 1.0 = very energetic)\n"
        prompt += "3. Suggested frequency range in Hz (consider alpha 8-12Hz for relaxation, beta 12-30Hz for focus, theta 4-8Hz for meditation, delta 0.5-4Hz for sleep)\n"
        prompt += "4. Suggested intensity (0.0-1.0)\n"
        prompt += "5. Recommended color temperature in Kelvin (2000K warm amber for relaxation, 6500K cool white for focus)\n"
        prompt += "6. 3-5 key moments with timestamps where the tone or energy shifts\n"
        prompt += "7. A brief summary (2-3 sentences)\n"
        prompt += "8. Recommended preset name"

        return prompt
    }

    private func convertToAnalysisResult(aiResponse: AIAnalysisResponse, duration: TimeInterval) -> AnalysisResult {
        let mood = AnalysisResult.Mood(rawValue: aiResponse.mood.lowercased()) ?? .neutral

        // Parse frequency range
        let frequencyComponents = aiResponse.frequencyRange
            .components(separatedBy: CharacterSet(charactersIn: "-–—"))
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }

        let frequencyRange: ClosedRange<Double>
        if frequencyComponents.count == 2 {
            frequencyRange = frequencyComponents[0]...frequencyComponents[1]
        } else {
            frequencyRange = 8.0...12.0 // Default to alpha waves
        }

        // Convert key moments
        let keyMoments = aiResponse.keyMoments.map { moment in
            KeyMoment(
                time: moment.timestamp,
                description: moment.description,
                suggestedAction: moment.action
            )
        }

        return AnalysisResult(
            mood: mood,
            energyLevel: aiResponse.energyLevel,
            suggestedFrequencyRange: frequencyRange,
            suggestedIntensity: aiResponse.intensity,
            suggestedColorTemperature: aiResponse.colorTemperature,
            keyMoments: keyMoments,
            aiSummary: aiResponse.summary,
            recommendedPreset: aiResponse.recommendedPreset
        )
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }

    func cancelAnalysis() async {
        currentTask?.cancel()
        currentTask = nil
    }
}

// MARK: - AI Response Structure

@Generable(description: "Analysis of audio content for light therapy recommendations")
struct AIAnalysisResponse {
    @Guide(description: "The overall mood: relaxing, energizing, neutral, meditative, uplifting, or melancholic")
    var mood: String

    @Guide(description: "Energy level from 0.0 (very calm) to 1.0 (very energetic)", .range(0.0...1.0))
    var energyLevel: Double

    @Guide(description: "Suggested frequency range in Hz, format like '8-12' or '10-14'")
    var frequencyRange: String

    @Guide(description: "Suggested light intensity from 0.0 to 1.0", .range(0.0...1.0))
    var intensity: Double

    @Guide(description: "Recommended color temperature in Kelvin (2000-6500)", .range(2000...6500))
    var colorTemperature: Double

    @Guide(description: "Key moments where parameters should change", .count(3...5))
    var keyMoments: [AIKeyMoment]

    @Guide(description: "A brief 2-3 sentence summary of the analysis")
    var summary: String

    @Guide(description: "Recommended preset name")
    var recommendedPreset: String
}

@Generable(description: "A significant moment in the audio")
struct AIKeyMoment {
    @Guide(description: "Timestamp in seconds")
    var timestamp: Double

    @Guide(description: "Description of what happens at this moment")
    var description: String

    @Guide(description: "Suggested action like 'increase intensity' or 'shift to warmer colors'")
    var action: String
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
