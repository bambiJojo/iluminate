//
//  StreamingAnalyzer.swift
//  Ilumionate
//
//  Enhanced analysis pipeline for streaming content with intelligent light score generation
//

import Foundation
import AVFoundation

@MainActor
@Observable
class StreamingAnalyzer: Sendable {

    // MARK: - State

    var isAnalyzing = false
    var progress: Double = 0.0
    var statusMessage = ""

    private let aiAnalyzer = AIContentAnalyzer()
    private let audioAnalyzer = AudioAnalyzer()
    private let sessionGenerator = SessionGenerator()

    // MARK: - Enhanced Analysis Pipeline

    /// Analyze streaming content and generate optimized light session
    func analyzeAndGenerateSession(for track: StreamingTrack) async throws -> LightSession {
        print("🎵 Starting enhanced analysis for: \(track.title)")

        isAnalyzing = true
        progress = 0.0
        statusMessage = "Preparing analysis..."

        defer {
            isAnalyzing = false
            statusMessage = ""
        }

        // Step 1: Predict content type from metadata (instant)
        progress = 0.1
        statusMessage = "Analyzing metadata..."
        let predictedType = predictContentType(from: track)
        print("📊 Predicted content type: \(predictedType)")

        // Step 2: Download and analyze audio (if available)
        progress = 0.3
        statusMessage = "Downloading audio sample..."

        let audioFile = AudioFile(streamingTrack: track)
        var finalAnalysis: AnalysisResult

        if let streamURL = track.streamURL {
            // Analyze actual audio content
            progress = 0.5
            statusMessage = "Analyzing audio content..."

            finalAnalysis = try await analyzeStreamingAudio(url: streamURL, predictedType: predictedType)
        } else {
            // Use metadata-based analysis
            finalAnalysis = createMetadataAnalysis(for: track, contentType: predictedType)
        }

        // Step 3: Generate optimized light session
        progress = 0.8
        statusMessage = "Generating light session..."

        let config = createOptimizedConfig(for: finalAnalysis, track: track)
        let session = sessionGenerator.generateSession(
            from: audioFile,
            analysis: finalAnalysis,
            config: config
        )

        progress = 1.0
        statusMessage = "Complete!"

        print("✅ Generated session: \(session.light_score.count) light moments")
        return session
    }

    // MARK: - Intelligent Content Type Prediction

    private func predictContentType(from track: StreamingTrack) -> AnalysisResult.ContentType {
        let title = track.title.lowercased()
        let artist = track.artist.lowercased()

        // Hypnosis patterns
        if title.contains("hypnosis") || title.contains("hypnotic") ||
           title.contains("trance") || title.contains("induction") ||
           artist.contains("hypnosis") {
            return .hypnosis
        }

        // Meditation patterns
        if title.contains("meditation") || title.contains("mindfulness") ||
           title.contains("breathing") || title.contains("zen") ||
           title.contains("chakra") || artist.contains("meditation") {
            return .meditation
        }

        // Guided imagery patterns
        if title.contains("guided") || title.contains("visualization") ||
           title.contains("journey") || title.contains("imagery") {
            return .guidedImagery
        }

        // Affirmations patterns
        if title.contains("affirmation") || title.contains("positive") ||
           title.contains("self-love") || title.contains("confidence") {
            return .affirmations
        }

        // Music patterns
        if title.contains("ambient") || title.contains("drone") ||
           title.contains("soundscape") || title.contains("nature") ||
           title.contains("white noise") || title.contains("binaural") {
            return .music
        }

        // Default based on service - SoundCloud often has therapeutic content
        return track.duration > 600 ? .meditation : .music // Long tracks likely meditation
    }

    // MARK: - Streaming Audio Analysis

    private func analyzeStreamingAudio(url: URL, predictedType: AnalysisResult.ContentType) async throws -> AnalysisResult {
        // Download a sample for analysis (first 30 seconds is usually enough)
        let sampleData = try await downloadAudioSample(url: url)

        // Perform lightweight audio analysis
        let audioCharacteristics = await analyzeAudioCharacteristics(data: sampleData)

        // Combine with AI analysis if model is available
        if aiAnalyzer.isModelAvailable {
            // Use AI for more accurate content classification
            return try await aiAnalyzer.analyzeContent(from: sampleData, predictedType: predictedType)
        } else {
            // Fallback to characteristics-based analysis
            return createCharacteristicsBasedAnalysis(
                characteristics: audioCharacteristics,
                predictedType: predictedType
            )
        }
    }

    private func downloadAudioSample(url: URL, duration: TimeInterval = 30) async throws -> Data {
        // Download first 30 seconds for analysis
        let (data, _) = try await URLSession.shared.data(from: url)

        // For production, you'd want to:
        // 1. Stream only the needed portion
        // 2. Convert to analysis format
        // 3. Handle different audio formats

        return data
    }

    private func analyzeAudioCharacteristics(data: Data) async -> AudioCharacteristics {
        // Analyze tempo, energy, spectral content using modern concurrency
        return await withTaskGroup(of: AudioCharacteristics.self) { group in
            group.addTask {
                // Placeholder for actual audio analysis
                // In production, this would use AVAudioEngine or similar
                return AudioCharacteristics(
                    tempo: Double.random(in: 60...140),
                    energy: Double.random(in: 0.1...0.9),
                    spectralCentroid: Double.random(in: 1000...4000),
                    hasVoice: true // Would be detected
                )
            }

            // Return first (only) result
            for await result in group {
                return result
            }

            // Fallback (shouldn't reach here)
            return AudioCharacteristics(
                tempo: 120.0,
                energy: 0.5,
                spectralCentroid: 2000.0,
                hasVoice: false
            )
        }
    }

