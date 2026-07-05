//
//  AudioAnalyzer.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation
import os
import AVFoundation
import Observation
import WhisperKit
import Darwin

// MARK: - Model State

enum ModelState {
    case notLoaded
    case loading
    case loaded
    case failed(Error)
}

struct WhisperModelInstallation: Sendable, Equatable {
    let modelName: String
    let folderURL: URL
}

enum WhisperModelBootstrap {
    nonisolated static let modelRepositoryOwner = "argmaxinc"
    nonisolated static let modelRepositoryName = "whisperkit-coreml"
    nonisolated static let modelRepositoryID = "\(modelRepositoryOwner)/\(modelRepositoryName)"
    nonisolated static let preferredModelVariant = "base"

    nonisolated static func actualUserHomeDirectory() -> URL {
        guard let homeCString = getpwuid(getuid())?.pointee.pw_dir else {
            return URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
        }
        return URL(filePath: String(cString: homeCString), directoryHint: .isDirectory)
    }

    nonisolated static func sharedDownloadBaseURL(homeDirectory: URL? = nil) -> URL {
        // An explicit home directory always wins (deterministic for tests and for
        // callers that compute a shared location), regardless of platform.
        if let homeDirectory {
            return homeDirectory
                .appending(path: "Library", directoryHint: .isDirectory)
                .appending(path: "Application Support", directoryHint: .isDirectory)
                .appending(path: "Ilumionate", directoryHint: .isDirectory)
                .appending(path: "WhisperKit", directoryHint: .isDirectory)
        }

        #if os(macOS)
        let root = actualUserHomeDirectory()
        return root
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "Ilumionate", directoryHint: .isDirectory)
            .appending(path: "WhisperKit", directoryHint: .isDirectory)
        #else
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appending(path: "Ilumionate", directoryHint: .isDirectory)
            .appending(path: "WhisperKit", directoryHint: .isDirectory)
        #endif
    }

    nonisolated static func sharedRepositoryURL(downloadBase: URL = sharedDownloadBaseURL()) -> URL {
        downloadBase
            .appending(path: "models", directoryHint: .isDirectory)
            .appending(path: modelRepositoryOwner, directoryHint: .isDirectory)
            .appending(path: modelRepositoryName, directoryHint: .isDirectory)
    }

    nonisolated static func installedModels(
        in repositoryURL: URL = sharedRepositoryURL(),
        fileManager: FileManager = .default
    ) -> [WhisperModelInstallation] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: repositoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url in
            guard let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDirectory == true else {
                return nil
            }
            return WhisperModelInstallation(modelName: url.lastPathComponent, folderURL: url)
        }
        .sorted { $0.modelName < $1.modelName }
    }

    nonisolated static func preferredInstallation(
        preferredVariant: String = preferredModelVariant,
        repositoryURL: URL = sharedRepositoryURL(),
        fileManager: FileManager = .default
    ) -> WhisperModelInstallation? {
        let installations = installedModels(in: repositoryURL, fileManager: fileManager)
        guard !installations.isEmpty else { return nil }

        let exactNames = [
            "openai_whisper-\(preferredVariant)",
            preferredVariant
        ]

        if let exactMatch = installations.first(where: { exactNames.contains($0.modelName) }) {
            return exactMatch
        }

        if let partialMatch = installations.first(where: {
            $0.modelName.localizedCaseInsensitiveContains("openai_whisper-\(preferredVariant)")
        }) {
            return partialMatch
        }

        return installations.first
    }

    nonisolated static func isConnectivityFailure(_ description: String) -> Bool {
        let normalized = description.lowercased()
        return normalized.contains("hostname could not be found")
            || normalized.contains("offline")
            || normalized.contains("internet connection")
            || normalized.contains("network connection was lost")
            || normalized.contains("could not connect to the server")
            || normalized.contains("not connected to internet")
    }

    nonisolated static func actionableFailureMessage(
        underlyingError: Error,
        priorLocalModelError: Error? = nil,
        preferredVariant: String = preferredModelVariant,
        repositoryURL: URL = sharedRepositoryURL()
    ) -> String {
        let detail = underlyingError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let localMessage = "No local WhisperKit model is installed at \(repositoryURL.path)."
        let priorFailureMessage: String
        if let priorLocalModelError {
            priorFailureMessage = """
            A cached local WhisperKit model was found but failed to load, so the app cleared the cache and tried to download a fresh copy.
            Cached model error: \(priorLocalModelError.localizedDescription)
            """
        } else {
            priorFailureMessage = ""
        }

        if isConnectivityFailure(detail) {
            return """
            \(localMessage)
            \(priorFailureMessage)
            Automatic download of the \"\(preferredVariant)\" model from \(modelRepositoryID) failed because the app could not reach Hugging Face.
            Connect to the internet once and retry, or place a compatible WhisperKit model in that shared cache directory.
            Underlying error: \(detail)
            """
        }

        return """
        \(localMessage)
        \(priorFailureMessage)
        Automatic download of the \"\(preferredVariant)\" model from \(modelRepositoryID) failed.
        Underlying error: \(detail)
        """
    }
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

    /// Preloads the WhisperKit model so callers can fail fast with a real
    /// initialization error before beginning a long workflow.
    func prepareModel() async throws {
        statusMessage = "Loading ML Models (may download)..."
        try await whisperManager.ensureReady()
        statusMessage = await whisperManager.getStatus()
    }

    /// Transcribe an audio file using modern async/await patterns
    func transcribe(audioFile: AudioFile) async throws -> AudioTranscriptionResult {
        // Cancel any existing transcription
        currentTask?.cancel()

        isAnalyzing = true
        progress = 0.0
        statusMessage = "Loading ML Models (may download)..."

        // Initialize WhisperKit with priority for better UX
        try await whisperManager.initializeWithPriority()

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
        Log.audio.info("🛑 Transcription cancelled")
    }

    nonisolated static func whisperModelRepositoryURL() -> URL {
        WhisperModelBootstrap.sharedRepositoryURL()
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
        do {
            try await ensureReady()
        } catch {
            Log.audio.info("❌ Failed to initialize WhisperKit: \(error)")
        }
    }

    func initializeWithPriority() async throws {
        try await Task(priority: .userInitiated) {
            try await ensureReady()
        }.value
    }

    func ensureReady() async throws {
        if whisperKit != nil { return }

        if case .loading = modelState {
            try await waitForInitialization()
            if whisperKit != nil { return }
        }

        modelState = .loading

        do {
            Log.audio.info("🔄 Initializing WhisperKit...")
            try await initializeWhisperKit()
            modelState = .loaded
            Log.audio.info("✅ WhisperKit initialized successfully")
        } catch let analyzerError as AnalyzerError {
            Log.audio.info("❌ Failed to initialize WhisperKit: \(analyzerError)")
            modelState = .failed(analyzerError)
            throw analyzerError
        } catch {
            Log.audio.info("❌ Failed to initialize WhisperKit: \(error)")
            modelState = .failed(error)
            throw AnalyzerError.whisperKitInitializationFailed(error.localizedDescription)
        }
    }

    private func waitForInitialization() async throws {
        while case .loading = modelState {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func initializeWhisperKit() async throws {
        whisperKit = try await bootstrapWhisperKit()
    }

    /// Removes the cached WhisperKit model files and re-downloads fresh copies.
    /// Called when initialization or transcription fails due to corrupt CoreML models.
    private func clearCacheAndReinitialize() async throws {
        Log.audio.info("🗑 Clearing WhisperKit model cache...")
        whisperKit = nil
        modelState = .loading

        let fileManager = FileManager.default
        let cacheURL = WhisperModelBootstrap.sharedRepositoryURL()
        try? fileManager.removeItem(at: cacheURL)

        Log.audio.info("🔄 Retrying WhisperKit initialization after cache clear...")
        whisperKit = try await bootstrapWhisperKit(forceDownload: true)
        modelState = .loaded
        Log.audio.info("✅ WhisperKit re-initialized successfully after cache clear")
    }

    private func bootstrapWhisperKit(forceDownload: Bool = false) async throws -> WhisperKit {
        let fileManager = FileManager.default
        let downloadBase = WhisperModelBootstrap.sharedDownloadBaseURL()
        let repositoryURL = WhisperModelBootstrap.sharedRepositoryURL(downloadBase: downloadBase)

        try fileManager.createDirectory(at: downloadBase, withIntermediateDirectories: true, attributes: nil)

        if !forceDownload,
           let installed = WhisperModelBootstrap.preferredInstallation(
               preferredVariant: WhisperModelBootstrap.preferredModelVariant,
               repositoryURL: repositoryURL,
               fileManager: fileManager
           ) {
            do {
                let whisper = try await makeWhisperKit(downloadBase: downloadBase)
                whisper.modelFolder = installed.folderURL
                try await whisper.loadModels()
                return whisper
            } catch {
                Log.audio.info("⚠️ Cached WhisperKit model failed to load. Clearing cache and retrying download: \(error)")
                try? fileManager.removeItem(at: repositoryURL)
                return try await downloadAndLoadWhisperKit(
                    downloadBase: downloadBase,
                    repositoryURL: repositoryURL,
                    priorLocalModelError: error
                )
            }
        }

        return try await downloadAndLoadWhisperKit(
            downloadBase: downloadBase,
            repositoryURL: repositoryURL
        )
    }

    private func makeWhisperKit(downloadBase: URL) async throws -> WhisperKit {
        let whisper = try await WhisperKit(WhisperKitConfig(
            model: WhisperModelBootstrap.preferredModelVariant,
            downloadBase: downloadBase,
            modelRepo: WhisperModelBootstrap.modelRepositoryID,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: false,
            download: false
        ))
        return whisper
    }

    private func downloadAndLoadWhisperKit(
        downloadBase: URL,
        repositoryURL: URL,
        priorLocalModelError: Error? = nil
    ) async throws -> WhisperKit {
        do {
            let whisper = try await makeWhisperKit(downloadBase: downloadBase)
            let downloadedFolder = try await WhisperKit.download(
                variant: WhisperModelBootstrap.preferredModelVariant,
                downloadBase: downloadBase,
                from: WhisperModelBootstrap.modelRepositoryID
            )
            whisper.modelFolder = downloadedFolder
            try await whisper.loadModels()
            return whisper
        } catch {
            throw AnalyzerError.whisperKitInitializationFailed(
                WhisperModelBootstrap.actionableFailureMessage(
                    underlyingError: error,
                    priorLocalModelError: priorLocalModelError,
                    preferredVariant: WhisperModelBootstrap.preferredModelVariant,
                    repositoryURL: repositoryURL
                )
            )
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
        try await ensureReady()
        guard let whisper = whisperKit else { throw AnalyzerError.whisperKitNotInitialized }

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
        let transcribePath = transcribeURL.path(percentEncoded: false)
        currentTask = Task(priority: .userInitiated) {
            let decodeOptions = DecodingOptions(
                verbose: false,  // Reduce overhead
                language: nil,   // nil = auto-detect; WhisperKit identifies the spoken language
                temperature: 0.0 // Deterministic output
            )

            return try await whisper.transcribe(
                audioPath: transcribePath,
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

        let task = currentTask!
        let results: [TranscriptionResult]
        do {
            results = try await task.value
        } catch {
            // If transcription fails with a CoreML/MIL parsing error, the cached
            // model is likely corrupted. Clear cache and retry once.
            let errorString = String(describing: error)
            if errorString.localizedStandardContains("MIL") ||
               errorString.localizedStandardContains("mlmodelc") ||
               errorString.localizedStandardContains("parsing") {
                Log.audio.info("⚠️ CoreML model corruption detected during transcription. Recovering...")
                await onProgress(ProgressInfo(progress: 0.05, message: "Repairing ML model..."))
                try await clearCacheAndReinitialize()

                guard let freshWhisper = whisperKit else {
                    throw AnalyzerError.whisperKitNotInitialized
                }

                let retryResults = try await freshWhisper.transcribe(
                    audioPath: transcribePath,
                    decodeOptions: DecodingOptions(verbose: false, language: nil, temperature: 0.0)
                )
                results = retryResults
            } else {
                throw error
            }
        }
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
        let detectedLanguage = whisperResult.language.isEmpty
            ? (Locale.current.language.languageCode?.identifier ?? "en")
            : whisperResult.language

        let result = AudioTranscriptionResult(
            fullText: whisperResult.text,
            segments: segments,
            duration: audioFile.duration,
            detectedLanguage: detectedLanguage
        )

        Log.audio.info("✅ Transcription completed: \(result.fullText.prefix(100))...")
        Log.audio.info("📊 Segments: \(segments.count), Words: \(result.wordCount)")

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
        self.fullText = Self.sanitizedTranscriptText(fullText)
        self.segments = segments.compactMap { segment in
            let sanitizedText = Self.sanitizedTranscriptText(segment.text)
            guard !sanitizedText.isEmpty else { return nil }
            return AudioTranscriptionSegment(
                id: segment.id,
                text: sanitizedText,
                timestamp: segment.timestamp,
                duration: segment.duration,
                confidence: segment.confidence
            )
        }
        self.duration = duration
        self.locale = detectedLanguage
    }

    nonisolated var wordCount: Int {
        fullText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    nonisolated static func sanitizedTranscriptText(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"<\|[^>]*\|>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[\u{00A0}\s]+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    case whisperKitInitializationFailed(String)
    case transcriptionFailed(Error)
    case audioFileInvalid
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .whisperKitNotInitialized:
            return "WhisperKit is not initialized. Please wait for the model to load."
        case .whisperKitInitializationFailed(let reason):
            return "WhisperKit failed to initialize: \(reason)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .audioFileInvalid:
            return "The audio file is invalid or corrupted"
        case .noAudioData:
            return "No audio data found"
        }
    }
}
