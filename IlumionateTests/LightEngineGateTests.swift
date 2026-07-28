//  LightEngineGateTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct LightEngineGateTests {

    @Test func engineDrivesOutputWhenStartedAndEnabled() {
        let engine = LightEngine()
        engine.start()

        #expect(engine.isRunning)
        #expect(engine.isDrivingOutput)

        engine.stop()
    }

    @Test func disablingGateStopsOutputButKeepsRunningIntent() {
        let engine = LightEngine()
        engine.start()

        engine.mindMachineEnabled = false

        #expect(engine.isRunning)             // intent preserved
        #expect(engine.isDrivingOutput == false)
        #expect(engine.brightness == 0)
        #expect(engine.brightnessLeft == 0)
        #expect(engine.brightnessRight == 0)

        engine.stop()
    }

    @Test func reEnablingGateResumesOutput() {
        let engine = LightEngine()
        engine.start()
        engine.mindMachineEnabled = false

        engine.mindMachineEnabled = true

        #expect(engine.isRunning)
        #expect(engine.isDrivingOutput)

        engine.stop()
    }

    @Test func enablingGateWhileStoppedDoesNotStartOutput() {
        let engine = LightEngine()
        engine.mindMachineEnabled = false

        engine.mindMachineEnabled = true

        #expect(engine.isRunning == false)
        #expect(engine.isDrivingOutput == false)
    }

    @Test func startingWhileGatedDoesNotDriveOutput() {
        let engine = LightEngine()
        engine.mindMachineEnabled = false

        engine.start()

        #expect(engine.isRunning)
        #expect(engine.isDrivingOutput == false)

        engine.stop()
    }

    @Test func stopClearsOutputRegardlessOfGate() {
        let engine = LightEngine()
        engine.start()

        engine.stop()

        #expect(engine.isRunning == false)
        #expect(engine.isDrivingOutput == false)
        #expect(engine.brightness == 0)
    }

    @Test func outputIsSuspendedWhileTheDrivingScoreIsPaused() {
        let engine = LightEngine()
        let player = makePlayer()

        engine.attachSession(player: player)
        engine.start()
        player.play()

        #expect(engine.isOutputSuspended == false)

        // What .audioLight and .playlist do on pause: they pause the score
        // player but never tell the engine. Output must stop anyway.
        player.pause()
        #expect(engine.isOutputSuspended)

        player.play()
        #expect(engine.isOutputSuspended == false)

        engine.stop()
    }

    @Test func outputIsSuspendedForAnAttachedScoreThatHasNotStarted() {
        let engine = LightEngine()
        engine.attachSession(player: makePlayer())
        engine.start()

        #expect(engine.isOutputSuspended)

        engine.stop()
    }

    @Test func outputIsSuspendedAfterTheScoreStops() {
        let engine = LightEngine()
        let player = makePlayer()
        engine.attachSession(player: player)
        engine.start()
        player.play()

        player.stop()
        #expect(engine.isOutputSuspended)

        engine.stop()
    }

    @Test func explicitEnginePauseStillSuspendsOutput() {
        let engine = LightEngine()
        let player = makePlayer()
        engine.attachSession(player: player)
        engine.start()
        player.play()

        engine.pause()
        #expect(engine.isOutputSuspended)

        engine.resume()
        #expect(engine.isOutputSuspended == false)

        engine.stop()
    }

    /// Manual / preview usage drives the engine with no score attached and must
    /// keep emitting — only an attached-but-idle score suspends output.
    @Test func manualDrivingWithoutAScoreIsNotSuspended() {
        let engine = LightEngine()
        engine.start()

        #expect(engine.isOutputSuspended == false)

        engine.stop()
    }

    private func makePlayer(duration: Double = 300) -> LightScorePlayer {
        LightScorePlayer(session: LightSession(
            session_name: "Pause Test",
            duration_sec: duration,
            light_score: [LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)]
        ))
    }

    @Test func attachingSessionWhileGatedDoesNotArmOutput() {
        let engine = LightEngine()
        let session = LightSession(
            session_name: "Gated",
            duration_sec: 60,
            light_score: [LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)]
        )
        engine.start()
        engine.mindMachineEnabled = false

        engine.attachSession(player: LightScorePlayer(session: session))

        #expect(engine.isDrivingOutput == false)

        engine.stop()
    }
}
