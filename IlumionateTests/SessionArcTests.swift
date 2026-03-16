//
//  SessionArcTests.swift
//  IlumionateTests
//
//  Tests for Step 4.3: SessionArc — session-length-aware arc waypoints.
//  Verifies:
//  1. Emergence ≥ 60 s on all session lengths.
//  2. Phase ordering (betaEntrance < alpha < theta < deepHold < emergence).
//  3. Minimum-duration floors are respected.
//  4. generateHypnosisFromDuration output is correctly arc-aligned.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - SessionArc Structural Tests

struct SessionArcStructureTests {

    @Test func phasesAreStrictlyOrdered() {
        for duration in [120.0, 300.0, 600.0, 1800.0, 3600.0, 7200.0] {
            let arc = SessionArc(duration: duration)
            #expect(arc.betaEntranceEnd  < arc.alphaDescentEnd,
                "\(duration)s: betaEntranceEnd (\(arc.betaEntranceEnd)) ≥ alphaDescentEnd (\(arc.alphaDescentEnd))")
            #expect(arc.alphaDescentEnd  < arc.thetaInductionEnd,
                "\(duration)s: alphaDescentEnd ≥ thetaInductionEnd")
            #expect(arc.thetaInductionEnd <= arc.deepHoldEnd,
                "\(duration)s: thetaInductionEnd > deepHoldEnd")
            #expect(arc.deepHoldEnd      < arc.emergenceStart,
                "\(duration)s: deepHoldEnd (\(arc.deepHoldEnd)) ≥ emergenceStart (\(arc.emergenceStart))")
            #expect(arc.emergenceStart   < arc.duration,
                "\(duration)s: emergenceStart ≥ duration")
        }
    }

    @Test func emergenceIsAtLeastSixtySeconds() {
        // The key guarantee: any session ≥120 s gets ≥60 s of emergence.
        for duration in [120.0, 180.0, 300.0, 600.0, 900.0, 1800.0, 3600.0] {
            let arc = SessionArc(duration: duration)
            #expect(arc.emergenceDuration >= 60.0,
                "\(duration)s: emergence only \(arc.emergenceDuration)s (< 60s guarantee)")
        }
    }

    @Test func fiveMinuteSessionHasSufficientBetaEntrance() {
        let arc = SessionArc(duration: 300)
        #expect(arc.betaEntranceEnd >= 30.0,
            "5-min session: betaEntranceEnd \(arc.betaEntranceEnd)s must be ≥30s")
    }

    @Test func fiveMinuteSessionHasSufficientAlphaDescent() {
        let arc = SessionArc(duration: 300)
        let alphaDuration = arc.alphaDescentEnd - arc.betaEntranceEnd
        #expect(alphaDuration >= 45.0,
            "5-min alpha descent \(alphaDuration)s must be ≥45s")
    }

    @Test func fiveMinuteSessionHasSufficientThetaInduction() {
        let arc = SessionArc(duration: 300)
        let thetaDuration = arc.thetaInductionEnd - arc.alphaDescentEnd
        #expect(thetaDuration >= 45.0,
            "5-min theta induction \(thetaDuration)s must be ≥45s")
    }

    @Test func emergenceNeverStartsBeforeHalfway() {
        // emergenceStart must be ≥ 50% of duration
        for duration in [120.0, 300.0, 600.0, 1800.0] {
            let arc = SessionArc(duration: duration)
            #expect(arc.emergenceStart >= duration * 0.50,
                "\(duration)s: emergenceStart (\(arc.emergenceStart)s) < 50% of duration")
        }
    }

    @Test func thirtyMinuteSessionUsesPercentageWaypoints() {
        // For a 30-min session, percentages dominate (minimums don't bind).
        let arc = SessionArc(duration: 1800)
        #expect(arc.betaEntranceEnd >= 60.0,
            "30-min: betaEntranceEnd should be ~90s (5% of 1800)")
        #expect(arc.alphaDescentEnd >= 300.0,
            "30-min: alphaDescentEnd should be ~360s (20% of 1800)")
        #expect(arc.emergenceDuration >= 60.0,
            "30-min: emergence must still be ≥60s")
    }

    @Test func allBoundariesAreWithinDuration() {
        for duration in [120.0, 300.0, 1800.0, 3600.0] {
            let arc = SessionArc(duration: duration)
            for (name, value) in [
                ("betaEntranceEnd", arc.betaEntranceEnd),
                ("alphaDescentEnd", arc.alphaDescentEnd),
                ("thetaInductionEnd", arc.thetaInductionEnd),
                ("deepHoldEnd", arc.deepHoldEnd),
                ("emergenceStart", arc.emergenceStart)
            ] {
                #expect(value <= duration,
                    "\(duration)s: \(name) (\(value)s) exceeds session duration")
                #expect(value >= 0,
                    "\(duration)s: \(name) (\(value)s) is negative")
            }
        }
    }
}

// MARK: - generateHypnosisFromDuration arc alignment

@MainActor
struct HypnosisFromDurationArcTests {

    private let gen = SessionGenerator()
    private let config = SessionGenerator.GenerationConfig.default

    @Test func fiveMinuteSessionMomentsAreSortedByTime() {
        let moments = gen.generateHypnosisFromDuration(duration: 300, config: config)
        let times = moments.map(\.time)
        #expect(times == times.sorted(), "Moments must be sorted ascending by time")
    }

    @Test func fiveMinuteSessionFirstMomentAtZero() {
        let moments = gen.generateHypnosisFromDuration(duration: 300, config: config)
        #expect(moments.first?.time == 0, "First moment must be at t=0")
    }

    @Test func fiveMinuteSessionLastMomentWithinDuration() {
        let moments = gen.generateHypnosisFromDuration(duration: 300, config: config)
        #expect((moments.last?.time ?? 0) <= 300,
            "Last moment must not exceed session duration")
    }

    @Test func thirtyMinuteSessionLastMomentWithinDuration() {
        let moments = gen.generateHypnosisFromDuration(duration: 1800, config: config)
        #expect((moments.last?.time ?? 0) <= 1800)
    }

    @Test func allFrequenciesInValidRange() {
        for duration in [300.0, 1800.0] {
            let moments = gen.generateHypnosisFromDuration(duration: duration, config: config)
            for m in moments {
                #expect(m.frequency >= 0.5 && m.frequency <= 40.0,
                    "\(duration)s: frequency \(m.frequency) Hz out of valid range")
            }
        }
    }

    @Test func allIntensitiesInValidRange() {
        for duration in [300.0, 1800.0] {
            let moments = gen.generateHypnosisFromDuration(duration: duration, config: config)
            for m in moments {
                #expect(m.intensity >= 0.0 && m.intensity <= 1.0,
                    "\(duration)s: intensity \(m.intensity) out of [0, 1]")
            }
        }
    }

    @Test func fiveMinuteSessionHasReasonableMomentCount() {
        let moments = gen.generateHypnosisFromDuration(duration: 300, config: config)
        #expect(moments.count >= 6,
            "5-min session should have at least 6 moments, got \(moments.count)")
    }
}
