//
//  FlashTintTests.swift
//  IlumionateTests
//
//  A TestFlight tester asked to "select from more colors to flash with". The
//  flash field renders a blackbody colour temperature, which spans amber to
//  cool white and cannot express teal, violet, or rose. FlashTint is the
//  render-time override that can, without touching the session JSON schema.
//

import Foundation
import Testing

@testable import Ilumionate

@Suite("Flash tint")
struct FlashTintTests {

    // MARK: - Resolution

    @Test("Defaults to the session's own colour temperature")
    func defaultMatchesSession() {
        #expect(FlashTint.default == .matchSession)
        #expect(FlashTint.matchSession.overrideTint == nil)
    }

    @Test("An explicit tint overrides the session colour")
    func explicitTintOverrides() {
        #expect(FlashTint.tint(.violet).overrideTint == .violet)
    }

    @Test("Every palette colour is selectable", arguments: VisualTint.palette)
    func paletteRoundTrips(swatch: VisualTint) {
        #expect(FlashTint.tint(swatch).overrideTint == swatch)
    }

    @Test("Custom hex survives selection")
    func customHexIsPreserved() {
        #expect(FlashTint.tint(.custom("FF0055")).overrideTint == .custom("FF0055"))
    }

    // MARK: - Persistence

    @Test("Unset preference falls back to the session colour")
    func unsetFallsBackToSession() throws {
        let defaults = try makeDefaults()

        #expect(FlashTintPreference.current(defaults: defaults) == .matchSession)
    }

    @Test("Selection round-trips through UserDefaults", arguments: [
        FlashTint.matchSession,
        .tint(.teal),
        .tint(.gold),
        .tint(.custom("3366FF"))
    ])
    func selectionRoundTrips(tint: FlashTint) throws {
        let defaults = try makeDefaults()

        FlashTintPreference.set(tint, defaults: defaults)

        #expect(FlashTintPreference.current(defaults: defaults) == tint)
    }

    @Test("Corrupt stored data falls back instead of crashing")
    func corruptDataFallsBack() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: AppSettingsManager.Key.flashTint)

        #expect(FlashTintPreference.current(defaults: defaults) == .matchSession)
    }

    @Test("Preference reset restores the session colour")
    @MainActor
    func resetRestoresDefault() throws {
        let defaults = try makeDefaults()
        FlashTintPreference.set(.tint(.rose), defaults: defaults)

        AppSettingsManager.resetPreferences(
            defaults: defaults,
            resetAnalysisPreferences: false
        )

        #expect(FlashTintPreference.current(defaults: defaults) == .matchSession)
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> UserDefaults {
        let name = "FlashTintTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
