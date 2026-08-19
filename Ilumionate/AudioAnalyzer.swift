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
@preconcurrency import WhisperKit
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
    private var currentTranscriptionID: UUID?

    // MARK: - Initialization

    init() {
        // Keep the large WhisperKit model unloaded until transcription is
        // requested. `transcribe` and `prepareModel` both initialize it through
        // the actor-isolated manager before use.
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
        let trace = PerformanceTrace.begin("Transcription")
        defer { PerformanceTrace.end(trace) }

        return try await AudioTranscriptResolver().transcribe(
            filename: audioFile.filename,
            duration: audioFile.duration
        ) {
            try await self.transcribeWithWhisperKit(audioFile: audioFile)
        }
    }

    /// Uses WhisperKit only after the bundled transcript resolver has declined
    /// the file.
    private func transcribeWithWhisperKit(
        audioFile: AudioFile
    ) async throws -> AudioTranscriptionResult {
        // A cancelled task keeps running until it cooperates. Wait for the old
        // operation to finish before allowing a new one to reuse WhisperKit.
        if let previousTask = currentTask {
            previousTask.cancel()
            _ = try? await previousTask.value
        }

        isAnalyzing = true
        progress = 0.0
        statusMessage = "Preparing audio & ML models..."
        let transcriptionID = UUID()
        currentTranscriptionID = transcriptionID

        // Model initialization happens inside `whisperManager.transcribe`,
        // concurrently with MP3 pre-conversion, so neither serializes the other.

        // Create cancellable task
        let task = Task {
            try await whisperManager.transcribe(audioFile: audioFile) { @MainActor progressInfo in
                guard self.currentTranscriptionID == transcriptionID else { return }
                self.progress = progressInfo.progress
                self.statusMessage = progressInfo.message
            }
        }
        currentTask = task

        defer {
            if currentTranscriptionID == transcriptionID {
                currentTask = nil
                currentTranscriptionID = nil
                isAnalyzing = false
                progress = 0.0
                statusMessage = "Ready"
            }
        }
        return try await task.value
    }

    /// Cancel ongoing transcription with proper cleanup
    func cancelTranscription() async {
        let task = currentTask
        task?.cancel()
        await whisperManager.cancelTranscription()
        _ = try? await task?.value
        await whisperManager.releaseResources()

        currentTask = nil
        currentTranscriptionID = nil
        isAnalyzing = false
        progress = 0.0
        statusMessage = "Cancelled"
        Log.audio.info("🛑 Transcription cancelled")
    }

    /// Releases Core ML model resources after an analysis queue finishes.
    func releaseResources() async {
        let task = currentTask
        task?.cancel()
        _ = try? await task?.value
        currentTask = nil
        currentTranscriptionID = nil
        await whisperManager.releaseResources()
        statusMessage = "Model unloaded"
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
    private var currentTaskID: UUID?
    private var lifecycleGeneration = 0

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

        let trace = PerformanceTrace.begin("Whisper Model Bootstrap")
        defer { PerformanceTrace.end(trace) }

        if case .loading = modelState {
            try await waitForInitialization()
            if whisperKit != nil { return }
        }

        modelState = .loading
        let generation = lifecycleGeneration

        do {
            Log.audio.info("🔄 Initializing WhisperKit...")
            let loadedWhisperKit = try await bootstrapWhisperKit()
            guard generation == lifecycleGeneration else {
                await loadedWhisperKit.unloadModels()
                throw CancellationError()
            }
            whisperKit = loadedWhisperKit
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

    /// Removes the cached WhisperKit model files and re-downloads fresh copies.
    /// Called when initialization or transcription fails due to corrupt CoreML models.
    private func clearCacheAndReinitialize() async throws {
        Log.audio.info("🗑 Clearing WhisperKit model cache...")
        whisperKit = nil
        modelState = .loading
        let generation = lifecycleGeneration

        let fileManager = FileManager.default
        let cacheURL = WhisperModelBootstrap.sharedRepositoryURL()
        try? fileManager.removeItem(at: cacheURL)

        Log.audio.info("🔄 Retrying WhisperKit initialization after cache clear...")
        let loadedWhisperKit = try await bootstrapWhisperKit(forceDownload: true)
        guard generation == lifecycleGeneration else {
            await loadedWhisperKit.unloadModels()
            throw CancellationError()
        }
        whisperKit = loadedWhisperKit
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
        // MP3 files can fail inside WhisperKit's internal AVFoundation pipeline.
        // Pre-convert to M4A in a temp directory so WhisperKit always receives
        // a format it handles reliably. The conversion starts immediately so it
        // overlaps model loading instead of waiting behind it.
        let sourceURL = audioFile.url
        let conversionTask: Task<URL, Error>? = sourceURL.pathExtension.lowercased() == "mp3"
            ? Task(priority: .userInitiated) { try await Self.convertMP3ToM4A(sourceURL) }
            : nil

        // Ensure WhisperKit is initialized before proceeding
        do {
            try await initializeWithPriority()
        } catch {
            conversionTask?.cancel()
            throw error
        }
        guard let whisper = whisperKit else {
            conversionTask?.cancel()
            throw AnalyzerError.whisperKitNotInitialized
        }

        let transcribeURL: URL
        var tempURL: URL?
        if let conversionTask {
            let converted = try await conversionTask.value
            tempURL = converted
            transcribeURL = converted
        } else {
            transcribeURL = sourceURL
        }
        defer { if let url = tempURL { try? FileManager.default.removeItem(at: url) } }

        // Get audio duration for progress calculation
        let asset = AVURLAsset(url: audioFile.url)
        let duration = try await asset.load(.duration)
        let audioDuration = CMTimeGetSeconds(duration)

        await onProgress(ProgressInfo(progress: 0.1, message: "Starting transcription..."))

        // Create transcription task with optimizations
        let transcribePath = transcribeURL.path(percentEncoded: false)
        let taskID = UUID()
        let transcriptionTask = Task(priority: .userInitiated) {
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
        currentTaskID = taskID
        currentTask = transcriptionTask

        defer {
            if currentTaskID == taskID {
                currentTask = nil
                currentTaskID = nil
            }
        }
        let results: [TranscriptionResult]
        do {
            results = try await transcriptionTask.value
        } catch is CancellationError {
            throw CancellationError()
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
        let task = currentTask
        task?.cancel()
        _ = try? await task?.value
    }

    func releaseResources() async {
        lifecycleGeneration &+= 1
        let task = currentTask
        task?.cancel()
        _ = try? await task?.value
        currentTask = nil
        currentTaskID = nil
        if let whisperKit {
            await whisperKit.unloadModels()
        }
        whisperKit = nil
        modelState = .notLoaded
        Log.audio.info("🧹 WhisperKit models unloaded")
    }

    // MARK: - MP3 Pre-Conversion

    /// Exports an MP3 to a temporary M4A file so WhisperKit always receives a
    /// format that AVFoundation's internal pipeline handles without errors.
    /// Nonisolated so it can run concurrently with actor-isolated model loading.
    private nonisolated static func convertMP3ToM4A(_ sourceURL: URL) async throws -> URL {
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
