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

    @Test("Every phase resolves to an atmosphere colour")
    func everyPhaseHasAtmosphere() {
        for phase in TrancePhase.allCases {
            #expect(phase.atmosphereColor != Color.clear)
        }
    }

    @Test("Structural phases keep their established colours")
    func knownPhaseColors() {
        #expect(TrancePhase.induction.atmosphereColor == Color.phaseInduction)
        #expect(TrancePhase.deepening.atmosphereColor == Color.phaseDeepener)
        #expect(TrancePhase.emergence.atmosphereColor == Color.phaseAwakening)
        #expect(TrancePhase.preTalk.atmosphereColor == Color.phaseIntro)
    }
}
