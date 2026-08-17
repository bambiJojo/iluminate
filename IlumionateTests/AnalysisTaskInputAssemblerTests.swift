//
//  AnalysisTaskInputAssemblerTests.swift
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

struct AnalysisTaskInputAssemblerTests {

    @Test func queueIsDeduplicatedPreservingFirstOccurrence() {
        let a = UUID(), b = UUID()
        #expect(AnalysisTaskInputAssembler.deduplicate(queue: [a, b, a, b]) == [a, b])
    }

    @Test func deduplicateLeavesAUniqueQueueUnchanged() {
        let a = UUID(), b = UUID()
        #expect(AnalysisTaskInputAssembler.deduplicate(queue: [a, b]) == [a, b])
    }

    @Test func failureSnapshotCarriesDismissalFromTheDurableRecovery() {
        let file = makeAudioFile()
        let dismissedAt = Date(timeIntervalSince1970: 200)
        let checkpoint = AnalysisCheckpoint(
            audioFile: file,
            transcription: nil,
            analysis: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 100),
            manualRecovery: AnalysisManualRecovery(
                reason: .transcription,
                failedStage: .transcription,
                failedAt: Date(timeIntervalSince1970: 100),
                dismissedAt: dismissedAt
            )
        )
        let snapshot = AnalysisTaskInputAssembler.failureSnapshot(from: checkpoint)
        #expect(snapshot?.dismissedAt == dismissedAt)
        #expect(snapshot?.retryState == .manual)
        #expect(snapshot?.failedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func checkpointWithoutManualRecoveryYieldsNoFailureSnapshot() {
        let checkpoint = AnalysisCheckpoint(
            audioFile: makeAudioFile(),
            transcription: nil,
            analysis: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 100)
        )
        #expect(AnalysisTaskInputAssembler.failureSnapshot(from: checkpoint) == nil)
    }

    @Test func checkpointSnapshotCarriesRecoveryStageAndRecency() {
        let checkpoint = AnalysisCheckpoint(
            audioFile: makeAudioFile(),
            transcription: nil,
            analysis: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 100)
        )
        let snapshot = AnalysisTaskInputAssembler.checkpointSnapshot(from: checkpoint)
        #expect(snapshot.recoveryStage == AnalysisRecoveryStage.none)
        #expect(snapshot.lastUpdated == Date(timeIntervalSince1970: 100))
    }
}
