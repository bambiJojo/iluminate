//  ReaderVisualModulation.swift
//  Ilumionate
//
//  Turns the session's reading phase and pace into the three values the shaders
//  take. Every safety limit lives here rather than in Metal, so the caps are
//  unit-testable and cannot be bypassed by editing a shader constant.

import SwiftUI

struct ReaderVisualModulation: Equatable, Sendable {
    /// Phase tint, from the shared `TrancePhase.atmosphereColor` table.
    let tint: Color
    /// Normalised motion rate, always within `ReaderVisualModulator.speedBand`.
    /// Each shader interprets it for its own geometry — a revolution rate for a
    /// spiral, a ring-crossing rate for a tunnel — so the same value produces
    /// different physical rates per effect.
    let speed: Double
    /// Pattern strength, always within `ReaderVisualModulator.amplitudeBand`
    /// (currently floored at 0.25, never 0 — a selected effect stays visible).
    let amplitude: Double

    static let still = ReaderVisualModulation(tint: .phaseIntro, speed: 0, amplitude: 0.25)
}

enum ReaderVisualModulator {

    /// The motion budget every effect must fit inside.
    ///
    /// The safety target is that no effect makes a repeating feature cross a
    /// fixed pixel at 3 Hz or more, since that is where flicker starts to carry
    /// photosensitivity risk. This band is the *input* budget; it does not by
    /// itself guarantee the target. Each shader multiplies `speed` by its own
    /// feature count, so meeting the target is a per-effect obligation: pick
    /// constants such that `featureCount * speedBand.upperBound < 3.0`, and
    /// record that arithmetic beside the constant.
    static let speedBand: ClosedRange<Double> = 0.05...0.45
    static let amplitudeBand: ClosedRange<Double> = 0.25...1.0

    static func modulation(
        for phase: TrancePhase,
        speedMultiplier: Double,
        reduceMotion: Bool
    ) -> ReaderVisualModulation {
        let tint = phase.atmosphereColor
        let depth = depthWeight(for: phase)

        guard reduceMotion == false else {
            return ReaderVisualModulation(
                tint: tint, speed: 0, amplitude: amplitude(for: depth)
            )
        }

        // Reading pace nudges the visual, but depth dominates: a fast reader in
        // pre-talk should still see something calm.
        let pace = (min(max(speedMultiplier, 0.5), 2.0) - 0.5) / 1.5   // 0…1
        let blend = depth * (0.7 + 0.3 * pace)

        return ReaderVisualModulation(
            tint: tint,
            speed: clamp(
                speedBand.lowerBound
                    + (speedBand.upperBound - speedBand.lowerBound) * blend,
                to: speedBand
            ),
            amplitude: amplitude(for: depth)
        )
    }

    private static func amplitude(for depth: Double) -> Double {
        clamp(
            amplitudeBand.lowerBound
                + (amplitudeBand.upperBound - amplitudeBand.lowerBound) * depth,
            to: amplitudeBand
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
