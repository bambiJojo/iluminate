//  ReadingVisualModulator.swift
//  Ilumionate
//
//  Turns the session's reading phase and pace into a VisualModulation. This is
//  the reader's producer; the Create tab's Visual Field produces the same struct
//  directly from VisualFieldSettings instead.
//
//  Every safety limit lives on VisualModulation itself rather than here, so no
//  producer can exceed the bands.

import SwiftUI

enum ReadingVisualModulator {

    static func modulation(
        for phase: TrancePhase,
        speedMultiplier: Double,
        reduceMotion: Bool
    ) -> VisualModulation {
        let tint = phase.atmosphereColor
        let depth = depthWeight(for: phase)

        guard reduceMotion == false else {
            return VisualModulation(
                tint: tint, speed: 0, amplitude: amplitude(for: depth)
            )
        }

        // Reading pace nudges the visual, but depth dominates: a fast reader in
        // pre-talk should still see something calm.
        let pace = (min(max(speedMultiplier, 0.5), 2.0) - 0.5) / 1.5   // 0…1
        let blend = depth * (0.7 + 0.3 * pace)

        let band = VisualModulation.speedBand

        return VisualModulation(
            tint: tint,
            speed: clamp(
                band.lowerBound + (band.upperBound - band.lowerBound) * blend,
                to: band
            ),
            amplitude: amplitude(for: depth)
        )
    }

    private static func amplitude(for depth: Double) -> Double {
        let band = VisualModulation.amplitudeBand
        return clamp(
            band.lowerBound + (band.upperBound - band.lowerBound) * depth,
            to: band
        )
    }

    /// How deep into trance a phase sits, 0…1. Drives both speed and amplitude
    /// so the background intensifies with the script and eases off on the way out.
    private static func depthWeight(for phase: TrancePhase) -> Double {
        switch phase {
        case .preTalk:            return 0.10
        case .emergence:          return 0.20
        case .induction:          return 0.45
        case .transitional:       return 0.50
        case .suggestions:        return 0.62
        case .therapy:            return 0.62
        case .eroticSuggestions:  return 0.70
        case .conditioning:       return 0.70
        case .deepening:          return 0.78
        case .brainwashing:       return 0.85
        case .confusion:          return 0.92
        case .fractionation:      return 0.95
        }
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
