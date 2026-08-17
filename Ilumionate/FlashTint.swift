//
//  FlashTint.swift
//  Ilumionate
//
//  The colour the flash field renders with.
//
//  Sessions carry a `color_temperature` in Kelvin, which `Color.fromKelvin`
//  maps through a blackbody curve: candle amber at 2000K to cool blue-white at
//  6500K. That curve has no teal, violet, or rose anywhere on it, so exposing
//  it alone could never answer a request for "more colours to flash with".
//
//  This overrides the resolved colour at render time only. Session JSON, the
//  generator, and the AI models keep working in Kelvin and are untouched —
//  which is the whole point of putting the override here rather than in
//  `LightMoment`.
//

import SwiftUI

enum FlashTint: Codable, Equatable, Sendable {
    /// Render whatever colour temperature the session asked for.
    case matchSession
    /// Render this colour instead, whatever the session asked for.
    case tint(VisualTint)

    static let `default`: FlashTint = .matchSession

    /// The chosen colour, or `nil` when the session's own Kelvin value wins.
    var overrideTint: VisualTint? {
        guard case .tint(let tint) = self else { return nil }
        return tint
    }

    /// Resolves against the session's colour temperature.
    ///
    /// `VisualTint.color` applies the palette's luminance floor, so a very dark
    /// custom pick is lifted rather than rendering the screen as black.
    func color(colorTemperature: Int) -> Color {
        overrideTint?.color ?? Color.fromKelvin(colorTemperature)
    }

    var displayName: String {
        switch self {
        case .matchSession:      return "Match Session"
        case .tint(let tint):    return tint.displayName
        }
    }
}

// MARK: - Persistence

enum FlashTintPreference {

    /// Falls back to `.matchSession` for both an unset and an unreadable value,
    /// so a bad write can never leave the flash field unrenderable.
    static func current(defaults: UserDefaults = .standard) -> FlashTint {
        guard
            let data = defaults.data(forKey: AppSettingsManager.Key.flashTint),
            let decoded = try? JSONDecoder().decode(FlashTint.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func set(_ tint: FlashTint, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(tint) else { return }
        defaults.set(data, forKey: AppSettingsManager.Key.flashTint)
    }
}
