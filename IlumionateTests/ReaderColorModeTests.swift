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
}
