//  VisualDirection.swift
//  Ilumionate
//
//  Which way an effect travels. Reaches Metal as the SIGN of the shader's `rate`
//  argument rather than as a uniform of its own: every effect derives motion
//  from the shared phase rule
//
//      phase = convergentDepth(r, turns) * density - time * speed * rate
//
//  so negating `rate` reverses the direction of travel with no per-effect work.
//
//  `TranceVisual.motionRate` stays unsigned so `peakCrossingHz` and the
//  photosensitivity ceiling keep measuring magnitude. Reversing travel must
//  never be a way past the budget.

import Foundation

enum VisualDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Toward the centre. The reader's only option — its effects exist to pull
    /// focus to the word.
    case inward
    /// Away from the centre. Wordless only.
    case outward

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inward:  return "Inward"
        case .outward: return "Outward"
        }
    }

    var summary: String {
        switch self {
        case .inward:  return "Drawing toward the centre"
        case .outward: return "Streaming out of the centre"
        }
    }

    var systemImage: String {
        switch self {
        case .inward:  return "arrow.down.right.and.arrow.up.left"
        case .outward: return "arrow.up.left.and.arrow.down.right"
        }
    }

    /// Multiplier applied to the shader's `rate` argument.
    var sign: Double {
        switch self {
        case .inward:  return 1
        case .outward: return -1
        }
    }
}
