//
//  ReaderVisualModulatorTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct ReaderVisualModulatorTests {

    @Test("Speed never leaves the safe band, for any phase at any pace")
    func speedAlwaysInBand() {
        for phase in TrancePhase.allCases {
            for multiplier in [-10.0, 0.0, 0.25, 1.0, 4.0, 1_000.0] {
                let m = ReaderVisualModulator.modulation(
                    for: phase, speedMultiplier: multiplier, reduceMotion: false
                )
                #expect(ReaderVisualModulator.speedBand.contains(m.speed))
            }
        }
    }

    @Test("Amplitude never leaves its band")
    func amplitudeAlwaysInBand() {
        for phase in TrancePhase.allCases {
            let m = ReaderVisualModulator.modulation(
                for: phase, speedMultiplier: 1.0, reduceMotion: false
            )
            #expect(ReaderVisualModulator.amplitudeBand.contains(m.amplitude))
        }
    }

    @Test("Reduce Motion pins speed to zero for every phase")
    func reduceMotionFreezes() {
        for phase in TrancePhase.allCases {
            let m = ReaderVisualModulator.modulation(
                for: phase, speedMultiplier: 2.0, reduceMotion: true
            )
            #expect(m.speed == 0)
        }
    }

    @Test("Reduce Motion still reports the phase tint")
    func reduceMotionKeepsTint() {
        let m = ReaderVisualModulator.modulation(
            for: .deepening, speedMultiplier: 1.0, reduceMotion: true
        )
        #expect(m.tint == Color.phaseDeepener)
    }

    @Test("Amplitude deepens through the arc and eases off at emergence")
    func amplitudeFollowsTheArc() {
        func amp(_ phase: TrancePhase) -> Double {
            ReaderVisualModulator.modulation(
                for: phase, speedMultiplier: 1.0, reduceMotion: false
            ).amplitude
        }
        #expect(amp(.preTalk) < amp(.induction))
        #expect(amp(.induction) < amp(.deepening))
        #expect(amp(.deepening) < amp(.fractionation))
        #expect(amp(.emergence) < amp(.deepening))
    }

    @Test("Amplitude ordering pins the whole depth table, not just a few phases")
    func amplitudeOrderingCoversEveryPhase() {
        func amp(_ phase: TrancePhase) -> Double {
            ReaderVisualModulator.modulation(
                for: phase, speedMultiplier: 1.0, reduceMotion: false
            ).amplitude
        }
        // Every phase, in intended ascending depth order. Because amplitude is
        // monotonic in depth, asserting this order pins all 12 table entries —
        // band-membership alone cannot, since the modulator clamps regardless.
        let ascendingDepth: [TrancePhase] = [
            .preTalk, .emergence, .induction, .transitional,
            .suggestions, .therapy, .eroticSuggestions, .conditioning,
            .deepening, .brainwashing, .confusion, .fractionation
        ]
        let amplitudes = ascendingDepth.map(amp)
        #expect(amplitudes == amplitudes.sorted())
        // Two deliberate ties (suggestions/therapy, eroticSuggestions/conditioning)
        // leave 10 distinct values. A collapsed or duplicated row breaks this.
        #expect(Set(amplitudes).count == 10)
    }

    @Test("A faster reading pace yields a faster visual")
    func paceRaisesSpeed() {
        let slow = ReaderVisualModulator.modulation(
            for: .deepening, speedMultiplier: 0.5, reduceMotion: false
        )
        let fast = ReaderVisualModulator.modulation(
            for: .deepening, speedMultiplier: 2.0, reduceMotion: false
        )
        #expect(fast.speed > slow.speed)
    }

    @Test("Tint comes from the shared phase table")
    func tintMatchesPhase() {
        let m = ReaderVisualModulator.modulation(
            for: .emergence, speedMultiplier: 1.0, reduceMotion: false
        )
        #expect(m.tint == TrancePhase.emergence.atmosphereColor)
    }
}
