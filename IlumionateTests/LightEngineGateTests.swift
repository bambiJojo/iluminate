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
