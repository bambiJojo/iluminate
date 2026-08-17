//
//  ThresholdChoreographyTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct ThresholdChoreographyTests {

    private let full = ThresholdChoreography(motion: .full)
    private let reduced = ThresholdChoreography(motion: .reduced)

    // MARK: - Arrival

    @Test("The arc opens with the orb invisible and the vignette wide open")
    func arrivalStart() {
        let frame = full.frame(atElapsed: 0)
        #expect(frame.orbOpacity == 0)
        #expect(frame.vignetteClosure == 0)
        #expect(frame.auroraOpacity == 0)
    }

    @Test("Arrival closes the vignette from the edges")
    func arrivalClosesVignette() {
        // The periphery — where the cluttered phone was — darkens first.
        let samples = stride(from: 0.0, through: 0.5, by: 0.05)
            .map { full.frame(atElapsed: $0).vignetteClosure }
        for (earlier, later) in zip(samples, samples.dropFirst()) {
            #expect(later >= earlier)
        }
        #expect(full.frame(atElapsed: 0.5).vignetteClosure == 1)
    }

    // MARK: - Bloom

    @Test("Bloom is the only beat where the orb grows")
    func bloomGrows() {
        // A spinner never grows. One unrepeated expansion is the clearest
        // available signal that this arc has a beginning.
        let samples = stride(from: 0.5, through: 1.6, by: 0.05)
            .map { full.frame(atElapsed: $0).orbScale }
        for (earlier, later) in zip(samples, samples.dropFirst()) {
            #expect(later > earlier)
        }
        #expect(abs(full.frame(atElapsed: 0.5).orbScale - 0.6) < 0.0001)
        #expect(abs(full.frame(atElapsed: 1.6).orbScale - 1.0) < 0.0001)
    }

    // MARK: - Settle

    @Test("Settle holds the choreographed scale perfectly flat")
    func settleIsFlat() {
        // The plateau is the point. The eye reads a flat stretch as an ending
        // rather than a wait — this is the beat a loading indicator lacks.
        for elapsed in stride(from: 1.6, through: 2.2, by: 0.05) {
            #expect(abs(full.frame(atElapsed: elapsed).orbScale - 1.0) < 0.0001)
        }
    }

    // MARK: - Opening

    @Test("Opening clears the orb and releases the vignette")
    func openingClears() {
        let frame = full.frame(atElapsed: full.totalDuration)
        #expect(frame.orbOpacity == 0)
        #expect(frame.vignetteClosure == 0)
    }

    @Test("Opening lifts the orb outward as it fades")
    func openingLifts() {
        // Scaling up while fading reads as the field opening, not the orb leaving.
        #expect(full.frame(atElapsed: 2.4).orbScale > 1.0)
        #expect(full.frame(atElapsed: full.totalDuration).orbScale > 1.0)
    }

    @Test("The aurora never fades out, including on the final frame")
    func auroraHolds() {
        // The threshold's aurora is the same field Home is already drawing
        // underneath. Fading it during Opening would darken the screen and
        // force Home's copy to fade back in — the exact seam this avoids.
        for elapsed in stride(from: 1.6, through: full.totalDuration, by: 0.05) {
            #expect(full.frame(atElapsed: elapsed).auroraOpacity == 1)
        }
        #expect(full.frame(atElapsed: full.totalDuration).auroraOpacity == 1)
    }

    // MARK: - Clamping

    @Test("Elapsed past the end clamps to the final frame")
    func clampsPastEnd() {
        #expect(full.frame(atElapsed: full.totalDuration * 2)
                == full.frame(atElapsed: full.totalDuration))
    }

    @Test("Negative elapsed clamps to the first frame")
    func clampsBeforeStart() {
        #expect(full.frame(atElapsed: -1) == full.frame(atElapsed: 0))
    }

    // MARK: - Reduce Motion

    @Test("Reduced motion pins the orb scale at rest")
    func reducedMotionDoesNotScale() {
        for elapsed in stride(from: 0.0, through: reduced.totalDuration, by: 0.05) {
            #expect(reduced.frame(atElapsed: elapsed).orbScale == 1.0)
        }
    }

    @Test("Reduced motion never travels the vignette")
    func reducedMotionHasNoVignette() {
        for elapsed in stride(from: 0.0, through: reduced.totalDuration, by: 0.05) {
            #expect(reduced.frame(atElapsed: elapsed).vignetteClosure == 0)
        }
    }

    @Test("Reduced motion still fades the orb in and back out")
    func reducedMotionFades() {
        #expect(reduced.frame(atElapsed: 0).orbOpacity == 0)
        #expect(reduced.frame(atElapsed: 0.5).orbOpacity == 1)
        #expect(reduced.frame(atElapsed: reduced.totalDuration).orbOpacity == 0)
    }

    @Test("Reduced motion matches whatever total duration was requested, not a fixed short arc")
    func reducedMotionMatchesRequestedDuration() {
        // The old launch-only arc was fixed short. At session entry the hold
        // must absorb the user's configured duration exactly as Settle does
        // for the full arc, so both motions honour the same timing contract.
        #expect(reduced.totalDuration == full.totalDuration)
        #expect(ThresholdChoreography(motion: .reduced, duration: 7).totalDuration == 7)
    }

    @Test("Reduced motion also holds the aurora up")
    func reducedMotionHoldsAurora() {
        #expect(reduced.frame(atElapsed: reduced.totalDuration).auroraOpacity == 1)
    }

    // MARK: - Skip

    @Test("A skip that runs to completion lands on the resting frame")
    func skipLandsAtRest() {
        let midBloom = full.frame(atElapsed: 1.0)
        #expect(full.exitFrame(from: midBloom, progress: 1)
                == full.frame(atElapsed: full.totalDuration))
    }

    @Test("A skip begins from exactly where the arc was")
    func skipStartsWhereItWas() {
        // Easing out from the current frame is what stops a skip snapping.
        let midBloom = full.frame(atElapsed: 1.0)
        #expect(full.exitFrame(from: midBloom, progress: 0) == midBloom)
    }

    @Test("Skip progress is clamped at both ends")
    func skipClamps() {
        let midBloom = full.frame(atElapsed: 1.0)
        #expect(full.exitFrame(from: midBloom, progress: -0.5) == midBloom)
        #expect(full.exitFrame(from: midBloom, progress: 2)
                == full.exitFrame(from: midBloom, progress: 1))
    }

    // MARK: - Duration scaling

    @Test("The default duration reproduces the previously-pinned 2.6s arc")
    func defaultDurationMatchesExplicit2_6() {
        let explicit = ThresholdChoreography(motion: .full, duration: 2.6)
        #expect(full.totalDuration == 2.6)
        for elapsed in stride(from: 0.0, through: full.totalDuration, by: 0.1) {
            #expect(full.frame(atElapsed: elapsed) == explicit.frame(atElapsed: elapsed))
        }
    }

    @Test("Settle absorbs all extra duration at 10s while Arrival, Bloom and Opening keep their absolute lengths")
    func settleAbsorbsExtraDurationAtTenSeconds() {
        let long = ThresholdChoreography(motion: .full, duration: 10)
        #expect(long.totalDuration == 10)

        // Arrival and Bloom land at the same absolute instants as the default arc.
        #expect(long.frame(atElapsed: 0.5).vignetteClosure == full.frame(atElapsed: 0.5).vignetteClosure)
        #expect(abs(long.frame(atElapsed: 1.6).orbScale - 1.0) < 0.0001)

        // Settle now runs from 1.6s to 9.6s: nearly 8s of held plateau.
        for elapsed in stride(from: 1.6, through: 9.6, by: 0.5) {
            #expect(abs(long.frame(atElapsed: elapsed).orbScale - 1.0) < 0.0001)
        }

        // Opening still takes exactly the final 0.4s.
        #expect(abs(long.frame(atElapsed: 9.6).orbScale - 1.0) < 0.0001)
        #expect(long.frame(atElapsed: 9.6).vignetteClosure == 1)
        #expect(long.frame(atElapsed: 10).orbOpacity == 0)
        #expect(long.frame(atElapsed: 10).vignetteClosure == 0)
    }

    @Test("Bloom ends 1.6s in regardless of the requested duration", arguments: [2.6, 3.0, 7.0, 10.0])
    func bloomEndsAtFixedAbsoluteTime(duration: TimeInterval) {
        let choreography = ThresholdChoreography(motion: .full, duration: duration)
        #expect(abs(choreography.frame(atElapsed: 1.6).orbScale - 1.0) < 0.0001)
        #expect(choreography.frame(atElapsed: 1.59).orbScale < 1.0)
    }

    @Test("Opening always occupies exactly the final 0.4s", arguments: [2.6, 3.0, 7.0, 10.0])
    func openingOccupiesFinalFourTenths(duration: TimeInterval) {
        let choreography = ThresholdChoreography(motion: .full, duration: duration)
        let openingStart = duration - 0.4

        // Still flat immediately before Opening begins.
        #expect(abs(choreography.frame(atElapsed: openingStart).orbScale - 1.0) < 0.0001)
        #expect(choreography.frame(atElapsed: openingStart).vignetteClosure == 1)

        // Fully open by the end.
        #expect(choreography.frame(atElapsed: duration).orbOpacity == 0)
        #expect(choreography.frame(atElapsed: duration).vignetteClosure == 0)
    }

    @Test("Orb scale peaks at exactly 1.0 as Bloom hands off to Settle", arguments: [2.6, 3.0, 7.0, 10.0])
    func scalePeaksEnteringSettle(duration: TimeInterval) {
        let choreography = ThresholdChoreography(motion: .full, duration: duration)
        let samples = stride(from: 0.0, through: 1.6, by: 0.1)
            .map { choreography.frame(atElapsed: $0).orbScale }
        #expect(samples.allSatisfy { $0 <= 1.0 + 0.0001 })
        #expect(abs((samples.last ?? 0) - 1.0) < 0.0001)
    }

    @Test("The aurora holds at 1 through Settle and Opening at every duration", arguments: [2.6, 3.0, 7.0, 10.0])
    func auroraHoldsAtEveryDuration(duration: TimeInterval) {
        let choreography = ThresholdChoreography(motion: .full, duration: duration)
        for elapsed in stride(from: 1.6, through: duration, by: max(0.1, duration / 20)) {
            #expect(choreography.frame(atElapsed: elapsed).auroraOpacity == 1)
        }
        #expect(choreography.frame(atElapsed: duration).auroraOpacity == 1)
    }

    @Test("Reduced motion absorbs extra duration in the hold, matching the requested total")
    func reducedMotionAbsorbsDurationInHold() {
        let long = ThresholdChoreography(motion: .reduced, duration: 10)
        #expect(long.totalDuration == 10)
        for elapsed in stride(from: 0.0, through: 10, by: 0.5) {
            #expect(long.frame(atElapsed: elapsed).orbScale == 1.0)
        }
        // Held flat through the middle of the budget.
        #expect(long.frame(atElapsed: 5.0).orbOpacity == 1)
    }

    // MARK: - Degenerate short duration

    @Test("A duration under the floor clamps up to the natural 2.6s arc instead of inverting")
    func degenerateShortDurationClampsForFullMotion() {
        let tooShort = ThresholdChoreography(motion: .full, duration: 1.0)
        #expect(tooShort.totalDuration == 2.6)
        for elapsed in stride(from: 0.0, through: 2.6, by: 0.1) {
            #expect(tooShort.frame(atElapsed: elapsed) == full.frame(atElapsed: elapsed))
        }
    }

    @Test("A degenerately short duration also clamps for reduced motion")
    func degenerateShortDurationClampsForReducedMotion() {
        let tooShort = ThresholdChoreography(motion: .reduced, duration: 0.2)
        #expect(tooShort.totalDuration == 0.9)
    }

    @Test("Zero and negative durations do not invert the arc")
    func nonPositiveDurationsClampSafely() {
        #expect(ThresholdChoreography(motion: .full, duration: 0).totalDuration == 2.6)
        #expect(ThresholdChoreography(motion: .full, duration: -5).totalDuration == 2.6)
    }
}
