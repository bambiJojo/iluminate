//
//  AnalysisTaskInputAssembler.swift
//  Ilumionate
//
//  Every disk and store read for the task projection happens here. The
//  projection itself is pure and receives already-built maps.
//
//  GeneratedSessionStore cannot enumerate — each accessor takes an AudioFile —
//  so ready sessions are discovered by walking the library inventory.
//

import Foundation

nonisolated enum AnalysisTaskInputAssembler {

    // MARK: Pure helpers

    /// Queue uniqueness is enforced here so the projection never has to guess.
    static func deduplicate(queue: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return queue.filter { seen.insert($0).inserted }
    }

    static func failureSnapshot(from checkpoint: AnalysisCheckpoint) -> AnalysisFailureSnapshot? {
        guard let recovery = checkpoint.manualRecovery else { return nil }
        return AnalysisFailureSnapshot(
            reason: recovery.reason,
            failedStage: recovery.failedStage,
            failedAt: recovery.failedAt,
            recoveryStage: checkpoint.recoveryStage,
            // A durable recovery exists precisely because automatic retry was
            // exhausted, so it is always `.manual`.
            retryState: .manual,
            dismissedAt: recovery.dismissedAt
        )
    }

    static func checkpointSnapshot(from checkpoint: AnalysisCheckpoint) -> AnalysisCheckpointSnapshot {
        AnalysisCheckpointSnapshot(
            recoveryStage: checkpoint.recoveryStage,
            startedAt: checkpoint.startedAt,
            lastUpdated: checkpoint.lastUpdated
        )
    }

    static func failureSnapshot(from failure: FailedAnalysis) -> AnalysisFailureSnapshot {
        AnalysisFailureSnapshot(
            reason: failure.reason,
            failedStage: failure.failedStage,
            failedAt: failure.failedAt,
            recoveryStage: failure.recoveryStage,
            retryState: failure.retryState,
            // The runtime list has no dismissal concept; only the durable
            // record carries it, and the merge prefers that on equal failedAt.
            dismissedAt: nil
        )
    }

    // MARK: Disk-backed

    /// Ready sessions generated from the listener's own audio.
    ///
    /// Disk only, and deliberately `nonisolated` so it runs off the main actor.
    /// `GeneratedSessionStore.load(for:)` cannot be used here: it is
    /// `@MainActor` because it also consults a mutable gold-match cache, and
    /// putting a JSON decode per library file on the main actor is what the
    /// refresh design exists to avoid. Bundled gold sessions are folded in by
    /// the caller, which already has main-actor context — see
    /// `AnalysisCenterModel.live`.
    ///
    /// A session that is missing or fails to decode is omitted, so a task never
    /// advertises something unplayable. `readyAt` is the session file's
    /// modification date, which survives relaunch and needs no new persistence
    /// format.
    static func generatedReadySnapshots(
        for files: [AudioFile],
        store: GeneratedSessionStore
    ) -> [UUID: AnalysisReadySnapshot] {
        var result: [UUID: AnalysisReadySnapshot] = [:]
        for file in files {
            let url = store.sessionURL(forAudioFileID: file.id)
            guard let data = try? Data(contentsOf: url),
                  let session = try? JSONDecoder().decode(LightSession.self, from: data) else {
                continue
            }
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path()))?[.modificationDate] as? Date
            result[file.id] = AnalysisReadySnapshot(
                sessionID: session.id,
                readyAt: modified ?? file.createdDate
            )
        }
        return result
    }
}
