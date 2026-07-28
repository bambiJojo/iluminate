//  MindMachineToggleTests.swift
//  IlumionateTests

import Foundation
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
