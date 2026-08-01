//
//  ReaderColorModeTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct ReaderColorModeTests {

    @Test("Default color mode is followApp")
    func defaultIsFollowApp() {
        #expect(ReaderDisplayPreferences.standard.colorMode == .followApp)
    }

    @Test("Legacy persisted JSON without colorMode decodes to followApp")
    func legacyDecoding() throws {
        let legacy = """
        {"theme":"void","font":"monospaced","fontScale":1.0,"lineSpacing":1.0,
         "orpColor":"teal","backgroundBrightness":0.5,"hideControls":false,
         "dyslexiaFriendly":false}
        """.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(ReaderDisplayPreferences.self, from: legacy)
        #expect(prefs.colorMode == .followApp)
        #expect(prefs.theme == .void)
    }

    @Test("followApp + light app swaps dark themes to dawn")
    func followAppLightSwapsToDawn() {
        var prefs = ReaderDisplayPreferences.standard   // theme: .void
        prefs.colorMode = .followApp
        #expect(prefs.resolved(appColorScheme: .light).theme == .dawn)
        #expect(prefs.resolved(appColorScheme: .dark).theme == .void)
    }

    @Test("Explicit dark mode swaps light themes to void")
    func explicitDarkSwapsToVoid() {
        var prefs = ReaderDisplayPreferences.standard
        prefs.theme = .paper
        prefs.colorMode = .dark
        #expect(prefs.resolved(appColorScheme: .light).theme == .void)
    }

    @Test("Explicit light mode leaves light themes untouched")
    func explicitLightKeepsLightThemes() {
        var prefs = ReaderDisplayPreferences.standard
        prefs.theme = .sepia
        prefs.colorMode = .light
        #expect(prefs.resolved(appColorScheme: .dark).theme == .sepia)
    }

    @Test("Resolved scheme follows mode")
    func resolvedScheme() {
        var prefs = ReaderDisplayPreferences.standard
        prefs.colorMode = .light
        #expect(prefs.resolvedScheme(appColorScheme: .dark) == .light)
        prefs.colorMode = .followApp
        #expect(prefs.resolvedScheme(appColorScheme: .dark) == .dark)
    }

    @Test("Dawn theme is light with ink text and shows phase atmosphere")
    func dawnThemeProperties() {
        #expect(ReaderTheme.dawn.isDark == false)
        #expect(ReaderTheme.dawn.showsPhaseAtmosphere == true)
        #expect(ReaderTheme.void.isDark == true)
    }

    // MARK: - Reader Visuals

    @Test("Default visual is breath at 0.35 opacity")
    func visualDefaults() {
        #expect(ReaderDisplayPreferences.standard.visual == .breath)
        #expect(ReaderDisplayPreferences.standard.visualOpacity == 0.35)
    }

    @Test("Legacy persisted JSON without visual fields decodes to the defaults")
    func legacyVisualDecoding() throws {
        let legacy = """
        {"theme":"void","font":"monospaced","fontScale":1.0,"lineSpacing":1.0,
         "orpColor":"teal","backgroundBrightness":0.5,"hideControls":false,
         "dyslexiaFriendly":false,"colorMode":"followApp"}
        """.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(ReaderDisplayPreferences.self, from: legacy)
        #expect(prefs.visual == .breath)
        #expect(prefs.visualOpacity == 0.35)
    }

    @Test("Visual fields round-trip through Codable")
    func visualRoundTrip() throws {
        var prefs = ReaderDisplayPreferences.standard
        prefs.visual = .moire
        prefs.visualOpacity = 0.7
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(ReaderDisplayPreferences.self, from: data)
        #expect(decoded.visual == .moire)
        #expect(decoded.visualOpacity == 0.7)
    }

    @Test("Visual opacity clamps to its range at both bounds")
    func visualOpacityClamps() {
        var prefs = ReaderDisplayPreferences.standard
        prefs.visualOpacity = 5.0
        #expect(prefs.clampedVisualOpacity == ReaderDisplayPreferences.visualOpacityRange.upperBound)
        prefs.visualOpacity = -3.0
        #expect(prefs.clampedVisualOpacity == ReaderDisplayPreferences.visualOpacityRange.lowerBound)
    }
}
