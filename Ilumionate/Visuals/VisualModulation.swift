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
    /// Normalised motion rate, always within `ReadingVisualModulator.speedBand`.
    /// Each shader interprets it for its own geometry — a revolution rate for a
    /// spiral, a ring-crossing rate for a tunnel — so the same value produces
    /// different physical rates per effect.
    let speed: Double
    /// Pattern strength, always within `ReadingVisualModulator.amplitudeBand`
    /// (currently floored at 0.25, never 0 — a selected effect stays visible).
    let amplitude: Double

    static let still = VisualModulation(tint: .phaseIntro, speed: 0, amplitude: 0.25)
}

