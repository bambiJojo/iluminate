//  ReaderVisual.swift
//  Ilumionate
//
//  The reader's animated background choices. `.none` and `.breath` are handled
//  without a shader — `.breath` is the phase-tinted radial glow the reader has
//  always had, kept as a named option so it can stay the default.

import Foundation

enum ReaderVisual: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case breath
    case spiral
    case tunnel
    case moire
    case drift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:   return "None"
        case .breath: return "Breath"
        case .spiral: return "Spiral"
        case .tunnel: return "Tunnel"
        case .moire:  return "Moiré"
        case .drift:  return "Drift"
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
        }
    }

    /// A one-line description for the settings row.
    var summary: String {
        switch self {
        case .none:   return "Flat background"
        case .breath: return "Slow phase-tinted glow"
        case .spiral: return "Rotating arms"
        case .tunnel: return "Rings falling inward"
        case .moire:  return "Interfering rings"
        case .drift:  return "Particles on a slow vortex"
        }
    }
}
