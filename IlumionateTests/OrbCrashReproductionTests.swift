//
//  OrbCrashReproductionTests.swift
//  IlumionateTests
//
//  Systematic crash reproduction and isolation tests
//

import Testing
import SwiftUI
@testable import Ilumionate

@MainActor
struct OrbCrashReproductionTests {

    @Test func isolateMinimalOrb() {
        print("🔬 CRASH TEST 1: Minimal Orb Creation")

        // Test 1: Just create AuraBackground without any engine
        print("   Step 1a: Creating AuraBackground...")
        let auraView = AuraBackground()
        print("   Step 1a: ✅ AuraBackground created successfully")

        // Test 1b: Render it (this might be where crash happens)
        print("   Step 1b: Attempting to render AuraBackground...")
        let hostingController = UIHostingController(rootView: auraView)
        print("   Step 1b: ✅ AuraBackground rendered successfully")

        print("🔬 CRASH TEST 1: ✅ PASSED - Basic orb creation works")
    }

    @Test func isolateSessionPlayerMinimal() {
        print("🔬 CRASH TEST 2: Minimal SessionPlayer")

        print("   Step 2a: Creating LightEngine...")
        let engine = LightEngine()
        print("   Step 2a: ✅ LightEngine created")

        print("   Step 2b: Creating minimal session...")
        let session = LightSession(
            session_name: "Crash Test Session",
            duration_sec: 10,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine),
                LightMoment(time: 10, frequency: 10, intensity: 0.0, waveform: .sine)
            ]
        )
        print("   Step 2b: ✅ Session created")

        print("   Step 2c: Creating SessionPlayerView...")
        let playerView = SessionPlayerView(session: session, engine: engine)
        print("   Step 2c: ✅ SessionPlayerView created")

        print("   Step 2d: Attempting to render SessionPlayerView...")
        let hostingController = UIHostingController(rootView: playerView)
        print("   Step 2d: ✅ SessionPlayerView rendered successfully")

        print("🔬 CRASH TEST 2: ✅ PASSED - Basic session player works")
    }

    @Test func isolateEngineStartup() {
        print("🔬 CRASH TEST 3: Engine Startup Isolation")

        let engine = LightEngine()

        print("   Step 3a: Engine initial state...")
        print("      isRunning: \(engine.isRunning)")
        print("      brightness: \(engine.brightness)")

        print("   Step 3b: Starting engine...")
        engine.start()

        print("   Step 3c: Engine after start...")
        print("      isRunning: \(engine.isRunning)")
        print("      brightness: \(engine.brightness)")

        // Let it run for a moment
        print("   Step 3d: Letting engine run for 100ms...")
        Thread.sleep(forTimeInterval: 0.1)

        print("   Step 3e: Engine after brief run...")
        print("      isRunning: \(engine.isRunning)")
        print("      brightness: \(engine.brightness)")
        print("      currentFrequency: \(engine.currentFrequency)")

        print("   Step 3f: Stopping engine...")
        engine.stop()

        print("   Step 3g: Engine after stop...")
        print("      isRunning: \(engine.isRunning)")
        print("      brightness: \(engine.brightness)")

        print("🔬 CRASH TEST 3: ✅ PASSED - Engine startup/shutdown works")
    }

    @Test func isolateColorCreation() {
        print("🔬 CRASH TEST 4: Color Creation Isolation")

        print("   Step 4a: Testing SafeColor.rgb...")
        let color1 = SafeColor.rgb(80/255, 40/255, 180/255, opacity: 0.22, context: "CrashTest_Color1")
        print("   Step 4a: ✅ SafeColor.rgb works")

        print("   Step 4b: Testing multiple color creation (simulating AuraBackground)...")
        let colors = [
            SafeColor.rgb(80/255, 40/255, 180/255, opacity: 0.22, context: "CrashTest_Batch1"),
            SafeColor.rgb(50/255, 20/255, 140/255, opacity: 0.16, context: "CrashTest_Batch2"),
            SafeColor.rgb(100/255, 40/255, 160/255, opacity: 0.2, context: "CrashTest_Batch3"),
            SafeColor.rgb(60/255, 20/255, 120/255, opacity: 0.15, context: "CrashTest_Batch4"),
            SafeColor.rgb(70/255, 30/255, 150/255, opacity: 0.12, context: "CrashTest_Batch5")
        ]
        print("   Step 4b: ✅ Multiple color creation works")

        print("   Step 4c: Testing RadialGradient creation...")
        let gradient = SafeColor.radialGradient(
            colors: colors,
            center: .center,
            startRadius: 50,
            endRadius: 800,
            context: "CrashTest_MainGradient"
        )
        print("   Step 4c: ✅ RadialGradient creation works")

        print("🔬 CRASH TEST 4: ✅ PASSED - Color creation works")
    }

    @Test func isolateFloatingBlobAnimation() {
        print("🔬 CRASH TEST 5: FloatingBlob Animation Isolation")

        print("   Step 5a: Creating single FloatingBlob...")
        let color = SafeColor.rgb(90/255, 45/255, 200/255, opacity: 0.35, context: "CrashTest_Blob")
        let blob = FloatingBlob(color: color, size: 350, duration: 22)
        print("   Step 5a: ✅ FloatingBlob created")

        print("   Step 5b: Rendering FloatingBlob...")
        let hostingController = UIHostingController(rootView: blob)
        print("   Step 5b: ✅ FloatingBlob rendered")

        print("🔬 CRASH TEST 5: ✅ PASSED - FloatingBlob works")
    }

    @Test func isolateGeometryReaderIssues() {
        print("🔬 CRASH TEST 6: GeometryReader Isolation")

        print("   Step 6a: Creating view with GeometryReader...")
        let geometryView = GeometryReader { geometry in
            let color = SafeColor.rgb(90/255, 45/255, 200/255, opacity: 0.35, context: "CrashTest_GeometryBlob")
            FloatingBlob(color: color, size: 350, duration: 22)
                .position(x: geometry.size.width * 0.1, y: geometry.size.height * 0.1)
        }
        print("   Step 6a: ✅ GeometryReader view created")

        print("   Step 6b: Rendering GeometryReader view...")
        let hostingController = UIHostingController(rootView: geometryView)
        print("   Step 6b: ✅ GeometryReader view rendered")

        print("🔬 CRASH TEST 6: ✅ PASSED - GeometryReader works")
    }

    @Test func isolateFullOrbWithPrintStatements() {
        print("🔬 CRASH TEST 7: Full Orb With Detailed Logging")

        print("   Step 7a: About to create full AuraBackground...")

        // This will use all the logging in AuraBackground
        let fullOrb = AuraBackground()
        print("   Step 7a: ✅ Full AuraBackground created")

        print("   Step 7b: About to render full orb (CRITICAL STEP)...")
        let hostingController = UIHostingController(rootView: fullOrb)
        print("   Step 7b: ✅ Full AuraBackground rendered WITHOUT CRASH!")

        print("🔬 CRASH TEST 7: ✅ PASSED - Full orb works in test")
    }

    @Test func isolateEngineWithSessionIntegration() {
        print("🔬 CRASH TEST 8: Engine + Session Integration")

        let engine = LightEngine()
        let session = LightSession(
            session_name: "Integration Test",
            duration_sec: 5,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine),
                LightMoment(time: 2.5, frequency: 12, intensity: 0.8, waveform: .sine),
                LightMoment(time: 5, frequency: 8, intensity: 0.3, waveform: .sine)
            ]
        )
        let player = LightScorePlayer(session: session)

        print("   Step 8a: Starting engine...")
        engine.start()
        print("   Step 8a: ✅ Engine started")

        print("   Step 8b: Attaching session player...")
        engine.attachSession(player: player)
        print("   Step 8b: ✅ Session attached")

        print("   Step 8c: Starting session playback...")
        player.play()
        print("   Step 8c: ✅ Session playing")

        print("   Step 8d: Letting it run briefly...")
        Thread.sleep(forTimeInterval: 0.2)

        print("   Step 8e: Checking state after run...")
        let engineState = OrbCrashLogger.shared.captureEngineState(from: engine)
        print("      Engine State: \(engineState)")
        print("      Player Progress: \(player.progress)")

        print("   Step 8f: Stopping...")
        player.stop()
        engine.detachSession()
        engine.stop()

        print("🔬 CRASH TEST 8: ✅ PASSED - Engine+Session integration works")
    }
}