//
//  SessionGeneratorTests.swift
//  IlumionateTests
//
//  Tests for Step 3.3: SessionGenerator structural invariants.
//  Covers frequency mapping, phase-to-parameter helpers, and the clamp utility.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - FrequencyRangeForPhase

@MainActor
struct FrequencyRangeForPhaseTests {

    private let gen = SessionGenerator()
    private let config = SessionGenerator.GenerationConfig.default

    @Test func allPhasesHaveValidRange() {
        let phases: [HypnosisMetadata.Phase] = [
            .preTalk, .induction, .deepening, .therapy,
            .suggestions, .conditioning, .emergence, .transitional
        ]
        for phase in phases {
            let range = gen.frequencyRangeForPhase(phase)
            #expect(range.lowerBound < range.upperBound,
                "\(phase.rawValue): lowerBound must be < upperBound")
            #expect(range.lowerBound >= 0.5, "\(phase.rawValue) lower bound below 0.5 Hz")
            #expect(range.upperBound <= 40.0, "\(phase.rawValue) upper bound above 40 Hz")
        }
    }

    @Test func deepStatesPhasesAreBelowTenHz() {
        for phase in [HypnosisMetadata.Phase.therapy, .deepening] {
            let range = gen.frequencyRangeForPhase(phase)
            #expect(range.upperBound <= 10.0,
                "\(phase.rawValue) upper bound must be ≤10 Hz (theta region)")
        }
    }

    @Test func emergenceIsInAlphaOrHigher() {
        let range = gen.frequencyRangeForPhase(.emergence)
        #expect(range.lowerBound >= 7.0, "emergence must start in alpha/theta-alpha boundary")
    }
}

// MARK: - targetFrequencyForPhase

@MainActor
struct TargetFrequencyForPhaseTests {

    private let gen = SessionGenerator()
    private let config = SessionGenerator.GenerationConfig.default

    @Test func targetFrequencyIsWithinPhaseRange() {
        let phases: [HypnosisMetadata.Phase] = [
            .preTalk, .induction, .deepening, .therapy,
            .suggestions, .conditioning, .emergence, .transitional
        ]
        for phase in phases {
            let range = gen.frequencyRangeForPhase(phase)
            let target = gen.targetFrequencyForPhase(phase, config: config)
            #expect(target >= range.lowerBound - 0.01,
                "\(phase.rawValue) target \(target) Hz below range lower \(range.lowerBound)")
            #expect(target <= range.upperBound + 0.01,
                "\(phase.rawValue) target \(target) Hz above range upper \(range.upperBound)")
        }
    }

    @Test func deepestPhaseHasLowestTarget() {
        let therapyFreq = gen.targetFrequencyForPhase(.therapy, config: config)
        let preTalkFreq = gen.targetFrequencyForPhase(.preTalk, config: config)
        #expect(therapyFreq < preTalkFreq,
            "therapy (\(therapyFreq) Hz) must be lower than pre_talk (\(preTalkFreq) Hz)")
    }

    @Test func configMaxClamps() {
        let tight = SessionGenerator.GenerationConfig(maxFrequency: 5.0)
        let target = gen.targetFrequencyForPhase(.preTalk, config: tight)
        #expect(target <= 5.0, "target must be clamped to config.maxFrequency")
    }
}

// MARK: - intensityForPhase

@MainActor
struct IntensityForPhaseTests {

    private let gen = SessionGenerator()

    @Test func allIntensitiesInRange() {
        let phases: [HypnosisMetadata.Phase] = [
            .preTalk, .induction, .deepening, .therapy,
            .suggestions, .conditioning, .emergence, .transitional
        ]
        for phase in phases {
            let intensity = gen.intensityForPhase(phase)
            #expect(intensity >= 0.0 && intensity <= 1.0,
                "\(phase.rawValue) intensity \(intensity) out of [0, 1]")
        }
    }

    @Test func therapyIntensityIsLowest() {
        let therapy = gen.intensityForPhase(.therapy)
        let preTalk = gen.intensityForPhase(.preTalk)
        #expect(therapy < preTalk, "therapy must be dimmer than pre_talk")
    }
}

// MARK: - colorTemperatureForPhase

@MainActor
struct ColorTemperatureForPhaseTests {

    private let gen = SessionGenerator()

    @Test func deepStatesAreWarm() {
        for phase in [HypnosisMetadata.Phase.therapy, .deepening] {
            let kelvin = gen.colorTemperatureForPhase(phase)
            #expect(kelvin <= 3000, "\(phase.rawValue) must be ≤3000K, got \(kelvin)K")
        }
    }

    @Test func emergenceIsCool() {
        let kelvin = gen.colorTemperatureForPhase(.emergence)
        #expect(kelvin >= 4000, "emergence must be ≥4000K, got \(kelvin)K")
    }

    @Test func allTemperaturesInValidRange() {
        let phases: [HypnosisMetadata.Phase] = [
            .preTalk, .induction, .deepening, .therapy,
            .suggestions, .conditioning, .emergence, .transitional
        ]
        for phase in phases {
            let kelvin = gen.colorTemperatureForPhase(phase)
            #expect(kelvin >= 2000 && kelvin <= 7000,
                "\(phase.rawValue) color temp \(kelvin)K out of range [2000, 7000]")
        }
    }
}

// MARK: - clamp utility

@MainActor
struct ClampTests {

    private let gen = SessionGenerator()

    @Test func valueWithinRangePassesThrough() {
        #expect(gen.clamp(5.0, lower: 0.0, upper: 10.0) == 5.0)
    }

    @Test func valueBelowLowerClamped() {
        #expect(gen.clamp(-1.0, lower: 0.0, upper: 10.0) == 0.0)
    }

    @Test func valueAboveUpperClamped() {
        #expect(gen.clamp(15.0, lower: 0.0, upper: 10.0) == 10.0)
    }

    @Test func equalBoundsReturnsTheBound() {
        #expect(gen.clamp(5.0, lower: 5.0, upper: 5.0) == 5.0)
    }
}
