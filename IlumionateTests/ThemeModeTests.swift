//
//  ThemeModeTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct ThemeModeTests {

    @Test("Raw values match the persisted appearanceMode strings")
    func rawValues() {
        #expect(ThemeMode.system.rawValue == "system")
        #expect(ThemeMode.light.rawValue == "light")
        #expect(ThemeMode.dark.rawValue == "dark")
    }

    @Test("system maps to nil colorScheme; light/dark map to their schemes")
    func colorSchemeMapping() {
        #expect(ThemeMode.system.colorScheme == nil)
        #expect(ThemeMode.light.colorScheme == .light)
        #expect(ThemeMode.dark.colorScheme == .dark)
    }

    @Test("Unknown persisted string falls back to system")
    func unknownFallsBackToSystem() {
        #expect(ThemeMode(persisted: "bogus") == .system)
        #expect(ThemeMode(persisted: nil) == .system)
        #expect(ThemeMode(persisted: "light") == .light)
    }
}
