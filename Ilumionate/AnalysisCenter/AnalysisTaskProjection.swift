//
//  AnalysisTaskProjection.swift
//  Ilumionate
//
//  Pure input -> ordered [AnalysisTask]. No actor, no async, no disk access.
//  Every analysis surface renders this one list; none re-derives state.
//

import Foundation

nonisolated struct AnalysisTaskProjectionInput: Equatable, Sendable {
    let libraryFiles: [AudioFile]
    let activeAnalysis: ActiveAnalysisSnapshot?
    let modelDownload: ModelDownloadProgress?
    /// Audio file ids in queue order. The assembler enforces uniqueness; the
    /// projection uses first occurrence if a duplicate slips through.
    let queue: [UUID]
    let failures: [UUID: AnalysisFailureSnapshot]
    let checkpoints: [UUID: AnalysisCheckpointSnapshot]
    let ready: [UUID: AnalysisReadySnapshot]
}

nonisolated enum AnalysisTaskProjection {

    static func tasks(from input: AnalysisTaskProjectionInput) -> [AnalysisTask] {
        var positions: [UUID: Int] = [:]
        for (index, id) in input.queue.enumerated() where positions[id] == nil {
            positions[id] = index + 1          // one-based, first occurrence
        }

        let tasks = input.libraryFiles.compactMap { file -> AnalysisTask? in
            guard let state = state(for: file.id, in: input, queuePosition: positions[file.id]) else {
                return nil
            }
            return AnalysisTask(
                audioFile: file,
                state: state,
                lastFailure: input.failures[file.id],
                recovery: input.checkpoints[file.id]?.recoveryStage ?? .none,
                checkpointLastUpdated: input.checkpoints[file.id]?.lastUpdated,
                ready: input.ready[file.id]
            )
        }

        return sorted(tasks, queuePositions: positions)
    }

    // MARK: Collapse

    private static func state(
        for fileID: UUID,
        in input: AnalysisTaskProjectionInput,
        queuePosition: Int?
    ) -> AnalysisTaskState? {
        // Rules 1 and 2 — an active, non-terminal analysis. Terminal stages fall
        // through: the pipeline leaves `currentAnalysis` populated with
        // `.failed` while re-queueing the file, and collapsing that to
        // `.running(.failed)` would defeat the automatic-retry rule.
        if let active = input.activeAnalysis, active.audioFileID == fileID, !active.isTerminal {
            if let download = input.modelDownload,
               download.audioFileID == fileID,
               download.attemptID == active.attemptID {
                return .preparing(download)
            }
            return .running(stage: active.stage, progress: active.progress, startedAt: active.startedAt)
        }

        // Rule 3 — above rule 4 so an automatic retry reads as queued.
        if let position = queuePosition {
            return .queued(position: position)
        }

        // Rule 4
        if input.failures[fileID] != nil {
            return .failed
        }

        // Rule 5 — a checkpoint counts even with `.none` recovery, but not when
        // a completed session has already superseded it.
        if let checkpoint = input.checkpoints[fileID] {
            let overtaken = input.ready[fileID].map { checkpoint.lastUpdated <= $0.readyAt } ?? false
            if !overtaken {
                return .paused
            }
        }

        // Rule 6
        if input.ready[fileID] != nil {
            return .ready
        }

        return nil
    }

    // MARK: Sort

    /// Tier 1 is computed here rather than on the failure snapshot because it
    /// depends on queue membership: an `.automatic` failure is only harmless
    /// while something is going to retry it.
    static func needsDecision(_ task: AnalysisTask, queuePositions: [UUID: Int]) -> Bool {
        guard let failure = task.lastFailure, failure.dismissedAt == nil else { return false }
        return failure.needsDecisionIntrinsically || queuePositions[task.id] == nil
    }

    private static func tier(_ task: AnalysisTask, queuePositions: [UUID: Int]) -> Int {
        if needsDecision(task, queuePositions: queuePositions) { return 1 }
        switch task.state {
        case .preparing, .running: return 2
        case .queued:              return 3
        case .paused:              return 4
        case .failed:              return 5
        case .ready:               return 6
        }
    }

    private static func sorted(_ tasks: [AnalysisTask], queuePositions: [UUID: Int]) -> [AnalysisTask] {
        tasks.sorted { lhs, rhs in
            let lhsTier = tier(lhs, queuePositions: queuePositions)
            let rhsTier = tier(rhs, queuePositions: queuePositions)
            if lhsTier != rhsTier { return lhsTier < rhsTier }
            if let ordering = withinTier(lhsTier, lhs, rhs, queuePositions: queuePositions) { return ordering }
            return lhs.id.uuidString < rhs.id.uuidString      // stable tie-breaker
        }
    }

    private static func withinTier(
        _ tier: Int,
        _ lhs: AnalysisTask,
        _ rhs: AnalysisTask,
        queuePositions: [UUID: Int]
    ) -> Bool? {
        switch tier {
        case 1, 5:
            guard let l = lhs.lastFailure?.failedAt, let r = rhs.lastFailure?.failedAt, l != r else { return nil }
            return l > r
        case 2:
            guard case .running(_, _, let l) = lhs.state, case .running(_, _, let r) = rhs.state, l != r else { return nil }
            return l > r
        case 3:
            guard let l = queuePositions[lhs.id], let r = queuePositions[rhs.id], l != r else { return nil }
            return l < r
        case 4:
            guard let l = lhs.checkpointLastUpdated, let r = rhs.checkpointLastUpdated, l != r else { return nil }
            return l > r
        case 6:
            guard let l = lhs.ready?.readyAt, let r = rhs.ready?.readyAt, l != r else { return nil }
            return l > r
        default:
            return nil
        }
    }
}
