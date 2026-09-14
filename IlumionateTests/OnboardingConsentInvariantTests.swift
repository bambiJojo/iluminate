//
//  OnboardingConsentInvariantTests.swift
//  IlumionateTests
//
//  App Review rejected builds 10029 and 10030 under Guideline 5.1.2(i),
//  both times for an onboarding screen that asked the user to allow data
//  collection. 10029 used an alert; 10030 replaced it with an off-by-default
//  toggle and a single Continue button, and Apple rejected that too — a
//  dedicated consent step reads as a custom tracking prompt whatever its
//  controls.
//
//  Onboarding must therefore contain no analytics-consent surface at all.
//  Enabling analytics belongs in Settings, where a labelled row is not a
//  prompt. These are source invariants rather than behaviour tests because
//  the requirement is about what the reviewer can *see*, and a reintroduced
//  screen would otherwise pass every functional test in the suite.
//

import Testing
import Foundation
@testable import Ilumionate

@Suite("Onboarding consent invariants")
struct OnboardingConsentInvariantTests {

    private var onboardingSource: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // IlumionateTests
                .deletingLastPathComponent()   // repo root
                .appending(path: "Ilumionate/OnboardingView.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test("Onboarding declares no analytics-consent phase")
    func onboardingHasNoAnalyticsPhase() throws {
        let source = try onboardingSource.lowercased()

        #expect(
            !source.contains("analyticsconsent"),
            "onboarding must not declare an analytics-consent phase (Guideline 5.1.2(i))"
        )
        #expect(
            !source.contains("analyticsoptin"),
            "onboarding must not hold analytics opt-in state"
        )
    }

    @Test("Onboarding never asks the user to allow data collection")
    func onboardingHasNoConsentCopy() throws {
        let source = try onboardingSource.lowercased()

        // Phrasings App Review has objected to, plus the shape of any future
        // rewording that still amounts to asking permission during onboarding.
        let bannedPhrases = [
            "share anonymous analytics",
            "help improve",
            "allow tracking",
            "anonymous analytics",
            "usage analytics",
        ]

        for phrase in bannedPhrases {
            #expect(
                !source.contains(phrase),
                "onboarding copy contains \"\(phrase)\" — consent belongs in Settings, not onboarding"
            )
        }
    }

    @Test("Onboarding never writes the analytics preference")
    func onboardingDoesNotSetAnalyticsConsent() throws {
        let source = try onboardingSource

        // Onboarding may still *emit* analytics events (they no-op while
        // disabled). What it must never do is decide the preference, because
        // that is only reachable through a consent control.
        #expect(
            !source.contains("UsageAnalytics.shared.setEnabled"),
            "onboarding must not set the analytics preference"
        )
        #expect(
            !source.contains(UsageAnalytics.preferenceKey),
            "onboarding must not write the analytics consent key directly"
        )
    }

    @Test("Analytics stay off until the user opts in from Settings")
    func analyticsAreOffUntilExplicitlyEnabled() throws {
        let suiteName = "OnboardingConsentInvariantTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let analytics = UsageAnalytics(defaults: defaults, emit: { _ in })
        #expect(!analytics.hasAnsweredConsent)
        #expect(!analytics.isEnabled, "a fresh install must not emit analytics")

        analytics.setEnabled(true)
        #expect(analytics.isEnabled, "the Settings control must still work")

        analytics.setEnabled(false)
        #expect(!analytics.isEnabled)
    }
}
