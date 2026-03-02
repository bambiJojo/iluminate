//
//  Waveforms.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/7/26.
//

import Foundation

/// Pure math waveform functions.
/// Each function takes a normalized phase in [0, 1) and returns
/// a normalized amplitude in [0, 1].
enum Waveform: String, CaseIterable, Identifiable {
    case sine
    case triangle
    case square
    case sawUp
    case sawDown
    case softPulse
    case rampHold
    case noiseModulatedSine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sine:               return "Sine"
        case .triangle:           return "Triangle"
        case .square:             return "Square"
        case .sawUp:              return "Saw Up"
        case .sawDown:            return "Saw Down"
        case .softPulse:          return "Soft Pulse"
        case .rampHold:           return "Ramp Hold"
        case .noiseModulatedSine: return "Noise Sine"
        }
    }

    /// Evaluate the waveform at a given phase.
    /// - Parameter phase: Normalized phase in [0, 1).
    /// - Returns: Normalized amplitude in [0, 1].
    func evaluate(at phase: Double) -> Double {
        let wrappedPhase = phase - floor(phase) // wrap to [0, 1)
        switch self {
        case .sine:
            // Standard sine, shifted to [0, 1]
            return (sin(2.0 * .pi * wrappedPhase) + 1.0) * 0.5

        case .triangle:
            // Linear ramp up then down
            return wrappedPhase < 0.5 ? wrappedPhase * 2.0 : (1.0 - wrappedPhase) * 2.0

        case .square:
            return wrappedPhase < 0.5 ? 1.0 : 0.0

        case .sawUp:
            return wrappedPhase

        case .sawDown:
            return 1.0 - wrappedPhase

        case .softPulse:
            // Sine-shaped pulse — smooth on/off with a brief peak
            let angle = 2.0 * .pi * wrappedPhase
            return pow((sin(angle) + 1.0) * 0.5, 2.0)

        case .rampHold:
            // Fast ramp up (first 30%), hold at peak (30-70%), smooth release (70-100%)
            // Creates a relaxation/release sensation
            if wrappedPhase < 0.3 {
                return wrappedPhase / 0.3
            } else if wrappedPhase < 0.7 {
                return 1.0
            } else {
                // Smooth cosine release
                let releaseTime = (wrappedPhase - 0.7) / 0.3
                return (cos(.pi * releaseTime) + 1.0) * 0.5
            }

        case .noiseModulatedSine:
            // Sine carrier with subtle pseudo-random amplitude modulation
            // for an organic, non-fatiguing long-session feel.
            // Uses a second sine at a prime-ratio frequency as the "noise" source.
            let carrier = (sin(2.0 * .pi * wrappedPhase) + 1.0) * 0.5
            let modulator = (sin(2.0 * .pi * wrappedPhase * 7.3) + 1.0) * 0.5
            return carrier * (0.85 + 0.15 * modulator)
        }
    }
}
// MARK: - Ramp Curve

/// Defines the interpolation shape for frequency transitions.
/// Per spec: no hard frequency jumps ever.
enum RampCurve: String, CaseIterable, Identifiable {
    case linear
    case exponentialEaseOut
    case sigmoid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .linear:             return "Linear"
        case .exponentialEaseOut: return "Exp Ease Out"
        case .sigmoid:            return "Sigmoid"
        }
    }

    /// Evaluate the curve at normalized time t in [0, 1].
    /// Returns a normalized progress value in [0, 1].
    func evaluate(at time: Double) -> Double {
        let clampedTime = max(0.0, min(1.0, time))
        switch self {
        case .linear:
            return clampedTime

        case .exponentialEaseOut:
            // 1 - e^(-5t) normalized to reach 1 at t=1
            // Creates a "sinking" sensation — fast initial movement, soft landing
            return (1.0 - exp(-5.0 * clampedTime)) / (1.0 - exp(-5.0))

        case .sigmoid:
            // Smooth S-curve — natural transition feel
            // Uses logistic function centered at t=0.5
            let steepness = 10.0 // steepness
            return 1.0 / (1.0 + exp(-steepness * (clampedTime - 0.5)))
        }
    }
}

// MARK: - Frequency Ramp

/// Manages a smooth frequency transition between two values over a duration.
/// The ramp advances via `advance(dt:)` called each display frame.
struct FrequencyRamp {

    /// Starting frequency in Hz.
    let fromFrequency: Double

    /// Target frequency in Hz.
    let toFrequency: Double

    /// Total ramp duration in seconds.
    let duration: Double

    /// Interpolation curve shape.
    let curve: RampCurve

    /// Elapsed time within this ramp, in seconds.
    private(set) var elapsed: Double = 0.0

    /// Whether the ramp has completed.
    var isComplete: Bool { elapsed >= duration }

    /// Current interpolated frequency.
    var currentFrequency: Double {
        guard duration > 0 else { return toFrequency }
        let normalizedTime = min(elapsed / duration, 1.0)
        let progress = curve.evaluate(at: normalizedTime)
        return fromFrequency + (toFrequency - fromFrequency) * progress
    }

    /// Advance the ramp by dt seconds. Returns the current frequency.
    @discardableResult
    mutating func advance(dt: Double) -> Double {
        elapsed = min(elapsed + dt, duration)
        return currentFrequency
    }
}
