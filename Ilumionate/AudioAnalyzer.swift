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

/// Handles audio transcription using WhisperKit with modern Swift concurrency
@MainActor @Observable
class AudioAnalyzer: Sendable {

    // MARK: - Published State

    var isAnalyzing = false
    var progress: Double = 0.0
    var statusMessage: String = ""

    // MARK: - Actor-Isolated Components

    private let whisperManager = WhisperManager()
    private var currentTask: Task<AudioTranscriptionResult, Error>?

    // MARK: - Initialization

    init() {
        // Initialize WhisperKit asynchronously
        Task {
            await whisperManager.initialize()
            statusMessage = await whisperManager.getStatus()
        }
    }

    // MARK: - Transcription

    /// Transcribe an audio file using modern async/await patterns
    func transcribe(audioFile: AudioFile) async throws -> AudioTranscriptionResult {
        // Cancel any existing transcription
        currentTask?.cancel()

        isAnalyzing = true
        progress = 0.0
        statusMessage = "Loading ML Models (may download)..."

        // Ensure WhisperKit is initialized before proceeding
        await whisperManager.initialize()

        statusMessage = "Preparing audio..."

        // Create cancellable task
        currentTask = Task {
            defer {
                Task { @MainActor in
                    self.isAnalyzing = false
                    self.progress = 0.0
                    self.statusMessage = "Ready"
                }
            }

            return try await whisperManager.transcribe(audioFile: audioFile) { @MainActor progressInfo in
                self.progress = progressInfo.progress
                self.statusMessage = progressInfo.message
            }
        }

        return try await currentTask!.value
    }

    /// Cancel ongoing transcription with proper cleanup
    func cancelTranscription() async {
        currentTask?.cancel()
        await whisperManager.cancelTranscription()

        isAnalyzing = false
        progress = 0.0
        statusMessage = "Cancelled"
        print("🛑 Transcription cancelled")
    }
}

// MARK: - WhisperKit Manager Actor

/// Actor-isolated WhisperKit manager for thread-safe operations
actor WhisperManager {

    // MARK: - State

    private var whisperKit: WhisperKit?
    private var modelState: ModelState = .notLoaded
    private var currentTask: Task<[TranscriptionResult], Error>?

    // MARK: - Progress Info

    struct ProgressInfo: Sendable {
        let progress: Double
        let message: String
    }

    // MARK: - Initialization

    func initialize() async {
        guard whisperKit == nil else { return }

        do {
            print("🔄 Initializing WhisperKit...")
            do {
                // Initialize with tiny model for performance
                whisperKit = try await WhisperKit(model: "tiny")
            } catch {
                print("⚠️ WhisperKit initialization failed. Attempting to clear corrupted cache...")
                let fileManager = FileManager.default
                let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let cacheURL = documentsURL.appendingPathComponent("huggingface/models", isDirectory: true)
                try? fileManager.removeItem(at: cacheURL)
                
                print("🔄 Retrying WhisperKit initialization after cache clear...")
                whisperKit = try await WhisperKit(model: "tiny")
            }
            modelState = .loaded
            print("✅ WhisperKit initialized successfully")
        } catch {
            print("❌ Failed to initialize WhisperKit: \(error)")
            modelState = .failed(error)
        }
    }

    func getStatus() async -> String {
        switch modelState {
        case .notLoaded:
            return "Model not loaded"
        case .loading:
            return "Loading model..."
        case .loaded:
            return "Ready"
        case .failed(let error):
            return "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Transcription

    func transcribe(
        audioFile: AudioFile,
        onProgress: @Sendable @escaping (ProgressInfo) async -> Void
    ) async throws -> AudioTranscriptionResult {
        // Ensure WhisperKit is initialized before proceeding
        if whisperKit == nil {
            await initialize()
        }

        guard let whisper = whisperKit else {
            throw AnalyzerError.whisperKitNotInitialized
        }

        // Get audio duration for progress calculation
        let asset = AVURLAsset(url: audioFile.url)
        let duration = try await asset.load(.duration)
        let audioDuration = CMTimeGetSeconds(duration)

        await onProgress(ProgressInfo(progress: 0.1, message: "Starting transcription..."))

        // Create transcription task
        currentTask = Task {
            try await whisper.transcribe(
                audioPath: audioFile.url.path(percentEncoded: false),
                decodeOptions: DecodingOptions(verbose: true)
            ) { transcriptionProgress in
                Task {
                    // WhisperKit processes in ~30 second windows, roughly advancing 28s at a time.
                    let estimatedSecondsProcessed = Double(transcriptionProgress.windowId) * 28.0
                    let progressRatio = estimatedSecondsProcessed / audioDuration
                    let clampedRatio = min(max(progressRatio, 0.0), 1.0)
                    let overallProgress = 0.1 + (clampedRatio * 0.85)
                    await onProgress(ProgressInfo(
                        progress: overallProgress,
                        message: "Transcribing... \(Int(overallProgress * 100))%"
                    ))
                }
                return nil // Continue transcription
            }
        }

        let results = try await currentTask!.value
        currentTask = nil

        // Process results
        guard let whisperResult = results.first else {
            throw AnalyzerError.noAudioData
        }

        // Convert segments
        let segments = whisperResult.segments.map { segment in
            AudioTranscriptionSegment(
                text: segment.text,
                timestamp: TimeInterval(segment.start),
                duration: TimeInterval(segment.duration),
                confidence: Double(segment.avgLogprob)
            )
        }

        await onProgress(ProgressInfo(progress: 1.0, message: "Transcription complete"))

        let result = AudioTranscriptionResult(
            fullText: whisperResult.text,
            segments: segments,
            duration: audioFile.duration,
            locale: Locale.current
        )

        print("✅ Transcription completed: \(result.fullText.prefix(100))...")
        print("📊 Segments: \(segments.count), Words: \(result.wordCount)")

        return result
    }

    func cancelTranscription() async {
        currentTask?.cancel()
        currentTask = nil
    }
}

// MARK: - Audio Transcription Result

/// Result of audio transcription
struct AudioTranscriptionResult: Codable, Sendable {
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
struct AudioTranscriptionSegment: Codable, Identifiable, Sendable {
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
