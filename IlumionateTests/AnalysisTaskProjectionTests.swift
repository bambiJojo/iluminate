//
//  AnalysisTaskProjectionTests.swift
//  IlumionateTests
//
//  Pure projection: no actor, no async, no disk.
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

private func input(
    files: [AudioFile],
    active: ActiveAnalysisSnapshot? = nil,
    download: ModelDownloadProgress? = nil,
    queue: [UUID] = [],
    failures: [UUID: AnalysisFailureSnapshot] = [:],
    checkpoints: [UUID: AnalysisCheckpointSnapshot] = [:],
    ready: [UUID: AnalysisReadySnapshot] = [:]
) -> AnalysisTaskProjectionInput {
    AnalysisTaskProjectionInput(
        libraryFiles: files,
        activeAnalysis: active,
        modelDownload: download,
        queue: queue,
        failures: failures,
        checkpoints: checkpoints,
        ready: ready
    )
}

private func failure(
    failedAt: TimeInterval = 100,
    retryState: AnalysisRetryState = .manual,
    dismissedAt: Date? = nil,
    recoveryStage: AnalysisRecoveryStage = .transcription
) -> AnalysisFailureSnapshot {
    AnalysisFailureSnapshot(
        reason: .transcription,
        failedStage: .transcription,
        failedAt: Date(timeIntervalSince1970: failedAt),
        recoveryStage: recoveryStage,
        retryState: retryState,
        dismissedAt: dismissedAt
    )
}

private func checkpoint(
    recoveryStage: AnalysisRecoveryStage = .transcription,
    lastUpdated: TimeInterval = 100
) -> AnalysisCheckpointSnapshot {
    AnalysisCheckpointSnapshot(
        recoveryStage: recoveryStage,
        startedAt: Date(timeIntervalSince1970: 0),
        lastUpdated: Date(timeIntervalSince1970: lastUpdated)
    )
}

private func ready(readyAt: TimeInterval = 100) -> AnalysisReadySnapshot {
    AnalysisReadySnapshot(sessionID: UUID(), readyAt: Date(timeIntervalSince1970: readyAt))
}

private func active(
    _ fileID: UUID,
    stage: AnalysisStage = .transcribing,
    attemptID: UUID = UUID(),
    progress: Double = 0.4
) -> ActiveAnalysisSnapshot {
    ActiveAnalysisSnapshot(
        audioFileID: fileID,
        attemptID: attemptID,
        stage: stage,
        progress: progress,
        startedAt: Date(timeIntervalSince1970: 50)
    )
}

struct AnalysisTaskProjectionTests {

    // MARK: Rule 1 / 2 — active

