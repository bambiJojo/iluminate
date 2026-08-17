//
//  VisualFieldFadeTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct VisualFieldFadeTests {

    @Test("An open-ended session never fades")
    func openEndedNeverFades() {
        for elapsed in [0.0, 60.0, 3_600.0, 86_400.0] {
            #expect(VisualFieldFade.multiplier(elapsed: elapsed, duration: nil) == 1)
        }
    }

    @Test("A timed session holds full strength until the fade window opens")
    func fullStrengthBeforeTheWindow() {
        #expect(VisualFieldFade.multiplier(elapsed: 0, duration: 600) == 1)
        #expect(VisualFieldFade.multiplier(elapsed: 300, duration: 600) == 1)
        // The window is the last 20 seconds, so 579 is still outside it.
        #expect(VisualFieldFade.multiplier(elapsed: 579, duration: 600) == 1)
    }

    @Test("The fade runs to zero across the window")
    func fadesAcrossTheWindow() {
        let half = VisualFieldFade.multiplier(elapsed: 590, duration: 600)
        #expect(half > 0.4)
        #expect(half < 0.6)
        #expect(VisualFieldFade.multiplier(elapsed: 600, duration: 600) == 0)
    }

    @Test("Past the end it stays at zero rather than going negative")
    func clampsPastTheEnd() {
        #expect(VisualFieldFade.multiplier(elapsed: 900, duration: 600) == 0)
    }

    @Test("The fade decreases monotonically")
    func monotonic() {
        var previous = 1.0
        for elapsed in stride(from: 0.0, through: 600.0, by: 5.0) {
            let value = VisualFieldFade.multiplier(elapsed: elapsed, duration: 600)
            #expect(value <= previous + 0.0001)
            previous = value
        }
    }

    @Test("A duration shorter than the window still starts at full strength")
    func shortSessionFadesFromTheStart() {
        #expect(VisualFieldFade.multiplier(elapsed: 0, duration: 10) == 1)
        #expect(VisualFieldFade.multiplier(elapsed: 10, duration: 10) == 0)
        let middle = VisualFieldFade.multiplier(elapsed: 5, duration: 10)
        #expect(middle > 0)
        #expect(middle < 1)
    }

    @Test("Nonsense input does not produce a NaN opacity")
    func hostileInput() {
        for value in [Double.nan, .infinity, -1] {
            #expect(VisualFieldFade.multiplier(elapsed: value, duration: 600).isFinite)
            #expect(VisualFieldFade.multiplier(elapsed: 100, duration: value).isFinite)
        }
    }

    @Test("A zero or negative duration is treated as open-ended, not as instantly over")
    func nonPositiveDurationIsOpenEnded() {
        #expect(VisualFieldFade.multiplier(elapsed: 5, duration: 0) == 1)
        #expect(VisualFieldFade.multiplier(elapsed: 5, duration: -60) == 1)
        #expect(VisualFieldFade.isComplete(elapsed: 5, duration: 0) == false)
    }

    @Test("The session is over exactly when its duration elapses")
    func completion() {
        #expect(VisualFieldFade.isComplete(elapsed: 599, duration: 600) == false)
        #expect(VisualFieldFade.isComplete(elapsed: 600, duration: 600))
        #expect(VisualFieldFade.isComplete(elapsed: 10_000, duration: nil) == false)
    }

    @Test("Completion and a zero multiplier agree")
    func completionAgreesWithFade() {
        // A session that reads as complete must not still be drawing a field.
        for elapsed in stride(from: 0.0, through: 700.0, by: 10.0) {
            if VisualFieldFade.isComplete(elapsed: elapsed, duration: 600) {
                #expect(VisualFieldFade.multiplier(elapsed: elapsed, duration: 600) == 0)
            }
        }
    }
}
