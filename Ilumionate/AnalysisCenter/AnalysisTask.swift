//
//  AnalysisTask.swift
//  Ilumionate
//
//  One task per audio file. `state` is what the pipeline is doing right now;
//  `lastFailure`, `recovery`, and `ready` are what has been salvaged, and are
//  populated independently of `state`.
//

import Foundation

nonisolated struct AnalysisTask: Identifiable, Equatable, Sendable {
    var id: UUID { audioFile.id }

    let audioFile: AudioFile
    let state: AnalysisTaskState
    /// Present whenever a failure has been recorded, including when `state` has
    /// moved on to `.queued` for an automatic retry.
    let lastFailure: AnalysisFailureSnapshot?
    /// The most useful partial result on disk, independent of `state`.
    let recovery: AnalysisRecoveryStage
    /// Present whenever a generated session exists, including during re-analysis.
    let ready: AnalysisReadySnapshot?
}

nonisolated enum AnalysisTaskState: Equatable, Sendable {
    case queued(position: Int)          // one-based
    case preparing(ModelDownloadProgress)
    case running(stage: AnalysisStage, progress: Double, startedAt: Date)
    /// A durable checkpoint exists and nothing is scheduled. Named for what the
    /// user sees, not for what was saved: `recovery` may be `.none` when a
    /// cancellation left a checkpoint with no partial result yet.
    case paused
    case failed
    case ready
}
