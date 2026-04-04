//
//  TranceDesignSystem.swift
//  Ilumionate
//
//  Trance Design System — Pink Light Mode + Dark Mode
//

import SwiftUI

// MARK: - Dynamic Color Helper

extension Color {
    /// Creates a color that adapts between light and dark mode.
    init(light: Color, dark: Color) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

// MARK: - Trance Color Palette (Light + Dark)

struct TranceColors {

    // MARK: Backgrounds
    static let bgPrimary   = Color(light: Color(hex: "FFF5F7"), dark: Color(hex: "1A0D14"))
    static let bgSecondary = Color(light: Color(hex: "FFECF0"), dark: Color(hex: "261219"))
    static let bgCard      = Color(
        light: Color(hex: "FFE4E8").opacity(0.55),
        dark:  Color(hex: "2E1520").opacity(0.65)
    )

    // MARK: Accents
    static let roseGold   = Color(light: Color(hex: "D4789A"), dark: Color(hex: "E896B4"))
    static let roseDeep   = Color(light: Color(hex: "C06080"), dark: Color(hex: "D4789A"))
    static let blush      = Color(light: Color(hex: "F8C8D4"), dark: Color(hex: "5A2A3A"))
    static let lavender   = Color(light: Color(hex: "E8D0F0"), dark: Color(hex: "3A2050"))
    static let warmAccent = Color(light: Color(hex: "F5C78E"), dark: Color(hex: "C4884A"))

    // MARK: Text
    static let textPrimary   = Color(light: Color(hex: "4A2035"), dark: Color(hex: "F5E8EE"))
    static let textSecondary = Color(light: Color(hex: "8A6075"), dark: Color(hex: "B08898"))
    static let textLight     = Color(light: Color(hex: "B08898"), dark: Color(hex: "6E4E5E"))

    // MARK: Borders & Glass
    static let glassBorder = Color(
        light: Color(hex: "E8A0B0").opacity(0.3),
        dark:  Color(hex: "7A3A55").opacity(0.35)
    )
    static let glassFill = Color(
        light: Color.white.opacity(0.15),
        dark:  Color.white.opacity(0.08)
    )

    // MARK: Brainwave Zone Colors (vivid — unchanged between modes)
    static let bwDelta = Color(hex: "8B6BA8")
    static let bwTheta = Color(hex: "B07DC8")
    static let bwAlpha = Color(hex: "D4789A")
    static let bwBeta  = Color(hex: "E88A9A")
    static let bwGamma = Color(hex: "F5B87A")

    // MARK: Hypnosis Phase Colors (vivid — unchanged)
    static let phaseIntro         = Color(hex: "78A0D2")
    static let phaseInduction     = Color(hex: "4ECDC4")
    static let phaseDeepener      = Color(hex: "8B6BA8")
    static let phaseFractionation = Color(hex: "E8A060")
    static let phaseSuggestion    = Color(hex: "D4789A")
    static let phaseAwakening     = Color(hex: "F5C78E")

