//  MindMachineToggleTests.swift
//  IlumionateTests

import Foundation
import QuartzCore
import Testing
@testable import Ilumionate

@MainActor
struct MindMachinePreferenceTests {

    private func makeDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "MindMachinePreferenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @Test func defaultsToEnabled() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        #expect(AppSettingsManager.isMindMachineEnabled(defaults: fixture.defaults))
    }

    @Test func roundTripsStoredValue() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        fixture.defaults.set(false, forKey: AppSettingsManager.Key.mindMachineEnabled)
        #expect(AppSettingsManager.isMindMachineEnabled(defaults: fixture.defaults) == false)

        fixture.defaults.set(true, forKey: AppSettingsManager.Key.mindMachineEnabled)
        #expect(AppSettingsManager.isMindMachineEnabled(defaults: fixture.defaults))
    }

    @Test func resetRestoresEnabled() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        fixture.defaults.set(false, forKey: AppSettingsManager.Key.mindMachineEnabled)
        AppSettingsManager.resetPreferences(
            defaults: fixture.defaults,
            resetAnalysisPreferences: false
        )

        #expect(AppSettingsManager.isMindMachineEnabled(defaults: fixture.defaults))
    }
}

@MainActor
struct MindMachineModeFlagTests {

    private func makeSession(duration: Double = 300) -> LightSession {
        LightSession(
            session_name: "Mode Test",
            duration_sec: duration,
            light_score: [LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)]
        )
    }

    private func makeAudioFile() -> AudioFile {
        AudioFile(
            id: UUID(),
            filename: "track.m4a",
            duration: 300,
            fileSize: 2048,
            createdDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    @Test func sessionWithAudioHasTheToggle() {
        let mode = PlayerMode.session(session: makeSession(), audioFile: makeAudioFile())
        #expect(mode.hasMindMachineToggle)
    }

    @Test func sessionWithoutAudioHasNoToggle() {
        let mode = PlayerMode.session(session: makeSession(), audioFile: nil)
        #expect(mode.hasMindMachineToggle == false)
    }

    @Test func playlistHasTheToggle() {
        let mode = PlayerMode.playlist(playlist: Playlist(name: "Evening"))
        #expect(mode.hasMindMachineToggle)
    }

    @Test func audioLightHasNoToggle() {
        let mode = PlayerMode.audioLight(audioFile: makeAudioFile())
        #expect(mode.hasMindMachineToggle == false)
    }

    @Test func colorPulseHasNoToggle() {
        let mode = PlayerMode.colorPulse(frequency: 10, intensity: 0.5)
        #expect(mode.hasMindMachineToggle == false)
    }

    @Test("Every mode that starts the flashing-light engine requires acknowledgement")
    func flashingModesRequireSafetyWarning() {
        let session = PlayerMode.session(session: makeSession(), audioFile: makeAudioFile())
        let playlist = PlayerMode.playlist(playlist: Playlist(name: "Evening"))
        let flash = PlayerMode.flashMode(
            frequency: 10,
            intensity: 0.5,
            colorTemperature: 3_000,
            pattern: .sine,
            binauralEnabled: false,
            binauralCarrier: 200,
            binauralVolume: 0.5
        )

        #expect(session.requiresSafetyWarning)
        #expect(playlist.requiresSafetyWarning)
        #expect(flash.requiresSafetyWarning)
        #expect(PlayerMode.colorPulse(frequency: 10, intensity: 0.5).requiresSafetyWarning)
        #expect(PlayerMode.audioLight(audioFile: makeAudioFile()).requiresSafetyWarning == false)
        #expect(
            PlayerMode.visualField(settings: .standard, audioFile: nil, binaural: nil)
                .requiresSafetyWarning == false
        )
    }
}

@MainActor
struct MindMachineViewModelTests {

