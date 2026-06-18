//
//  UsageAnalytics.swift
//  Ilumionate
//
//  The single entry point for usage analytics. Only file that touches the SDK.
//  Opt-out (default ON) is enforced here, and every event is built from the
//  typed catalog in AnalyticsEvent.swift.
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
    static let optOutKey = "analyticsEnabled"

    private let defaults: UserDefaults
    private let emit: (AnalyticsEvent) -> Void

    /// - Parameters:
    ///   - defaults: storage for the opt-out flag (injected in tests).
    ///   - emit: event sink (defaults to TelemetryDeck; a spy in tests).
    init(
        defaults: UserDefaults = .standard,
        emit: @escaping (AnalyticsEvent) -> Void = UsageAnalytics.telemetryDeckEmit
    ) {
        self.defaults = defaults
        self.emit = emit
        // Default-on: if the flag was never written, treat analytics as enabled.
        if defaults.object(forKey: Self.optOutKey) == nil {
            defaults.set(true, forKey: Self.optOutKey)
        }
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.optOutKey) }

    // MARK: - SDK lifecycle

    /// Call once at app launch.
    static func configure() {
        #if canImport(TelemetryDeck)
        guard !appID.isEmpty else { return }
        TelemetryDeck.initialize(config: .init(appID: appID))
        #endif
    }

    private static var appID: String {
        (Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String) ?? ""
    }

    private static func telemetryDeckEmit(_ event: AnalyticsEvent) {
        #if canImport(TelemetryDeck)
        TelemetryDeck.signal(event.name, parameters: event.parameters)
        #endif
    }

    // MARK: - Core send

    private func send(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        emit(event)
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

    func sessionCompleted(fraction: Double) {
        send(AnalyticsEvent("session.completed",
                            ["completionBucket": CompletionBucket(fraction: fraction).rawValue]))
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

    func settingsToggled(key: String) {
        send(AnalyticsEvent("settings.toggled", ["key": key]))
    }
}
