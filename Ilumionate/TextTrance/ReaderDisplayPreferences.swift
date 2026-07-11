//  ReaderDisplayPreferences.swift
//  Ilumionate
//
//  User-facing typography and color controls for the RSVP reader.

import SwiftUI

struct ReaderDisplayPreferences: Codable, Equatable, Sendable {
    var theme: ReaderTheme
    var font: ReaderFont
    var fontScale: Double
    var lineSpacing: Double
    var orpColor: ReaderORPColor
    var backgroundBrightness: Double
    var hideControls: Bool
    var dyslexiaFriendly: Bool

    init(theme: ReaderTheme = .void,
         font: ReaderFont = .monospaced,
         fontScale: Double = 1.0,
         lineSpacing: Double = 1.0,
         orpColor: ReaderORPColor = .teal,
         backgroundBrightness: Double = 0.5,
         hideControls: Bool = false,
         dyslexiaFriendly: Bool = false) {
        self.theme = theme
        self.font = font
        self.fontScale = fontScale
        self.lineSpacing = lineSpacing
        self.orpColor = orpColor
        self.backgroundBrightness = backgroundBrightness
        self.hideControls = hideControls
        self.dyslexiaFriendly = dyslexiaFriendly
    }

    static let standard = ReaderDisplayPreferences()
}

enum ReaderTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case void
    case dusk
    case paper
    case sepia
    case highContrast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .void: return "Void"
        case .dusk: return "Dusk"
        case .paper: return "Paper"
        case .sepia: return "Sepia"
        case .highContrast: return "Contrast"
        }
    }

    var background: Color {
        switch self {
        case .void: return .voidDeep
        case .dusk: return Color(hex: "101927")
        case .paper: return Color(hex: "F4F0E8")
        case .sepia: return Color(hex: "EAD8B8")
        case .highContrast: return .black
        }
    }

    var text: Color {
        switch self {
        case .void, .dusk, .highContrast: return .textBright
        case .paper: return Color(hex: "1D2530")
        case .sepia: return Color(hex: "2F2418")
        }
    }

    var secondaryText: Color {
        switch self {
        case .void, .dusk, .highContrast: return .textDim
        case .paper: return Color(hex: "657181")
        case .sepia: return Color(hex: "735E42")
        }
    }

    var showsPhaseAtmosphere: Bool {
        switch self {
        case .void, .dusk: return true
        case .paper, .sepia, .highContrast: return false
        }
    }
}

enum ReaderFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case monospaced
    case system
    case rounded
    case serif

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monospaced: return "Mono"
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        }
    }

    var design: Font.Design {
        switch self {
        case .monospaced: return .monospaced
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        }
    }
}

enum ReaderORPColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case teal
    case blue
    case amber
    case pink
    case white

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .amber: return "Amber"
        case .pink: return "Pink"
        case .white: return "White"
        }
    }

    var color: Color {
        switch self {
        case .teal: return .auroraTeal
        case .blue: return .auroraBlue
        case .amber: return .warmAccent
        case .pink: return .auroraPink
        case .white: return .white
        }
    }
}

extension ReaderDisplayPreferences {
    static let fontScaleRange: ClosedRange<Double> = 0.75...1.45
    static let lineSpacingRange: ClosedRange<Double> = 0.8...1.8
    static let backgroundBrightnessRange: ClosedRange<Double> = 0.2...0.9

    var clampedFontScale: Double {
        min(max(fontScale, Self.fontScaleRange.lowerBound), Self.fontScaleRange.upperBound)
    }

    var clampedLineSpacing: Double {
        min(max(lineSpacing, Self.lineSpacingRange.lowerBound), Self.lineSpacingRange.upperBound)
    }

    var clampedBackgroundBrightness: Double {
        min(
            max(backgroundBrightness, Self.backgroundBrightnessRange.lowerBound),
            Self.backgroundBrightnessRange.upperBound
        )
    }

    var effectiveFont: ReaderFont {
        dyslexiaFriendly ? .rounded : font
    }

    var effectiveFontWeight: Font.Weight {
        dyslexiaFriendly ? .medium : .regular
    }

    var lineSpacingPoints: CGFloat {
        CGFloat((clampedLineSpacing - 1.0) * 18.0)
    }

    var adjustedBackground: Color {
        let brightness = clampedBackgroundBrightness
        if brightness >= 0.5 {
            let opacity = (brightness - 0.5) * 0.55
            return theme.background.blend(with: .white, opacity: opacity)
        } else {
            let opacity = (0.5 - brightness) * 0.75
            return theme.background.blend(with: .black, opacity: opacity)
        }
    }

    var textColor: Color { theme.text }
    var secondaryTextColor: Color { theme.secondaryText }
    var pivotColor: Color { orpColor.color }
}

private extension Color {
    func blend(with overlay: Color, opacity: Double) -> Color {
        self.opacity(1 - opacity).mix(with: overlay, by: opacity)
    }
}
