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

nonisolated struct BulkTranscriptionAvailability: Equatable, Sendable {
    let cachedCount: Int
    let pendingCount: Int
    let totalCount: Int

    init(files: [LabeledFile], transcribedHashes: Set<String>) {
        let eligibleHashes = Set(files.map(\.audioSHA256).filter { !$0.isEmpty })
        totalCount = eligibleHashes.count
        cachedCount = eligibleHashes.intersection(transcribedHashes).count
        pendingCount = TranscriptInventory.pending(files, transcribed: transcribedHashes).count
    }

    var actionTitle: String {
        switch pendingCount {
        case 0: "All Transcribed"
        case 1: "Transcribe 1 Missing"
        default: "Transcribe \(pendingCount) Missing"
        }
    }

    var summary: String {
        "\(cachedCount) of \(totalCount) cached · \(pendingCount) missing"
    }
}

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
                    try TranscriptCacheStore.save(result, for: file, in: datasetDirectory)
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

}
