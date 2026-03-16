//
//  MinRunScalingTests.swift
//  IlumionateTests
//
//  Tests for Step 1.4: minRun scales with session duration.
//  Formula: max(20, Int(duration * 0.035))
//  Results: 5-min → 20s, 30-min → 63s, 60-min → 126s
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Formula Tests

struct MinRunFormulaTests {

    /// Mirrors the formula used in both analyzers.
    private func minRun(for duration: Double) -> Int {
        max(20, Int(duration * 0.035))
    }

    @Test func fiveMinuteSessionUsesFloor() {
        // 300s * 0.035 = 10.5 → floor → max(20, 10) = 20
        #expect(minRun(for: 300) == 20)
    }

    @Test func thirtyMinuteSessionMatchesOldBehaviorApproximately() {
        // 1800s * 0.035 = 63 → max(20, 63) = 63
        // Old hard-coded value was 45 — 63 is slightly more aggressive, correct for 30-min
        #expect(minRun(for: 1800) == 63)
    }

    @Test func sixtyMinuteSessionScalesUp() {
        // 3600s * 0.035 = 126 → max(20, 126) = 126
        #expect(minRun(for: 3600) == 126)
    }

    @Test func veryShortSessionNeverGoesBelowFloor() {
        // A 30-second recording: 30 * 0.035 = 1.05 → max(20, 1) = 20
        #expect(minRun(for: 30) == 20)
    }

    @Test func twoHourSessionScalesProperly() {
        // 7200s * 0.035 = 252 → max(20, 252) = 252
        #expect(minRun(for: 7200) == 252)
    }

    @Test func formulaIsMonotonicAboveFloor() {
        // For durations where formula > 20, longer sessions get larger minRun
        let durations: [Double] = [600, 1200, 1800, 2400, 3600]
        var prev = minRun(for: durations[0])
        for duration in durations.dropFirst() {
            let current = minRun(for: duration)
            #expect(current >= prev,
                "minRun must be non-decreasing: \(prev) at \(duration - 600)s vs \(current) at \(duration)s")
            prev = current
        }
    }
}

// MARK: - Pipeline Behaviour Tests

struct MinRunPipelineTests {

    /// Builds a synthetic keyword timeline with a short pre_talk run at the start
    /// and a short emergence run at the end, verifying they survive collapse on
    /// a short (5-min) session but get absorbed on a long (60-min) session.
    private func buildTimeline(
        preTalkDuration: Int,
        therapyDuration: Int,
        emergenceDuration: Int
    ) -> [HypnosisMetadata.Phase?] {
        var timeline: [HypnosisMetadata.Phase?] = []
        timeline += Array(repeating: HypnosisMetadata.Phase.preTalk, count: preTalkDuration)
        timeline += Array(repeating: HypnosisMetadata.Phase.therapy, count: therapyDuration)
        timeline += Array(repeating: HypnosisMetadata.Phase.emergence, count: emergenceDuration)
        return timeline
    }

    @Test func shortSessionPreservesPreTalkWithSmallMinRun() {
        // 5-min session → minRun = 20s
        // pre_talk run = 25s > 20s → must survive
        let timeline = buildTimeline(preTalkDuration: 25, therapyDuration: 250, emergenceDuration: 25)
        let result = ChunkedPhaseAnalyzer.collapseShortRuns(timeline, minRun: 20)

        let preTalkCount = result.filter { $0 == .preTalk }.count
        #expect(preTalkCount > 0, "pre_talk (25s) must survive minRun=20 on 5-min session")
    }

    @Test func shortSessionPreservesEmergenceWithSmallMinRun() {
        // 5-min session → minRun = 20s
        // emergence run = 25s > 20s → must survive
        let timeline = buildTimeline(preTalkDuration: 25, therapyDuration: 250, emergenceDuration: 25)
        let result = ChunkedPhaseAnalyzer.collapseShortRuns(timeline, minRun: 20)

        let emergenceCount = result.filter { $0 == .emergence }.count
        #expect(emergenceCount > 0, "emergence (25s) must survive minRun=20 on 5-min session")
    }

    @Test func shortSessionAbsorbsTinyRun() {
        // A 10s run with minRun=20 must get absorbed
        let timeline = buildTimeline(preTalkDuration: 10, therapyDuration: 280, emergenceDuration: 10)
        let result = ChunkedPhaseAnalyzer.collapseShortRuns(timeline, minRun: 20)

        let preTalkCount = result.filter { $0 == .preTalk }.count
        #expect(preTalkCount == 0, "pre_talk (10s) must be absorbed when minRun=20")
    }

    @Test func longSessionAbsorbsMediumRunUnderHighMinRun() {
        // 60-min session → minRun = 126s
        // A 30s pre_talk run < 126s → must be absorbed into therapy
        let timeline = buildTimeline(preTalkDuration: 30, therapyDuration: 3510, emergenceDuration: 60)
        let result = ChunkedPhaseAnalyzer.collapseShortRuns(timeline, minRun: 126)

        let preTalkCount = result.filter { $0 == .preTalk }.count
        #expect(preTalkCount == 0, "pre_talk (30s) must be absorbed when minRun=126 on 60-min session")
    }

    @Test func collapseShortRunsHandlesAllNilTimeline() {
        let timeline: [HypnosisMetadata.Phase?] = [nil, nil, nil, nil]
        let result = ChunkedPhaseAnalyzer.collapseShortRuns(timeline, minRun: 20)
        #expect(result.count == 4)
        #expect(result.allSatisfy { $0 == nil })
    }

    @Test func collapseShortRunsHandlesSingleElement() {
        let timeline: [HypnosisMetadata.Phase?] = [.therapy]
        let result = ChunkedPhaseAnalyzer.collapseShortRuns(timeline, minRun: 20)
        #expect(result.count == 1)
        #expect(result[0] == .therapy)
    }

    @Test func collapseShortRunsSessionShorterThanMinRun() {
        // Entire session is 5 seconds, minRun = 20 → single run, must not crash
        let timeline: [HypnosisMetadata.Phase?] = Array(repeating: .induction, count: 5)
        let result = ChunkedPhaseAnalyzer.collapseShortRuns(timeline, minRun: 20)
        // Should return one consolidated run without crashing
        #expect(result.count == 5)
    }
}