    private func makeDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "MindMachineViewModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    private func makeSession() -> LightSession {
        LightSession(
            session_name: "VM Test",
            duration_sec: 300,
            light_score: [LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)]
        )
    }

    private func makeAudioFile() -> AudioFile {
        AudioFile(
            id: UUID(),
            filename: "track.m4a",
            duration: 300,
            fileSize: 2048,
            createdDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func makeViewModel(
        engine: LightEngine,
        defaults: UserDefaults
    ) -> UnifiedPlayerViewModel {
        UnifiedPlayerViewModel(
            mode: .session(session: makeSession(), audioFile: makeAudioFile()),
            engine: engine,
            userDefaults: defaults
        )
    }

    @Test func togglingOffPersistsAndGatesTheEngine() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let engine = LightEngine()
        let viewModel = makeViewModel(engine: engine, defaults: fixture.defaults)

        #expect(viewModel.mindMachineEnabled)

        viewModel.toggleMindMachine()

        #expect(viewModel.mindMachineEnabled == false)
        #expect(engine.mindMachineEnabled == false)
        #expect(fixture.defaults.bool(forKey: AppSettingsManager.Key.mindMachineEnabled) == false)
    }

    @Test func storedPreferenceIsAppliedOnAppear() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.defaults.set(false, forKey: AppSettingsManager.Key.mindMachineEnabled)

        let engine = LightEngine()
        let viewModel = makeViewModel(engine: engine, defaults: fixture.defaults)
        viewModel.onAppear()

        #expect(viewModel.mindMachineEnabled == false)
        #expect(engine.mindMachineEnabled == false)

        viewModel.onDisappear()
    }

    @Test func audioLightModeIgnoresTheStoredPreference() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.defaults.set(false, forKey: AppSettingsManager.Key.mindMachineEnabled)

        let engine = LightEngine()
        let viewModel = UnifiedPlayerViewModel(
            mode: .audioLight(audioFile: makeAudioFile()),
            engine: engine,
            userDefaults: fixture.defaults
        )
        viewModel.onAppear()

        // Plain audio files keep their own Light Sync control, so the shared
        // preference must not gate their engine.
        #expect(engine.mindMachineEnabled)

        viewModel.onDisappear()
    }
}

@MainActor
struct MindMachineIntegrationTests {

    final class TestClock {
        private(set) var value: CFTimeInterval = 1_000
        func advance(_ seconds: CFTimeInterval) { value += seconds }
        var read: () -> CFTimeInterval { { self.value } }
    }

    private func makeSession(duration: Double = 600) -> LightSession {
        LightSession(
            session_name: "Integration",
            duration_sec: duration,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine),
                LightMoment(time: duration, frequency: 4, intensity: 0.9, waveform: .sine)
            ]
        )
    }

    /// The scenario that drove the design: with lights off, the score player
    /// must survive a pause/resume and still agree with the audio position.
    @Test func scoreStaysInSyncAcrossPauseWhileAudioOnly() {
        let clock = TestClock()
        let engine = LightEngine()
        let player = LightScorePlayer(session: makeSession(), now: clock.read)

        engine.attachSession(player: player)
        engine.start()
        player.play()

        // Play to 1:00, then drop to audio-only.
        clock.advance(60)
        engine.mindMachineEnabled = false
        #expect(engine.isDrivingOutput == false)

        // Audio continues to 5:00 with nothing ticking the score player.
        clock.advance(240)
        #expect(abs(player.currentTime - 300) < 0.001)

        // Pause for 45 seconds, then resume.
        player.pause()
        clock.advance(45)
        #expect(abs(player.currentTime - 300) < 0.001)
        player.play()

        // Lights back on — the score is at 5:00, not 1:00.
        engine.mindMachineEnabled = true
        #expect(engine.isDrivingOutput)
        #expect(abs(player.currentTime - 300) < 0.001)

        engine.stop()
    }

    /// Re-attaching a session — what a playlist track change does — must not
    /// arm output while the gate is off, and must pick up the new position
    /// when it is turned back on.
    @Test func trackChangeWhileAudioOnlyDoesNotArmOutput() {
        let clock = TestClock()
        let engine = LightEngine()

        engine.start()
        engine.mindMachineEnabled = false

        // Three "tracks" attach in sequence, as a playlist would.
        for _ in 0..<3 {
            let trackPlayer = LightScorePlayer(session: makeSession(duration: 120), now: clock.read)
            engine.attachSession(player: trackPlayer)
            trackPlayer.play()
            clock.advance(120)
            #expect(engine.isDrivingOutput == false)
        }

        // Fourth track, lights back on mid-playlist.
        let current = LightScorePlayer(session: makeSession(duration: 120), now: clock.read)
        engine.attachSession(player: current)
        current.play()
        clock.advance(30)
        engine.mindMachineEnabled = true

        #expect(engine.isDrivingOutput)
        #expect(abs(current.currentTime - 30) < 0.001)

        engine.stop()
    }
}
