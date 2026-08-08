//
//  ThresholdControllerTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct ThresholdControllerTests {

    @Test("A controller that is allowed to run starts out presenting")
    func runsWhenAllowed() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        #expect(controller.isPresenting)
    }

    @Test("A suppressed controller never presents")
    func suppressedNeverPresents() {
        // VoiceOver lands here: the numeric countdown takes over instead.
        let controller = ThresholdController(isSuppressed: true, motion: .full)
        #expect(controller.isPresenting == false)
    }

    @Test("Skipping a running threshold moves it into the exit")
    func skipStartsExit() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        controller.skip(now: .now)
        #expect(controller.isExiting)
        #expect(controller.isPresenting)
    }

    @Test("Skipping twice is a no-op")
    func skipTwiceIsIgnored() {
        // Otherwise a double tap restarts the exit interpolation and stutters.
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        let start = Date.now
        controller.skip(now: start)
        let firstExit = controller.frame(at: start.addingTimeInterval(0.1))
        controller.skip(now: start.addingTimeInterval(0.1))
        #expect(controller.frame(at: start.addingTimeInterval(0.1)) == firstExit)
    }

    @Test("Finishing stops presentation")
    func finishStopsPresenting() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        controller.finish()
        #expect(controller.isPresenting == false)
    }

    @Test("Skipping after finishing is a no-op")
    func skipAfterFinishIsIgnored() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        controller.finish()
        controller.skip(now: .now)
        #expect(controller.isPresenting == false)
    }

    @Test("While running, the frame tracks elapsed time from the start date")
    func runningFrameTracksElapsed() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        let start = Date.now
        controller.begin(at: start)
        let choreography = ThresholdChoreography(motion: .full)
        #expect(controller.frame(at: start.addingTimeInterval(1.0))
                == choreography.frame(atElapsed: 1.0))
    }

    @Test("The exit interpolates from the frame captured at the moment of the tap")
    func exitInterpolatesFromCapturedFrame() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        let start = Date.now
        controller.begin(at: start)
        let tapTime = start.addingTimeInterval(1.0)
        let choreography = ThresholdChoreography(motion: .full)
        let captured = choreography.frame(atElapsed: 1.0)

        controller.skip(now: tapTime)

        #expect(controller.frame(at: tapTime) == captured)
        #expect(controller.frame(at: tapTime.addingTimeInterval(ThresholdChoreography.skipDuration))
                == choreography.frame(atElapsed: choreography.totalDuration))
    }

    @Test("Reduced motion controllers still honour the default arc duration")
    func reducedMotionUsesSameDurationAsFull() {
        // Reduced motion is no longer a fixed short arc: its hold absorbs
        // whatever duration was requested, just like Settle does for the
        // full arc, so both motions share the same timing contract.
        let controller = ThresholdController(isSuppressed: false, motion: .reduced)
        #expect(controller.totalDuration == ThresholdChoreography(motion: .full).totalDuration)
    }

    // MARK: - Suppression

    @Test("The numeric-countdown preference mirrors the platform's VoiceOver state")
    func prefersNumericCountdownMirrorsVoiceOver() {
        // At session entry the countdown's numerals carry information a
        // screen reader user needs, so VoiceOver running is now the sole
        // trigger for falling back to it — unlike the old launch-time
        // suppression rules (first launch, unconditional VoiceOver skip),
        // this one has a single, testable source of truth.
        #expect(ThresholdController.prefersNumericCountdown == PlatformAccessibility.isVoiceOverRunning)
    }
}
