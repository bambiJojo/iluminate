//
//  LightSafety.swift
//  Ilumionate
//
//  Single source of truth for photosensitivity / seizure-safety limits in the
//  light-flashing path. Any code that drives strobe/flash frequency MUST route
//  through `clampFlashHz(_:)` at the engine input boundary so no path (UI
//  sliders, generated sessions, JSON sessions) can exceed the documented cap.
//

import Foundation

/// Conservative limits for the full-screen flashing-light path.
enum LightSafety {
    /// Hard upper bound for any flash/strobe frequency, in Hz.
    ///
    /// W3C WCAG 2.3.2 disallows more than three flashes in any one-second
    /// period regardless of brightness or area. The app uses large/full-screen
    /// fields and has not been certified with a flash-analysis tool, so this
    /// simple, testable ceiling is the release boundary. Do not raise it based
    /// on a warning or a claimed physiological effect.
    static let maxFlashHz: Double = 3.0

    static let flashFrequencyRange: ClosedRange<Double> = 0.5...maxFlashHz

    /// Clamp a requested flash/strobe frequency to the safe range.
    /// Frequencies are also floored at a small positive value so the period
    /// (`1 / frequency`) never divides by zero.
    static func clampFlashHz(_ frequency: Double) -> Double {
        guard frequency.isFinite else { return maxFlashHz }
        return max(0.1, min(frequency, maxFlashHz))
    }
}
