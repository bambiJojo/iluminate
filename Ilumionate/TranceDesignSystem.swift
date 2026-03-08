//
//  TranceDesignSystem.swift
//  Ilumionate
//
//  Trance Design System - Pink Light Mode
//  Complete implementation following the app_design_spec.md
//

import SwiftUI

// MARK: - Design Tokens

// MARK: - Trance Color Palette

struct TranceColors {
    // MARK: - Backgrounds
    static let bgPrimary    = Color(red: 1.0, green: 0.961, blue: 0.969)    // FFF5F7 near-white blush
    static let bgSecondary  = Color(red: 1.0, green: 0.925, blue: 0.941)    // FFECF0 soft rose tint
    static let bgCard       = Color(red: 1.0, green: 0.894, blue: 0.910).opacity(0.55) // FFE4E8 glass card fill

    // MARK: - Accents
    static let roseGold     = Color(red: 0.831, green: 0.471, blue: 0.604)  // D4789A primary accent
    static let roseDeep     = Color(red: 0.753, green: 0.376, blue: 0.502)  // C06080 pressed / CTA gradient end
    static let blush        = Color(red: 0.973, green: 0.784, blue: 0.831)  // F8C8D4 soft highlights
    static let lavender     = Color(red: 0.910, green: 0.816, blue: 0.941)  // E8D0F0 tertiary accent
    static let warmAccent   = Color(red: 0.961, green: 0.780, blue: 0.557)  // F5C78E amber/warm touches

    // MARK: - Text
    static let textPrimary   = Color(red: 0.290, green: 0.125, blue: 0.208) // 4A2035 dark plum
    static let textSecondary = Color(red: 0.541, green: 0.376, blue: 0.459) // 8A6075 mauve
    static let textLight     = Color(red: 0.690, green: 0.533, blue: 0.596) // B08898 muted labels

    // MARK: - Borders & Glass
    static let glassBorder  = Color(red: 0.910, green: 0.627, blue: 0.690).opacity(0.3) // E8A0B0
    static let glassFill    = Color.white.opacity(0.15)

    // MARK: - Brainwave Zone Colors
    static let bwDelta  = Color(red: 0.545, green: 0.420, blue: 0.659)  // 8B6BA8 indigo
    static let bwTheta  = Color(red: 0.690, green: 0.490, blue: 0.784)  // B07DC8 lavender-purple
    static let bwAlpha  = Color(red: 0.831, green: 0.471, blue: 0.604)  // D4789A rose
    static let bwBeta   = Color(red: 0.910, green: 0.541, blue: 0.604)  // E88A9A warm pink
    static let bwGamma  = Color(red: 0.961, green: 0.722, blue: 0.478)  // F5B87A peach gold

    // MARK: - Hypnosis Phase Colors
    static let phaseIntro         = Color(red: 0.471, green: 0.627, blue: 0.824) // 78A0D2 blue
    static let phaseInduction     = Color(red: 0.306, green: 0.804, blue: 0.769) // 4ECDC4 teal
    static let phaseDeepener      = Color(red: 0.545, green: 0.420, blue: 0.659) // 8B6BA8 indigo
    static let phaseFractionation = Color(red: 0.910, green: 0.627, blue: 0.376) // E8A060 amber
    static let phaseSuggestion    = Color(red: 0.831, green: 0.471, blue: 0.604) // D4789A rose
    static let phaseAwakening     = Color(red: 0.961, green: 0.780, blue: 0.557) // F5C78E peach

    // MARK: - Flash Mode Colors
    static let flashOn  = Color(red: 0.973, green: 0.784, blue: 0.831)  // F8C8D4 active pulse
    static let flashOff = Color(red: 1.0, green: 0.961, blue: 0.969)    // FFF5F7 rest state
}

extension Color {
    // MARK: - Convenience accessors for Trance colors
    static let bgPrimary = TranceColors.bgPrimary
    static let bgSecondary = TranceColors.bgSecondary
    static let bgCard = TranceColors.bgCard
    static let roseGold = TranceColors.roseGold
    static let roseDeep = TranceColors.roseDeep
    static let blush = TranceColors.blush
    static let lavender = TranceColors.lavender
    static let warmAccent = TranceColors.warmAccent
    static let textPrimary = TranceColors.textPrimary
    static let textSecondary = TranceColors.textSecondary
    static let textLight = TranceColors.textLight
    static let glassBorder = TranceColors.glassBorder
    static let glassFill = TranceColors.glassFill
    static let bwDelta = TranceColors.bwDelta
    static let bwTheta = TranceColors.bwTheta
    static let bwAlpha = TranceColors.bwAlpha
    static let bwBeta = TranceColors.bwBeta
    static let bwGamma = TranceColors.bwGamma
    static let phaseIntro = TranceColors.phaseIntro
    static let phaseInduction = TranceColors.phaseInduction
    static let phaseDeepener = TranceColors.phaseDeepener
    static let phaseFractionation = TranceColors.phaseFractionation
    static let phaseSuggestion = TranceColors.phaseSuggestion
    static let phaseAwakening = TranceColors.phaseAwakening
    static let flashOn = TranceColors.flashOn
    static let flashOff = TranceColors.flashOff
}

