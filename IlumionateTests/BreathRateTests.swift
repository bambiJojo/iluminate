//
//  BreathRateTests.swift
//  IlumionateTests
//
//  Tests for Step 2.5: duration-scaled breath oscillation rate.
//  Formula: max(0.08, min(0.15, 0.15 - (duration - 300) / 3300 * 0.07))
//

import Testing
import Foundation
@testable import Ilumionate

struct BreathRateTests {

    // MARK: Floor and ceiling

    @Test func shortSessionUsesMaxRate() {
        // 5 min (300s) → formula gives 0.15 (maximum breath rate)
        #expect(abs(SessionGenerator.breathRate(for: 300) - 0.15) < 0.001)
    }

    @Test func veryShortSessionClampedToMax() {
        // Under 5 min → formula gives > 0.15, clamped
        #expect(SessionGenerator.breathRate(for: 60) == 0.15)
    }

    @Test func sixtyMinuteSessionUsesMinRate() {
        // 60 min (3600s) → formula: 0.15 - (3300/3300)*0.07 = 0.08
        #expect(abs(SessionGenerator.breathRate(for: 3600) - 0.08) < 0.001)
    }

    @Test func veryLongSessionClampedToMin() {
        // Beyond 60 min, rate stays at floor
        #expect(SessionGenerator.breathRate(for: 7200) == 0.08)
    }

    // MARK: Intermediate values

    @Test func thirtyMinuteSessionIsIntermediate() {
        // 30 min (1800s): 0.15 - (1500/3300)*0.07 ≈ 0.118
        let rate = SessionGenerator.breathRate(for: 1800)
        #expect(rate > 0.08, "30-min rate must be above floor")
        #expect(rate < 0.15, "30-min rate must be below ceiling")
    }

    @Test func fifteenMinuteSessionIsIntermediate() {
        let rate = SessionGenerator.breathRate(for: 900)
        #expect(rate > 0.08)
        #expect(rate < 0.15)
    }

    // MARK: Monotonicity

    @Test func breathRateIsNonIncreasingWithDuration() {
        let durations: [Double] = [300, 600, 900, 1200, 1800, 2700, 3600]
        var prev = SessionGenerator.breathRate(for: durations[0])
        for duration in durations.dropFirst() {
            let current = SessionGenerator.breathRate(for: duration)
            #expect(current <= prev,
                "breathRate must be non-increasing: \(prev) at \(duration - 300)s vs \(current) at \(duration)s")
            prev = current
        }
    }

    // MARK: Bounds invariant

    @Test func breathRateAlwaysWithinPhysiologicalRange() {
        let testDurations: [Double] = [0, 60, 300, 600, 900, 1800, 3600, 7200, 10_800]
        for duration in testDurations {
            let rate = SessionGenerator.breathRate(for: duration)
            #expect(rate >= 0.08, "breathRate for \(duration)s must be ≥0.08 Hz, got \(rate)")
            #expect(rate <= 0.15, "breathRate for \(duration)s must be ≤0.15 Hz, got \(rate)")
        }
    }
}
