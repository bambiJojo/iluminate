//
//  ReaderORPColorTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct ReaderORPColorTests {

    // MARK: - Match background

    @Test("Matching the background resolves to the phase tint, not the theme fill")
    func matchResolvesToThePhaseTint() {
        for phase in TrancePhase.allCases {
            let resolved = ReaderORPColor.matchBackground.color(phase: phase)
            #expect(resolved == phase.atmosphereColor)
        }
    }

    @Test("The pivot never resolves to the surface it sits on")
    func pivotIsNeverInvisible() {
        // The literal background would make the highlighted letter disappear
        // into the page. Matching means matching the TINT — the colour the glow
        // and the shaders use — which is always distinct from the fill.
        for theme in ReaderTheme.allCases {
            var preferences = ReaderDisplayPreferences.standard
            preferences.theme = theme
            preferences.orpColor = .matchBackground
            for phase in TrancePhase.allCases {
                #expect(preferences.pivotColor(phase: phase) != theme.background)
            }
        }
    }

    @Test("Matching tracks the phase, so the highlight changes as the script deepens")
    func matchTracksThePhase() {
        let induction = ReaderORPColor.matchBackground.color(phase: .induction)
        let deepening = ReaderORPColor.matchBackground.color(phase: .deepening)
        #expect(induction != deepening)
    }

    // MARK: - Fixed colours

    @Test("A fixed colour ignores the phase entirely")
    func fixedColoursIgnoreThePhase() {
        for orp in ReaderORPColor.allCases where orp != .matchBackground {
            let induction = orp.color(phase: .induction)
            let fractionation = orp.color(phase: .fractionation)
            #expect(induction == fractionation)
        }
    }

    @Test("Every case has a non-empty display name")
    func displayNames() {
        for orp in ReaderORPColor.allCases {
            #expect(orp.displayName.isEmpty == false)
        }
    }

    // MARK: - Defaults and persistence

    @Test("Matching the background is the default")
    func matchIsTheDefault() {
        #expect(ReaderDisplayPreferences.standard.orpColor == .matchBackground)
    }

    @Test("Raw values are stable for persistence")
    func rawValues() {
        // Existing saved preferences carry these strings. Changing one silently
        // resets that preference for every script that stored it.
        #expect(ReaderORPColor.allCases.map(\.rawValue)
                == ["matchBackground", "teal", "blue", "amber", "pink", "white"])
    }

    @Test("A preference saved before matchBackground existed still decodes to its fixed colour")
    func existingPreferencesSurvive() throws {
        let data = Data(#"{"orpColor":"amber"}"#.utf8)
        let decoded = try JSONDecoder().decode(ReaderDisplayPreferences.self, from: data)
        #expect(decoded.orpColor == .amber)
    }
}
