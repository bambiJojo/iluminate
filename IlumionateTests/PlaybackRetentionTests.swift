//
//  PlaybackRetentionTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct PlaybackRetentionTests {

    @Test func timedFlashPresetExposesItsGoal() {
        let mode = PlayerMode.flashMode(
            frequency: 10,
            intensity: 0.75,
            colorTemperature: 4_000,
            pattern: .sine,
            binauralEnabled: true,
            binauralCarrier: 200,
            binauralVolume: 0.5,
            goalDuration: 10 * 60
        )

        #expect(mode.goalDuration == 600)
        #expect(mode.hasFiniteDuration)
    }

    @Test func untimedMindMachineSessionRemainsOpenEnded() {
        let mode = PlayerMode.flashMode(
            frequency: 10,
            intensity: 0.75,
            colorTemperature: 4_000,
            pattern: .sine,
            binauralEnabled: false,
            binauralCarrier: 200,
            binauralVolume: 0.5
        )

        #expect(mode.goalDuration == nil)
        #expect(mode.hasFiniteDuration == false)
    }

    @Test(arguments: [
        (PlaybackState.playing, PlaybackInterruptionAction.pause),
        (PlaybackState.countdown, PlaybackInterruptionAction.cancelPendingStart),
        (PlaybackState.paused, PlaybackInterruptionAction.none),
        (PlaybackState.complete, PlaybackInterruptionAction.none),
        (PlaybackState.idle, PlaybackInterruptionAction.none),
    ])
    func interruptionActionPreservesIntent(_ pair: (PlaybackState, PlaybackInterruptionAction)) {
        #expect(PlaybackRetentionPolicy.interruptionAction(for: pair.0) == pair.1)
    }

    @Test func finitePlaybackCompletesWithinEndTolerance() {
        #expect(PlaybackRetentionPolicy.hasReachedEnd(
            currentTime: 599.6,
            duration: 600,
            state: .playing
        ))
    }

    @Test(arguments: [
        (599.4, 600.0, PlaybackState.playing),
        (600.0, 600.0, PlaybackState.paused),
        (10.0, 0.0, PlaybackState.playing),
    ])
    func playbackDoesNotCompletePrematurely(_ values: (TimeInterval, TimeInterval, PlaybackState)) {
        #expect(PlaybackRetentionPolicy.hasReachedEnd(
            currentTime: values.0,
            duration: values.1,
            state: values.2
        ) == false)
    }
}
