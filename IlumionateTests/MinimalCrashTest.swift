//
//  MinimalCrashTest.swift
//  IlumionateTests
//
//  Minimal test to isolate crash
//

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct MinimalCrashTest {

    @Test func justCreateLightEngine() {
        let engine = LightEngine()
        #expect(engine != nil)
        print("✅ LightEngine created successfully")
    }

    @Test func lightEngineStartWithoutCrash() {
        let engine = LightEngine()
        print("Starting LightEngine...")
        engine.start()
        print("LightEngine started: \(engine.isRunning)")
        #expect(engine.isRunning)

        engine.stop()
        print("LightEngine stopped: \(!engine.isRunning)")
    }

    @Test func createSessionPlayerView() {
        let session = LightSession(
            session_name: "Minimal Test",
            duration_sec: 10,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)
            ]
        )
        let engine = LightEngine()

        print("Creating SessionPlayerView...")
        let view = SessionPlayerView(session: session, engine: engine)
        print("✅ SessionPlayerView created successfully")
        #expect(view.session.displayName == "Minimal Test")
    }

    // createTherapeuticColors removed — TherapeuticColors no longer in main target
}