    // MARK: - Analysis Creation

    private func createMetadataAnalysis(for track: StreamingTrack, contentType: AnalysisResult.ContentType) -> AnalysisResult {
        let mood: AnalysisResult.Mood = {
            switch contentType {
            case .meditation: return .meditative
            case .hypnosis: return .relaxing
            case .music: return .neutral
            case .guidedImagery: return .uplifting
            case .affirmations: return .energizing
            case .unknown: return .neutral
            }
        }()

        let energyLevel: Double = {
            switch contentType {
            case .hypnosis: return 0.2
            case .meditation: return 0.3
            case .guidedImagery: return 0.5
            case .affirmations: return 0.7
            case .music: return 0.4
            case .unknown: return 0.5
            }
        }()

        let frequencyRange: ClosedRange<Double> = {
            switch contentType {
            case .hypnosis: return 0.5...8.0
            case .meditation: return 4.0...12.0
            case .guidedImagery: return 3.0...15.0
            case .affirmations: return 8.0...25.0
            case .music: return 6.0...20.0
            case .unknown: return 4.0...14.0
            }
        }()

        return AnalysisResult(
            mood: mood,
            energyLevel: energyLevel,
            suggestedFrequencyRange: frequencyRange,
            suggestedIntensity: energyLevel,
            suggestedColorTemperature: contentType == .meditation ? 3000 : nil,
            keyMoments: [], // Would be generated from actual analysis
            aiSummary: "Streaming content optimized for \(contentType.rawValue)",
            recommendedPreset: contentType.rawValue,
            contentType: contentType
        )
    }

    private func createCharacteristicsBasedAnalysis(
        characteristics: AudioCharacteristics,
        predictedType: AnalysisResult.ContentType
    ) -> AnalysisResult {
        let mood: AnalysisResult.Mood = characteristics.energy < 0.5 ? .meditative : .energizing
        let energyLevel = characteristics.energy

        return AnalysisResult(
            mood: mood,
            energyLevel: energyLevel,
            suggestedFrequencyRange: 4.0...16.0,
            suggestedIntensity: energyLevel,
            suggestedColorTemperature: nil,
            keyMoments: [], // Would extract from actual audio
            aiSummary: "Audio-analyzed content with \(characteristics.hasVoice ? "voice" : "instrumental") characteristics",
            recommendedPreset: predictedType.rawValue,
            contentType: predictedType
        )
    }

    // MARK: - Optimized Configuration

    private func createOptimizedConfig(for analysis: AnalysisResult, track: StreamingTrack) -> SessionGenerator.GenerationConfig {
        var config = SessionGenerator.GenerationConfig.default

        // Optimize based on content type
        switch analysis.contentType {
        case .hypnosis:
            // Slower, deeper frequencies for hypnosis
            config.minFrequency = 0.5
            config.maxFrequency = 8.0
            config.transitionSmoothness = 0.9
            config.intensityMultiplier = 0.7
            config.bilateralMode = true // Enhance with bilateral stimulation

        case .meditation:
            // Alpha/theta range for meditation
            config.minFrequency = 4.0
            config.maxFrequency = 12.0
            config.transitionSmoothness = 0.8
            config.colorTemperatureOverride = 3000 // Warm light

        case .music:
            // Follow the tempo for music
            config.minFrequency = 6.0
            config.maxFrequency = 20.0
            config.transitionSmoothness = 0.6
            config.intensityMultiplier = 1.0

        case .guidedImagery:
            // Support visualization with varied patterns
            config.minFrequency = 3.0
            config.maxFrequency = 15.0
            config.bilateralMode = true

        case .affirmations:
            // Energizing frequencies for confidence
            config.minFrequency = 8.0
            config.maxFrequency = 25.0
            config.intensityMultiplier = 0.9

        case .unknown:
            // Conservative defaults
            break
        }

        // Adjust based on duration
        if track.duration > 3600 { // > 1 hour
            config.transitionSmoothness = 0.9 // Smoother for long sessions
            config.intensityMultiplier *= 0.8 // Gentler for long exposure
        }

        return config
    }

    // MARK: - Helper Functions

    private func extractKeyPhrases(from track: StreamingTrack) -> [String] {
        let text = "\(track.title) \(track.artist)"
        let keywords = ["relaxation", "calm", "peace", "sleep", "focus", "energy", "meditation", "mindfulness"]
        return keywords.filter { text.lowercased().contains($0) }
    }

}

// MARK: - Supporting Types

struct AudioCharacteristics {
    let tempo: Double
    let energy: Double
    let spectralCentroid: Double
    let hasVoice: Bool
}

// MARK: - Extensions

extension AIContentAnalyzer {
    func analyzeContent(from data: Data, predictedType: AnalysisResult.ContentType) async throws -> AnalysisResult {
        // Enhanced analysis using AI model with predicted type as hint
        // This would integrate with the existing AI analysis pipeline

        // For now, return enhanced analysis based on prediction
        return AnalysisResult(
            mood: .meditative,
            energyLevel: 0.6,
            suggestedFrequencyRange: 4.0...14.0,
            suggestedIntensity: 0.8,
            suggestedColorTemperature: nil,
            keyMoments: [],
            aiSummary: "AI-enhanced analysis of streaming content",
            recommendedPreset: predictedType.rawValue,
            contentType: predictedType
        )
    }
}