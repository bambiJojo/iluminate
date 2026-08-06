//  BinauralSettings.swift
//  Ilumionate
//
//  Binaural configuration for a mode that carries it.
//
//  `flashMode` still carries these three as loose parameters. Folding it in is a
//  tidy follow-on, but it touches every flashMode call site and none of that
//  work serves the Visual Field — so this starts as a type only the new mode uses.

import Foundation

struct BinauralSettings: Equatable, Codable, Sendable {
    var enabled: Bool
    var carrier: Double
    var volume: Double
    /// The difference between the ears, and the actual entrainment parameter.
    ///
    /// `flashMode` derives this from its light frequency, because there the
    /// light is what entrains and the beat should agree with it. A wordless
    /// visual field has no light frequency, so it carries its own — otherwise
    /// the only entrainment in the session would be pinned to a default nobody
    /// chose.
    var beatFrequency: Double

    static let standard = BinauralSettings(
        enabled: false, carrier: 200, volume: 0.5, beatFrequency: 10
    )
}
