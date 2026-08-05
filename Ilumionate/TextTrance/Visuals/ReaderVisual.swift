//  ReaderVisual.swift
//  Ilumionate
//
//  The reader's animated background choices. `.none` and `.breath` are handled
//  without a shader — `.breath` is the phase-tinted radial glow the reader has
//  always had, kept as a named option so it can stay the default.
//
//  Every shader-backed effect converges INWARD, toward the word at the centre
//  of the frame. See
//  docs/superpowers/specs/2026-08-04-reader-focus-visuals-design.md.

import Foundation

enum ReaderVisual: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case breath
    case spiral
    case tunnel
    case moire
    case drift
    case glass
    case linescape

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:      return "None"
        case .breath:    return "Breath"
        case .spiral:    return "Spiral"
        case .tunnel:    return "Tunnel"
        case .moire:     return "Moiré"
        case .drift:     return "Drift"
        case .glass:     return "Glass"
        case .linescape: return "Linescape"
        }
    }

    /// The `[[stitchable]]` Metal function backing this visual, or nil when the
    /// effect is rendered without a shader. This is the ONLY place shader names
    /// are written — `ShaderLibrary` resolves them at runtime, so a typo here is
    /// a blank background rather than a build error.
    var shaderName: String? {
        switch self {
        case .none, .breath: return nil
        case .spiral:        return "readerSpiral"
        case .tunnel:        return "readerTunnel"
        case .moire:         return "readerMoire"
        case .drift:         return "readerDrift"
        case .glass:         return "readerGlass"
        case .linescape:     return "readerLinescape"
        }
    }

    /// A one-line description for the settings row.
    var summary: String {
        switch self {
        case .none:      return "Flat background"
        case .breath:    return "Slow phase-tinted glow"
        case .spiral:    return "Arms winding inward"
        case .tunnel:    return "Rings falling toward the word"
        case .moire:     return "Interfering rings, drawing in"
        case .drift:     return "Particles streaming to the centre"
        case .glass:     return "Chromatic grid down a spiral"
        case .linescape: return "Contours receding to a point"
        }
    }

    // MARK: - Motion budget

    /// Feature crossings per second at speed 1.0, handed to the shader as its
    /// `rate` argument. The shader must not scale it further.
    ///
    /// This lives here rather than in Metal so the photosensitivity ceiling is
    /// enforced by `ReaderVisualTests`, not by a comment beside a constant that
    /// nothing checks.
    var motionRate: Double {
        switch self {
        case .none, .breath: return 0
        case .spiral:        return 4.0
        case .tunnel:        return 4.0
        case .moire:         return 3.0
        // Lifetime turnover, not feature crossings: motes make no repeating
        // full-frame luminance cycle, so the ceiling does not bind here.
        case .drift:         return 0.5
        case .glass:         return 3.5
        case .linescape:     return 3.0
        }
    }

    /// The highest harmonic the effect's own arithmetic can produce from
    /// `motionRate`, expressed as a multiplier on it.
    ///
    /// Moiré multiplies two bands, so their sum frequency appears in the output.
    /// Linescape's wobble term rides on the travelling phase, adding ~11%.
    /// Everything else passes `motionRate` through unchanged.
    var spectralMultiplier: Double {
        switch self {
        case .moire:     return 2.0
        case .linescape: return 1.15
        default:         return 1.0
        }
    }

    /// The fastest a repeating feature in this effect can cross a fixed pixel,
    /// in Hz, at the top of the modulator's speed band.
    ///
    /// Because every effect uses the shared phase rule, this rate is the same
    /// everywhere in the frame — the compressed centre does not flicker faster
    /// than the sparse rim.
    var peakCrossingHz: Double {
        motionRate * spectralMultiplier * ReaderVisualModulator.speedBand.upperBound
    }
}
