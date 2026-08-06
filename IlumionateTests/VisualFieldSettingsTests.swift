//
//  VisualFieldSettingsTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct VisualFieldSettingsTests {

    private func settings(
        speed: Double = 0.5,
        amplitude: Double = 0.5,
        direction: VisualDirection = .inward
    ) -> VisualFieldSettings {
        VisualFieldSettings(
            visual: .spiral,
            tint: .violet,
            speed: speed,
            amplitude: amplitude,
            direction: direction,
            opacity: 0.4,
            duration: nil
        )
    }

    // MARK: - The cap
    //
    // These are the tests that make the photosensitivity budget unbypassable
    // from the settings layer. If one of them starts failing, the fix is in the
    // mapping, never in the band.

    @Test("Speed always lands inside the safety band, whatever is asked for",
          arguments: [-99.0, -1.0, 0.0, 0.25, 0.5, 1.0, 2.0, 1_000.0])
    func speedAlwaysInBand(requested: Double) {
        let modulation = settings(speed: requested).modulation(reduceMotion: false)
        #expect(modulation.speed >= VisualModulation.speedBand.lowerBound)
        #expect(modulation.speed <= VisualModulation.speedBand.upperBound)
    }

    @Test("Amplitude always lands inside the safety band",
          arguments: [-99.0, -1.0, 0.0, 0.25, 0.5, 1.0, 2.0, 1_000.0])
    func amplitudeAlwaysInBand(requested: Double) {
        let modulation = settings(amplitude: requested).modulation(reduceMotion: false)
        #expect(modulation.amplitude >= VisualModulation.amplitudeBand.lowerBound)
        #expect(modulation.amplitude <= VisualModulation.amplitudeBand.upperBound)
    }

    @Test("A non-finite value degrades to the bottom of the band, not to NaN")
    func nonFiniteValuesDegrade() {
        for bad in [Double.nan, .infinity, -.infinity] {
            let modulation = settings(speed: bad, amplitude: bad)
                .modulation(reduceMotion: false)
            #expect(modulation.speed.isFinite)
            #expect(modulation.amplitude.isFinite)
            #expect(modulation.speed == VisualModulation.speedBand.lowerBound)
            #expect(modulation.amplitude == VisualModulation.amplitudeBand.lowerBound)
        }
    }

    @Test("Full speed is exactly the band ceiling — the same ceiling the reader's deepest phase reaches")
    func fullSpeedIsTheBandCeiling() {
        let modulation = settings(speed: 1.0).modulation(reduceMotion: false)
        #expect(modulation.speed == VisualModulation.speedBand.upperBound)
    }

    @Test("Zero speed is the band floor, not a standstill — an effect that is on stays alive")
    func zeroSpeedIsTheBandFloor() {
        let modulation = settings(speed: 0).modulation(reduceMotion: false)
        #expect(modulation.speed == VisualModulation.speedBand.lowerBound)
        #expect(modulation.speed > 0)
    }

    @Test("Even at full speed no effect breaches the 3 Hz flicker ceiling")
    func fullSpeedStaysUnderTheCeiling() {
        for visual in TranceVisual.allCases {
            var maxed = VisualFieldSettings.standard
            maxed.visual = visual
            maxed.speed = 1.0
            let modulation = maxed.modulation(reduceMotion: false)
            let crossing = visual.motionRate * visual.spectralMultiplier * modulation.speed
            #expect(crossing < 3.0)
        }
    }

    // MARK: - Reduce Motion

    @Test("Reduce Motion freezes the field but keeps its appearance")
    func reduceMotionFreezes() {
        let modulation = settings(speed: 1.0).modulation(reduceMotion: true)
        #expect(modulation.speed == 0)
        #expect(modulation.amplitude > 0)
        #expect(modulation.tint == VisualTint.violet.color)
    }

    // MARK: - Pass-through

    @Test("Tint and direction reach the modulation unchanged")
    func passThrough() {
        let modulation = settings(direction: .outward).modulation(reduceMotion: false)
        #expect(modulation.direction == .outward)
        #expect(modulation.tint == VisualTint.violet.color)
    }

    // MARK: - Defaults

    @Test("The default settings are a running, visible, open-ended field")
    func defaultsAreVisible() {
        let standard = VisualFieldSettings.standard
        let modulation = standard.modulation(reduceMotion: false)
        #expect(standard.visual != .none)
        #expect(standard.visual.shaderName != nil)
        #expect(modulation.speed > 0)
        #expect(modulation.amplitude > 0)
        #expect(standard.duration == nil)
    }

    @Test("Opacity is clamped to the shared band")
    func opacityIsClamped() {
        var high = VisualFieldSettings.standard
        high.opacity = 9
        #expect(high.clampedOpacity == VisualModulation.opacityBand.upperBound)

        var low = VisualFieldSettings.standard
        low.opacity = -9
        #expect(low.clampedOpacity == VisualModulation.opacityBand.lowerBound)
    }

    // MARK: - Persistence

    @Test("Settings round-trip through Codable")
    func codableRoundTrip() throws {
        let original = settings(direction: .outward)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(VisualFieldSettings.self, from: data) == original)
    }

    @Test("A timed duration survives a round trip")
    func durationRoundTrips() throws {
        var timed = VisualFieldSettings.standard
        timed.duration = 600
        let data = try JSONEncoder().encode(timed)
        #expect(try JSONDecoder().decode(VisualFieldSettings.self, from: data).duration == 600)
    }

    @Test("A partial payload keeps what it has and defaults the rest")
    func partialPayloadFallsBackPerField() throws {
        let data = Data(#"{"visual":"moire"}"#.utf8)
        let decoded = try JSONDecoder().decode(VisualFieldSettings.self, from: data)
        #expect(decoded.visual == .moire)
        #expect(decoded.tint == VisualFieldSettings.standard.tint)
        #expect(decoded.speed == VisualFieldSettings.standard.speed)
        #expect(decoded.duration == nil)
    }

    @Test("An unknown enum value degrades to its default instead of losing every other field")
    func unknownEnumValueDegrades() throws {
        // decodeIfPresent THROWS on a present-but-unmatched raw value, so a
        // future effect name reaching an older build would discard the whole
        // payload unless each enum field is decoded defensively.
        let data = Data(#"{"visual":"kaleidoscope","direction":"outward"}"#.utf8)
        let decoded = try JSONDecoder().decode(VisualFieldSettings.self, from: data)
        #expect(decoded.visual == VisualFieldSettings.standard.visual)
        #expect(decoded.direction == .outward)
    }
}
