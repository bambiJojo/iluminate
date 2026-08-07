//
//  ThresholdChoreographyTests.swift
//  IlumionateTests
//

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

    @Test("Reduced motion is markedly shorter than the full arc")
    func reducedMotionIsShort() {
        #expect(reduced.totalDuration < 1.0)
        #expect(reduced.totalDuration < full.totalDuration)
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
}
