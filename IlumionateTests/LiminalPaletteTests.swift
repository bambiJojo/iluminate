//
//  LiminalPaletteTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct LiminalPaletteTests {

    @Test("Void hex values are the approved Liminal palette")
    func voidHexValues() {
        #expect(LiminalHex.voidDeep == "03040C")
        #expect(LiminalHex.voidPrimary == "070D1F")
        #expect(LiminalHex.voidElevated == "0D1428")
    }

    @Test("Aurora accent hex values are the approved Liminal palette")
    func auroraHexValues() {
        #expect(LiminalHex.auroraTeal == "7EE8D8")
        #expect(LiminalHex.auroraBlue == "7C9EFF")
        #expect(LiminalHex.auroraViolet == "B07DC8")
        #expect(LiminalHex.auroraPink == "E87CB8")
    }

    @Test("voidPrimary is very dark — luminance well below mid-grey")
    func voidPrimaryIsDark() {
        let l = relativeLuminance(hex: LiminalHex.voidPrimary)
        #expect(l < 0.05)
    }

    @Test("textBright on voidPrimary meets WCAG AA for body text (>= 4.5:1)")
    func textBrightContrast() {
        let ratio = contrastRatio(LiminalHex.textBright, LiminalHex.voidPrimary)
        #expect(ratio >= 4.5)
    }

    @Test("textDim on voidPrimary meets WCAG AA for body text (>= 4.5:1)")
    func textDimContrast() {
        let ratio = contrastRatio(LiminalHex.textDim, LiminalHex.voidPrimary)
        #expect(ratio >= 4.5)
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