    @Test func nonTerminalActiveCollapsesToRunning() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(files: [file], active: active(file.id)))
        #expect(tasks.first?.state == .running(stage: .transcribing, progress: 0.4, startedAt: Date(timeIntervalSince1970: 50)))
    }

    @Test func preparingRequiresMatchingFileAndAttempt() {
        let file = makeAudioFile()
        let attempt = UUID()
        let download = ModelDownloadProgress(
            audioFileID: file.id, attemptID: attempt,
            completedUnitCount: 5, totalUnitCount: 10, fractionCompleted: 0.5
        )
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            active: active(file.id, attemptID: attempt),
            download: download
        ))
        #expect(tasks.first?.state == .preparing(download))
    }

    /// The lookahead prefetch downloads for the *next* file while the current
    /// file is generating. A global download flag would mislabel the active file.
    @Test func speculativeDownloadDoesNotRelabelActiveFile() {
        let current = makeAudioFile()
        let next = makeAudioFile()
        let download = ModelDownloadProgress(
            audioFileID: next.id, attemptID: UUID(),
            completedUnitCount: 5, totalUnitCount: 10, fractionCompleted: 0.5
        )
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [current, next],
            active: active(current.id, stage: .generatingSession),
            download: download,
            queue: [next.id]
        ))
        let currentTask = tasks.first { $0.id == current.id }
        let nextTask = tasks.first { $0.id == next.id }
        #expect(currentTask?.state == .running(stage: .generatingSession, progress: 0.4, startedAt: Date(timeIntervalSince1970: 50)))
        #expect(nextTask?.state == .queued(position: 1))
    }

    // MARK: Terminal active falls through

    @Test func terminalFailedActiveCollapsesToQueuedNotRunning() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            active: active(file.id, stage: .failed),
            queue: [file.id],
            failures: [file.id: failure(retryState: .automatic)]
        ))
        #expect(tasks.first?.state == .queued(position: 1))
    }

    @Test func terminalCompleteActiveCollapsesToReadyWhenReadyExists() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            active: active(file.id, stage: .complete),
            ready: [file.id: ready()]
        ))
        #expect(tasks.first?.state == .ready)
    }

    @Test func terminalCompleteWithoutReadySnapshotDoesNotSynthesiseReady() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            active: active(file.id, stage: .complete),
            checkpoints: [file.id: checkpoint()]
        ))
        #expect(tasks.first?.state == .paused)
    }

    // MARK: Rule 3 above rule 4

    @Test func automaticRetryCollapsesToQueuedAndKeepsFailureAsAttribute() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            queue: [file.id],
            failures: [file.id: failure(retryState: .automatic)]
        ))
        #expect(tasks.first?.state == .queued(position: 1))
        #expect(tasks.first?.lastFailure != nil)
    }

    @Test func queuePositionsAreOneBased() {
        let a = makeAudioFile(), b = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(files: [a, b], queue: [a.id, b.id]))
        #expect(tasks.first { $0.id == a.id }?.state == .queued(position: 1))
        #expect(tasks.first { $0.id == b.id }?.state == .queued(position: 2))
    }

    @Test func duplicateQueueEntriesUseFirstOccurrence() {
        let file = makeAudioFile()
        let other = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file, other],
            queue: [file.id, other.id, file.id]
        ))
        #expect(tasks.first { $0.id == file.id }?.state == .queued(position: 1))
    }

    // MARK: Rule 5 — paused

    @Test func checkpointWithNoRecoveryStageStillProducesPausedTask() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            checkpoints: [file.id: checkpoint(recoveryStage: .none)]
        ))
        #expect(tasks.first?.state == .paused)
        #expect(tasks.first?.recovery == AnalysisRecoveryStage.none)
    }

    @Test func checkpointOlderThanReadyYieldsReady() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            checkpoints: [file.id: checkpoint(lastUpdated: 50)],
            ready: [file.id: ready(readyAt: 100)]
        ))
        #expect(tasks.first?.state == .ready)
    }

    @Test func checkpointNewerThanReadyYieldsPaused() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            checkpoints: [file.id: checkpoint(lastUpdated: 150)],
            ready: [file.id: ready(readyAt: 100)]
        ))
        #expect(tasks.first?.state == .paused)
    }

    // MARK: Library is the spine

    @Test func fileAbsentFromLibraryEmitsNoTask() {
        let orphan = UUID()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [],
            queue: [orphan],
            failures: [orphan: failure()]
        ))
        #expect(tasks.isEmpty)
    }

    @Test func fileWithNoStateAtAllEmitsNoTask() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(files: [file]))
        #expect(tasks.isEmpty)
    }

    // MARK: Attributes survive collapse

    @Test func attributesSurviveQueuedCollapse() {
        let file = makeAudioFile()
        let readySnapshot = ready()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            queue: [file.id],
            failures: [file.id: failure(retryState: .automatic)],
            checkpoints: [file.id: checkpoint(recoveryStage: .analysis)],
            ready: [file.id: readySnapshot]
        ))
        let task = tasks.first
        #expect(task?.state == .queued(position: 1))
        #expect(task?.lastFailure?.retryState == .automatic)
        #expect(task?.recovery == AnalysisRecoveryStage.analysis)
        #expect(task?.ready == readySnapshot)
    }

    // MARK: Determinism

    @Test func identicalInputsProduceEqualSnapshots() {
        let file = makeAudioFile()
        let shared = input(files: [file], queue: [file.id])
        #expect(AnalysisTaskProjection.tasks(from: shared) == AnalysisTaskProjection.tasks(from: shared))
    }
}
