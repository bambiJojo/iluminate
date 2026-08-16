//
//  PlaybackRuntimeTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct PlaybackRuntimeTests {

    @Test("The controllerless runtime owns one coherent clock")
    func manualClockHonorsTransportState() {
        let runtime = ManualPlaybackRuntime(duration: 2, volume: 0.7)

        #expect(runtime.snapshot(elapsed: 1).currentTime == 0)

        runtime.begin()
        #expect(runtime.snapshot(elapsed: 0.5).currentTime == 0.5)

        runtime.pause()
        #expect(runtime.snapshot(elapsed: 1).currentTime == 0.5)

        runtime.seek(to: 1.5)
        runtime.resume()
        let completed = runtime.snapshot(elapsed: 0.6)
        #expect(completed.currentTime == 2)
        #expect(completed.hasReachedEnd)
    }

    @Test("Runtime volume and seeks are clamped at the Interface")
    func runtimeClampsInputs() {
        let runtime = ManualPlaybackRuntime(duration: 10, volume: 0.7)

        runtime.seek(to: 50)
        runtime.setVolume(2)
        let upper = runtime.snapshot(elapsed: 0)
        #expect(upper.currentTime == 10)
        #expect(upper.volume == 1)

        runtime.seek(to: -5)
        runtime.setVolume(-1)
        let lower = runtime.snapshot(elapsed: 0)
        #expect(lower.currentTime == 0)
        #expect(lower.volume == 0)
    }
}
