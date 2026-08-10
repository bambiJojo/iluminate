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

/// What an import resolved to.
nonisolated enum AudioImportOutcome: Sendable, Equatable {
    case imported(AudioFile)
    case alreadyInLibrary(existing: AudioFile.ID)
}

nonisolated enum AudioImportWorker {
    @concurrent
    static func prepareAudioFile(
        from sourceURL: URL,
        targetFilename: String,
        transferMode: AudioFileTransferMode,
        durationTimeout: Duration,
        documentsURL: URL = .documentsDirectory,
        existing: DuplicateAudioIndex = DuplicateAudioIndex([]),
        transferOperation: AudioFileTransferOperation? = nil
    ) async throws -> AudioImportOutcome {
        // Hashed at the source, before anything is written. Copying first and
        // checking after is how `Track (1).mp3` used to come into existence.
        let sourceFingerprint = AudioFingerprintService.computeFingerprint(for: sourceURL)
        let sourceSize = Int64(
            (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        )
        let verdict = existing.verdict(
            for: DuplicateAudioCandidate(
                contentFingerprint: sourceFingerprint,
                fileSize: sourceSize,
                duration: 0,
                title: targetFilename
            )
        )
        if case .identical(let existingID) = verdict {
            Log.audio.info("↩️ Already in the library, not copied: \(targetFilename, privacy: .public)")
            return .alreadyInLibrary(existing: existingID)
        }

        let destinationURL = uniqueDestinationURL(for: targetFilename, in: documentsURL)

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

            return await .imported(
                AudioFile(
                    filename: destinationURL.lastPathComponent,
                    duration: duration,
                    fileSize: fileSize,
                    trackMetadata: metadata,
                    contentFingerprint: sourceFingerprint
                        ?? AudioFingerprintService.computeFingerprint(for: destinationURL)
                )
            )
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    /// Still needed: a genuinely different recording can share a filename with
    /// one already stored. What changed is that a *duplicate* no longer reaches
    /// this function — it is resolved before anything is written.
    private static func uniqueDestinationURL(for filename: String, in documentsURL: URL) -> URL {
        let originalURL = documentsURL.appending(path: filename)
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
}
