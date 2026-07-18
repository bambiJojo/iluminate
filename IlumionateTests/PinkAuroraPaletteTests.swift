//
//  PinkAuroraPaletteTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct PinkAuroraPaletteTests {

    @Test("Dawn background hex values are the approved Pink Aurora palette")
    func dawnHexValues() {
        #expect(PinkAuroraHex.dawnDeep == "FFE9F4")
        #expect(PinkAuroraHex.dawnPrimary == "FFF3F9")
        #expect(PinkAuroraHex.dawnElevated == "FFFFFF")
    }

    @Test("Accent hex values are the approved Pink Aurora palette")
    func accentHexValues() {
        #expect(PinkAuroraHex.accentTeal == "0B8A76")
        #expect(PinkAuroraHex.accentBlue == "4D6DF0")
        #expect(PinkAuroraHex.hotPink == "FF2D8F")
        #expect(PinkAuroraHex.violet == "9A4DC8")
        #expect(PinkAuroraHex.peach == "C4611A")
    }

    @Test("dawnPrimary is very light — luminance well above mid-grey")
    func dawnPrimaryIsLight() {
        let l = relativeLuminance(hex: PinkAuroraHex.dawnPrimary)
        #expect(l > 0.85)
    }

    @Test("Ink text on dawnPrimary meets WCAG AA for body text (>= 4.5:1)")
    func textInkContrast() {
        #expect(contrastRatio(PinkAuroraHex.textInk, PinkAuroraHex.dawnPrimary) >= 4.5)
    }

    @Test("Muted text on dawnPrimary meets WCAG AA for body text (>= 4.5:1)")
    func textMutedContrast() {
        #expect(contrastRatio(PinkAuroraHex.textMuted, PinkAuroraHex.dawnPrimary) >= 4.5)
    }

    @Test("All accents meet WCAG 3:1 for UI elements on dawnPrimary",
          arguments: [
              PinkAuroraHex.accentTeal, PinkAuroraHex.accentBlue,
              PinkAuroraHex.hotPink, PinkAuroraHex.violet, PinkAuroraHex.peach,
              PinkAuroraHex.bwDelta, PinkAuroraHex.bwTheta, PinkAuroraHex.bwAlpha,
              PinkAuroraHex.bwBeta, PinkAuroraHex.bwGamma,
              PinkAuroraHex.phaseIntro, PinkAuroraHex.phaseInduction,
              PinkAuroraHex.phaseDeepener, PinkAuroraHex.phaseFractionation,
              PinkAuroraHex.phaseSuggestion, PinkAuroraHex.phaseAwakening
          ])
    func accentContrast(hex: String) {
        #expect(contrastRatio(hex, PinkAuroraHex.dawnPrimary) >= 3.0)
    }

    // MARK: - Helpers (sRGB relative luminance per WCAG 2.1)

    private func relativeLuminance(hex: String) -> Double {
        let (r, g, b) = rgb(hex)
        func lin(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private func contrastRatio(_ a: String, _ b: String) -> Double {
        let la = relativeLuminance(hex: a)
        let lb = relativeLuminance(hex: b)
        let hi = max(la, lb), lo = min(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }

    private func rgb(_ hex: String) -> (Double, Double, Double) {
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        return (Double(int >> 16) / 255.0,
                Double(int >> 8 & 0xFF) / 255.0,
                Double(int & 0xFF) / 255.0)
    }
}
