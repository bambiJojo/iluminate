//
//  PinkAuroraPalette.swift
//  Ilumionate
//
//  Single source of truth for the Pink Aurora (light mode) raw colors.
//  Semantic tokens in TranceDesignSystem.swift resolve to these in light mode
//  and to LiminalPalette values in dark mode.
//

import SwiftUI

/// Raw Pink Aurora hex strings. Kept as strings so they can be unit-tested
/// without constructing UIColors on a background thread.
/// Accents are deepened relative to their Liminal counterparts so they meet
/// WCAG 3:1 on the blush dawnPrimary background (text colors meet 4.5:1).
enum PinkAuroraHex {
    // Dawn backgrounds
    static let dawnDeep     = "FFE9F4"
    static let dawnPrimary  = "FFF3F9"
    static let dawnElevated = "FFFFFF"

    // Aurora accents (deepened)
    static let accentTeal = "0B8A76"
    static let accentBlue = "4D6DF0"
    static let hotPink    = "FF2D8F"
    static let violet     = "9A4DC8"
    static let peach      = "C4611A"

    // Text
    static let textInk     = "231024"
    static let textMuted   = "7A5A80"
    static let textWhisper = "B08DB8"

    // Brainwave zones
    static let bwDelta = "6B4788"
    static let bwTheta = "9A4DC8"
    static let bwAlpha = "4D6DF0"
    static let bwBeta  = "0B8A76"
    static let bwGamma = "C4611A"

    // Hypnosis phases
    static let phaseIntro         = "4D6DF0"
    static let phaseInduction     = "0B8A76"
    static let phaseDeepener      = "9A4DC8"
    static let phaseFractionation = "C4611A"
    static let phaseSuggestion    = "FF2D8F"
    static let phaseAwakening     = "A87400"
}

extension Color {
    static let dawnDeep     = Color(hex: PinkAuroraHex.dawnDeep)
    static let dawnPrimary  = Color(hex: PinkAuroraHex.dawnPrimary)
    static let dawnElevated = Color(hex: PinkAuroraHex.dawnElevated)
}
