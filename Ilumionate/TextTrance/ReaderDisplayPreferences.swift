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
    var colorMode: ReaderColorMode

    init(theme: ReaderTheme = .void,
         font: ReaderFont = .monospaced,
         fontScale: Double = 1.0,
         lineSpacing: Double = 1.0,
         orpColor: ReaderORPColor = .teal,
         backgroundBrightness: Double = 0.5,
         hideControls: Bool = false,
         dyslexiaFriendly: Bool = false,
         colorMode: ReaderColorMode = .followApp) {
        self.theme = theme
        self.font = font
        self.fontScale = fontScale
        self.lineSpacing = lineSpacing
        self.orpColor = orpColor
        self.backgroundBrightness = backgroundBrightness
        self.hideControls = hideControls
        self.dyslexiaFriendly = dyslexiaFriendly
        self.colorMode = colorMode
    }

    private enum CodingKeys: String, CodingKey {
        case theme, font, fontScale, lineSpacing, orpColor
        case backgroundBrightness, hideControls, dyslexiaFriendly, colorMode
    }

    // Custom decoder so prefs persisted before colorMode existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decode(ReaderTheme.self, forKey: .theme)
        font = try c.decode(ReaderFont.self, forKey: .font)
        fontScale = try c.decode(Double.self, forKey: .fontScale)
        lineSpacing = try c.decode(Double.self, forKey: .lineSpacing)
        orpColor = try c.decode(ReaderORPColor.self, forKey: .orpColor)
        backgroundBrightness = try c.decode(Double.self, forKey: .backgroundBrightness)
        hideControls = try c.decode(Bool.self, forKey: .hideControls)
        dyslexiaFriendly = try c.decode(Bool.self, forKey: .dyslexiaFriendly)
        colorMode = try c.decodeIfPresent(ReaderColorMode.self, forKey: .colorMode) ?? .followApp
    }

    static let standard = ReaderDisplayPreferences()
}

enum ReaderTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case void
    case dawn
    case dusk
    case paper
    case sepia
    case highContrast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .void: return "Void"
        case .dawn: return "Dawn"
        case .dusk: return "Dusk"
        case .paper: return "Paper"
        case .sepia: return "Sepia"
        case .highContrast: return "Contrast"
        }
    }

    var background: Color {
        switch self {
        case .void: return .voidDeep
        case .dawn: return .dawnPrimary
        case .dusk: return Color(hex: "101927")
        case .paper: return Color(hex: "F4F0E8")
        case .sepia: return Color(hex: "EAD8B8")
        case .highContrast: return .black
        }
    }

    var text: Color {
        switch self {
        case .void, .dusk, .highContrast: return .textBright
        case .dawn: return Color(hex: PinkAuroraHex.textInk)
        case .paper: return Color(hex: "1D2530")
        case .sepia: return Color(hex: "2F2418")
        }
    }

    var secondaryText: Color {
        switch self {
        case .void, .dusk, .highContrast: return .textDim
        case .dawn: return Color(hex: PinkAuroraHex.textMuted)
        case .paper: return Color(hex: "657181")
        case .sepia: return Color(hex: "735E42")
        }
    }

    var showsPhaseAtmosphere: Bool {
        switch self {
        case .void, .dusk, .dawn: return true
        case .paper, .sepia, .highContrast: return false
        }
    }

    var isDark: Bool {
        switch self {
        case .void, .dusk, .highContrast: return true
        case .paper, .sepia, .dawn: return false
        }
    }
}

enum ReaderColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case followApp
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .followApp: return "Follow App"
        case .light: return "Light"
        case .dark: return "Dark"
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
        case .teal: return .roseGold
        case .blue: return .roseDeep
        case .amber: return .warmAccent
        case .pink: return .blush
        // "White" means "match body text" — pure white would vanish on Dawn.
        case .white: return Color(light: Color(hex: PinkAuroraHex.textInk), dark: .white)
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

    /// The color scheme the reader should render in, honoring the override.
    func resolvedScheme(appColorScheme: ColorScheme) -> ColorScheme {
        switch colorMode {
        case .followApp: return appColorScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// A copy whose theme matches the resolved scheme: dark themes swap to
    /// .dawn under a light scheme; light themes swap to .void under dark.
    func resolved(appColorScheme: ColorScheme) -> ReaderDisplayPreferences {
        let scheme = resolvedScheme(appColorScheme: appColorScheme)
        var copy = self
        if scheme == .light && theme.isDark {
            copy.theme = .dawn
        } else if scheme == .dark && !theme.isDark {
            copy.theme = .void
        }
        return copy
    }
}

private extension Color {
    func blend(with overlay: Color, opacity: Double) -> Color {
        self.opacity(1 - opacity).mix(with: overlay, by: opacity)
    }
}
