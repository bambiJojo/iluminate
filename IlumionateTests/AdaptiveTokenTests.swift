//
//  AdaptiveTokenTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import Ilumionate

@MainActor
struct AdaptiveTokenTests {

    #if canImport(UIKit)
    private let lightAppearance = UITraitCollection(userInterfaceStyle: .light)
    private let darkAppearance  = UITraitCollection(userInterfaceStyle: .dark)

    private func resolvedHex(_ color: Color, _ appearance: UITraitCollection) -> String {
        let resolved = UIColor(color).resolvedColor(with: appearance)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func h(_ c: CGFloat) -> String { String(format: "%02X", Int(round(c * 255))) }
        return h(r) + h(g) + h(b)
    }
    #elseif canImport(AppKit)
    private let lightAppearance = NSAppearance(named: .aqua)!
    private let darkAppearance  = NSAppearance(named: .darkAqua)!

    private func resolvedHex(_ color: Color, _ appearance: NSAppearance) -> String {
        var components = (r: CGFloat.zero, g: CGFloat.zero, b: CGFloat.zero)
        appearance.performAsCurrentDrawingAppearance {
            guard let resolved = NSColor(color).usingColorSpace(.sRGB) else { return }
            resolved.getRed(
                &components.r,
                green: &components.g,
                blue: &components.b,
                alpha: nil
            )
        }
        func h(_ component: CGFloat) -> String {
            String(format: "%02X", Int(round(component * 255)))
        }
        return h(components.r) + h(components.g) + h(components.b)
    }
    #endif

    @Test("bgPrimary resolves to dawnPrimary in light and voidPrimary in dark")
    func bgPrimaryAdapts() {
        #expect(resolvedHex(.bgPrimary, lightAppearance) == PinkAuroraHex.dawnPrimary)
        #expect(resolvedHex(.bgPrimary, darkAppearance) == LiminalHex.voidPrimary)
    }

    @Test("bgDeep resolves to dawnDeep in light and voidDeep in dark")
    func bgDeepAdapts() {
        #expect(resolvedHex(.bgDeep, lightAppearance) == PinkAuroraHex.dawnDeep)
        #expect(resolvedHex(.bgDeep, darkAppearance) == LiminalHex.voidDeep)
    }

    @Test("Accent tokens adapt between palettes")
    func accentsAdapt() {
        #expect(resolvedHex(.roseGold, lightAppearance) == PinkAuroraHex.accentTeal)
        #expect(resolvedHex(.roseGold, darkAppearance) == LiminalHex.auroraTeal)
        #expect(resolvedHex(.blush, lightAppearance) == PinkAuroraHex.hotPink)
        #expect(resolvedHex(.blush, darkAppearance) == LiminalHex.auroraPink)
        #expect(resolvedHex(.textPrimary, lightAppearance) == PinkAuroraHex.textInk)
        #expect(resolvedHex(.textPrimary, darkAppearance) == LiminalHex.textBright)
    }

    @Test("Flash colors are hue-locked — identical in both modes")
    func flashColorsDoNotAdapt() {
        #expect(resolvedHex(.flashOn, lightAppearance) == resolvedHex(.flashOn, darkAppearance))
        #expect(resolvedHex(.flashOff, lightAppearance) == resolvedHex(.flashOff, darkAppearance))
        #expect(resolvedHex(.flashOff, darkAppearance) == LiminalHex.voidDeep)
    }
}
