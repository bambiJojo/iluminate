//
//  AudioAnalyzer.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation
import AVFoundation
import Observation
import WhisperKit

// MARK: - Model State

enum ModelState {
    case notLoaded
    case loading
    case loaded
    case failed(Error)
}

// MARK: - Audio Analyzer

/// Handles audio transcription using WhisperKit
@Observable
@MainActor
class AudioAnalyzer {

    // MARK: - State

    var isAnalyzing = false
    var progress: Double = 0.0
    var statusMessage: String = ""

    // MARK: - Private State

    private var whisperKit: WhisperKit?
    private var modelState: ModelState = .notLoaded

    // MARK: - Initialization

    init() {
        // Initialize WhisperKit asynchronously
        Task {
            await initializeWhisperKit()
        }
    }

    // MARK: - WhisperKit Setup

    private func initializeWhisperKit() async {
        do {
            statusMessage = "Loading Whisper model..."
            print("🔄 Initializing WhisperKit...")

            // Initialize with tiny model for fast performance
            whisperKit = try await WhisperKit(model: "tiny")
            modelState = .loaded

            print("✅ WhisperKit initialized successfully")
            statusMessage = "Ready"
        } catch {
            print("❌ Failed to initialize WhisperKit: \(error)")
            statusMessage = "Failed to load model"
            modelState = .failed(error)
        }
    }

    // MARK: - Transcription

    /// Transcribe an audio file to text using WhisperKit
    func transcribe(audioFile: AudioFile) async throws -> AudioTranscriptionResult {
        // Wait for WhisperKit to initialize if it's still loading
        if whisperKit == nil {
            statusMessage = "Loading Whisper model..."
            print("⏳ Waiting for WhisperKit to initialize...")

            // Wait up to 60 seconds for initialization
            for _ in 0..<60 {
                if whisperKit != nil {
                    break
                }
                try await Task.sleep(for: .seconds(1))
            }
        }

        guard let whisper = whisperKit else {
            throw AnalyzerError.whisperKitNotInitialized
        }

        isAnalyzing = true
        progress = 0.0
        statusMessage = "Preparing audio..."

        defer {
            isAnalyzing = false
        }

        do {
            // Get audio info for logging
            let asset = AVURLAsset(url: audioFile.url)
            let duration = try await asset.load(.duration)
            let audioDuration = CMTimeGetSeconds(duration)
            let minutes = Int(audioDuration / 60)
            print("🎵 Audio duration: \(minutes) minutes (\(Int(audioDuration)) seconds)")

            statusMessage = "Transcribing with Whisper..."
            print("🎤 Starting WhisperKit transcription...")
            progress = 0.1

            // Transcribe using WhisperKit with progress callback
            // Use path(percentEncoded: false) to get the actual file path without URL encoding
            let results: [TranscriptionResult] = try await whisper.transcribe(
                audioPath: audioFile.url.path(percentEncoded: false),
                decodeOptions: DecodingOptions(verbose: true)
            ) { transcriptionProgress in
                Task { @MainActor in
                    // Calculate progress based on timing
                    let progressRatio = transcriptionProgress.timings.fullPipeline / audioDuration
                    self.progress = 0.1 + (min(progressRatio, 1.0) * 0.85)
                    self.statusMessage = "Transcribing... \(Int(self.progress * 100))%"
                }
                return nil // Continue transcription
            }

            // Process WhisperKit result
            guard let whisperResult = results.first else {
                throw AnalyzerError.noAudioData
            }

            let transcription = whisperResult.text

            // Convert WhisperKit segments to our format
            var segments: [AudioTranscriptionSegment] = []
            for segment in whisperResult.segments {
                let transcriptionSegment = AudioTranscriptionSegment(
                    text: segment.text,
                    timestamp: TimeInterval(segment.start),
                    duration: TimeInterval(segment.duration),
                    confidence: Double(segment.avgLogprob) // Use log probability as confidence
                )
                segments.append(transcriptionSegment)
            }

            progress = 1.0
            statusMessage = "Transcription complete"

            let transcriptionResult = AudioTranscriptionResult(
                fullText: transcription,
                segments: segments,
                duration: audioFile.duration,
                locale: Locale.current
            )

            print("✅ Transcription completed: \(transcription.prefix(100))...")
            print("📊 Segments: \(segments.count), Words: \(transcription.components(separatedBy: " ").count)")

            return transcriptionResult

        } catch {
            statusMessage = "Transcription failed"
            print("❌ Transcription error: \(error)")
            throw AnalyzerError.transcriptionFailed(error)
        }
    }

    /// Cancel ongoing transcription
    func cancelTranscription() {
        // WhisperKit handles cancellation automatically via Task cancellation
        isAnalyzing = false
        statusMessage = "Cancelled"
        print("🛑 Transcription cancelled")
    }
}

// MARK: - Audio Transcription Result

/// Result of audio transcription
struct AudioTranscriptionResult: Codable {
    let fullText: String
    let segments: [AudioTranscriptionSegment]
    let duration: TimeInterval
    let locale: String

    init(fullText: String, segments: [AudioTranscriptionSegment], duration: TimeInterval, locale: Locale) {
        self.fullText = fullText
        self.segments = segments
        self.duration = duration
        self.locale = locale.identifier
    }

    var wordCount: Int {
        fullText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    var averageConfidence: Double {
        guard !segments.isEmpty else { return 0 }
        return segments.map { $0.confidence }.reduce(0, +) / Double(segments.count)
    }
}

/// A segment of transcribed text with timing information
struct AudioTranscriptionSegment: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Double

    init(id: UUID = UUID(), text: String, timestamp: TimeInterval, duration: TimeInterval, confidence: Double) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.confidence = confidence
    }
}

// MARK: - Errors

enum AnalyzerError: LocalizedError {
    case whisperKitNotInitialized
    case transcriptionFailed(Error)
    case audioFileInvalid
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .whisperKitNotInitialized:
            return "WhisperKit is not initialized. Please wait for the model to load."
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .audioFileInvalid:
            return "The audio file is invalid or corrupted"
        case .noAudioData:
            return "No audio data found"
        }
    }
}
