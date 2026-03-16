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

        // Initialize WhisperKit with priority for better UX
        await whisperManager.initializeWithPriority()

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
        modelState = .loading

        do {
            print("🔄 Initializing WhisperKit...")
            try await initializeWhisperKit()
            modelState = .loaded
            print("✅ WhisperKit initialized successfully")
        } catch {
            print("❌ Failed to initialize WhisperKit: \(error)")
            modelState = .failed(error)
        }
    }

    func initializeWithPriority() async {
        guard whisperKit == nil else { return }

        await Task(priority: .userInitiated) {
            await initialize()
        }.value
    }

    private func initializeWhisperKit() async throws {
        do {
            // Use base model for significantly better word-error-rate vs tiny
            whisperKit = try await WhisperKit(model: "base")
        } catch {
            print("⚠️ WhisperKit initialization failed. Attempting to clear corrupted cache...")

            // Clear potentially corrupted cache
            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let cacheURL = documentsURL.appendingPathComponent("huggingface/models", isDirectory: true)
            try? fileManager.removeItem(at: cacheURL)

            print("🔄 Retrying WhisperKit initialization after cache clear...")
            whisperKit = try await WhisperKit(model: "base")
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

        // MP3 files can fail inside WhisperKit's internal AVFoundation pipeline.
        // Pre-convert to M4A in a temp directory so WhisperKit always receives
        // a format it handles reliably.
        let transcribeURL: URL
        var tempURL: URL?
        if audioFile.url.pathExtension.lowercased() == "mp3" {
            let converted = try await convertMP3ToM4A(audioFile.url)
            tempURL = converted
            transcribeURL = converted
        } else {
            transcribeURL = audioFile.url
        }
        defer { if let url = tempURL { try? FileManager.default.removeItem(at: url) } }

        // Get audio duration for progress calculation
        let asset = AVURLAsset(url: audioFile.url)
        let duration = try await asset.load(.duration)
        let audioDuration = CMTimeGetSeconds(duration)

        await onProgress(ProgressInfo(progress: 0.1, message: "Starting transcription..."))

        // Create transcription task with optimizations
        currentTask = Task(priority: .userInitiated) {
            let decodeOptions = DecodingOptions(
                verbose: false,  // Reduce overhead
                language: nil,   // nil = auto-detect; WhisperKit identifies the spoken language
                temperature: 0.0 // Deterministic output
            )

            return try await whisper.transcribe(
                audioPath: transcribeURL.path(percentEncoded: false),
                decodeOptions: decodeOptions
            ) { transcriptionProgress in
                Task {
                    // Optimized progress calculation
                    let estimatedSecondsProcessed = Double(transcriptionProgress.windowId) * 28.0
                    let progressRatio = min(estimatedSecondsProcessed / audioDuration, 1.0)
                    let overallProgress = 0.1 + (progressRatio * 0.85)

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

        // WhisperKit sets `language` to the ISO 639-1 code it detected (e.g. "en", "fr").
        // Fall back to the device locale language code when auto-detection is inconclusive.
        let detectedLanguage = whisperResult.language
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"

        let result = AudioTranscriptionResult(
            fullText: whisperResult.text,
            segments: segments,
            duration: audioFile.duration,
            detectedLanguage: detectedLanguage
        )

        print("✅ Transcription completed: \(result.fullText.prefix(100))...")
        print("📊 Segments: \(segments.count), Words: \(result.wordCount)")

        return result
    }

    func cancelTranscription() async {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - MP3 Pre-Conversion

    /// Exports an MP3 to a temporary M4A file so WhisperKit always receives a
    /// format that AVFoundation's internal pipeline handles without errors.
    private func convertMP3ToM4A(_ sourceURL: URL) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString + ".m4a")

        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AnalyzerError.audioFileInvalid
        }

        try await session.export(to: tempURL, as: .m4a)
        return tempURL
    }
}

// MARK: - Audio Transcription Result

/// Result of audio transcription
struct AudioTranscriptionResult: Codable, Sendable {
    let fullText: String
    let segments: [AudioTranscriptionSegment]
    let duration: TimeInterval
    let locale: String

    /// - Parameter detectedLanguage: ISO 639-1 language code returned by WhisperKit (e.g. "en", "fr").
    nonisolated init(fullText: String, segments: [AudioTranscriptionSegment], duration: TimeInterval, detectedLanguage: String) {
        self.fullText = fullText
        self.segments = segments
        self.duration = duration
        self.locale = detectedLanguage
    }

    nonisolated var wordCount: Int {
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

    nonisolated init(id: UUID = UUID(), text: String, timestamp: TimeInterval, duration: TimeInterval, confidence: Double) {
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
