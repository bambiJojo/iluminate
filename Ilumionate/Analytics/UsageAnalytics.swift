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
    static let activationStartKey = "analyticsActivationStart"
    static let activationCompletedKey = "analyticsActivationCompleted"
    private static var isTelemetryDeckConfigured = false
    #if canImport(TelemetryDeck)
    private static var telemetryDeckConfig: TelemetryDeck.Config?
    #endif

    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private let emit: @MainActor (AnalyticsEvent) -> Void

    /// Exposed internally so lifecycle behavior can be regression-tested
    /// without asking the SDK to send a signal.
    static var isSDKConfigured: Bool { isTelemetryDeckConfigured }

    /// - Parameters:
    ///   - defaults: storage for the analytics preference (injected in tests).
    ///   - emit: event sink (defaults to TelemetryDeck; a spy in tests).
    init(
        defaults: UserDefaults = .standard,
        now: @MainActor @escaping () -> Date = Date.init,
        emit: @MainActor @escaping (AnalyticsEvent) -> Void = UsageAnalytics.telemetryDeckEmit
    ) {
        self.defaults = defaults
        self.now = now
        self.emit = emit
        recordActivationStartIfNeeded()
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
        guard analyticsEnabled else { return }
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
        if enabled { recordActivationStartIfNeeded() }
        #if canImport(TelemetryDeck)
        if enabled, !Self.isTelemetryDeckConfigured {
            Self.configure(appID: Self.appID, analyticsEnabled: true)
        } else {
            Self.telemetryDeckConfig?.analyticsDisabled = !enabled
            Self.telemetryDeckConfig?.sessionStatsEnabled = enabled
        }
        #endif
    }

    // MARK: - Screens

    func screen(_ screen: AnalyticsScreen) {
        send(AnalyticsEvent("screen.\(screen.rawValue)"))
    }

    // MARK: - Actions

    func sessionStarted(
        source: SessionSource,
        category: String,
        startType: PlaybackStartType
    ) {
        send(AnalyticsEvent("session.started", [
            "source": source.rawValue,
            "category": category,
            "startType": startType.rawValue,
        ]))
        markActivated(path: .playback)
    }

    func sessionEnded(
        source: SessionSource,
        category: String,
        endReason: PlaybackEndReason,
        fraction: Double?
    ) {
        let bucket = fraction.map { CompletionBucket(fraction: $0) } ?? .notApplicable
        let parameters = [
            "source": source.rawValue,
            "category": category,
            "endReason": endReason.rawValue,
            "completionBucket": bucket.rawValue,
        ]
        send(AnalyticsEvent("session.ended", parameters))
        if bucket == .complete {
            send(AnalyticsEvent("session.completed", parameters))
        }
        if bucket == .b75_95 || bucket == .complete {
            meaningfulSessionCompleted(source: source, category: category)
        }
    }

    func sessionCompletionAction(
        _ action: SessionCompletionAction,
        source: SessionSource,
        category: String
    ) {
        send(AnalyticsEvent("session.completionAction", [
            "action": action.rawValue,
            "source": source.rawValue,
            "category": category,
        ]))
    }

    func onboardingCompletionAction(_ action: OnboardingCompletionAction) {
        send(AnalyticsEvent("onboarding.completionAction", [
            "action": action.rawValue,
        ]))
    }

    func homeCoreActionSelected(_ destination: HomeCoreAction) {
        send(AnalyticsEvent("home.coreActionSelected", [
            "destination": destination.rawValue,
        ]))
    }

    func audioImported(source: AudioSource) {
        send(AnalyticsEvent("audio.imported", ["source": source.rawValue]))
    }

    func audioAnalyzeStarted(context: AudioAnalysisTelemetryContext) {
        send(AnalyticsEvent("audio.analyzeStarted", context.parameters))
    }

    func audioAnalyzeCompleted(
        context: AudioAnalysisTelemetryContext,
        processingTime: ProcessingTimeBucket
    ) {
        var parameters = context.parameters
        parameters["processingTime"] = processingTime.rawValue
        send(AnalyticsEvent("audio.analyzeCompleted", parameters))
        markActivated(path: .audioAnalysis)
    }

    func audioAnalysisFailed(
        context: AudioAnalysisTelemetryContext,
        stage: AnalyticsAnalysisStage,
        reason: AnalyticsAnalysisFailureReason,
        processingTime: ProcessingTimeBucket
    ) {
        var parameters = context.parameters
        parameters["stage"] = stage.rawValue
        parameters["reason"] = reason.rawValue
        parameters["processingTime"] = processingTime.rawValue
        send(AnalyticsEvent(
            AnalyticsError.audioAnalysisFailed.rawValue,
            parameters,
            kind: .error(.thrownException)
        ))
    }

    func audioAnalyzeCancelled(
        context: AudioAnalysisTelemetryContext,
        stage: AnalyticsAnalysisStage,
        processingTime: ProcessingTimeBucket
    ) {
        var parameters = context.parameters
        parameters["stage"] = stage.rawValue
        parameters["processingTime"] = processingTime.rawValue
        send(AnalyticsEvent("audio.analyzeCancelled", parameters))
    }

    func audioAnalyzeRetryRequested(
        reason: AnalyticsAnalysisFailureReason,
        recoveryStage: AnalysisRecoveryStage
    ) {
        send(AnalyticsEvent("audio.analyzeRetryRequested", [
            "reason": reason.rawValue,
            "recoveryStage": recoveryStage.rawValue,
        ]))
    }

    func analysisReadyAction(_ action: AnalysisReadyAction) {
        send(AnalyticsEvent("analysis.readyAction", [
            "action": action.rawValue,
        ]))
    }

    func sessionGenerated() { send(AnalyticsEvent("session.generated")) }

    func mindMachineStarted(mode: MindMachineMode, entryPoint: MindMachineEntryPoint) {
        send(AnalyticsEvent("mindMachine.started", [
            "mode": mode.rawValue,
            "entryPoint": entryPoint.rawValue,
        ]))
    }

    func mindMachineStartRequested(mode: MindMachineMode, entryPoint: MindMachineEntryPoint) {
        send(AnalyticsEvent("mindMachine.startRequested", [
            "mode": mode.rawValue,
            "entryPoint": entryPoint.rawValue,
        ]))
    }

    func textTranceStarted() {
        send(AnalyticsEvent("textTrance.started"))
        markActivated(path: .reading)
    }

    func readerQuickStartSelected(_ startType: PlaybackStartType) {
        send(AnalyticsEvent("reader.quickStartSelected", [
            "startType": startType.rawValue,
        ]))
    }

    func textTranceCompleted() {
        send(AnalyticsEvent("textTrance.completed"))
        meaningfulSessionCompleted(source: .textTrance, category: "Reading")
    }
    func readingSourceImported() { send(AnalyticsEvent("readingSource.imported")) }

    func onboardingStep(index: Int) {
        send(AnalyticsEvent("onboarding.step", ["index": String(index)]))
    }
    func onboardingCompleted() { send(AnalyticsEvent("onboarding.completed")) }

    func errorOccurred(_ error: AnalyticsError) {
        send(AnalyticsEvent(error.rawValue, kind: .error(error.category)))
    }

    private func recordActivationStartIfNeeded() {
        guard isEnabled, defaults.object(forKey: Self.activationStartKey) == nil else { return }
        defaults.set(now(), forKey: Self.activationStartKey)
    }

    private func markActivated(path: ActivationPath) {
        guard isEnabled, defaults.bool(forKey: Self.activationCompletedKey) == false else { return }
        let startedAt = defaults.object(forKey: Self.activationStartKey) as? Date ?? now()
        let bucket = TimeToValueBucket(seconds: now().timeIntervalSince(startedAt))
        defaults.set(true, forKey: Self.activationCompletedKey)
        send(AnalyticsEvent("activation.completed", [
            "path": path.rawValue,
            "timeToValue": bucket.rawValue,
        ]))
    }

    private func meaningfulSessionCompleted(source: SessionSource, category: String) {
        send(AnalyticsEvent("meaningfulSession.completed", [
            "source": source.rawValue,
            "category": category,
        ]))
    }
}
