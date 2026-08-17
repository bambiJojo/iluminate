//  VisualFieldSettings.swift
//  Ilumionate
//
//  The wordless Visual Field's controls, and the second producer of
//  VisualModulation. The reader's producer is ReadingVisualModulator, which
//  derives the same struct from reading phase and pace instead.
//
//  SPEED AND AMPLITUDE ARE STORED NORMALISED, 0…1, and mapped into
//  VisualModulation's bands here. That is what makes the photosensitivity cap
//  unbypassable from the settings layer: "100% speed" resolves to
//  speedBand.upperBound — the same ceiling the reader's deepest phase reaches —
//  rather than to an unbounded number. Never store band-space values in this
//  struct, and never let a caller build a VisualModulation around it.

import SwiftUI

struct VisualFieldSettings: Codable, Equatable, Sendable {
    var visual: TranceVisual
    var tint: VisualTint
    /// Normalised 0…1. Mapped into `VisualModulation.speedBand`.
    var speed: Double
    /// Normalised 0…1. Mapped into `VisualModulation.amplitudeBand`.
    var amplitude: Double
    var direction: VisualDirection
    /// Strength, in `VisualModulation.opacityBand` units.
    var opacity: Double
    /// nil runs open-ended.
    var duration: TimeInterval?

    static let standard = VisualFieldSettings(
        visual: .spiral,
        tint: .default,
        speed: 0.45,
        amplitude: 0.6,
        direction: .inward,
        opacity: 0.5,
        duration: nil
    )

    var clampedOpacity: Double {
        min(max(opacity, VisualModulation.opacityBand.lowerBound),
            VisualModulation.opacityBand.upperBound)
    }

    // MARK: - Modulation

    func modulation(reduceMotion: Bool) -> VisualModulation {
        let amplitude = Self.map(self.amplitude, into: VisualModulation.amplitudeBand)

        guard reduceMotion == false else {
            return VisualModulation(
                tint: tint.color, speed: 0, amplitude: amplitude, direction: direction
            )
        }

        return VisualModulation(
            tint: tint.color,
            speed: Self.map(speed, into: VisualModulation.speedBand),
            amplitude: amplitude,
            direction: direction
        )
    }

    /// Maps a normalised 0…1 value into a band. Non-finite input degrades to the
    /// bottom of the band rather than propagating NaN into a shader argument,
    /// where it would render a blank frame with no diagnostic.
    private static func map(_ value: Double, into band: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return band.lowerBound }
        let normalised = min(max(value, 0), 1)
        return band.lowerBound + (band.upperBound - band.lowerBound) * normalised
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case visual, tint, speed, amplitude, direction, opacity, duration
    }

    init(
        visual: TranceVisual,
        tint: VisualTint,
        speed: Double,
        amplitude: Double,
        direction: VisualDirection,
        opacity: Double,
        duration: TimeInterval?
    ) {
        self.visual = visual
        self.tint = tint
        self.speed = speed
        self.amplitude = amplitude
        self.direction = direction
        self.opacity = opacity
        self.duration = duration
    }

    /// Every field decodes optionally and falls back to its default, for the
    /// same reason `ReaderDisplayPreferences` does: one unreadable field must
    /// degrade to its default rather than discard every other setting with it.
    ///
    /// The enum fields additionally use `try?`, because `decodeIfPresent` THROWS
    /// on a present-but-unmatched raw value rather than returning nil. Without
    /// it, a settings file naming an effect this build does not know would take
    /// every other preference down with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.standard
        visual = (try? c.decodeIfPresent(TranceVisual.self, forKey: .visual)) ?? d.visual
        tint = (try? c.decodeIfPresent(VisualTint.self, forKey: .tint)) ?? d.tint
        direction = (try? c.decodeIfPresent(VisualDirection.self, forKey: .direction))
            ?? d.direction
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed
        amplitude = try c.decodeIfPresent(Double.self, forKey: .amplitude) ?? d.amplitude
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }
}
