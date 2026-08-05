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

    @Test("Every case has a non-empty summary")
    func summaries() {
        for visual in ReaderVisual.allCases {
            #expect(visual.summary.isEmpty == false)
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
        #expect(ReaderVisual.glass.shaderName == "readerGlass")
        #expect(ReaderVisual.linescape.shaderName == "readerLinescape")
    }

    @Test("Shader names are unique")
    func shaderNamesUnique() {
        let names = ReaderVisual.allCases.compactMap(\.shaderName)
        #expect(Set(names).count == names.count)
    }

    @Test("Raw values are stable for persistence")
    func rawValues() {
        #expect(ReaderVisual.allCases.map(\.rawValue)
                == ["none", "breath", "spiral", "tunnel",
                    "moire", "drift", "glass", "linescape"])
    }

    // MARK: - Motion budget
    //
    // The photosensitivity ceiling. These tests are the reason `motionRate`
    // lives in Swift rather than as a constant inside the shader: a new effect
    // that exceeds the budget fails here instead of shipping.

    @Test("Every effect stays under the 3 Hz flicker ceiling")
    func everyEffectStaysUnderTheFlickerCeiling() {
        for visual in ReaderVisual.allCases {
            #expect(
                visual.peakCrossingHz < 3.0,
                "\(visual.rawValue) crosses at \(visual.peakCrossingHz) Hz"
            )
        }
    }

    @Test("Only the shaderless cases have no motion")
    func motionRateIsZeroExactlyForShaderlessCases() {
        for visual in ReaderVisual.allCases {
            #expect((visual.motionRate == 0) == (visual.shaderName == nil))
        }
    }

    @Test("Moiré and Linescape declare the harmonics their arithmetic adds")
    func spectralMultipliers() {
        // Moiré multiplies two bands, so their sum frequency appears. Linescape's
        // wobble rides on the travelling phase. Dropping either multiplier would
        // silently understate those effects' real crossing rate.
        #expect(ReaderVisual.moire.spectralMultiplier == 2.0)
        #expect(ReaderVisual.linescape.spectralMultiplier > 1.0)
        for visual in [ReaderVisual.spiral, .tunnel, .drift, .glass] {
            #expect(visual.spectralMultiplier == 1.0)
        }
    }

    @Test("Moiré is the tightest against the ceiling, so it guards the margin")
    func moireHasTheLeastHeadroom() {
        let shaderBacked = ReaderVisual.allCases.filter { $0.shaderName != nil }
        let worst = shaderBacked.max { $0.peakCrossingHz < $1.peakCrossingHz }
        #expect(worst == .moire)
        #expect(abs(ReaderVisual.moire.peakCrossingHz - 2.7) < 0.0001)
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
