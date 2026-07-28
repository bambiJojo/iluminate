//  LightScorePlayerClockTests.swift
//  IlumionateTests

import Foundation
import QuartzCore
import Testing
@testable import Ilumionate

@MainActor
struct LightScorePlayerClockTests {

    /// A manually advanced clock so timing is deterministic — no sleeps.
    final class TestClock {
        private(set) var value: CFTimeInterval = 1_000
        func advance(_ seconds: CFTimeInterval) { value += seconds }
        var read: () -> CFTimeInterval { { self.value } }
    }

    private func makePlayer(duration: Double = 300, clock: TestClock) -> LightScorePlayer {
        let session = LightSession(
            session_name: "Clock Test",
            duration_sec: duration,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine),
                LightMoment(time: duration, frequency: 6, intensity: 0.8, waveform: .sine)
            ]
        )
        return LightScorePlayer(session: session, now: clock.read)
    }

    @Test func currentTimeAdvancesWithTheClockWhilePlaying() {
        let clock = TestClock()
        let player = makePlayer(clock: clock)

        player.play()
        clock.advance(60)

        #expect(abs(player.currentTime - 60) < 0.001)
        #expect(player.isPlaying)
    }

    /// Regression test for the stale-anchor bug: with no tick source running,
    /// pause must still capture the correct position.
    @Test func pauseCapturesPositionWithoutAnyTickSource() {
        let clock = TestClock()
        let player = makePlayer(clock: clock)

        player.play()
        clock.advance(300 - 60)   // 4 minutes of untracked playback
        player.pause()

        #expect(abs(player.currentTime - 240) < 0.001)

        clock.advance(45)         // paused for 45 seconds
        #expect(abs(player.currentTime - 240) < 0.001)
    }

    @Test func playAfterPauseResumesFromHeldOffset() {
        let clock = TestClock()
        let player = makePlayer(clock: clock)

        player.play()
        clock.advance(240)
        player.pause()
        clock.advance(45)
        player.play()
        clock.advance(10)

        #expect(abs(player.currentTime - 250) < 0.001)
    }

    @Test func seekWhileRunningReAnchors() {
        let clock = TestClock()
        let player = makePlayer(clock: clock)

        player.play()
        clock.advance(100)
        player.seek(to: 30)
        clock.advance(5)

        #expect(abs(player.currentTime - 35) < 0.001)
        #expect(player.isPlaying)
    }

    @Test func seekWhileIdleStoresPositionWithoutStartingTheClock() {
        let clock = TestClock()
        let player = makePlayer(clock: clock)

        player.seek(to: 30)
        clock.advance(5)

        #expect(abs(player.currentTime - 30) < 0.001)
        #expect(player.isPlaying == false)
    }

    @Test func currentTimeClampsToDuration() {
        let clock = TestClock()
        let player = makePlayer(duration: 100, clock: clock)

        player.play()
        clock.advance(500)

        #expect(abs(player.currentTime - 100) < 0.001)
        #expect(player.isComplete)
        #expect(player.isPlaying == false)
    }

    @Test func isCompleteUnlatchesAfterSeekingBackwards() {
        let clock = TestClock()
        let player = makePlayer(duration: 100, clock: clock)

        player.play()
        clock.advance(500)
        #expect(player.isComplete)

        player.seek(to: 20)
        #expect(player.isComplete == false)
        #expect(abs(player.currentTime - 20) < 0.001)
    }

    @Test func stopReturnsToZeroAndNotPlaying() {
        let clock = TestClock()
        let player = makePlayer(clock: clock)

        player.play()
        clock.advance(120)
        player.stop()

        #expect(player.currentTime == 0)
        #expect(player.isPlaying == false)
        #expect(player.isComplete == false)
    }
}
