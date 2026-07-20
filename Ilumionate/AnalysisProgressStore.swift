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
    /// A terminal retryable failure is kept on disk until the user explicitly
    /// asks to retry. Keeping it separate prevents BackgroundTasks from
    /// repeatedly launching work that already exhausted its automatic retry.
    var manualRecovery: AnalysisManualRecovery? = nil

    /// The most advanced stage that has been saved to disk.
    var resumeStage: AnalysisStage {
        if analysis != nil { return .generatingSession }
        if transcription != nil { return .analyzing }
        return .transcribing
    }

    /// The most useful partial result already saved for a future retry.
    var recoveryStage: AnalysisRecoveryStage {
        if analysis != nil { return .analysis }
        if transcription != nil { return .transcription }
        return .none
    }
}

nonisolated struct AnalysisManualRecovery: Codable, Sendable {
    let reason: AnalyticsAnalysisFailureReason
    let failedStage: AnalyticsAnalysisStage
    let failedAt: Date
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
        checkpoints.values.filter { $0.manualRecovery == nil }
    }

    func manualRecoveryCheckpoints() -> [AnalysisCheckpoint] {
        checkpoints.values
            .filter { $0.manualRecovery != nil }
            .sorted { $0.lastUpdated < $1.lastUpdated }
    }

    // MARK: Write

    /// Persist the queue entry before expensive work begins. This gives both a
    /// background launch and the next foreground launch something to resume if
    /// iOS suspends or terminates the process during transcription.
    func saveQueued(_ audioFile: AudioFile) {
        if var checkpoint = checkpoints[audioFile.id] {
            guard checkpoint.manualRecovery != nil else { return }
            checkpoint.manualRecovery = nil
            checkpoint.attemptCount = 0
            checkpoint.lastUpdated = Date()
            checkpoints[audioFile.id] = checkpoint
            persist()
            Log.analysis.info("🔁 Checkpoint: manual retry queued for \(audioFile.filename)")
            return
        }
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

    func markRequiresManualRetry(
        for audioFile: AudioFile,
        reason: AnalyticsAnalysisFailureReason,
        failedStage: AnalyticsAnalysisStage,
        failedAt: Date
    ) {
        var checkpoint = checkpoints[audioFile.id] ?? AnalysisCheckpoint(
            audioFile: audioFile,
            startedAt: failedAt,
            lastUpdated: failedAt,
            attemptCount: 2
        )
        checkpoint.manualRecovery = AnalysisManualRecovery(
            reason: reason,
            failedStage: failedStage,
            failedAt: failedAt
        )
        checkpoint.lastUpdated = failedAt
        checkpoints[audioFile.id] = checkpoint
        persist()
        Log.analysis.info("⏸️ Checkpoint: waiting for manual retry of \(audioFile.filename)")
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
