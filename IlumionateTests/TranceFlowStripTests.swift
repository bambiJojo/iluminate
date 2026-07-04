//
//  TranceFlowStripTests.swift
//  IlumionateTests
//
//  Tests for the Trance Flow strip's unit-space sampling of a light score.
//

import Testing
@testable import Ilumionate

@Suite("TranceFlowStripModel")
struct TranceFlowStripTests {

    private func moment(time: Double, frequency: Double, intensity: Double = 0.5) -> LightMoment {
        LightMoment(time: time, frequency: frequency, intensity: intensity, waveform: .sine,
                    ramp_duration: nil, bilateral: nil,
                    bilateral_transition_duration: nil, color_temperature: nil)
    }

    @Test("Maps time to unit x across the duration")
    func timeMapsToUnitX() {
        let samples = TranceFlowStripModel.samples(
            from: [moment(time: 0, frequency: 10), moment(time: 300, frequency: 6),
                   moment(time: 600, frequency: 2)],
            duration: 600
        )
        #expect(samples.map(\.x) == [0.0, 0.5, 1.0])
    }

    @Test("Frequency maps to unit y: alpha top (0), delta bottom (1)")
    func frequencyMapsToUnitY() {
        let samples = TranceFlowStripModel.samples(
            from: [moment(time: 0, frequency: 12), moment(time: 10, frequency: 0.5)],
            duration: 10
        )
        #expect(samples[0].frequencyY == 0.0)
        #expect(samples[1].frequencyY == 1.0)
    }

    @Test("Clamps out-of-range frequencies into unit space")
    func clampsFrequencies() {
        let samples = TranceFlowStripModel.samples(
            from: [moment(time: 0, frequency: 40), moment(time: 10, frequency: 0.1)],
            duration: 10
        )
        #expect(samples[0].frequencyY == 0.0)
        #expect(samples[1].frequencyY == 1.0)
    }

    @Test("Empty score or non-positive duration yields no samples")
    func emptyInputs() {
        #expect(TranceFlowStripModel.samples(from: [], duration: 600).isEmpty)
        #expect(TranceFlowStripModel.samples(
            from: [moment(time: 0, frequency: 6)], duration: 0).isEmpty)
    }

    @Test("Intensity passes through clamped to 0...1")
    func intensityClamped() {
        let samples = TranceFlowStripModel.samples(
            from: [moment(time: 0, frequency: 6, intensity: 1.4)],
            duration: 10
        )
        #expect(samples[0].intensity == 1.0)
    }
}