    // MARK: Flash Mode Colors
    // flashOn stays rose in both modes (light therapy needs visibility).
    // flashOff goes near-black in dark for better contrast / immersion.
    static let flashOn  = Color(light: Color(hex: "F8C8D4"), dark: Color(hex: "F8C8D4"))
    static let flashOff = Color(light: Color(hex: "FFF5F7"), dark: Color(hex: "0A0508"))
}

// MARK: - Color Extension — Semantic Accessors

extension Color {
    static let bgPrimary          = TranceColors.bgPrimary
    static let bgSecondary        = TranceColors.bgSecondary
    static let bgCard             = TranceColors.bgCard
    static let roseGold           = TranceColors.roseGold
    static let roseDeep           = TranceColors.roseDeep
    static let blush              = TranceColors.blush
    static let lavender           = TranceColors.lavender
    static let warmAccent         = TranceColors.warmAccent
    static let textPrimary        = TranceColors.textPrimary
    static let textSecondary      = TranceColors.textSecondary
    static let textLight          = TranceColors.textLight
    static let glassBorder        = TranceColors.glassBorder
    static let glassFill          = TranceColors.glassFill
    static let bwDelta            = TranceColors.bwDelta
    static let bwTheta            = TranceColors.bwTheta
    static let bwAlpha            = TranceColors.bwAlpha
    static let bwBeta             = TranceColors.bwBeta
    static let bwGamma            = TranceColors.bwGamma
    static let phaseIntro         = TranceColors.phaseIntro
    static let phaseInduction     = TranceColors.phaseInduction
    static let phaseDeepener      = TranceColors.phaseDeepener
    static let phaseFractionation = TranceColors.phaseFractionation
    static let phaseSuggestion    = TranceColors.phaseSuggestion
    static let phaseAwakening     = TranceColors.phaseAwakening
    static let flashOn            = TranceColors.flashOn
    static let flashOff           = TranceColors.flashOff
}

// Expose Trance colors as ShapeStyle members so that `.foregroundStyle(.roseGold)`
// resolves correctly without needing an explicit `Color.` prefix.
extension ShapeStyle where Self == Color {
    static var bgPrimary: Color          { .bgPrimary }
    static var bgSecondary: Color        { .bgSecondary }
    static var bgCard: Color             { .bgCard }
    static var roseGold: Color           { .roseGold }
    static var roseDeep: Color           { .roseDeep }
    static var blush: Color              { .blush }
    static var lavender: Color           { .lavender }
    static var warmAccent: Color         { .warmAccent }
    static var textPrimary: Color        { .textPrimary }
    static var textSecondary: Color      { .textSecondary }
    static var textLight: Color          { .textLight }
    static var glassBorder: Color        { .glassBorder }
    static var glassFill: Color          { .glassFill }
    static var bwDelta: Color            { .bwDelta }
    static var bwTheta: Color            { .bwTheta }
    static var bwAlpha: Color            { .bwAlpha }
    static var bwBeta: Color             { .bwBeta }
    static var bwGamma: Color            { .bwGamma }
    static var phaseIntro: Color         { .phaseIntro }
    static var phaseInduction: Color     { .phaseInduction }
    static var phaseDeepener: Color      { .phaseDeepener }
    static var phaseFractionation: Color { .phaseFractionation }
    static var phaseSuggestion: Color    { .phaseSuggestion }
    static var phaseAwakening: Color     { .phaseAwakening }
    static var flashOn: Color            { .flashOn }
    static var flashOff: Color           { .flashOff }
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
    /// Height of the mini-player bar
    static let miniPlayerHeight: CGFloat = 56
    /// Base clearance for the floating tab bar alone.
    static let tabBarBase: CGFloat = 100
    /// Bottom clearance needed so content/toolbars don't hide under the floating tab bar
    /// (and optionally the mini-player).
    @MainActor static var tabBarClearance: CGFloat {
        let extra = NowPlayingState.shared.isActive ? miniPlayerHeight + inner : 0
        return tabBarBase + extra
    }
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

    // Phone frame (dev preview only)2
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

// MARK: - Button Styles

struct TranceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TranceTypography.body)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, TranceSpacing.content)
            .padding(.vertical, TranceSpacing.card)
            .background(
                RoundedRectangle(cornerRadius: TranceRadius.button)
                    .fill(
                        LinearGradient(
                            colors: [.roseGold, .roseDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(
                color: TranceShadow.button.color,
                radius: TranceShadow.button.radius,
                x: TranceShadow.button.x,
                y: TranceShadow.button.y
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
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
        guard AppSettingsManager.isHapticFeedbackEnabled() else { return }
        lightImpact.impactOccurred()
    }

    // Play/Pause, Start Session
    func medium() {
        guard AppSettingsManager.isHapticFeedbackEnabled() else { return }
        mediumImpact.impactOccurred()
    }

    // Enter Flash
    func heavy() {
        guard AppSettingsManager.isHapticFeedbackEnabled() else { return }
        heavyImpact.impactOccurred()
    }

    // Color dot select
    func selection() {
        guard AppSettingsManager.isHapticFeedbackEnabled() else { return }
        selectionFeedback.selectionChanged()
    }
}
