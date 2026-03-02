//
//  AIContentAnalyzer.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation
import FoundationModels
import Combine

/// Uses Apple's on-device AI to analyze audio content and generate recommendations
@MainActor
class AIContentAnalyzer: ObservableObject {

    // MARK: - Published State

    @Published var isAnalyzing = false
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var modelAvailability: SystemLanguageModel.Availability = .unavailable(.modelNotReady)

    // MARK: - Private State

    private let model = SystemLanguageModel.default
    private var session: LanguageModelSession?

    // MARK: - Initialization

    init() {
        checkModelAvailability()
    }

    // MARK: - Model Availability

    func checkModelAvailability() {
        modelAvailability = model.availability

        switch modelAvailability {
        case .available:
            print("✅ Foundation Models available")
        case .unavailable(let reason):
            print("❌ Foundation Models unavailable: \(reason)")
        }
    }

    var isModelAvailable: Bool {
        if case .available = modelAvailability {
            return true
        }
        return false
    }

    // MARK: - Content Analysis

    /// Analyze transcribed audio content to generate therapy recommendations
    func analyzeContent(transcription: AudioTranscriptionResult, audioFile: AudioFile) async throws -> AnalysisResult {
        guard isModelAvailable else {
            throw AIAnalyzerError.modelUnavailable
        }

        // Update UI state on main thread
        await MainActor.run {
            isAnalyzing = true
            progress = 0.0
            statusMessage = "Analyzing content with AI..."
        }

        defer {
            Task { @MainActor in
                isAnalyzing = false
            }
        }

        // Perform analysis on background thread for better performance
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached { [weak self] in
                await self?.performBackgroundAnalysis(
                    transcription: transcription,
                    audioFile: audioFile,
                    continuation: continuation
                )
            }
        }
    }

    /// Performs the actual analysis on a background queue
    private func performBackgroundAnalysis(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile,
        continuation: CheckedContinuation<AnalysisResult, Error>
    ) async {

        do {
            // Create analysis session with instructions
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

            await MainActor.run {
                progress = 0.2
            }

            // Build the analysis prompt efficiently
            let prompt = buildAnalysisPrompt(transcription: transcription, duration: audioFile.duration)

            await MainActor.run {
                progress = 0.4
                statusMessage = "Generating AI recommendations..."
            }

            // Request structured analysis
            let response = try await session!.respond(
                to: prompt,
                generating: AIAnalysisResponse.self
            )

            await MainActor.run {
                progress = 0.8
                statusMessage = "Processing recommendations..."
            }

            // Convert AI response to AnalysisResult
            let result = convertToAnalysisResult(
                aiResponse: response.content,
                duration: audioFile.duration
            )

            await MainActor.run {
                progress = 1.0
                statusMessage = "Analysis complete"
            }

            print("✅ AI Analysis completed")
            print("📊 Mood: \(result.mood.rawValue), Energy: \(result.energyLevel)")
            print("💡 Frequency range: \(result.suggestedFrequencyRange)")
            print("🎯 Key moments: \(result.keyMoments.count)")

            continuation.resume(returning: result)

        } catch {
            await MainActor.run {
                statusMessage = "Analysis failed"
            }
            print("❌ AI Analysis error: \(error)")
            continuation.resume(throwing: AIAnalyzerError.analysisFailed(error))
        }
    }

    /// Analyze audio without transcription (for music or instrumental content)
    func analyzeWithoutTranscription(audioFile: AudioFile, audioFeatures: AudioFeatures) async throws -> AnalysisResult {
        guard isModelAvailable else {
            throw AIAnalyzerError.modelUnavailable
        }

        isAnalyzing = true
        progress = 0.0
        statusMessage = "Analyzing audio characteristics..."

        defer {
            isAnalyzing = false
        }

        do {
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

            progress = 0.5

            let response = try await session!.respond(
                to: prompt,
                generating: AIAnalysisResponse.self
            )

            progress = 0.9

            let result = convertToAnalysisResult(
                aiResponse: response.content,
                duration: audioFile.duration
            )

            progress = 1.0
            statusMessage = "Analysis complete"

            return result

        } catch {
            statusMessage = "Analysis failed"
            print("❌ AI Analysis error: \(error)")
            throw AIAnalyzerError.analysisFailed(error)
        }
    }

    // MARK: - Helper Methods

    /// Efficiently builds analysis prompt using StringBuilder pattern
    private func buildAnalysisPrompt(transcription: AudioTranscriptionResult, duration: TimeInterval) -> String {
        // Pre-allocate capacity for better performance
        var prompt = ""
        prompt.reserveCapacity(1000)

        let wordCount = transcription.wordCount
        let textPreview = String(transcription.fullText.prefix(500))
        let durationStr = formatDuration(duration)
        let confidenceStr = String(format: "%.1f%%", transcription.averageConfidence * 100)

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
        // Convert AI response to our AnalysisResult model
        let mood = AnalysisResult.Mood(rawValue: aiResponse.mood.lowercased()) ?? .neutral

        // Parse frequency range (format: "8-12" or "8.0-12.0")
        let frequencyComponents = aiResponse.frequencyRange
            .components(separatedBy: CharacterSet(charactersIn: "-–—"))
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }

        let frequencyRange: ClosedRange<Double>
        if frequencyComponents.count == 2 {
            frequencyRange = frequencyComponents[0]...frequencyComponents[1]
        } else {
            // Default to alpha waves if parsing fails
            frequencyRange = 8.0...12.0
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
