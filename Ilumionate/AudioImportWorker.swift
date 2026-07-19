//
//  AudioImportWorker.swift
//  Ilumionate
//
//  Performs file-system and media inspection work outside the main actor so
//  importing large audio files never blocks interaction or rendering.
//

import AVFoundation
import Foundation
import os

nonisolated enum AudioFileTransferMode: Sendable {
    case copy
    case move
}

typealias AudioFileTransferOperation = @Sendable (
    _ sourceURL: URL,
    _ destinationURL: URL,
    _ mode: AudioFileTransferMode
) throws -> Void

nonisolated enum AudioImportWorker {
    @concurrent
    static func prepareAudioFile(
        from sourceURL: URL,
        targetFilename: String,
        transferMode: AudioFileTransferMode,
        durationTimeout: Duration,
        transferOperation: AudioFileTransferOperation? = nil
    ) async throws -> AudioFile {
        let destinationURL = uniqueDestinationURL(for: targetFilename)

        do {
            if let transferOperation {
                try transferOperation(sourceURL, destinationURL, transferMode)
            } else {
                switch transferMode {
                case .copy:
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                case .move:
                    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                }
            }
            Log.audio.info("📁 Audio stored at: \(destinationURL.path)")

            try Task.checkCancellation()
            let resources = try destinationURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(resources.fileSize ?? 0)

            async let duration = loadDuration(
                from: destinationURL,
                timeout: durationTimeout
            )
            async let metadata = AudioMetadataExtractor.metadata(from: destinationURL)
            async let fingerprint = fingerprint(for: destinationURL)

            return await AudioFile(
                filename: destinationURL.lastPathComponent,
                duration: duration,
                fileSize: fileSize,
                trackMetadata: metadata,
                contentFingerprint: fingerprint
            )
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    private static func uniqueDestinationURL(for filename: String) -> URL {
        let originalURL = URL.documentsDirectory.appending(path: filename)
        var candidate = originalURL
        var counter = 1

        while FileManager.default.fileExists(atPath: candidate.path) {
            let baseName = originalURL.deletingPathExtension().lastPathComponent
            let fileExtension = originalURL.pathExtension
            let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
            candidate = originalURL.deletingLastPathComponent()
                .appending(path: "\(baseName) (\(counter))\(suffix)")
            counter += 1
        }
        return candidate
    }

    private static func loadDuration(
        from url: URL,
        timeout: Duration
    ) async -> TimeInterval {
        await withTaskGroup(of: TimeInterval?.self) { group in
            group.addTask {
                do {
                    let duration = try await AVURLAsset(url: url).load(.duration)
                    let seconds = duration.seconds
                    return seconds.isFinite ? seconds : 0
                } catch {
                    Log.audio.info("Could not load audio duration: \(error.localizedDescription)")
                    return 0
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return 0
                } catch {
                    return nil
                }
            }

            let result = await group.next() ?? 0
            group.cancelAll()
            return result ?? 0
        }
    }

    @concurrent
    private static func fingerprint(for url: URL) async -> String? {
        AudioFingerprintService.computeFingerprint(for: url)
    }
}
