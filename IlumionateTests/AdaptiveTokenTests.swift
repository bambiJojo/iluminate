//
//  AdaptiveTokenTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI

@testable import Ilumionate

@MainActor
struct AdaptiveTokenTests {

    private let lightAppearance = ColorScheme.light
    private let darkAppearance = ColorScheme.dark

    private func resolvedHex(_ color: Color, _ appearance: ColorScheme) -> String {
        var environment = EnvironmentValues()
        environment.colorScheme = appearance
        let resolved = color.resolve(in: environment)
        func h(_ component: Float) -> String {
            String(format: "%02X", Int(round(component * 255)))
        }
        return h(resolved.red) + h(resolved.green) + h(resolved.blue)
    }

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
