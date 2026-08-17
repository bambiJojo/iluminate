//
//  AnalysisTaskSnapshotTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

struct AnalysisTaskSnapshotTests {

    @Test func manualUndismissedFailureNeedsDecisionIntrinsically() {
        let failure = AnalysisFailureSnapshot(
            reason: .transcription,
            failedStage: .transcription,
            failedAt: Date(timeIntervalSince1970: 100),
            recoveryStage: .transcription,
            retryState: .manual,
            dismissedAt: nil
        )
        #expect(failure.needsDecisionIntrinsically)
    }

    @Test func dismissedFailureDoesNotNeedDecision() {
        let failure = AnalysisFailureSnapshot(
            reason: .transcription,
            failedStage: .transcription,
            failedAt: Date(timeIntervalSince1970: 100),
            recoveryStage: .transcription,
            retryState: .manual,
            dismissedAt: Date(timeIntervalSince1970: 200)
        )
        #expect(failure.needsDecisionIntrinsically == false)
    }

    @Test func automaticFailureDoesNotNeedDecisionIntrinsically() {
        let failure = AnalysisFailureSnapshot(
            reason: .transcription,
            failedStage: .transcription,
            failedAt: Date(timeIntervalSince1970: 100),
            recoveryStage: .none,
            retryState: .automatic,
            dismissedAt: nil
        )
        #expect(failure.needsDecisionIntrinsically == false)
    }

    @Test func activeSnapshotTerminalStages() {
        func snapshot(_ stage: AnalysisStage) -> ActiveAnalysisSnapshot {
            ActiveAnalysisSnapshot(
                audioFileID: UUID(),
                attemptID: UUID(),
                stage: stage,
                progress: 0.5,
                startedAt: Date(timeIntervalSince1970: 0)
            )
        }
        #expect(snapshot(.complete).isTerminal)
        #expect(snapshot(.failed).isTerminal)
        #expect(snapshot(.transcribing).isTerminal == false)
        #expect(snapshot(.starting).isTerminal == false)
        #expect(snapshot(.analyzing).isTerminal == false)
        #expect(snapshot(.generatingSession).isTerminal == false)
    }

    @Test func identicalSnapshotsAreEqual() {
        let id = UUID()
        let attempt = UUID()
        let date = Date(timeIntervalSince1970: 42)
        let a = ActiveAnalysisSnapshot(
            audioFileID: id, attemptID: attempt, stage: .transcribing, progress: 0.25, startedAt: date
        )
        let b = ActiveAnalysisSnapshot(
            audioFileID: id, attemptID: attempt, stage: .transcribing, progress: 0.25, startedAt: date
        )
        #expect(a == b)
    }
}
