//  VisualTint.swift
//  Ilumionate
//
//  The colour driving a wordless Visual Field. The reader takes its tint from
//  the reading phase instead — see TrancePhase.atmosphereColor.
//
//  The palette cases are drawn from the app's existing phase table so a Visual
//  Field session looks like it belongs to this app. `.custom` exists because a
//  fixed palette eventually feels like a cage.
//
//  THE FLOOR IS LOAD-BEARING. `tint` multiplies the shader's output, so a very
//  dark colour does not render a moody field — it renders a black rectangle that
//  reads as a broken screen. Dark picks are lifted, not rejected.

import SwiftUI

enum VisualTint: Codable, Equatable, Hashable, Sendable {
    case teal
    case violet
    case rose
    case amber
    case ice
    case gold
    /// `RRGGBB`, with or without a leading `#`.
    case custom(String)

    static let `default`: VisualTint = .violet

    /// The named cases, in picker order. Deliberately not `allCases`: `custom`
    /// carries a payload and has no place in a swatch list.
    static let palette: [VisualTint] = [.teal, .violet, .rose, .amber, .ice, .gold]

    var displayName: String {
        switch self {
        case .teal:   return "Teal"
        case .violet: return "Violet"
        case .rose:   return "Rose"
        case .amber:  return "Amber"
        case .ice:    return "Ice"
        case .gold:   return "Gold"
        case .custom: return "Custom"
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    // MARK: - Resolution

    var color: Color {
        switch self {
        case .teal:   return .phaseInduction
        case .violet: return .phaseDeepener
        case .rose:   return .phaseSuggestion
        case .amber:  return .phaseFractionation
        case .ice:    return .bwAlpha
        case .gold:   return .phaseAwakening
        case .custom(let hex):
            guard let channels = Self.channels(fromHex: hex) else {
                return Self.default.color
            }
            let lifted = Self.lift(
                red: channels.red, green: channels.green, blue: channels.blue
            )
            return Color(red: lifted.red, green: lifted.green, blue: lifted.blue)
        }
    }

    // MARK: - Hex parsing

    struct Channels: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// Parses `RRGGBB`, with or without a leading `#`. Returns nil for anything
    /// else so the caller can fall back rather than render black.
    static func channels(fromHex hex: String) -> Channels? {
        let trimmed = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing("#", with: "")
        guard trimmed.count == 6,
              trimmed.allSatisfy(\.isHexDigit),
              let value = Int(trimmed, radix: 16) else { return nil }
        return Channels(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue:  Double(value & 0xFF) / 255
        )
    }

    // MARK: - Luminance floor

    /// Below this, a tint renders as an apparently broken screen rather than as
    /// a dark mood. Chosen so every curated palette case clears it comfortably.
    static let luminanceFloor: Double = 0.30

    /// Rec. 709 relative luminance.
    static func luminance(_ channels: Channels) -> Double {
        0.2126 * channels.red + 0.7152 * channels.green + 0.0722 * channels.blue
    }

    /// Lifts a colour to the floor, preserving hue where there is a hue to
    /// preserve. Pure black has none to keep, so it becomes neutral grey.
    static func lift(red: Double, green: Double, blue: Double) -> Channels {
        let clamped = Channels(
            red: min(max(red, 0), 1),
            green: min(max(green, 0), 1),
            blue: min(max(blue, 0), 1)
        )
        let current = luminance(clamped)
        guard current < luminanceFloor else { return clamped }
        guard current > 0 else {
            return Channels(
                red: luminanceFloor, green: luminanceFloor, blue: luminanceFloor
            )
        }
        // Scale toward WHITE, not by a multiplier on the channels. Pure blue has
        // luminance 0.0722 with its channel already at 1.0, so multiplying can
        // never reach the floor — it just saturates to the same blue. Mixing
        // toward white always can.
        let headroom = max(1 - current, 0.0001)
        let t = min(max((luminanceFloor - current) / headroom, 0), 1)
        return Channels(
            red: clamped.red + (1 - clamped.red) * t,
            green: clamped.green + (1 - clamped.green) * t,
            blue: clamped.blue + (1 - clamped.blue) * t
        )
    }
}
