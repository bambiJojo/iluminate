//  VisualModulation.swift
//  Ilumionate
//
//  The three values every visual shader takes, and the bands they must stay
//  inside. Two producers build this struct: ReadingVisualModulator, from the
//  reader's phase and pace, and VisualFieldSettings, from the Create tab's
//  direct controls.
//
//  Every safety limit lives here rather than in Metal, so the caps are
//  unit-testable and cannot be bypassed by editing a shader constant.

import SwiftUI

struct VisualModulation: Equatable, Sendable {
    /// Phase tint, from the shared `TrancePhase.atmosphereColor` table.
    let tint: Color
    /// Normalised motion rate, always within `VisualModulation.speedBand`.
    /// Each shader interprets it for its own geometry — a revolution rate for a
    /// spiral, a ring-crossing rate for a tunnel — so the same value produces
    /// different physical rates per effect.
    let speed: Double
    /// Pattern strength, always within `VisualModulation.amplitudeBand`
    /// (currently floored at 0.25, never 0 — a selected effect stays visible).
    let amplitude: Double
    /// Which way the effect travels. The reader is always `.inward` — its
    /// effects exist to pull focus to the word. Only the wordless Visual Field,
    /// which has no word to converge on, sets `.outward`.
    let direction: VisualDirection

    /// `direction` defaults to `.inward` so the reader's producer constructs
    /// this exactly as it did before the Visual Field existed.
    init(
        tint: Color,
        speed: Double,
        amplitude: Double,
        direction: VisualDirection = .inward
    ) {
        self.tint = tint
        self.speed = speed
        self.amplitude = amplitude
        self.direction = direction
    }

    static let still = VisualModulation(tint: .phaseIntro, speed: 0, amplitude: 0.25)
}

// MARK: - Safety bands
//
// These live on the struct every producer must build, rather than on any one
// producer, so that adding a producer cannot add a way around them. Both
// ReadingVisualModulator and VisualFieldSettings map into these ranges; neither
// can widen them.

extension VisualModulation {

    /// The motion budget every effect must fit inside.
    ///
    /// The safety target is that no effect makes a repeating feature cross a
    /// fixed pixel at 3 Hz or more, since that is where flicker starts to carry
    /// photosensitivity risk.
    ///
    /// Every shader derives its motion from the shared phase rule
    ///
    ///     phase = convergentDepth(r, turns) * density - time * speed * rate
    ///
    /// whose time derivative is `speed * rate` — independent of radius. The
    /// compressed centre therefore does not flicker faster than the sparse rim,
    /// and meeting the target reduces to a single multiplication rather than
    /// per-effect reasoning about feature counts.
    ///
    /// `rate` lives on `TranceVisual.motionRate` and reaches Metal as a shader
    /// argument, so `TranceVisualTests.everyEffectStaysUnderTheFlickerCeiling`
    /// checks the ceiling for every case. Editing a shader constant cannot
    /// bypass it. `density` scales only the spatial term and is free to tune
    /// without re-deriving any of this.
    static let speedBand: ClosedRange<Double> = 0.05...0.45

    /// Pattern strength. Floored above zero on purpose: a chosen effect stays
    /// visible rather than resolving to an invisible one.
    static let amplitudeBand: ClosedRange<Double> = 0.25...1.0

    /// Strength band for any surface drawing an effect.
    ///
    /// Capped below 1.0 on purpose: at full strength even a centre-faded effect
    /// starts competing with the reader's word at the ellipse boundary. The
    /// Visual Field has no word, but shares the band so one strength value means
    /// the same thing on both surfaces.
    static let opacityBand: ClosedRange<Double> = 0.05...0.85
}

