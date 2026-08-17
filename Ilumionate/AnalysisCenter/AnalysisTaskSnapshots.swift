//
//  AnalysisTaskSnapshots.swift
//  Ilumionate
//
//  Immutable value snapshots of everything the Analysis Task Center projects.
//  The live types cannot be used: ActiveAnalysis is a non-Sendable @Observable
//  class, SyncPlayerItem regenerates its id per instance, and FailedAnalysis is
//  not Equatable.
//

import Foundation

/// The active analysis, flattened to values.
nonisolated struct ActiveAnalysisSnapshot: Equatable, Sendable {
    let audioFileID: UUID
    let attemptID: UUID
    let stage: AnalysisStage
    let progress: Double
    let startedAt: Date

    /// `.complete` and `.failed` are terminal: the pipeline leaves
    /// `currentAnalysis` populated after it has stopped working on the file.
    var isTerminal: Bool { stage == .complete || stage == .failed }
}

/// Progress of a WhisperKit model download. Produced in Phase 2c; defined here
/// so the model does not change when that lands.
nonisolated struct ModelDownloadProgress: Equatable, Sendable {
    /// The file whose analysis this download is bootstrapping. A speculative
    /// prefetch downloads for the *next* file, not the active one.
    let audioFileID: UUID
    let attemptID: UUID
    let completedUnitCount: Int64
    let totalUnitCount: Int64
    let fractionCompleted: Double
}

/// A recorded failure, merged from the durable recovery and the runtime list.
nonisolated struct AnalysisFailureSnapshot: Equatable, Sendable {
    let reason: AnalyticsAnalysisFailureReason
    let failedStage: AnalyticsAnalysisStage
    let failedAt: Date
    let recoveryStage: AnalysisRecoveryStage
    let retryState: AnalysisRetryState
    let dismissedAt: Date?

    var presentation: AnalysisFailurePresentation {
        AnalysisFailurePresentation(
            reason: reason,
            failedStage: failedStage,
            recoveryStage: recoveryStage,
            retryState: retryState
        )
    }

    /// True when this failure needs a decision *regardless of queue state*.
    /// Tier-1 eligibility is broader — an `.automatic` failure that is no
    /// longer queued is also stranded. See `AnalysisTaskProjection`.
    var needsDecisionIntrinsically: Bool {
        dismissedAt == nil && (retryState == .manual || retryState == .unavailable)
    }
}

/// A durable checkpoint, flattened. Carries `lastUpdated` because tier-4
/// ordering needs it and because it is the only way to detect a checkpoint
/// overtaken by a completed session.
nonisolated struct AnalysisCheckpointSnapshot: Equatable, Sendable {
    let recoveryStage: AnalysisRecoveryStage
    let startedAt: Date
    let lastUpdated: Date
}

/// A generated session that is ready to play.
nonisolated struct AnalysisReadySnapshot: Equatable, Sendable {
    /// `LightSession.id` — decoded from stored JSON, stable across loads.
    /// Deliberately not `SyncPlayerItem.id`, which regenerates per instance.
    let sessionID: UUID
    let readyAt: Date
}
