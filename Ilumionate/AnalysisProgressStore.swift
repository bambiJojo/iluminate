//
//  AnalysisProgressStore.swift
//  Ilumionate
//
//  Persists mid-pipeline checkpoints so analysis can resume after the app
//  is closed.  One checkpoint is written per audio file; it is deleted when
//  the full pipeline completes successfully.
//
//  Checkpoint lifecycle:
//    1. File enters queue       → no checkpoint yet
//    2. Transcription done      → checkpoint saved with transcription
//    3. AI analysis done        → checkpoint saved with analysis
//    4. Session generated       → checkpoint deleted (pipeline finished)
//
//  On launch, AnalysisStateManager reads any surviving checkpoints and
//  re-queues their audio files.  The coordinator skips already-completed
//  stages by reusing the saved intermediate results.
//

import Foundation

// MARK: - Checkpoint Model

/// Intermediate pipeline state for a single audio file.
struct AnalysisCheckpoint: Codable, Sendable {
    let audioFile: AudioFile
    var transcription: AudioTranscriptionResult?
    var analysis: AnalysisResult?
    let startedAt: Date
    var lastUpdated: Date

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

    private static var storeURL: URL {
        URL.documentsDirectory.appending(path: "AnalysisProgress.json")
    }

    // MARK: Init

    init() {
        guard
            let data = try? Data(contentsOf: Self.storeURL),
            let decoded = try? JSONDecoder().decode([String: AnalysisCheckpoint].self, from: data)
        else { return }

        for (key, checkpoint) in decoded {
            guard let id = UUID(uuidString: key) else { continue }
            checkpoints[id] = checkpoint
        }

        if !checkpoints.isEmpty {
            print("📂 Loaded \(checkpoints.count) analysis checkpoint(s) to resume")
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
        print("💾 Checkpoint: saved transcription for \(audioFile.filename)")
    }

    func saveAnalysis(_ analysis: AnalysisResult, for audioFile: AudioFile) {
        guard var cp = checkpoints[audioFile.id] else { return }
        cp.analysis = analysis
        cp.lastUpdated = Date()
        checkpoints[audioFile.id] = cp
        persist()
        print("💾 Checkpoint: saved analysis for \(audioFile.filename)")
    }

    func clear(for audioFile: AudioFile) {
        guard checkpoints.removeValue(forKey: audioFile.id) != nil else { return }
        persist()
        print("🧹 Checkpoint: cleared for \(audioFile.filename)")
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
        try? data.write(to: Self.storeURL, options: .atomic)
    }
}
