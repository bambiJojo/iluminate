//
//  AnalysisFailureMergeTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

private func snapshot(
    failedAt: TimeInterval,
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

struct AnalysisFailureMergeTests {

    @Test func durableWinsOnEqualFailedAt() {
        let id = UUID()
        let durable = snapshot(failedAt: 100, dismissedAt: Date(timeIntervalSince1970: 150))
        let runtime = snapshot(failedAt: 100, dismissedAt: nil)
        let merged = AnalysisFailureMerge.merge(durable: [id: durable], runtime: [id: runtime])
        #expect(merged[id]?.dismissedAt == Date(timeIntervalSince1970: 150))
    }

    @Test func laterFailedAtWins() {
        let id = UUID()
        let durable = snapshot(failedAt: 100, dismissedAt: Date(timeIntervalSince1970: 150))
        let runtime = snapshot(failedAt: 300, dismissedAt: nil)
        let merged = AnalysisFailureMerge.merge(durable: [id: durable], runtime: [id: runtime])
        #expect(merged[id]?.failedAt == Date(timeIntervalSince1970: 300))
        #expect(merged[id]?.dismissedAt == nil)
    }

    @Test func durableOnlyIsRetained() {
        let id = UUID()
        let durable = snapshot(failedAt: 100)
        let merged = AnalysisFailureMerge.merge(durable: [id: durable], runtime: [:])
        #expect(merged[id]?.failedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func runtimeOnlyIsRetained() {
        let id = UUID()
        let runtime = snapshot(failedAt: 100, retryState: .unavailable, recoveryStage: .none)
        let merged = AnalysisFailureMerge.merge(durable: [:], runtime: [id: runtime])
        #expect(merged[id]?.retryState == .unavailable)
    }

    @Test func mergeCoversUnionOfBothKeySets() {
        let a = UUID(), b = UUID()
        let merged = AnalysisFailureMerge.merge(
            durable: [a: snapshot(failedAt: 1)],
            runtime: [b: snapshot(failedAt: 2)]
        )
        #expect(merged.count == 2)
        #expect(merged[a] != nil)
        #expect(merged[b] != nil)
    }
}