// MARK: - Spacing Scale

struct TranceSpacing {
    static let micro: CGFloat = 4      // micro gap (between caption lines)
    static let icon: CGFloat = 6       // icon-to-label inside cat items
    static let inner: CGFloat = 8      // inner card element spacing
    static let small: CGFloat = 10     // between small cards
    static let list: CGFloat = 12      // between list items
    static let cardMargin: CGFloat = 14 // card bottom margin / card-to-card
    static let card: CGFloat = 16      // standard card padding
    static let content: CGFloat = 20   // content horizontal inset
    static let screen: CGFloat = 22    // screen horizontal padding
    static let statusBar: CGFloat = 28 // status bar horizontal padding
}

// MARK: - Corner Radius Scale

struct TranceRadius {
    static let phoneFrame: CGFloat = 48    // phone frame (dev preview)
    static let glassCard: CGFloat = 18     // glass cards
    static let categoryIcon: CGFloat = 26  // category icons (full circle)
    static let thumbnail: CGFloat = 14     // library thumbnails
    static let button: CGFloat = 16        // CTA buttons
    static let pill: CGFloat = 20          // phase pill
    static let pattern: CGFloat = 18       // pattern cards
    static let tabItem: CGFloat = 10       // tab bar items
    static let toggle: CGFloat = 26        // toggle track (capsule)
}

// MARK: - Shadow Styles

struct TranceShadow {
    // Card shadow
    static let card = (
        color: Color(red: 0.353, green: 0.188, blue: 0.271).opacity(0.05), // 5A3045
        radius: 10.0,
        x: 0.0,
        y: 4.0
    )

    // CTA button shadow
    static let button = (
        color: Color.roseGold.opacity(0.3),
        radius: 12.0,
        x: 0.0,
        y: 8.0
    )

    // Category icon halo glow
    static func iconHalo(_ color: Color) -> (Color, CGFloat, CGFloat, CGFloat) {
        return (color.opacity(0.3), 10.0, 0.0, 0.0)
    }

    // Elevated card hover
    static let elevated = (
        color: Color.roseGold.opacity(0.15),
        radius: 12.0,
        x: 0.0,
        y: 8.0
    )

    // Phone frame (dev preview only)
    static let phoneFrame = (
        color: Color(red: 0.353, green: 0.188, blue: 0.271).opacity(0.12), // 5A3045
        radius: 40.0,
        x: 0.0,
        y: 25.0
    )
}

// MARK: - Typography

struct TranceTypography {
    // Screen title
    static let screenTitle = Font.system(size: 18, weight: .semibold)

    // Greeting
    static let greeting = Font.system(size: 26, weight: .light)
    static let greetingAccent = Font.system(size: 26, weight: .medium)

    // Section title
    static let sectionTitle = Font.system(size: 16, weight: .semibold)

    // Card label
    static let cardLabel = Font.system(size: 11, weight: .semibold)

    // Body
    static let body = Font.system(size: 14, weight: .regular)

    // Caption
    static let caption = Font.system(size: 11, weight: .regular)

    // Frequency display
    static let frequency = Font.system(size: 18, weight: .semibold)

    // Track title and artist
    static let trackTitle = Font.system(size: 20, weight: .semibold)
    static let trackArtist = Font.system(size: 13, weight: .regular)

    // Tab label
    static let tabLabel = Font.system(size: 10, weight: .medium)
}

// MARK: - Glass Background View Modifier

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
            .overlay(
                RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
            .shadow(
                color: TranceShadow.card.color,
                radius: TranceShadow.card.radius,
                x: TranceShadow.card.x,
                y: TranceShadow.card.y
            )
    }
}

// MARK: - Haptic Feedback Manager

@MainActor
final class TranceHaptics {
    static let shared = TranceHaptics()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    private init() {}

    // Tab switch
    func light() {
        lightImpact.impactOccurred()
    }

    // Play/Pause, Start Session
    func medium() {
        mediumImpact.impactOccurred()
    }

    // Enter Flash
    func heavy() {
        heavyImpact.impactOccurred()
    }

    // Color dot select
    func selection() {
        selectionFeedback.selectionChanged()
    }
}