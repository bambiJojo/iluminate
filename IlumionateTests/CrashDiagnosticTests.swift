//
//  CrashDiagnosticTests.swift
//  IlumionateTests
//
//  Tests to isolate app crash issues
//

import Testing
import SwiftUI
@testable import Ilumionate

// MARK: - LightEngine Crash Diagnostic Tests

@MainActor
struct LightEngineCrashTests {

    @Test func lightEngineBrightnessRanges() {
        let engine = LightEngine()

        // Test extreme session intensities
        let extremeIntensities = [0.0, 0.5, 1.0, 1.5, 2.0, 5.0]
        let userMultipliers = [0.1, 0.5, 1.0]

        for intensity in extremeIntensities {
            for multiplier in userMultipliers {
                let calculatedMax = intensity * multiplier
                let clampedMax = max(0.0, min(1.0, calculatedMax))

                // Verify our clamping logic works
                #expect(clampedMax >= 0.0)
                #expect(clampedMax <= 1.0)

                print("Intensity \(intensity) * Multiplier \(multiplier) = \(calculatedMax) -> Clamped: \(clampedMax)")
            }
        }
    }

    @Test func lightEngineStartStop() throws {
        let engine = LightEngine()

        // Test basic start/stop without crash
        #expect(!engine.isRunning)

        engine.start()
        #expect(engine.isRunning)

        // Let it run briefly
        try #require(engine.isRunning)

        engine.stop()
        #expect(!engine.isRunning)
    }

    @Test func lightEngineBrightnessAfterStart() async throws {
        let engine = LightEngine()
        engine.start()

        // Wait a moment for initial values
        try await Task.sleep(for: .milliseconds(100))

        // Check brightness values are in valid range
        #expect(engine.brightness >= 0.0)
        #expect(engine.brightness <= 1.0)
        #expect(engine.brightnessLeft >= 0.0)
        #expect(engine.brightnessLeft <= 1.0)
        #expect(engine.brightnessRight >= 0.0)
        #expect(engine.brightnessRight <= 1.0)

        engine.stop()
    }

    @Test func lightEngineWithExtremeBrightness() async throws {
        let engine = LightEngine()

        // Test setting extreme values before starting
        engine.userBrightnessMultiplier = 1.0
        engine.maximumBrightness = 2.0 // This should get clamped
        engine.minimumBrightness = -0.5 // This should get clamped

        engine.start()

        // Wait for engine tick
        try await Task.sleep(for: .milliseconds(100))

        // Values should still be in valid range
        #expect(engine.brightness >= 0.0)
        #expect(engine.brightness <= 1.0)

        engine.stop()
    }
}

// MARK: - Color Range Tests
// TherapeuticColors removed from main target — tests relocated

// MARK: - UnifiedPlayerView Component Tests

@MainActor
struct UnifiedPlayerViewComponentTests {

    @Test func unifiedPlayerViewInitialization() {
        let session = LightSession(
            session_name: "Test Session",
            duration_sec: 300,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine),
                LightMoment(time: 300, frequency: 6, intensity: 0.8, waveform: .sine)
            ]
        )
        let engine = LightEngine()

        // Test that UnifiedPlayerView can be created without crash
        let mode = PlayerMode.session(session: session, audioFile: nil)
        #expect(mode.title == "Test Session")
        let _ = UnifiedPlayerView(mode: mode, engine: engine)
    }
}

// MARK: - Session Integration Tests

@MainActor
struct SessionIntegrationCrashTests {

    @Test func sessionWithPlayerIntegration() async throws {
        let session = LightSession(
            session_name: "Integration Test",
            duration_sec: 60,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine),
                LightMoment(time: 30, frequency: 8, intensity: 0.8, waveform: .sine),
                LightMoment(time: 60, frequency: 12, intensity: 0.3, waveform: .sine)
            ]
        )

        let engine = LightEngine()
        let player = LightScorePlayer(session: session)

        // Attach session to engine (common crash point)
        engine.attachSession(player: player)

        // Start engine with session
        engine.start()
        player.play()

        // Wait for session playback
        try await Task.sleep(for: .milliseconds(200))

        // Check that brightness values are still valid
        #expect(engine.brightness >= 0.0)
        #expect(engine.brightness <= 1.0)
        #expect(engine.hasActiveSession)

        // Clean shutdown
        player.stop()
        engine.detachSession()
        engine.stop()
    }

    @Test func extremeSessionIntensityValues() async throws {
        // Test session with intensity values that could cause issues
        let session = LightSession(
            session_name: "Extreme Intensity Test",
            duration_sec: 30,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 1.0, waveform: .sine),
                LightMoment(time: 15, frequency: 10, intensity: 0.0, waveform: .sine),
                LightMoment(time: 30, frequency: 10, intensity: 1.0, waveform: .sine)
            ]
        )

        let engine = LightEngine()
        let player = LightScorePlayer(session: session)

        engine.attachSession(player: player)
        engine.start()
        player.play()

        // Wait for extreme values
        try await Task.sleep(for: .milliseconds(100))

        // Should handle extreme values without crash
        #expect(engine.brightness >= 0.0)
        #expect(engine.brightness <= 1.0)

        player.stop()
        engine.detachSession()
        engine.stop()
    }
}