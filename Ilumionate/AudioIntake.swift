//
//  AudioIntake.swift
//  Ilumionate
//
//  Owns the complete path from an external audio source to a library-ready
//  AudioFile. Playback deliberately lives elsewhere.
//

import Foundation
import os

nonisolated struct RemoteAudioIntakeRequest: Sendable {
    let sourceURL: URL
    let suggestedFilename: String?
    let creator: String?
    let remoteSource: RemoteAudioSource?

    init(
        sourceURL: URL,
        suggestedFilename: String? = nil,
        creator: String? = nil,
        remoteSource: RemoteAudioSource? = nil
    ) {
        self.sourceURL = sourceURL
        self.suggestedFilename = suggestedFilename
        self.creator = creator
        self.remoteSource = remoteSource
    }
}

@MainActor
final class AudioIntake {

    static let shared = AudioIntake()

    private init() {}

    func importAudio(from url: URL) async -> AudioFile? {
        let trace = PerformanceTrace.begin("Local Audio Intake")
        defer { PerformanceTrace.end(trace) }

        do {
            return try await prepareAudio(
                from: url,
                targetFilename: url.lastPathComponent,
                transferMode: .copy,
                durationTimeout: .seconds(3),
                origin: .files,
                remoteSource: nil,
                creator: nil
            )
        } catch {
            Log.audio.info("❌ Failed to import audio: \(error)")
            UsageAnalytics.shared.errorOccurred(.audioFileImportFailed)
            return nil
        }
    }

    /// Downloads and validates remote bytes before admitting them to the library.
    func downloadAudio(from sourceURL: URL) async throws -> AudioFile? {
        try await downloadAudio(RemoteAudioIntakeRequest(sourceURL: sourceURL))
    }

    /// Downloads a publisher-backed track while preserving stable provenance
    /// for duplicate detection and future catalog reconciliation.
    func downloadAudio(_ request: RemoteAudioIntakeRequest) async throws -> AudioFile? {
        let intakeTrace = PerformanceTrace.begin("Remote Audio Intake")
        defer { PerformanceTrace.end(intakeTrace) }

        let sourceURL = request.sourceURL
        let downloadTrace = PerformanceTrace.begin("Audio Download")
        let download: (URL, URLResponse)
        do {
            download = try await URLSession.shared.download(from: sourceURL)
            PerformanceTrace.end(downloadTrace)
        } catch {
            PerformanceTrace.end(downloadTrace)
            throw error
        }
        let (temporaryURL, response) = download
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let validationTrace = PerformanceTrace.begin("Audio Download Validation")
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            PerformanceTrace.end(validationTrace)
            throw URLError(.badServerResponse)
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
        let leadingBytes: Data
        do {
            leadingBytes = try readLeadingBytes(from: temporaryURL)
        } catch {
            PerformanceTrace.end(validationTrace)
            throw error
        }

        if let rejection = AudioDownloadValidation.rejectionReason(
            contentType: contentType,
            data: leadingBytes
        ) {
            PerformanceTrace.end(validationTrace)
            // A user-supplied URL can contain sensitive path/query data. Keep
            // it out of logs; the rejection itself is sufficient to diagnose.
            Log.audio.info("❌ Rejected non-audio download: \(rejection)")
            UsageAnalytics.shared.errorOccurred(.audioURLServerRejected)
            throw rejection
        }
        PerformanceTrace.end(validationTrace)

        let targetFilename = downloadFilename(
            for: sourceURL,
            suggestedFilename: request.suggestedFilename,
            contentType: contentType,
            leadingBytes: leadingBytes
        )

        do {
            return try await prepareAudio(
                from: temporaryURL,
                targetFilename: targetFilename,
                transferMode: .move,
                durationTimeout: .seconds(5),
                origin: .url,
                remoteSource: request.remoteSource,
                creator: request.creator
            )
        } catch {
            Log.audio.info("❌ Failed to admit downloaded audio to the library: \(error)")
            throw error
        }
    }

    private func prepareAudio(
        from sourceURL: URL,
        targetFilename: String,
        transferMode: AudioFileTransferMode,
        durationTimeout: Duration,
        origin: IntakeOrigin,
        remoteSource: RemoteAudioSource?,
        creator: String?
    ) async throws -> AudioFile? {
        let trace = PerformanceTrace.begin("Audio Admission")
        defer { PerformanceTrace.end(trace) }

        let outcome = try await AudioImportWorker.prepareAudioFile(
            from: sourceURL,
            targetFilename: targetFilename,
            transferMode: transferMode,
            durationTimeout: durationTimeout,
            documentsURL: AppStoragePaths.managedAudio,
            existing: await AudioLibraryStore.duplicateIndex(),
            storageLocation: .managed,
            remoteSource: remoteSource,
            creator: creator
        )

        switch outcome {
        case .alreadyInLibrary(let existingID):
            Log.audio.info("↩️ Audio was already in the library: \(targetFilename, privacy: .public)")
            return await AudioLibraryStore.file(withID: existingID)

        case .imported(let audioFile):
            let analysisManager = AnalysisStateManager.shared
            await analysisManager.prepareCachedResults()
            let restored = analysisManager.restoringCachedData(in: audioFile)
            if restored.isAnalyzed {
                Log.audio.info("⚡ Restored cached analysis for: \(audioFile.filename)")
            }

            Log.audio.info(
                "✅ Admitted audio: \(audioFile.filename) (Duration: \(audioFile.duration)s)"
            )
            UsageAnalytics.shared.audioImported(source: origin.analyticsSource)
            return restored
        }
    }

    private func readLeadingBytes(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 64) ?? Data()
    }

    private func downloadFilename(
        for sourceURL: URL,
        suggestedFilename: String?,
        contentType: String?,
        leadingBytes: Data
    ) -> String {
        let originalName = sanitizedFilename(suggestedFilename)
            ?? sourceURL.lastPathComponent
        let originalExtension = URL(fileURLWithPath: originalName).pathExtension.lowercased()

        if !originalName.isEmpty,
           AudioDownloadValidation.audioExtensions.contains(originalExtension) {
            return originalName
        }

        let inferredExtension = contentType
            .flatMap(AudioDownloadValidation.audioExtension(forContentType:))
            ?? AudioDownloadValidation.inferredExtension(from: leadingBytes)
            ?? "mp3"
        let baseName = originalName.isEmpty
            ? "DownloadedAudio"
            : (originalName as NSString).deletingPathExtension
        return "\(baseName).\(inferredExtension)"
    }

    private func sanitizedFilename(_ filename: String?) -> String? {
        guard let filename else { return nil }
        let invalid = CharacterSet(charactersIn: "/\\:")
        let sanitized = filename
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }

    private enum IntakeOrigin {
        case files
        case url

        var analyticsSource: AudioSource {
            switch self {
            case .files: .files
            case .url: .url
            }
        }
    }
}
