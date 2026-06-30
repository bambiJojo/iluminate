//
//  UsageAnalytics.swift
//  Ilumionate
//
//  The single entry point for usage analytics. Only file that touches the SDK.
//  Opt-in is enforced here, and every event is built from the typed catalog in
//  AnalyticsEvent.swift.
//
//  The TelemetryDeck dependency is wrapped in `#if canImport(TelemetryDeck)`
//  so the app compiles and tests run before the SPM package is added. Once the
//  package is present (and a `TelemetryDeckAppID` Info.plist key is set), the
//  real signal path activates automatically — no code change required.
//

import Foundation
import Observation
#if canImport(TelemetryDeck)
import TelemetryDeck
#endif

@MainActor
@Observable
final class UsageAnalytics {

    static let shared = UsageAnalytics()
    static let preferenceKey = "analyticsConsentGranted"
    static let consentAnsweredKey = "analyticsConsentAnswered"
    static let legacyPreferenceKey = "analyticsEnabled"
    static let optOutKey = legacyPreferenceKey
    private static var isTelemetryDeckConfigured = false
    #if canImport(TelemetryDeck)
    private static var telemetryDeckConfig: TelemetryDeck.Config?
    #endif

    private let defaults: UserDefaults
    private let emit: @MainActor (AnalyticsEvent) -> Void

    /// - Parameters:
    ///   - defaults: storage for the analytics preference (injected in tests).
    ///   - emit: event sink (defaults to TelemetryDeck; a spy in tests).
    init(
        defaults: UserDefaults = .standard,
        emit: @MainActor @escaping (AnalyticsEvent) -> Void = UsageAnalytics.telemetryDeckEmit
    ) {
        self.defaults = defaults
        self.emit = emit
    }

    var hasAnsweredConsent: Bool { defaults.bool(forKey: Self.consentAnsweredKey) }
    var isEnabled: Bool {
        hasAnsweredConsent && defaults.bool(forKey: Self.preferenceKey)
    }

    // MARK: - SDK lifecycle

    /// Call once at app launch.
    static func configure() {
        configure(appID: appID, analyticsEnabled: shared.isEnabled)
    }

    static func configure(appID: String, analyticsEnabled: Bool = true) {
        #if canImport(TelemetryDeck)
        isTelemetryDeckConfigured = false
        telemetryDeckConfig = nil
        guard let appID = normalizedAppID(appID) else { return }
        let config = makeTelemetryDeckConfig(appID: appID, analyticsEnabled: analyticsEnabled)
        telemetryDeckConfig = config
        TelemetryDeck.initialize(config: config)
        isTelemetryDeckConfigured = true
        #endif
    }

    #if canImport(TelemetryDeck)
    static func makeTelemetryDeckConfig(
        appID: String,
        analyticsEnabled: Bool
    ) -> TelemetryDeck.Config {
        let config = TelemetryDeck.Config(appID: appID)
        config.analyticsDisabled = !analyticsEnabled
        config.sessionStatsEnabled = analyticsEnabled
        return config
    }
    #endif

    private static var appID: String {
        (Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String) ?? ""
    }

    private static func normalizedAppID(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func telemetryDeckEmit(_ event: AnalyticsEvent) {
        #if canImport(TelemetryDeck)
        guard isTelemetryDeckConfigured else { return }
        switch event.kind {
        case .signal:
            TelemetryDeck.signal(event.name, parameters: event.parameters)
        case .error(let category):
            TelemetryDeck.errorOccurred(
                id: event.name,
                category: telemetryDeckErrorCategory(category),
                parameters: event.parameters
            )
        }
        #endif
    }

    #if canImport(TelemetryDeck)
    private static func telemetryDeckErrorCategory(
        _ category: AnalyticsErrorCategory
    ) -> ErrorCategory {
        switch category {
        case .thrownException: .thrownException
        case .userInput: .userInput
        case .appState: .appState
        }
    }
    #endif

    // MARK: - Core send

    private func send(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        emit(event)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: Self.consentAnsweredKey)
        defaults.set(enabled, forKey: Self.preferenceKey)
        defaults.set(enabled, forKey: Self.legacyPreferenceKey)
        #if canImport(TelemetryDeck)
        Self.telemetryDeckConfig?.analyticsDisabled = !enabled
        Self.telemetryDeckConfig?.sessionStatsEnabled = enabled
        #endif
    }

    // MARK: - Screens

    func screen(_ screen: AnalyticsScreen) {
        send(AnalyticsEvent("screen.\(screen.rawValue)"))
    }

    // MARK: - Actions

    func sessionStarted(source: SessionSource, category: String) {
        send(AnalyticsEvent("session.started",
                            ["source": source.rawValue, "category": category]))
    }

    func sessionEnded(fraction: Double?) {
        let bucket = fraction.map { CompletionBucket(fraction: $0) } ?? .notApplicable
        let parameters = ["completionBucket": bucket.rawValue]
        send(AnalyticsEvent("session.ended", parameters))
        if bucket == .complete {
            send(AnalyticsEvent("session.completed", parameters))
        }
    }

    func audioImported(source: AudioSource) {
        send(AnalyticsEvent("audio.imported", ["source": source.rawValue]))
    }

    func audioAnalyzeStarted() { send(AnalyticsEvent("audio.analyzeStarted")) }
    func audioAnalyzeCompleted() { send(AnalyticsEvent("audio.analyzeCompleted")) }
    func sessionGenerated() { send(AnalyticsEvent("session.generated")) }

    func mindMachineStarted(mode: MindMachineMode) {
        send(AnalyticsEvent("mindMachine.started", ["mode": mode.rawValue]))
    }

    func textTranceStarted() { send(AnalyticsEvent("textTrance.started")) }
    func textTranceCompleted() { send(AnalyticsEvent("textTrance.completed")) }
    func readingSourceImported() { send(AnalyticsEvent("readingSource.imported")) }

    func onboardingStep(index: Int) {
        send(AnalyticsEvent("onboarding.step", ["index": String(index)]))
    }
    func onboardingCompleted() { send(AnalyticsEvent("onboarding.completed")) }

    func errorOccurred(_ error: AnalyticsError) {
        send(AnalyticsEvent(error.rawValue, kind: .error(error.category)))
    }
}
