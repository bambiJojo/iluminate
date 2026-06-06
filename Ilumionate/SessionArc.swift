//
//  SessionArc.swift
//  Ilumionate
//
//  Extracted from SessionGenerator+Strategies.swift (structural decomposition).
//

import Foundation

// MARK: - SessionArc

/// Converts a session duration into absolute-time phase boundaries with minimum-duration guards.
///
/// Pure percentage waypoints break at the extremes:
/// - A 5-min session with `duration * 0.05` gives only 15 s of beta entrance.
/// - A 2-hour session with `duration * 0.88` starts emergence too late.
///
/// `SessionArc` applies percentage targets *and* floors so every phase is long enough
/// to produce its intended neurological effect. The hard guarantee is:
///   **emergence ≥ `minEmergenceDuration` seconds** (60 s on any session length).
struct SessionArc: Sendable {

    // MARK: Boundaries (absolute seconds from start)

    /// End of the beta-entrance ramp; beginning of alpha descent.
    let betaEntranceEnd: TimeInterval
    /// End of alpha descent; beginning of theta induction.
    let alphaDescentEnd: TimeInterval
    /// End of theta induction; beginning of deep-theta hold.
    let thetaInductionEnd: TimeInterval
    /// End of deep-theta hold; beginning of suggestions layer.
    let deepHoldEnd: TimeInterval
    /// Start of emergence ramp; end of suggestions layer.
    let emergenceStart: TimeInterval
    /// Total session duration.
    let duration: TimeInterval

    /// Guaranteed minimum for the emergence phase (seconds).
    static let minEmergenceDuration: TimeInterval = 60.0

    // MARK: Init

    init(duration: TimeInterval) {
        let d = max(duration, 120.0) // guard against very short edge cases
        self.duration = d

        // Emergence: percentage target, clamped so ≥60 s is always reserved at the end.
        let pctEmergence  = d * 0.88
        let maxEmergence  = d - SessionArc.minEmergenceDuration
        let halfwayPoint  = d * 0.50 // never start emergence before the halfway mark
        emergenceStart = max(halfwayPoint, min(maxEmergence, pctEmergence))

        // Time available for beta + alpha + theta phases before emergence.
        let available = emergenceStart

        // Scale minimum phase durations down if the session is too short to fit
        // all hard-minimum phases (30+45+45 = 120 s) before the emergence window.
        // A scale of 1.0 means the minimums are not binding; <1.0 compresses them.
        let rawMinTotal = 30.0 + 45.0 + 45.0 // 120 s combined
        let scale = min(1.0, (available * 0.90) / rawMinTotal)
        let minBeta  = 30.0 * scale
        let minAlpha = 45.0 * scale
        let minTheta = 45.0 * scale

        // Beta entrance
        betaEntranceEnd = max(minBeta, min(d * 0.05, available * 0.10))

        // Alpha descent
        alphaDescentEnd = max(betaEntranceEnd + minAlpha, min(d * 0.20, available * 0.25))

        // Theta induction — clamped to stay strictly before emergence.
        thetaInductionEnd = min(
            max(alphaDescentEnd + minTheta, min(d * 0.35, available * 0.40)),
            emergenceStart - 1.0
        )

        // Deep hold: fills up to the suggestions layer (last 15% before emergence),
        // clamped to stay strictly before emergence.
        deepHoldEnd = min(
            max(thetaInductionEnd, emergenceStart * 0.85),
            emergenceStart - 1.0
        )
    }

    /// Duration of the guaranteed emergence window (always ≥ `minEmergenceDuration`).
    var emergenceDuration: TimeInterval { duration - emergenceStart }
}
