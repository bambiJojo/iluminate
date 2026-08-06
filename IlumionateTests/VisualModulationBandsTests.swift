//
//  VisualModulationBandsTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct VisualModulationBandsTests {

    // MARK: - The bands live on the renderer

    @Test("The safety bands live on VisualModulation, where every producer must read them")
    func bandsLiveOnTheRenderer() {
        #expect(VisualModulation.speedBand == 0.05...0.45)
        #expect(VisualModulation.amplitudeBand == 0.25...1.0)
        #expect(VisualModulation.opacityBand == 0.05...0.85)
    }

    @Test("The bands are unchanged from before the Visual Field work")
    func bandsAreUnchanged() {
        // These are the photosensitivity budget. If a change to this file is
        // what made a test pass, the change is wrong.
        #expect(VisualModulation.speedBand.upperBound == 0.45)
        #expect(VisualModulation.amplitudeBand.lowerBound == 0.25)
        #expect(VisualModulation.opacityBand.upperBound == 0.85)
    }

    @Test("Amplitude never floors at zero, so a chosen effect always stays visible")
    func amplitudeNeverVanishes() {
        #expect(VisualModulation.amplitudeBand.lowerBound > 0)
    }

    // MARK: - Stilling

    @Test("Stilling stops the motion and nothing else")
    func stilledKeepsAppearance() {
        let running = VisualFieldSettings.standard.modulation(reduceMotion: false)
        let held = running.stilled

        #expect(held.speed == 0)
        #expect(held.tint == running.tint)
        #expect(held.amplitude == running.amplitude)
        #expect(held.direction == running.direction)
    }

    @Test("Stilling an already-still field changes nothing")
    func stillingIsIdempotent() {
        let held = VisualFieldSettings.standard.modulation(reduceMotion: false).stilled
        #expect(held.stilled == held)
    }

    @Test("A stilled field keeps its strength, so pausing does not blank the screen")
    func stilledStaysVisible() {
        // Zero speed, not zero amplitude: a paused session shows the field
        // frozen, not gone.
        for direction in VisualDirection.allCases {
            var settings = VisualFieldSettings.standard
            settings.direction = direction
            let held = settings.modulation(reduceMotion: false).stilled
            #expect(held.amplitude >= VisualModulation.amplitudeBand.lowerBound)
        }
    }

    // MARK: - The reader still reads them

    @Test("The reader's clamp uses the shared opacity band")
    func readerClampUsesSharedBand() {
        var preferences = ReaderDisplayPreferences.standard
        preferences.visualOpacity = 9.0
        #expect(preferences.clampedVisualOpacity == VisualModulation.opacityBand.upperBound)
        preferences.visualOpacity = -1.0
        #expect(preferences.clampedVisualOpacity == VisualModulation.opacityBand.lowerBound)
    }

    @Test("The reader's drag range still tops out at the shared opacity band")
    func readerDragRangeUsesSharedBand() {
        #expect(ReaderVisualStrength.dragRange.upperBound
                == VisualModulation.opacityBand.upperBound)
        #expect(ReaderVisualStrength.offThreshold
                == VisualModulation.opacityBand.lowerBound)
    }

    @Test("The reader's phase modulator still lands inside the shared bands")
    func readerModulatorRespectsSharedBands() {
        for phase in TrancePhase.allCases {
            for multiplier in [0.5, 1.0, 2.0] {
                let modulation = ReadingVisualModulator.modulation(
                    for: phase, speedMultiplier: multiplier, reduceMotion: false
                )
                #expect(VisualModulation.speedBand.contains(modulation.speed))
                #expect(VisualModulation.amplitudeBand.contains(modulation.amplitude))
            }
        }
    }
}
