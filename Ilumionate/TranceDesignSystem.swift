//
//  TranceDesignSystem.swift
//  Ilumionate
//
//  Trance Design System — Pink Light Mode + Dark Mode
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Dynamic Color Helper

extension Color {
    /// Creates a color that adapts between light and dark mode.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #elseif canImport(AppKit)
        let adaptive = NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(match == .darkAqua ? dark : light)
        }
        self.init(nsColor: adaptive)
        #else
        self = light
        #endif
    }
}

// MARK: - Trance Color Palette (Light + Dark)

struct TranceColors {

    // MARK: Backgrounds (dawn in light / Liminal void in dark)
    static let bgDeep      = Color(light: .dawnDeep, dark: .voidDeep)
    static let bgPrimary   = Color(light: .dawnPrimary, dark: .voidPrimary)
    static let bgSecondary = Color(light: .dawnElevated, dark: .voidElevated)
    static let bgCard      = Color(
        light: Color.white.opacity(0.72),
        dark: Color.voidElevated.opacity(0.65)
    )

    // MARK: Accents (aurora)
    static let roseGold   = Color(light: Color(hex: PinkAuroraHex.accentTeal), dark: .auroraTeal)
    static let roseDeep   = Color(light: Color(hex: PinkAuroraHex.accentBlue), dark: .auroraBlue)
    static let blush      = Color(light: Color(hex: PinkAuroraHex.hotPink), dark: .auroraPink)
    static let lavender   = Color(light: Color(hex: PinkAuroraHex.violet), dark: .auroraViolet)
    static let warmAccent = Color(light: Color(hex: PinkAuroraHex.peach), dark: Color(hex: "E8B07A"))

    // MARK: Text
    static let textPrimary   = Color(light: Color(hex: PinkAuroraHex.textInk), dark: .textBright)
    static let textSecondary = Color(light: Color(hex: PinkAuroraHex.textMuted), dark: .textDim)
    static let textLight     = Color(light: Color(hex: PinkAuroraHex.textWhisper), dark: .textGhost)

    // MARK: Borders & Glass
    static let glassBorder = Color(
        light: Color(hex: PinkAuroraHex.hotPink).opacity(0.18),
        dark: Color.auroraBlue.opacity(0.18)
    )
    static let glassFill = Color(
        light: Color.white.opacity(0.60),
        dark: Color.white.opacity(0.06)
    )

    // MARK: Brainwave Zone Colors
    static let bwDelta = Color(light: Color(hex: PinkAuroraHex.bwDelta), dark: Color(hex: "8B6BA8"))
    static let bwTheta = Color(light: Color(hex: PinkAuroraHex.bwTheta), dark: Color(hex: "B07DC8"))
    static let bwAlpha = Color(light: Color(hex: PinkAuroraHex.bwAlpha), dark: Color(hex: "7C9EFF"))
    static let bwBeta  = Color(light: Color(hex: PinkAuroraHex.bwBeta), dark: Color(hex: "7EE8D8"))
    static let bwGamma = Color(light: Color(hex: PinkAuroraHex.bwGamma), dark: Color(hex: "E8B07A"))

    // MARK: Hypnosis Phase Colors
    static let phaseIntro         = Color(light: Color(hex: PinkAuroraHex.phaseIntro), dark: Color(hex: "7C9EFF"))
    static let phaseInduction     = Color(light: Color(hex: PinkAuroraHex.phaseInduction), dark: Color(hex: "7EE8D8"))
    static let phaseDeepener      = Color(light: Color(hex: PinkAuroraHex.phaseDeepener), dark: Color(hex: "B07DC8"))
    static let phaseFractionation = Color(light: Color(hex: PinkAuroraHex.phaseFractionation), dark: Color(hex: "E8B07A"))
    static let phaseSuggestion    = Color(light: Color(hex: PinkAuroraHex.phaseSuggestion), dark: Color(hex: "E87CB8"))
    static let phaseAwakening     = Color(light: Color(hex: PinkAuroraHex.phaseAwakening), dark: Color(hex: "F5D08E"))

    // MARK: Flash Mode Colors (light-therapy output — hue-locked, NEVER adaptive)
    // flashOn must stay bright/visible; flashOff goes to true void.
    static let flashOn  = Color(hex: "F8C8D4")
    static let flashOff = Color.voidDeep
}

// MARK: - Color Extension — Semantic Accessors

extension Color {
    static let bgDeep             = TranceColors.bgDeep
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
    static var bgDeep: Color             { .bgDeep }
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
        var extra: CGFloat = 0
        if NowPlayingState.shared.isActive {
            extra += miniPlayerHeight + inner
        }
        // The analysis overlay sits above the mini-player while files are being
        // analyzed; without this, screen CTAs render underneath it.
        let overlayHeight = BottomChromeMetrics.shared.analysisOverlayHeight
        if overlayHeight > 0 {
            extra += overlayHeight + inner
        }
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
    // Card glow (soft aurora bloom instead of a dark drop shadow)
    static let card = (
        color: Color.roseDeep.opacity(0.10),
        radius: 16.0,
        x: 0.0,
        y: 0.0
    )

    // CTA button glow
    static let button = (
        color: Color.roseGold.opacity(0.35),
        radius: 18.0,
        x: 0.0,
        y: 6.0
    )

    // Category icon halo glow
    static func iconHalo(_ color: Color) -> (Color, CGFloat, CGFloat, CGFloat) {
        return (color.opacity(0.4), 14.0, 0.0, 0.0)
    }

    // Elevated card glow
    static let elevated = (
        color: Color.roseDeep.opacity(0.18),
        radius: 20.0,
        x: 0.0,
        y: 0.0
    )

    // Phone frame (dev preview only)
    static let phoneFrame = (
        color: Color.black.opacity(0.5),
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

    // Monospaced data readout (frequency / Hz / counts) — the instrument showing through (spec §2.2)
    static let dataReadout = Font.system(size: 18, weight: .semibold, design: .monospaced)

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

    #if canImport(UIKit)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    #endif

    private init() {}

    // Tab switch
    func light() {
        guard AppSettingsManager.isHapticFeedbackEnabled() else { return }
        #if canImport(UIKit)
        lightImpact.impactOccurred()
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }

    // Play/Pause, Start Session
    func medium() {
        guard AppSettingsManager.isHapticFeedbackEnabled() else { return }
        #if canImport(UIKit)
        mediumImpact.impactOccurred()
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }

    // Enter Flash
    func heavy() {
        guard AppSettingsManager.isHapticFeedbackEnabled() else { return }
        #if canImport(UIKit)
        heavyImpact.impactOccurred()
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #endif
    }

    // Color dot select
    func selection() {
        guard AppSettingsManager.isHapticFeedbackEnabled() else { return }
        #if canImport(UIKit)
        selectionFeedback.selectionChanged()
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }
}
