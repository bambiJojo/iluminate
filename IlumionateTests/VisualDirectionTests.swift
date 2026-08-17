//
//  VisualDirectionTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct VisualDirectionTests {

    @Test("Inward and outward are opposite signs")
    func signsAreOpposite() {
        #expect(VisualDirection.inward.sign == 1)
        #expect(VisualDirection.outward.sign == -1)
    }

    @Test("Direction changes the sign of the shader rate but never its magnitude")
    func magnitudeIsUnchanged() {
        for visual in TranceVisual.allCases {
            let inward = visual.motionRate * VisualDirection.inward.sign
            let outward = visual.motionRate * VisualDirection.outward.sign
            #expect(abs(inward) == abs(outward))
            #expect(inward == -outward || visual.motionRate == 0)
        }
    }

    @Test("The flicker ceiling holds in both directions")
    func ceilingHoldsBothWays() {
        // peakCrossingHz is derived from the unsigned motionRate, so reversing
        // travel cannot smuggle an effect past the budget.
        for visual in TranceVisual.allCases {
            #expect(visual.peakCrossingHz < 3.0)
            #expect(visual.motionRate >= 0)
        }
    }

    @Test("Raw values are stable for persistence")
    func rawValues() {
        #expect(VisualDirection.allCases.map(\.rawValue) == ["inward", "outward"])
    }

    @Test("Every case has a non-empty display name, summary and icon")
    func presentation() {
        for direction in VisualDirection.allCases {
            #expect(direction.displayName.isEmpty == false)
            #expect(direction.summary.isEmpty == false)
            #expect(direction.systemImage.isEmpty == false)
        }
    }

    @Test("The reader always converges inward")
    func readerIsAlwaysInward() {
        for phase in TrancePhase.allCases {
            let modulation = ReadingVisualModulator.modulation(
                for: phase, speedMultiplier: 1.0, reduceMotion: false
            )
            #expect(modulation.direction == .inward)
        }
    }

    @Test("A frozen modulation still carries a direction")
    func stillIsInward() {
        #expect(VisualModulation.still.direction == .inward)
    }
}
