//
//  AnalysisProgressStore.swift
//  Ilumionate
//
//  Persists mid-pipeline checkpoints so analysis can resume after the app
//  is closed.  One checkpoint is written per audio file; it is deleted when
//  the full pipeline completes successfully.
//
//  Checkpoint lifecycle:
//    1. File enters queue       → queued checkpoint saved
//    2. Transcription done      → checkpoint saved with transcription
//    3. AI analysis done        → checkpoint saved with analysis
//    4. Session generated       → checkpoint deleted (pipeline finished)
//
//  On launch, AnalysisStateManager reads any surviving checkpoints and
//  re-queues their audio files.  The coordinator skips already-completed
//  stages by reusing the saved intermediate results.
//

import Foundation
import os

// MARK: - Checkpoint Model

/// Intermediate pipeline state for a single audio file.
nonisolated struct AnalysisCheckpoint: Codable, Sendable {
    let audioFile: AudioFile
    var transcription: AudioTranscriptionResult?
    var analysis: AnalysisResult?
    let startedAt: Date
    var lastUpdated: Date
    /// Optional for backwards-compatible decoding of checkpoints written by
    /// versions that did not track attempts.
    var attemptCount: Int? = nil

    /// The most advanced stage that has been saved to disk.
    var resumeStage: AnalysisStage {
        if analysis != nil { return .generatingSession }
        if transcription != nil { return .analyzing }
        return .transcribing
    }
}

// MARK: - Store

/// Actor-isolated store for analysis checkpoints.
actor AnalysisProgressStore {

    static let shared = AnalysisProgressStore()

    private var checkpoints: [UUID: AnalysisCheckpoint] = [:]
    private let storeURL: URL

    private static var defaultStoreURL: URL {
        URL.documentsDirectory.appending(path: "AnalysisProgress.json")
    }

    // MARK: Init

    init(storeURL: URL = AnalysisProgressStore.defaultStoreURL) {
        self.storeURL = storeURL
        guard
            let data = try? Data(contentsOf: storeURL),
            let decoded = try? JSONDecoder().decode([String: AnalysisCheckpoint].self, from: data)
        else { return }

        for (key, checkpoint) in decoded {
            guard let id = UUID(uuidString: key) else { continue }
            checkpoints[id] = checkpoint
        }

        let checkpointCount = checkpoints.count
        if checkpointCount > 0 {
            Log.analysis.info("📂 Loaded \(checkpointCount) analysis checkpoint(s) to resume")
        }
    }

    // MARK: Read

    func checkpoint(for audioFile: AudioFile) -> AnalysisCheckpoint? {
        checkpoints[audioFile.id]
    }

    func allPending() -> [AnalysisCheckpoint] {
        Array(checkpoints.values)
    }

    // MARK: Write

    /// Persist the queue entry before expensive work begins. This gives both a
    /// background launch and the next foreground launch something to resume if
    /// iOS suspends or terminates the process during transcription.
    func saveQueued(_ audioFile: AudioFile) {
        guard checkpoints[audioFile.id] == nil else { return }
        checkpoints[audioFile.id] = AnalysisCheckpoint(
            audioFile: audioFile,
            transcription: nil,
            analysis: nil,
            startedAt: Date(),
            lastUpdated: Date(),
            attemptCount: 0
        )
        persist()
        Log.analysis.info("💾 Checkpoint: queued \(audioFile.filename)")
    }

    /// Records a pipeline start and returns its one-based attempt number.
    /// Persisting this before work begins keeps first-vs-resumed telemetry
    /// accurate even when iOS terminates the process mid-analysis.
    func beginAttempt(for audioFile: AudioFile) -> Int {
        var cp = checkpoints[audioFile.id] ?? AnalysisCheckpoint(
            audioFile: audioFile,
            startedAt: Date(),
            lastUpdated: Date(),
            attemptCount: 0
        )
        let attempt = (cp.attemptCount ?? 1) + 1
        cp.attemptCount = attempt
        cp.lastUpdated = Date()
        checkpoints[audioFile.id] = cp
        persist()
        return attempt
    }

    func saveTranscription(_ transcription: AudioTranscriptionResult, for audioFile: AudioFile) {
        var cp = checkpoints[audioFile.id] ?? AnalysisCheckpoint(
            audioFile: audioFile,
            startedAt: Date(),
            lastUpdated: Date()
        )
        cp.transcription = transcription
        cp.lastUpdated = Date()
        checkpoints[audioFile.id] = cp
        persist()
        Log.analysis.info("💾 Checkpoint: saved transcription for \(audioFile.filename)")
    }

    func saveAnalysis(_ analysis: AnalysisResult, for audioFile: AudioFile) {
        guard var cp = checkpoints[audioFile.id] else { return }
        cp.analysis = analysis
        cp.lastUpdated = Date()
        checkpoints[audioFile.id] = cp
        persist()
        Log.analysis.info("💾 Checkpoint: saved analysis for \(audioFile.filename)")
    }

    func clear(for audioFile: AudioFile) {
        guard checkpoints.removeValue(forKey: audioFile.id) != nil else { return }
        persist()
        Log.analysis.info("🧹 Checkpoint: cleared for \(audioFile.filename)")
    }

    func clearAll() {
        checkpoints.removeAll()
        persist()
    }

    // MARK: Private

    private func persist() {
        let stringKeyed = Dictionary(
            uniqueKeysWithValues: checkpoints.map { ($0.key.uuidString, $0.value) }
        )
        guard let data = try? JSONEncoder().encode(stringKeyed) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
