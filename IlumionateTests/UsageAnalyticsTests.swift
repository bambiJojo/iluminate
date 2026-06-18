//
//  UsageAnalyticsTests.swift
//  IlumionateTests
//

import Foundation
import Testing
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

    // MARK: - Opt-out gate

    @Test
    func defaultsToEnabledWhenUnset() {
        let analytics = UsageAnalytics(defaults: makeDefaults(), emit: { _ in })
        #expect(analytics.isEnabled == true)
    }

    @Test
    func optOutSuppressesEmission() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: UsageAnalytics.optOutKey)
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: defaults, emit: { captured.append($0) })
        analytics.screen(.home)
        #expect(captured.isEmpty)
    }

    // MARK: - Typed emission

    @Test
    func enabledEmitsScreenEvent() {
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: makeDefaults(), emit: { captured.append($0) })
        analytics.screen(.lightScoreEditor)
        #expect(captured == [AnalyticsEvent("screen.lightScoreEditor")])
    }

    @Test
    func sessionStartedCarriesSourceAndCategory() {
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: makeDefaults(), emit: { captured.append($0) })
        analytics.sessionStarted(source: .generated, category: "Sleep")
        #expect(captured == [AnalyticsEvent("session.started",
                                            ["source": "generated", "category": "Sleep"])])
    }

    @Test
    func sessionCompletedEmitsBucket() {
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: makeDefaults(), emit: { captured.append($0) })
        analytics.sessionCompleted(fraction: 0.97)
        #expect(captured == [AnalyticsEvent("session.completed",
                                            ["completionBucket": "complete"])])
    }
}
