//
//  UnifiedPlayerLightExposureLimitTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@Suite(.serialized)
@MainActor
struct UnifiedPlayerLightExposureLimitTests {
    @Test
    func lightOnlySessionCannotOutlastTheSelectedLimit() throws {
        let fixture = try makeDefaults(limit: .fiveMinutes)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = UnifiedPlayerViewModel(
            mode: .session(session: makeSession(duration: 900), audioFile: nil),
            engine: LightEngine(),
            userDefaults: fixture.defaults
        )
        viewModel.onAppear()
        defer { viewModel.onDisappear() }

        #expect(viewModel.duration == 300)
        #expect(viewModel.lightExposureRemaining == 300)
    }

    @Test
    func audioBackedSessionKeepsItsTimelineAfterLightsEnd() throws {
        let fixture = try makeDefaults(limit: .fiveMinutes)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = UnifiedPlayerViewModel(
            mode: .session(
                session: makeSession(duration: 900),
                audioFile: makeAudioFile(duration: 900)
            ),
            engine: LightEngine(),
            userDefaults: fixture.defaults
        )
        viewModel.onAppear()
        defer { viewModel.onDisappear() }

        #expect(viewModel.duration == 900)
        #expect(viewModel.lightExposureRemaining == 300)
    }

    @Test
    func untimedFlashModeUsesTheSelectedLimit() throws {
        let fixture = try makeDefaults(limit: .tenMinutes)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = UnifiedPlayerViewModel(
            mode: makeFlashMode(goalDuration: nil),
            engine: LightEngine(),
            userDefaults: fixture.defaults
        )
        viewModel.onAppear()
        defer { viewModel.onDisappear() }

        #expect(viewModel.duration == 600)
        #expect(viewModel.lightExposureRemaining == 600)
    }

    @Test
    func shorterFlashGoalIsPreserved() throws {
        let fixture = try makeDefaults(limit: .twentyMinutes)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = UnifiedPlayerViewModel(
            mode: makeFlashMode(goalDuration: 300),
            engine: LightEngine(),
            userDefaults: fixture.defaults
        )
        viewModel.onAppear()
        defer { viewModel.onDisappear() }

        #expect(viewModel.duration == 300)
        #expect(viewModel.lightOutputMultiplier == 1)
    }

    @Test
    func colorPulseUsesTheSelectedLimit() throws {
        let fixture = try makeDefaults(limit: .fifteenMinutes)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = UnifiedPlayerViewModel(
            mode: .colorPulse(frequency: 8, intensity: 0.5),
            engine: LightEngine(),
            userDefaults: fixture.defaults
        )
        viewModel.onAppear()
        defer { viewModel.onDisappear() }

        #expect(viewModel.duration == 900)
        #expect(viewModel.showsLightExposureStatus)
    }

    private func makeDefaults(
        limit: LightExposureLimit
    ) throws -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "UnifiedPlayerLightExposureLimitTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(limit.rawValue, forKey: AppSettingsManager.Key.maximumLightTimeMinutes)
        defaults.set(true, forKey: "hasSeenFlashWarning")
        return (defaults, suiteName)
    }

    private func makeSession(duration: TimeInterval) -> LightSession {
        LightSession(
            session_name: "Light comfort test",
            duration_sec: duration,
            light_score: [
                LightMoment(time: 0, frequency: 8, intensity: 0.5, waveform: .sine),
                LightMoment(time: duration, frequency: 4, intensity: 0.25, waveform: .sine),
            ]
        )
    }

    private func makeAudioFile(duration: TimeInterval) -> AudioFile {
        AudioFile(
            id: UUID(),
            filename: "light-comfort-test.m4a",
            duration: duration,
            fileSize: 1_024,
            createdDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func makeFlashMode(goalDuration: TimeInterval?) -> PlayerMode {
        .flashMode(
            frequency: 8,
            intensity: 0.5,
            colorTemperature: 4_000,
            pattern: .sine,
            binauralEnabled: false,
            binauralCarrier: 200,
            binauralVolume: 0.5,
            goalDuration: goalDuration
        )
    }
}
