//  UnifiedPlayerViewModelLightSyncTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct UnifiedPlayerViewModelLightSyncTests {

    @Test func initialLightSessionMakesAudioModeReady() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = makeViewModel(userDefaults: fixture.defaults)

        #expect(viewModel.lightSession?.session_name == "Ready Session")
        guard case .ready = viewModel.lightSyncStatus else {
            Issue.record("Expected Light Sync to be ready when an initial session is supplied")
            return
        }
    }

    @Test func firstLightSyncToggleShowsWarning() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = makeViewModel(userDefaults: fixture.defaults)
        viewModel.toggleLightSync()

        #expect(viewModel.showingLightSyncWarning)
        #expect(viewModel.lightSyncEnabled == false)
    }

    @Test func acknowledgingWarningEnablesLightSyncAndPersistsConsent() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = makeViewModel(userDefaults: fixture.defaults)

        viewModel.toggleLightSync()
        viewModel.acknowledgeLightSyncWarning()

        #expect(viewModel.showingLightSyncWarning == false)
        #expect(viewModel.lightSyncEnabled)
        #expect(fixture.defaults.bool(forKey: "hasSeenLightSyncWarning"))
    }

    private func makeViewModel(userDefaults: UserDefaults) -> UnifiedPlayerViewModel {
        UnifiedPlayerViewModel(
            mode: .audioLight(audioFile: makeAudioFile()),
            engine: LightEngine(),
            initialLightSession: makeSession(),
            userDefaults: userDefaults
        )
    }

    private func makeDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "UnifiedPlayerViewModelLightSyncTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    private func makeAudioFile() -> AudioFile {
        AudioFile(
            id: UUID(),
            filename: "ready-audio.m4a",
            duration: 90,
            fileSize: 1024,
            createdDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func makeSession() -> LightSession {
        LightSession(
            session_name: "Ready Session",
            duration_sec: 90,
            light_score: [
                LightMoment(
                    time: 0,
                    frequency: 8,
                    intensity: 0.4,
                    waveform: .sine
                )
            ]
        )
    }
}

struct PlaybackAnalyticsLifecycleTests {

    @Test func cancellationBeforePlaybackDoesNotEndSession() {
        var lifecycle = PlaybackAnalyticsLifecycle()
        lifecycle.prepareForNewAttempt()

        let didEnd = lifecycle.markEnded()
        #expect(didEnd == false)
    }

    @Test func playbackStartsAndEndsOnlyOnce() {
        var lifecycle = PlaybackAnalyticsLifecycle()
        lifecycle.prepareForNewAttempt()

        let firstStart = lifecycle.markStarted()
        let secondStart = lifecycle.markStarted()
        let firstEnd = lifecycle.markEnded()
        let secondEnd = lifecycle.markEnded()

        #expect(firstStart)
        #expect(secondStart == false)
        #expect(firstEnd)
        #expect(secondEnd == false)
    }

    @Test func newAttemptResetsLifecycle() {
        var lifecycle = PlaybackAnalyticsLifecycle()
        lifecycle.prepareForNewAttempt()
        _ = lifecycle.markStarted()
        _ = lifecycle.markEnded()

        lifecycle.prepareForNewAttempt()

        let didStart = lifecycle.markStarted()
        let didEnd = lifecycle.markEnded()
        #expect(didStart)
        #expect(didEnd)
    }

    @Test func matchingSavedSessionResumesAtStoredProgress() {
        let decision = PlaybackResumeDecision(
            sessionID: "session-a",
            duration: 600,
            storedSessionID: "session-a",
            storedProgress: 0.4
        )

        #expect(decision.startType == .resumed)
        #expect(decision.startTime == 240)
    }

    @Test(arguments: [
        ("different", 0.4),
        ("session-a", 0.0),
        ("session-a", 1.0),
    ])
    func invalidSavedProgressStartsFresh(_ pair: (storedSessionID: String, storedProgress: Double)) {
        let decision = PlaybackResumeDecision(
            sessionID: "session-a",
            duration: 600,
            storedSessionID: pair.storedSessionID,
            storedProgress: pair.storedProgress
        )

        #expect(decision.startType == .fresh)
        #expect(decision.startTime == 0)
    }
}
