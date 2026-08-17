//
//  CreateSessionKindTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct CreateSessionKindTests {

    @Test("Every kind has a non-empty title, icon and summary")
    func presentation() {
        for kind in CreateSessionKind.allCases {
            #expect(kind.title.isEmpty == false)
            #expect(kind.systemImage.isEmpty == false)
            #expect(kind.summary.isEmpty == false)
        }
    }

    @Test("Raw values are stable for persistence")
    func rawValues() {
        #expect(CreateSessionKind.allCases.map(\.rawValue)
                == ["flash", "colourPulse", "bilateral", "visualField"])
    }

    @Test("Only the visual field is wordless; the rest drive the light engine")
    func lightEngineUse() {
        #expect(CreateSessionKind.visualField.usesLightEngine == false)
        for kind in [CreateSessionKind.flash, .colourPulse, .bilateral] {
            #expect(kind.usesLightEngine)
        }
    }

    @Test("Only light-engine kinds require the photosensitivity warning")
    func safetyWarning() {
        // The warning belongs to the flashing path. Showing it on a session that
        // never flashes teaches people to dismiss it.
        for kind in CreateSessionKind.allCases {
            #expect(kind.requiresSafetyWarning == kind.usesLightEngine)
        }
        #expect(CreateSessionKind.visualField.requiresSafetyWarning == false)
    }

    @Test("Every kind maps to a distinct analytics mode")
    func analyticsModesAreDistinct() {
        let modes = CreateSessionKind.allCases.map(\.analyticsMode)
        #expect(Set(modes.map(\.rawValue)).count == modes.count)
        #expect(CreateSessionKind.visualField.analyticsMode == .visualField)
    }

    @Test("Every kind maps to a distinct mind machine mode")
    func mindMachineModesAreDistinct() {
        let modes = CreateSessionKind.allCases.map(\.mindMachineMode)
        #expect(Set(modes.map(\.rawValue)).count == modes.count)
        #expect(CreateSessionKind.visualField.mindMachineMode == .visualField)
    }

    // MARK: - Start bar copy

    @Test("Binaural changes the start title only for the kinds that offer it")
    func startTitleReflectsBinaural() {
        for kind in [CreateSessionKind.flash, .bilateral] {
            #expect(kind.startTitle(binauralEnabled: true)
                    != kind.startTitle(binauralEnabled: false))
        }
        for kind in [CreateSessionKind.visualField, .colourPulse] {
            #expect(kind.startTitle(binauralEnabled: true)
                    == kind.startTitle(binauralEnabled: false))
        }
    }

    @Test("Every kind has a non-empty start title and icon in both binaural states")
    func startCopyIsAlwaysPresent() {
        for kind in CreateSessionKind.allCases {
            for binaural in [true, false] {
                #expect(kind.startTitle(binauralEnabled: binaural).isEmpty == false)
                #expect(kind.startIcon(binauralEnabled: binaural).isEmpty == false)
            }
        }
    }
}
