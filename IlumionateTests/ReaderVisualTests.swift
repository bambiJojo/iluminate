//
//  ReaderVisualTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct ReaderVisualTests {

    @Test("Every case has a non-empty display name")
    func displayNames() {
        for visual in ReaderVisual.allCases {
            #expect(visual.displayName.isEmpty == false)
        }
    }

    @Test("Only shader-backed cases carry a shader name")
    func shaderNames() {
        #expect(ReaderVisual.none.shaderName == nil)
        #expect(ReaderVisual.breath.shaderName == nil)
        #expect(ReaderVisual.spiral.shaderName == "readerSpiral")
        #expect(ReaderVisual.tunnel.shaderName == "readerTunnel")
        #expect(ReaderVisual.moire.shaderName == "readerMoire")
        #expect(ReaderVisual.drift.shaderName == "readerDrift")
    }

    @Test("Shader names are unique")
    func shaderNamesUnique() {
        let names = ReaderVisual.allCases.compactMap(\.shaderName)
        #expect(Set(names).count == names.count)
    }

    @Test("Raw values are stable for persistence")
    func rawValues() {
        #expect(ReaderVisual.allCases.map(\.rawValue)
                == ["none", "breath", "spiral", "tunnel", "moire", "drift"])
    }

    // MARK: - Phase Atmosphere

    @Test("Phases that share a colour group stay grouped")
    func phaseColorGrouping() {
        #expect(TrancePhase.preTalk.atmosphereColor == TrancePhase.transitional.atmosphereColor)
        #expect(TrancePhase.fractionation.atmosphereColor == TrancePhase.confusion.atmosphereColor)
        #expect(TrancePhase.suggestions.atmosphereColor == TrancePhase.therapy.atmosphereColor)
        #expect(TrancePhase.suggestions.atmosphereColor == TrancePhase.eroticSuggestions.atmosphereColor)
        #expect(TrancePhase.suggestions.atmosphereColor == TrancePhase.conditioning.atmosphereColor)
        #expect(TrancePhase.suggestions.atmosphereColor == TrancePhase.brainwashing.atmosphereColor)
    }

    @Test("The six colour groups are visually distinct from each other")
    func phaseColorGroupsAreDistinct() {
        // One representative per group. If two groups collapse to the same
        // colour the reader loses its phase signal, which no other test catches.
        let representatives: [TrancePhase] = [
            .preTalk, .induction, .deepening, .fractionation, .suggestions, .emergence
        ]
        #expect(Set(representatives.map(\.atmosphereColor)).count == representatives.count)
    }

    @Test("Structural phases keep their established colours")
    func knownPhaseColors() {
        #expect(TrancePhase.induction.atmosphereColor == Color.phaseInduction)
        #expect(TrancePhase.deepening.atmosphereColor == Color.phaseDeepener)
        #expect(TrancePhase.emergence.atmosphereColor == Color.phaseAwakening)
        #expect(TrancePhase.preTalk.atmosphereColor == Color.phaseIntro)
    }
}
