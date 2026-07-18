//
//  AdaptiveTokenTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
import UIKit
@testable import Ilumionate

@MainActor
struct AdaptiveTokenTests {

    private let lightTraits = UITraitCollection(userInterfaceStyle: .light)
    private let darkTraits  = UITraitCollection(userInterfaceStyle: .dark)

    private func resolvedHex(_ color: Color, _ traits: UITraitCollection) -> String {
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func h(_ c: CGFloat) -> String { String(format: "%02X", Int(round(c * 255))) }
        return h(r) + h(g) + h(b)
    }

    @Test("bgPrimary resolves to dawnPrimary in light and voidPrimary in dark")
    func bgPrimaryAdapts() {
        #expect(resolvedHex(.bgPrimary, lightTraits) == PinkAuroraHex.dawnPrimary)
        #expect(resolvedHex(.bgPrimary, darkTraits) == LiminalHex.voidPrimary)
    }

    @Test("bgDeep resolves to dawnDeep in light and voidDeep in dark")
    func bgDeepAdapts() {
        #expect(resolvedHex(.bgDeep, lightTraits) == PinkAuroraHex.dawnDeep)
        #expect(resolvedHex(.bgDeep, darkTraits) == LiminalHex.voidDeep)
    }

    @Test("Accent tokens adapt between palettes")
    func accentsAdapt() {
        #expect(resolvedHex(.roseGold, lightTraits) == PinkAuroraHex.accentTeal)
        #expect(resolvedHex(.roseGold, darkTraits) == LiminalHex.auroraTeal)
        #expect(resolvedHex(.blush, lightTraits) == PinkAuroraHex.hotPink)
        #expect(resolvedHex(.blush, darkTraits) == LiminalHex.auroraPink)
        #expect(resolvedHex(.textPrimary, lightTraits) == PinkAuroraHex.textInk)
        #expect(resolvedHex(.textPrimary, darkTraits) == LiminalHex.textBright)
    }

    @Test("Flash colors are hue-locked — identical in both modes")
    func flashColorsDoNotAdapt() {
        #expect(resolvedHex(.flashOn, lightTraits) == resolvedHex(.flashOn, darkTraits))
        #expect(resolvedHex(.flashOff, lightTraits) == resolvedHex(.flashOff, darkTraits))
        #expect(resolvedHex(.flashOff, darkTraits) == LiminalHex.voidDeep)
    }
}
