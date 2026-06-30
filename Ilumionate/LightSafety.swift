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

/// Seizure-safety limits for the light entrainment / flash path.
enum LightSafety {
    /// Hard upper bound for any flash/strobe frequency, in Hz.
    ///
    /// Matches the documented generation safety max (`SessionGenerator`'s
    /// `GenerationConfig.maxFrequency = 40`). The Harding/photosensitive-epilepsy
    /// guidance treats the ~3–60 Hz band as the high-risk flash range; capping at
    /// 40 Hz keeps the engine input below the most reactive part of that band.
    /// This is the strictest documented value in the app — do not raise it.
    static let maxFlashHz: Double = 40.0

    /// Clamp a requested flash/strobe frequency to the safe range.
    /// Frequencies are also floored at a small positive value so the period
    /// (`1 / frequency`) never divides by zero.
    static func clampFlashHz(_ frequency: Double) -> Double {
        guard frequency.isFinite else { return maxFlashHz }
        return max(0.1, min(frequency, maxFlashHz))
    }
}
