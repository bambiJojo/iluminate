//
//  LightScorePhaseTargeting.swift
//  Ilumionate
//
//  Shared phase-to-light target functions used by score repair and alignment
//  scoring. Kept independent from SessionGenerator so runtime validation can
//  evaluate a generated LightSession without constructing a generator.
//

import Foundation

enum LightScorePhaseTargeting {

    static func targetFrequency(
        phase: HypnosisMetadata.Phase,
        tranceDepth: Double,
        progress: Double,
        config: SessionGenerator.GenerationConfig
    ) -> Double {
        let range = frequencyRange(for: phase)
        let anchor = baseFrequency(phase: phase)
        let expectedDepth = expectedDepth(for: phase)
        let depthShift = (clamp(tranceDepth, lower: 0, upper: 1) - expectedDepth)
            * (range.upperBound - range.lowerBound)
            * 0.45
        let contourShift: Double

        switch phase {
        case .preTalk, .induction:
            contourShift = -0.65 * progress
        case .deepening:
            contourShift = -0.85 * progress
        case .therapy, .suggestions, .conditioning:
            contourShift = sin(progress * .pi * 2.0) * 0.22
        case .fractionation:
            contourShift = sin(progress * .pi * 3.0) * 0.75
        case .confusion:
            contourShift = sin(progress * .pi * 5.0) * 0.45
        case .emergence:
            contourShift = 1.25 * progress
        case .eroticSuggestions, .brainwashing:
            contourShift = -0.35 * progress
        case .transitional:
            contourShift = 0
        }

        return clamp(
            anchor - depthShift + contourShift,
            lower: max(config.minFrequency, range.lowerBound),
            upper: min(config.maxFrequency, range.upperBound)
        )
    }

    static func intensity(
        phase: HypnosisMetadata.Phase,
        tranceDepth: Double,
        confidence: HypnosisMetadata.ConfidenceLevel
    ) -> Double {
        let base: Double
        switch phase {
        case .preTalk, .induction: base = 0.45
        case .fractionation: base = 0.41
        case .deepening: base = 0.38
        case .confusion: base = 0.35
        case .therapy: base = 0.32
        case .suggestions: base = 0.34
        case .eroticSuggestions: base = 0.33
        case .brainwashing: base = 0.31
        case .conditioning: base = 0.36
        case .emergence: base = 0.44
        case .transitional: base = 0.40
        }

        let confidenceScale = 0.82 + confidence.numericValue * 0.18
        let depthDimming = max(0, clamp(tranceDepth, lower: 0, upper: 1) - 0.55) * 0.12
        let emergenceLift = phase == .emergence ? 0.04 : 0
        return clamp(base * confidenceScale - depthDimming + emergenceLift, lower: 0.05, upper: 1.0)
    }

    static func waveform(for phase: HypnosisMetadata.Phase, longSegment: Bool = false) -> WaveformType {
        if longSegment {
            switch phase {
            case .therapy, .brainwashing, .deepening:
                return .noiseModulatedSine
            default:
                break
            }
        }

        switch phase {
        case .preTalk, .induction, .emergence, .transitional:
            return .sine
        case .fractionation, .deepening, .suggestions, .eroticSuggestions, .conditioning:
            return .softPulse
        case .confusion, .therapy, .brainwashing:
            return .noiseModulatedSine
        }
    }

    static func colorTemperature(for phase: HypnosisMetadata.Phase) -> Double {
        switch phase {
        case .preTalk, .induction: return 4000
        case .fractionation: return 3400
        case .deepening: return 3000
        case .confusion: return 2550
        case .therapy: return 2400
        case .suggestions: return 2600
        case .eroticSuggestions: return 2250
        case .brainwashing: return 2100
        case .conditioning: return 2800
        case .emergence: return 4500
        case .transitional: return 3500
        }
    }

    static func bilateral(for phase: HypnosisMetadata.Phase) -> Bool {
        switch phase {
        case .fractionation, .deepening, .confusion, .therapy, .suggestions,
             .eroticSuggestions, .brainwashing, .conditioning:
            return true
        default:
            return false
        }
    }

    static func frequencyRange(for phase: HypnosisMetadata.Phase) -> ClosedRange<Double> {
        switch phase {
        case .preTalk, .induction: return 8.0...12.0
        case .fractionation: return 6.5...9.5
        case .deepening: return 5.0...8.0
        case .confusion: return 4.5...6.5
        case .therapy: return 4.5...6.5
        case .suggestions: return 5.0...7.0
        case .eroticSuggestions: return 3.5...5.5
        case .brainwashing: return 4.0...5.8
        case .conditioning: return 5.5...7.5
        case .emergence: return 8.0...14.0
        case .transitional: return 6.0...10.0
        }
    }

    static func expectedDepth(for phase: HypnosisMetadata.Phase) -> Double {
        switch phase {
        case .preTalk, .induction: return 0.30
        case .fractionation: return 0.45
        case .deepening: return 0.58
        case .confusion: return 0.62
        case .therapy, .suggestions: return 0.72
        case .eroticSuggestions: return 0.78
        case .brainwashing: return 0.82
        case .conditioning: return 0.66
        case .emergence: return 0.20
        case .transitional: return 0.45
        }
    }

    private static func baseFrequency(phase: HypnosisMetadata.Phase) -> Double {
        let range = frequencyRange(for: phase)
        let fraction: Double
        switch phase {
        case .preTalk, .induction: fraction = 0.75
        case .fractionation: fraction = 0.55
        case .deepening: fraction = 0.35
        case .confusion: fraction = 0.18
        case .therapy: fraction = 0.10
        case .suggestions: fraction = 0.25
        case .eroticSuggestions: fraction = 0.35
        case .brainwashing: fraction = 0.15
        case .conditioning: fraction = 0.40
        case .emergence: fraction = 0.60
        case .transitional: fraction = 0.50
        }
        return range.lowerBound + (range.upperBound - range.lowerBound) * fraction
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
