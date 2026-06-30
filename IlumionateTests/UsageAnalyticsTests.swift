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
        let analytics = UsageAnalytics(defaults: makeEnabledDefaults(), emit: { captured.append($0) })
        analytics.sessionStarted(source: .generated, category: "Sleep")
        #expect(captured == [AnalyticsEvent("session.started",
                                            ["source": "generated", "category": "Sleep"])])
    }

    @Test
    func endingIncompleteSessionEmitsOnlyEndedEvent() {
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: makeEnabledDefaults(), emit: { captured.append($0) })
        analytics.sessionEnded(fraction: 0.70)
        #expect(captured == [AnalyticsEvent("session.ended",
                                            ["completionBucket": "b50_75"])])
    }

    @Test
    func endingCompletedSessionEmitsEndedAndCompletedEvents() {
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: makeEnabledDefaults(), emit: { captured.append($0) })
        analytics.sessionEnded(fraction: 0.97)
        let parameters = ["completionBucket": "complete"]
        #expect(captured == [
            AnalyticsEvent("session.ended", parameters),
            AnalyticsEvent("session.completed", parameters),
        ])
    }

    @Test
    func endingUnboundedSessionUsesNotApplicableBucket() {
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: makeEnabledDefaults(), emit: { captured.append($0) })
        analytics.sessionEnded(fraction: nil)
        #expect(captured == [AnalyticsEvent("session.ended",
                                            ["completionBucket": "notApplicable"])])
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
