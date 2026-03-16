//
//  ChunkCountTests.swift
//  IlumionateTests
//
//  Tests for Step 2.1: duration-proportional chunk count in ChunkedPhaseAnalyzer.
//  Formula: max(6, min(60, Int(duration / 90)))
//

import Testing
import Foundation
@testable import Ilumionate

struct ChunkCountTests {

    // MARK: Floor enforcement

    @Test func twoMinuteSessionUsesMinimumChunks() {
        // 120 / 90 = 1 → max(6, 1) = 6
        #expect(ChunkedPhaseAnalyzer.chunkCount(for: 120) == 6)
    }

    @Test func fiveMinuteSessionUsesMinimumChunks() {
        // 300 / 90 = 3 → max(6, 3) = 6
        #expect(ChunkedPhaseAnalyzer.chunkCount(for: 300) == 6)
    }

    @Test func zeroSecondSessionUsesMinimumChunks() {
        // Edge: 0 / 90 = 0 → max(6, 0) = 6
        #expect(ChunkedPhaseAnalyzer.chunkCount(for: 0) == 6)
    }

    // MARK: Proportional middle range

    @Test func thirtyMinuteSessionGetsTwentyChunks() {
        // 1800 / 90 = 20 → clamped to 20
        #expect(ChunkedPhaseAnalyzer.chunkCount(for: 1800) == 20)
    }

    @Test func sixtyMinuteSessionGetsFortyChunks() {
        // 3600 / 90 = 40 → clamped to 40
        #expect(ChunkedPhaseAnalyzer.chunkCount(for: 3600) == 40)
    }

    // MARK: Ceiling enforcement

    @Test func ninetyMinuteSessionUsesCeiling() {
        // 5400 / 90 = 60 → min(60, 60) = 60
        #expect(ChunkedPhaseAnalyzer.chunkCount(for: 5400) == 60)
    }

    @Test func twoHourSessionUsesCeiling() {
        // 7200 / 90 = 80 → min(60, 80) = 60
        #expect(ChunkedPhaseAnalyzer.chunkCount(for: 7200) == 60)
    }

    @Test func veryLongSessionUsesCeiling() {
        // 3-hour session: 10800 / 90 = 120 → capped at 60
        #expect(ChunkedPhaseAnalyzer.chunkCount(for: 10_800) == 60)
    }

    // MARK: Monotonicity

    @Test func chunkCountIsNonDecreasing() {
        let durations: [Double] = [300, 600, 900, 1800, 2700, 3600, 4500, 5400]
        var prev = ChunkedPhaseAnalyzer.chunkCount(for: durations[0])
        for duration in durations.dropFirst() {
            let current = ChunkedPhaseAnalyzer.chunkCount(for: duration)
            #expect(current >= prev,
                "chunkCount must be non-decreasing: \(prev) at \(duration - 300)s vs \(current) at \(duration)s")
            prev = current
        }
    }

    // MARK: Bounds

    @Test func chunkCountNeverGoesOutOfBounds() {
        let testDurations: [Double] = [0, 30, 120, 300, 900, 1800, 3600, 5400, 7200, 10_800]
        for duration in testDurations {
            let count = ChunkedPhaseAnalyzer.chunkCount(for: duration)
            #expect(count >= 6, "chunkCount for \(duration)s must be ≥6, got \(count)")
            #expect(count <= 60, "chunkCount for \(duration)s must be ≤60, got \(count)")
        }
    }
}
