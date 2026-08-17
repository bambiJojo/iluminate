//
//  SteadyLightPreference.swift
//  Ilumionate
//
//  Whether the light field should hold a steady brightness instead of
//  oscillating.
//
//  The engine has always been able to render a steady field, but the only way
//  to ask for it was the system-wide Reduce Motion setting — so a user who
//  wanted steady light had to change it for their whole device. This adds an
//  in-app toggle that reaches the same code paths.
//
//  THE UNION IS DELIBERATE. The app toggle can only ever *add* steadiness.
//  System Reduce Motion still wins on its own, so turning the in-app toggle
//  off can never opt a motion-sensitive user back into strobing.
//

import Foundation

@MainActor
enum SteadyLightPreference {

    /// Resolves the two independent sources of "hold the light steady".
    ///
    /// Pure and isolation-free so the light paths can be tested without a
    /// live `UserDefaults` or a running accessibility environment.
    nonisolated static func prefersSteadyLight(
        userPrefersSteadyLight: Bool,
        systemReduceMotion: Bool
    ) -> Bool {
        userPrefersSteadyLight || systemReduceMotion
    }

    /// The stored in-app preference, independent of any system setting.
    nonisolated static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: AppSettingsManager.Key.steadyLightEnabled)
    }

    nonisolated static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: AppSettingsManager.Key.steadyLightEnabled)
    }

    /// The live answer for non-SwiftUI callers (display-link callbacks), which
    /// have no access to the `accessibilityReduceMotion` environment value.
    ///
    /// Read per frame rather than cached so a mid-session toggle of either
    /// source takes effect immediately — both reads are in-memory.
    static func prefersSteadyLight(defaults: UserDefaults = .standard) -> Bool {
        prefersSteadyLight(
            userPrefersSteadyLight: isEnabled(defaults: defaults),
            systemReduceMotion: PlatformAccessibility.isReduceMotionEnabled
        )
    }
}
