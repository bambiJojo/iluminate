//
//  UsageAnalyticsTests.swift
//  IlumionateTests
//

import Foundation
import Testing
#if canImport(TelemetryDeck)
import TelemetryDeck
#endif
@testable import Ilumionate

@MainActor
struct UsageAnalyticsTests {

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suite = "UsageAnalyticsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeEnabledDefaults() -> UserDefaults {
        let defaults = makeDefaults()
        defaults.set(true, forKey: UsageAnalytics.consentAnsweredKey)
        defaults.set(true, forKey: UsageAnalytics.preferenceKey)
        return defaults
    }

    private func makeAnalytics(
        defaults: UserDefaults? = nil,
        now: @MainActor @escaping () -> Date = Date.init,
        captured: @MainActor @escaping (AnalyticsEvent) -> Void
    ) -> UsageAnalytics {
        UsageAnalytics(
            defaults: defaults ?? makeEnabledDefaults(),
            now: now,
            emit: captured
        )
    }

    // MARK: - Completion bucketing

    @Test(arguments: [
        (0.0, CompletionBucket.under25),
        (0.24, CompletionBucket.under25),
        (0.25, CompletionBucket.b25_50),
        (0.49, CompletionBucket.b25_50),
        (0.50, CompletionBucket.b50_75),
        (0.74, CompletionBucket.b50_75),
        (0.75, CompletionBucket.b75_95),
        (0.94, CompletionBucket.b75_95),
        (0.95, CompletionBucket.complete),
        (1.0, CompletionBucket.complete),
    ])
    func bucketsFraction(_ pair: (fraction: Double, expected: CompletionBucket)) {
        #expect(CompletionBucket(fraction: pair.fraction) == pair.expected)
    }

    // MARK: - Consent gate

    @Test
    func defaultsToDisabledWhenUnset() {
        let analytics = UsageAnalytics(defaults: makeDefaults(), emit: { _ in })
        #expect(analytics.isEnabled == false)
    }

    @Test
    func disabledPreferenceSuppressesEmission() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: UsageAnalytics.consentAnsweredKey)
        defaults.set(false, forKey: UsageAnalytics.preferenceKey)
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: defaults, emit: { captured.append($0) })
        analytics.screen(.home)
        #expect(captured.isEmpty)
    }

    @Test
    func legacyEnabledPreferenceDoesNotEmitBeforeConsent() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: UsageAnalytics.legacyPreferenceKey)
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: defaults, emit: { captured.append($0) })

        analytics.screen(.home)

        #expect(analytics.hasAnsweredConsent == false)
        #expect(analytics.isEnabled == false)
        #expect(captured.isEmpty)
    }

    @Test
    func changingPreferenceUpdatesEmissionGate() {
        let defaults = makeDefaults()
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: defaults, emit: { captured.append($0) })

        analytics.setEnabled(false)
        analytics.screen(.home)
        #expect(analytics.isEnabled == false)
        #expect(captured.isEmpty)

        analytics.setEnabled(true)
        analytics.screen(.home)
        #expect(analytics.hasAnsweredConsent)
        #expect(analytics.isEnabled)
        #expect(captured == [AnalyticsEvent("screen.home")])
    }

    #if canImport(TelemetryDeck)
    @Test(arguments: [true, false])
    func telemetryDeckConfigurationMatchesPreference(_ enabled: Bool) {
        let config = UsageAnalytics.makeTelemetryDeckConfig(
            appID: "1A7508D7-E62A-4429-9F51-D091C879D280",
            analyticsEnabled: enabled
        )

        #expect(config.analyticsDisabled != enabled)
        #expect(config.sessionStatsEnabled == enabled)
    }
    #endif

    @Test
    func analyticsSDKDoesNotConfigureBeforeConsent() {
        UsageAnalytics.configure(
            appID: "1A7508D7-E62A-4429-9F51-D091C879D280",
            analyticsEnabled: false
        )

        #expect(UsageAnalytics.isSDKConfigured == false)
    }

    @Test
    func missingTelemetryDeckAppIDLeavesDefaultEmitterSafe() {
        UsageAnalytics.configure(appID: "")
        let analytics = UsageAnalytics(defaults: makeDefaults())
        analytics.screen(.home)
    }

    @Test
    func unresolvedTelemetryDeckBuildSettingLeavesDefaultEmitterSafe() {
        UsageAnalytics.configure(appID: "$(TELEMETRYDECK_APP_ID)")
        let analytics = UsageAnalytics(defaults: makeDefaults())
        analytics.screen(.home)
    }

    // MARK: - Typed emission

    @Test
    func enabledEmitsScreenEvent() {
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: makeEnabledDefaults(), emit: { captured.append($0) })
        analytics.screen(.lightScoreEditor)
        #expect(captured == [AnalyticsEvent("screen.lightScoreEditor")])
    }

    @Test
    func sessionStartedCarriesSourceAndCategory() {
        var captured: [AnalyticsEvent] = []
        let analytics = makeAnalytics(captured: { captured.append($0) })
        analytics.sessionStarted(source: .generated, category: "Sleep", startType: .resumed)
        #expect(captured == [AnalyticsEvent("session.started",
                                            [
                                                "source": "generated",
                                                "category": "Sleep",
                                                "startType": "resumed",
                                            ]),
                             AnalyticsEvent("activation.completed",
                                            [
                                                "path": "playback",
                                                "timeToValue": "under5Minutes",
                                            ])])
    }

    @Test
    func endingIncompleteSessionEmitsOnlyEndedEvent() {
        var captured: [AnalyticsEvent] = []
        let analytics = makeAnalytics(captured: { captured.append($0) })
        analytics.sessionEnded(
            source: .generated,
            category: "Relax",
            endReason: .userStopped,
            fraction: 0.70
        )
        #expect(captured == [AnalyticsEvent("session.ended",
                                            [
                                                "source": "generated",
                                                "category": "Relax",
                                                "endReason": "userStopped",
                                                "completionBucket": "b50_75",
                                            ])])
    }

    @Test
    func endingCompletedSessionEmitsEndedAndCompletedEvents() {
        var captured: [AnalyticsEvent] = []
        let analytics = makeAnalytics(captured: { captured.append($0) })
        analytics.sessionEnded(
            source: .preset,
            category: "Focus",
            endReason: .completed,
            fraction: 0.97
        )
        let parameters = [
            "source": "preset",
            "category": "Focus",
            "endReason": "completed",
            "completionBucket": "complete",
        ]
        #expect(captured == [
            AnalyticsEvent("session.ended", parameters),
            AnalyticsEvent("session.completed", parameters),
            AnalyticsEvent("meaningfulSession.completed", ["source": "preset", "category": "Focus"]),
        ])
    }

    @Test
    func completionActionCarriesReplayIntent() {
        var captured: [AnalyticsEvent] = []
        let analytics = makeAnalytics(captured: { captured.append($0) })

        analytics.sessionCompletionAction(
            .replay,
            source: .preset,
            category: "Focus"
        )

        #expect(captured == [AnalyticsEvent("session.completionAction", [
            "action": "replay",
            "source": "preset",
            "category": "Focus",
        ])])
    }

    @Test
    func endingUnboundedSessionUsesNotApplicableBucket() {
        var captured: [AnalyticsEvent] = []
        let analytics = makeAnalytics(captured: { captured.append($0) })
        analytics.sessionEnded(
            source: .mindMachine,
            category: "Trance",
            endReason: .dismissed,
            fraction: nil
        )
        #expect(captured == [AnalyticsEvent("session.ended",
                                            [
                                                "source": "mindMachine",
                                                "category": "Trance",
                                                "endReason": "dismissed",
                                                "completionBucket": "notApplicable",
                                            ])])
    }

    @Test
    func activationIsEmittedOnlyOnceWithBucketedElapsedTime() {
        let defaults = makeEnabledDefaults()
        defaults.set(Date(timeIntervalSince1970: 1_000), forKey: UsageAnalytics.activationStartKey)
        var captured: [AnalyticsEvent] = []
        let analytics = makeAnalytics(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_700) },
            captured: { captured.append($0) }
        )

        analytics.textTranceStarted()
        analytics.sessionStarted(source: .preset, category: "Relax", startType: .fresh)

        #expect(captured.filter { $0.name == "activation.completed" } == [
            AnalyticsEvent("activation.completed", ["path": "reading", "timeToValue": "under1Hour"]),
        ])
    }

    @Test
    func analysisFailureContainsOnlyStableBucketedContext() {
        var captured: [AnalyticsEvent] = []
        let analytics = makeAnalytics(captured: { captured.append($0) })
        let context = AudioAnalysisTelemetryContext(
            format: .mp3,
            duration: .fiveToThirtyMinutes,
            attempt: .resumed
        )

        analytics.audioAnalysisFailed(
            context: context,
            stage: .transcription,
            reason: .modelInitialization,
            processingTime: .oneToFiveMinutes
        )

        #expect(captured == [
            AnalyticsEvent(
                "Audio.Analysis.Failed",
                [
                    "format": "mp3",
                    "duration": "fiveToThirtyMinutes",
                    "attempt": "resumed",
                    "stage": "transcription",
                    "reason": "modelInitialization",
                    "processingTime": "oneToFiveMinutes",
                ],
                kind: .error(.thrownException)
            ),
        ])
    }

    @Test(arguments: [
        (30.0, ProcessingTimeBucket.underOneMinute),
        (60.0, ProcessingTimeBucket.oneToFiveMinutes),
        (300.0, ProcessingTimeBucket.fiveToFifteenMinutes),
        (900.0, ProcessingTimeBucket.fifteenMinutesOrMore),
    ])
    func processingTimesAreBucketed(_ pair: (seconds: TimeInterval, expected: ProcessingTimeBucket)) {
        #expect(ProcessingTimeBucket(seconds: pair.seconds) == pair.expected)
    }

    @Test
    func errorUsesStableIdentifierWithoutUserContent() {
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: makeEnabledDefaults(), emit: { captured.append($0) })
        analytics.errorOccurred(.audioAnalysisFailed)
        #expect(captured == [
            AnalyticsEvent(
                "Audio.Analysis.Failed",
                kind: .error(.thrownException)
            ),
        ])
    }
}
