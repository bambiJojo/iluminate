//
//  AnalysisTaskSortingTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

private func makeAudioFile(id: UUID = UUID()) -> AudioFile {
    AudioFile(
        id: id,
        filename: "test_\(id.uuidString).m4a",
        duration: 300,
        fileSize: 1_024_000,
        createdDate: Date(timeIntervalSince1970: 0)
    )
}

private func failure(
    failedAt: TimeInterval,
    retryState: AnalysisRetryState = .manual,
    dismissedAt: Date? = nil
) -> AnalysisFailureSnapshot {
    AnalysisFailureSnapshot(
        reason: .transcription,
        failedStage: .transcription,
        failedAt: Date(timeIntervalSince1970: failedAt),
        recoveryStage: .transcription,
        retryState: retryState,
        dismissedAt: dismissedAt
    )
}

private func input(
    files: [AudioFile],
    active: ActiveAnalysisSnapshot? = nil,
    queue: [UUID] = [],
    failures: [UUID: AnalysisFailureSnapshot] = [:],
    checkpoints: [UUID: AnalysisCheckpointSnapshot] = [:],
    ready: [UUID: AnalysisReadySnapshot] = [:]
) -> AnalysisTaskProjectionInput {
    AnalysisTaskProjectionInput(
        libraryFiles: files, activeAnalysis: active, modelDownload: nil,
        queue: queue, failures: failures, checkpoints: checkpoints, ready: ready
    )
}

struct AnalysisTaskSortingTests {

    @Test func actionRequiredFailureOutranksActiveWork() {
        let failed = makeAudioFile()
        let running = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [running, failed],
            active: ActiveAnalysisSnapshot(
                audioFileID: running.id, attemptID: UUID(), stage: .transcribing,
                progress: 0.5, startedAt: Date(timeIntervalSince1970: 10)
            ),
            failures: [failed.id: failure(failedAt: 100)]
        ))
        #expect(tasks.first?.id == failed.id)
    }

    /// Criterion 7: an automatic retry is still queued, so it must not
    /// masquerade as something needing a decision.
    @Test func queuedAutomaticRetryStaysBelowActiveWork() {
        let retrying = makeAudioFile()
        let running = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [retrying, running],
            active: ActiveAnalysisSnapshot(
                audioFileID: running.id, attemptID: UUID(), stage: .transcribing,
                progress: 0.5, startedAt: Date(timeIntervalSince1970: 10)
            ),
            queue: [retrying.id],
            failures: [retrying.id: failure(failedAt: 100, retryState: .automatic)]
        ))
        #expect(tasks.first?.id == running.id)
    }

    /// The hole: clearQueue() strands an automatic failure. Nothing will retry
    /// it, so it must surface rather than sitting in no tier at all.
    @Test func strandedAutomaticFailureReachesTierOne() {
        let stranded = makeAudioFile()
        let running = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [stranded, running],
            active: ActiveAnalysisSnapshot(
                audioFileID: running.id, attemptID: UUID(), stage: .transcribing,
                progress: 0.5, startedAt: Date(timeIntervalSince1970: 10)
            ),
            queue: [],
            failures: [stranded.id: failure(failedAt: 100, retryState: .automatic)]
        ))
        #expect(tasks.first?.id == stranded.id)
    }

    @Test func dismissedFailuresSortBelowPaused() {
        let dismissed = makeAudioFile()
        let paused = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [dismissed, paused],
            failures: [dismissed.id: failure(failedAt: 100, dismissedAt: Date(timeIntervalSince1970: 200))],
            checkpoints: [paused.id: AnalysisCheckpointSnapshot(
                recoveryStage: .transcription,
                startedAt: Date(timeIntervalSince1970: 0),
                lastUpdated: Date(timeIntervalSince1970: 10)
            )]
        ))
        #expect(tasks.first?.id == paused.id)
    }

    /// Fixed ids, deliberately ordered *against* the expected result: `older`
    /// sorts first by id, so this can only pass if tier-4 ordering by checkpoint
    /// recency actually runs. With random ids it would be a coin flip.
    @Test func pausedTasksOrderByCheckpointLastUpdatedDescending() {
        let older = makeAudioFile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
        let newer = makeAudioFile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!)
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [older, newer],
            checkpoints: [
                older.id: AnalysisCheckpointSnapshot(
                    recoveryStage: .transcription,
                    startedAt: Date(timeIntervalSince1970: 0),
                    lastUpdated: Date(timeIntervalSince1970: 10)
                ),
                newer.id: AnalysisCheckpointSnapshot(
                    recoveryStage: .transcription,
                    startedAt: Date(timeIntervalSince1970: 0),
                    lastUpdated: Date(timeIntervalSince1970: 99)
                )
            ]
        ))
        #expect(tasks.first?.id == newer.id)
    }

    /// Same construction as the paused case: id order runs against the expected
    /// result so the tie-breaker cannot make this pass by accident.
    @Test func readyTasksOrderByReadyAtDescending() {
        let older = makeAudioFile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
        let newer = makeAudioFile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!)
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [older, newer],
            ready: [
                older.id: AnalysisReadySnapshot(sessionID: UUID(), readyAt: Date(timeIntervalSince1970: 10)),
                newer.id: AnalysisReadySnapshot(sessionID: UUID(), readyAt: Date(timeIntervalSince1970: 99))
            ]
        ))
        #expect(tasks.first?.id == newer.id)
    }

    @Test func equalTimestampsFallBackToStableIDOrder() {
        let a = makeAudioFile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
        let b = makeAudioFile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!)
        let sameReady = Date(timeIntervalSince1970: 50)
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [b, a],
            ready: [
                a.id: AnalysisReadySnapshot(sessionID: UUID(), readyAt: sameReady),
                b.id: AnalysisReadySnapshot(sessionID: UUID(), readyAt: sameReady)
            ]
        ))
        #expect(tasks.map(\.id) == [a.id, b.id])
    }
}
