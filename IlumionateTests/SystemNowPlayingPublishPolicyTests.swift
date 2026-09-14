//
//  SystemNowPlayingPublishPolicyTests.swift
//  IlumionateTests
//
//  The player pushes Now Playing state on every UI tick. These pin the rule
//  that keeps steady playback from rebuilding the MediaPlayer dictionary
//  4–10 times a second, without letting a real change go unpublished.
//

import Testing
import Foundation
@testable import Ilumionate

@Suite("System Now Playing publish policy")
struct SystemNowPlayingPublishPolicyTests {

    private func state(
        title: String = "Session",
        isPlaying: Bool = true,
        currentTime: TimeInterval = 0,
        duration: TimeInterval = 600
    ) -> SystemNowPlayingPublishPolicy.State {
        .init(title: title, isPlaying: isPlaying, currentTime: currentTime, duration: duration)
    }

    @Test("The first update always publishes")
    func firstUpdatePublishes() {
        var policy = SystemNowPlayingPublishPolicy()

        let published = policy.shouldPublish(state(), at: 100)
        #expect(published)
    }

    @Test("Steady playback is skipped because the system extrapolates it")
    func steadyPlaybackIsSkipped() {
        var policy = SystemNowPlayingPublishPolicy()
        _ = policy.shouldPublish(state(currentTime: 10), at: 100)

        // Five seconds later, the position advanced by exactly five seconds.
        let published = policy.shouldPublish(state(currentTime: 15), at: 105)
        #expect(!published)
    }

    @Test("A seek publishes because position jumped off the extrapolation")
    func seekPublishes() {
        var policy = SystemNowPlayingPublishPolicy()
        _ = policy.shouldPublish(state(currentTime: 10), at: 100)

        // One second later the user scrubbed to 4:00 instead of reaching 0:11.
        let published = policy.shouldPublish(state(currentTime: 240), at: 101)
        #expect(published)
    }

    @Test("A backwards seek publishes")
    func backwardSeekPublishes() {
        var policy = SystemNowPlayingPublishPolicy()
        _ = policy.shouldPublish(state(currentTime: 100), at: 100)

        let published = policy.shouldPublish(state(currentTime: 85), at: 101)
        #expect(published)
    }

    @Test("Pausing publishes even at the same position")
    func pauseStateChangePublishes() {
        var policy = SystemNowPlayingPublishPolicy()
        _ = policy.shouldPublish(state(currentTime: 10), at: 100)

        let published = policy.shouldPublish(state(isPlaying: false, currentTime: 10), at: 100)
        #expect(published)
    }

    @Test("A paused session does not drift, so repeats are skipped")
    func pausedRepeatsAreSkipped() {
        var policy = SystemNowPlayingPublishPolicy()
        _ = policy.shouldPublish(state(isPlaying: false, currentTime: 30), at: 100)

        // Time passes but a paused player has not moved.
        let published = policy.shouldPublish(state(isPlaying: false, currentTime: 30), at: 160)
        #expect(!published)
    }

    @Test("A different title publishes")
    func titleChangePublishes() {
        var policy = SystemNowPlayingPublishPolicy()
        _ = policy.shouldPublish(state(title: "First", currentTime: 10), at: 100)

        let published = policy.shouldPublish(state(title: "Second", currentTime: 10), at: 100)
        #expect(published)
    }

    @Test("A different duration publishes")
    func durationChangePublishes() {
        var policy = SystemNowPlayingPublishPolicy()
        _ = policy.shouldPublish(state(currentTime: 10, duration: 600), at: 100)

        let published = policy.shouldPublish(state(currentTime: 10, duration: 900), at: 100)
        #expect(published)
    }

    @Test("Reset makes the next identical update publish again")
    func resetForcesRepublish() {
        var policy = SystemNowPlayingPublishPolicy()
        _ = policy.shouldPublish(state(currentTime: 10), at: 100)
        let beforeReset = policy.shouldPublish(state(currentTime: 11), at: 101)
        #expect(!beforeReset)

        policy.reset()

        let afterReset = policy.shouldPublish(state(currentTime: 11), at: 101)
        #expect(afterReset)
    }

    @Test("Drift is measured against the extrapolation, not the last raw value")
    func driftIsMeasuredAgainstExtrapolation() {
        var policy = SystemNowPlayingPublishPolicy()
        _ = policy.shouldPublish(state(currentTime: 0), at: 100)

        // A full minute of ordinary playback: the raw delta is 60s, but the
        // extrapolated position matches, so this must not publish.
        let published = policy.shouldPublish(state(currentTime: 60), at: 160)
        #expect(!published)
    }

    @Test("A skipped update does not become the new baseline")
    func skippedUpdateDoesNotMoveTheBaseline() {
        var policy = SystemNowPlayingPublishPolicy()
        _ = policy.shouldPublish(state(currentTime: 0), at: 100)
        let steady = policy.shouldPublish(state(currentTime: 1), at: 101)
        #expect(!steady)

        // Still on the original baseline, so a 6s jump from it is a seek.
        let afterJump = policy.shouldPublish(state(currentTime: 6), at: 102)
        #expect(afterJump)
    }
}
