//
//  BulkTranscriptionController.swift
//  LumeLabel
//
//  Works through every corpus file that has no transcript yet, so the app can be
//  left running rather than each file being transcribed by hand.
//
//  Sequential on purpose. WhisperKit loads a model per analyser and transcription
//  is the slowest thing this app does; running several at once competes for the
//  same hardware and makes the whole job slower, not faster.
//
//  What to do is decided by `TranscriptInventory`, which is tested. This drives
//  it and reports progress.
//

import Foundation
import Observation

@MainActor
@Observable
final class BulkTranscriptionController {

    private(set) var isRunning = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var currentFilename: String?
    private(set) var statusMessage: String?

    /// Kept per file rather than as a count: after an unattended run the useful
    /// question is which files still have no transcript and why.
    private(set) var failures: [(filename: String, reason: String)] = []

    private var task: Task<Void, Never>?

    var progress: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    func start(corpus: TrainingCorpusManager) {
        guard isRunning == false else { return }

        let datasetDirectory = corpus.analyzerDatasetDirectory
        let transcribed = TranscriptInventory.availableHashes(in: datasetDirectory)
        let pending = TranscriptInventory.pending(corpus.labeledFiles, transcribed: transcribed)

        guard pending.isEmpty == false else {
            statusMessage = "Every file already has a transcript."
            return
        }

        isRunning = true
        completed = 0
        total = pending.count
        failures = []
        statusMessage = "Transcribing \(pending.count) file(s)…"

        task = Task { [weak self] in
            // One analyser for the whole run: re-creating it per file would
            // reload the model every time.
            let analyzer = AudioAnalyzer()

            for file in pending {
                if Task.isCancelled { break }
                self?.currentFilename = file.audioFilename

                do {
                    let audioURL = corpus.audioURL(for: file)
                    let values = try? audioURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                    let audioFile = AudioFile(
                        id: file.id,
                        filename: audioURL.standardizedFileURL.path(),
                        duration: file.audioDuration,
                        fileSize: Int64(values?.fileSize ?? 0),
                        createdDate: values?.creationDate ?? file.labeledAt
                    )
                    let result = try await analyzer.transcribe(audioFile: audioFile)
                    try Self.persist(result, for: file, in: datasetDirectory)
                } catch is CancellationError {
                    break
                } catch {
                    // One unreadable file must not end the run — the whole point
                    // is that it can be left alone.
                    self?.failures.append((file.audioFilename, error.localizedDescription))
                }

                self?.completed += 1
            }

            self?.finish()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        finish(cancelled: true)
    }

    private func finish(cancelled: Bool = false) {
        isRunning = false
        currentFilename = nil
        task = nil

        if cancelled {
            statusMessage = "Stopped after \(completed) of \(total)."
        } else if failures.isEmpty {
            statusMessage = "Transcribed \(completed) file(s)."
        } else {
            statusMessage = "Transcribed \(completed - failures.count) of \(total); \(failures.count) failed."
        }
    }

    /// Written in the same shape the per-file path uses, so a bulk run and a
    /// hand-made transcript are indistinguishable to everything downstream.
    private nonisolated static func persist(
        _ result: AudioTranscriptionResult,
        for file: LabeledFile,
        in datasetDirectory: URL
    ) throws {
        let destination = TranscriptInventory.cacheURL(forHash: file.audioSHA256, in: datasetDirectory)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(
            BulkCachedTranscription(
                schemaVersion: 1,
                cachedAt: Date(),
                exampleID: file.id,
                audioSHA256: file.audioSHA256,
                transcription: result
            )
        ).write(to: destination, options: .atomic)
    }
}

private struct BulkCachedTranscription: Codable {
    let schemaVersion: Int
    let cachedAt: Date
    let exampleID: UUID
    let audioSHA256: String
    let transcription: AudioTranscriptionResult
}
