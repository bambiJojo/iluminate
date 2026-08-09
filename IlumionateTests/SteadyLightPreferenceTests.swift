//
//  SteadyLightPreferenceTests.swift
//  IlumionateTests
//
//  The steady-light preference is the in-app escape hatch from the strobing
//  light field. It has to hold two guarantees: the user's own toggle works
//  without touching system settings, and system Reduce Motion still wins even
//  when the app-level toggle is off.
//

import Foundation
import Testing

@testable import Ilumionate

@Suite("Steady light preference")
struct SteadyLightPreferenceTests {

    // MARK: - Resolver

    @Test(
        "Either source alone holds the light steady",
        arguments: [
            (user: false, system: false, expected: false),
            (user: true,  system: false, expected: true),
            (user: false, system: true,  expected: true),
            (user: true,  system: true,  expected: true)
        ]
    )
    func resolverIsTheUnionOfBothSources(
        testCase: (user: Bool, system: Bool, expected: Bool)
    ) {
        let resolved = SteadyLightPreference.prefersSteadyLight(
            userPrefersSteadyLight: testCase.user,
            systemReduceMotion: testCase.system
        )

        #expect(resolved == testCase.expected)
    }

    @Test("System Reduce Motion cannot be overridden by the app toggle")
    func systemReduceMotionAlwaysWins() {
        // The in-app toggle is an additive escape hatch, never a way to opt
        // back into strobing after the system asked for reduced motion.
        #expect(
            SteadyLightPreference.prefersSteadyLight(
                userPrefersSteadyLight: false,
                systemReduceMotion: true
            )
        )
    }

    // MARK: - Persistence

    @Test("Defaults to off so existing sessions keep their entrainment")
    func defaultsToDisabled() throws {
        let defaults = try makeDefaults()

        #expect(SteadyLightPreference.isEnabled(defaults: defaults) == false)
    }

    @Test("Round-trips through UserDefaults")
    func persistsUserChoice() throws {
        let defaults = try makeDefaults()

        SteadyLightPreference.setEnabled(true, defaults: defaults)
        #expect(SteadyLightPreference.isEnabled(defaults: defaults))

        SteadyLightPreference.setEnabled(false, defaults: defaults)
        #expect(SteadyLightPreference.isEnabled(defaults: defaults) == false)
    }

    @Test("Stores under the shared settings key so resets reach it")
    func usesTheSharedSettingsKey() throws {
        let defaults = try makeDefaults()

        SteadyLightPreference.setEnabled(true, defaults: defaults)

        #expect(defaults.bool(forKey: AppSettingsManager.Key.steadyLightEnabled))
    }

    @Test("Preference reset turns steady light back off")
    @MainActor
    func resetRestoresTheDefault() throws {
        let defaults = try makeDefaults()
        SteadyLightPreference.setEnabled(true, defaults: defaults)

        AppSettingsManager.resetPreferences(
            defaults: defaults,
            resetAnalysisPreferences: false
        )

        #expect(SteadyLightPreference.isEnabled(defaults: defaults) == false)
    }

    // MARK: - Helpers

    /// An isolated defaults suite so tests never read or clobber the real one.
    private func makeDefaults() throws -> UserDefaults {
        let name = "SteadyLightPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
