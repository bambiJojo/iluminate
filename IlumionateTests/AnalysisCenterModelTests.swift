//
//  AnalysisCenterModelTests.swift
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
    failedAt: TimeInterval = 100,
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

/// Main-actor counter; a plain captured `var` is not expressible under strict
/// concurrency in an `@escaping` closure.
@MainActor
private final class Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@MainActor
struct AnalysisCenterModelTests {

    @Test func snapshotIsNilBeforeFirstPublication() {
        let model = AnalysisCenterModel(loadStructure: { .empty })
        #expect(model.tasks == nil)
    }

    @Test func snapshotIsEmptyArrayAfterPublishingAnEmptyLibrary() async {
        let model = AnalysisCenterModel(loadStructure: { .empty })
        await model.refreshAndWait()
        #expect(model.tasks == [])
    }

    @Test func progressRefreshPerformsNoStructuralLoad() async {
        let loads = Counter()
        let file = makeAudioFile()
        let model = AnalysisCenterModel(loadStructure: {
            loads.increment()
            return AnalysisStructuralInput(
                libraryFiles: [file], queue: [file.id], failures: [:], checkpoints: [:], ready: [:]
            )
        })
        await model.refreshAndWait()
        let afterFirstLoad = loads.value

        model.updateProgress(active: ActiveAnalysisSnapshot(
            audioFileID: file.id, attemptID: UUID(), stage: .transcribing,
            progress: 0.5, startedAt: Date(timeIntervalSince1970: 0)
        ), download: nil)

        #expect(loads.value == afterFirstLoad)
        #expect(model.tasks?.first?.state == .running(
            stage: .transcribing, progress: 0.5, startedAt: Date(timeIntervalSince1970: 0)
        ))
    }

    /// Rule 4: a structural commit must not rewind progress newer than the
    /// pass that produced it.
    @Test func structuralCommitPreservesNewerProgress() async {
        let file = makeAudioFile()
        let model = AnalysisCenterModel(loadStructure: {
            AnalysisStructuralInput(
                libraryFiles: [file], queue: [file.id], failures: [:], checkpoints: [:], ready: [:]
            )
        })
        await model.refreshAndWait()

        model.updateProgress(active: ActiveAnalysisSnapshot(
            audioFileID: file.id, attemptID: UUID(), stage: .analyzing,
            progress: 0.9, startedAt: Date(timeIntervalSince1970: 0)
        ), download: nil)

        await model.refreshAndWait()

        #expect(model.tasks?.first?.state == .running(
            stage: .analyzing, progress: 0.9, startedAt: Date(timeIntervalSince1970: 0)
        ))
    }

    @Test func pillCandidatesExcludeDismissedFailures() async {
        let dismissed = makeAudioFile()
        let queued = makeAudioFile()
        let model = AnalysisCenterModel(loadStructure: {
            AnalysisStructuralInput(
                libraryFiles: [dismissed, queued],
                queue: [queued.id],
                failures: [dismissed.id: failure(dismissedAt: Date(timeIntervalSince1970: 200))],
                checkpoints: [:], ready: [:]
            )
        })
        await model.refreshAndWait()
        #expect(model.pillCandidates.map(\.id) == [queued.id])
    }

    @Test func pillShowsActiveProgressAndAFailureSimultaneously() async {
        let failed = makeAudioFile()
        let running = makeAudioFile()
        let model = AnalysisCenterModel(loadStructure: {
            AnalysisStructuralInput(
                libraryFiles: [failed, running],
                queue: [],
                failures: [failed.id: failure()],
                checkpoints: [:], ready: [:]
            )
        })
        await model.refreshAndWait()
        model.updateProgress(active: ActiveAnalysisSnapshot(
            audioFileID: running.id, attemptID: UUID(), stage: .transcribing,
            progress: 0.3, startedAt: Date(timeIntervalSince1970: 0)
        ), download: nil)

        #expect(model.activeTask?.id == running.id)
        #expect(model.attentionCount == 1)
    }

    @Test func taskLookupFindsTheFileSlice() async {
        let file = makeAudioFile()
        let other = makeAudioFile()
        let model = AnalysisCenterModel(loadStructure: {
            AnalysisStructuralInput(
                libraryFiles: [file, other],
                queue: [file.id, other.id],
                failures: [:], checkpoints: [:], ready: [:]
            )
        })
        await model.refreshAndWait()
        #expect(model.task(for: file.id)?.state == .queued(position: 1))
        #expect(model.task(for: UUID()) == nil)
    }
}
