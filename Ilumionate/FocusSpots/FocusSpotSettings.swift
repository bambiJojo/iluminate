//
//  FocusSpotSettings.swift
//  Ilumionate
//
//  Geometry for the optional pair of black focus spots drawn over the light
//  field — holes punched in the light for the eye to rest on.
//
//  Like `FlashTint`, this is a render-time display preference only. Nothing
//  here reaches `LightSession`, the session JSON schema, or `SessionGenerator`,
//  which is the whole point of keeping it in user preferences rather than in
//  the score.
//
//  Diameter and spacing are POINTS, not fractions of the screen: they are
//  aimed at a physical thing — your eyes — and should not rescale when the
//  window does. Vertical position is a FRACTION, because "upper third" is
//  inherently proportional and should hold across portrait, landscape, and a
//  resized Mac window.
//
//  Horizontal spacing and diameter are clamped independently, and a small
//  spacing paired with a large diameter is permitted even though the two
//  spots then overlap into a single blob. A cross-field invariant would mean
//  a slider that refuses to shrink, which is worse than the overlap it would
//  prevent — the calibration screen (Task 6) renders the pair live, so the
//  user sees and can correct an overlap immediately.
//

import Foundation

nonisolated struct FocusSpotSettings: Codable, Equatable, Sendable {
    /// Fraction of field height where the spot centres sit. 0 = top, 1 = bottom.
    var verticalPosition: Double
    /// Points between the two spot centres.
    var horizontalSpacing: Double
    /// Diameter of each spot, in points.
    var diameter: Double

    // MARK: - Ranges

    static let verticalPositionRange: ClosedRange<Double> = 0.1...0.9
    static let horizontalSpacingRange: ClosedRange<Double> = 40...400
    static let diameterRange: ClosedRange<Double> = 16...120

    /// The three vertical anchors the calibration slider snaps to: upper
    /// third, centre, lower third.
    static let verticalDetents: [Double] = [1.0 / 3.0, 0.5, 2.0 / 3.0]

    /// How close the slider must come to a detent before it snaps.
    static let detentTolerance: Double = 0.02

    static let `default` = FocusSpotSettings(
        verticalPosition: 1.0 / 3.0,
        horizontalSpacing: 180,
        diameter: 48
    )

    // MARK: - Clamping

    /// Every field forced into range, applied on read and on write so a
    /// hand-edited or partially-written value can never produce an
    /// unrenderable field.
    var clamped: FocusSpotSettings {
        FocusSpotSettings(
            verticalPosition: Self.clamp(
                verticalPosition,
                to: Self.verticalPositionRange,
                fallback: Self.default.verticalPosition
            ),
            horizontalSpacing: Self.clamp(
                horizontalSpacing,
                to: Self.horizontalSpacingRange,
                fallback: Self.default.horizontalSpacing
            ),
            diameter: Self.clamp(
                diameter,
                to: Self.diameterRange,
                fallback: Self.default.diameter
            )
        )
    }

    /// Snaps a vertical position onto the nearest detent when it is within
    /// tolerance, so upper third / centre / lower third stay one flick away
    /// while everything between them is still reachable.
    static func snappingVerticalPosition(_ value: Double) -> Double {
        let bounded = clamp(
            value,
            to: verticalPositionRange,
            fallback: Self.default.verticalPosition
        )
        guard
            let nearest = verticalDetents.min(by: {
                abs($0 - bounded) < abs($1 - bounded)
            })
        else {
            return bounded
        }
        return abs(nearest - bounded) <= detentTolerance ? nearest : bounded
    }

    /// `.nan` fails every comparison `min`/`max` make, so it is caught and
    /// replaced with the default explicitly; `.infinity` compares correctly
    /// and clamps to the relevant bound like any other out-of-range value.
    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard !value.isNaN else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Persistence

/// Reads and writes the stored preference.
///
/// Falls back to `.default` for an unset key or an undecodable value, and
/// clamps every field of a decoded value into range — a bad write can never
/// leave the field unrenderable.
nonisolated enum FocusSpotPreference {

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: AppSettingsManager.Key.focusSpotsEnabled)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: AppSettingsManager.Key.focusSpotsEnabled)
    }

    static func current(defaults: UserDefaults = .standard) -> FocusSpotSettings {
        guard
            let data = defaults.data(forKey: AppSettingsManager.Key.focusSpots),
            let decoded = try? JSONDecoder().decode(FocusSpotSettings.self, from: data)
        else {
            return .default
        }
        return decoded.clamped
    }

    static func set(_ settings: FocusSpotSettings, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings.clamped) else { return }
        defaults.set(data, forKey: AppSettingsManager.Key.focusSpots)
    }
}
