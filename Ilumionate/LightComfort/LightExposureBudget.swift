//
//  LightExposureBudget.swift
//  Ilumionate
//
//  Counts actual light-output time independently of the audio playback clock.
//

import Foundation

nonisolated struct LightExposureBudget: Equatable, Sendable {
    /// A slow landing avoids replacing an entrainment field with darkness at a
    /// single instant, which can be more disruptive than the limit itself.
    static let fadeDuration: TimeInterval = 60

    let limit: LightExposureLimit
    private(set) var elapsed: TimeInterval = 0

    var remaining: TimeInterval {
        max(0, limit.duration - elapsed)
    }

    var isExpired: Bool {
        remaining == 0
    }

    /// Smoothstep from full output to zero during the final fade window.
    var outputMultiplier: Double {
        Self.outputMultiplier(remaining: remaining)
    }

    static func outputMultiplier(remaining: TimeInterval) -> Double {
        guard remaining < fadeDuration else { return 1 }
        let progress = max(0, min(1, remaining / fadeDuration))
        return progress * progress * (3 - (2 * progress))
    }

    /// Advances only while light is genuinely being emitted. Returns true once,
    /// on the update that first consumes the full budget.
    mutating func advance(by interval: TimeInterval, whileEmitting: Bool) -> Bool {
        guard whileEmitting, interval > 0, isExpired == false else { return false }
        elapsed = min(limit.duration, elapsed + interval)
        return isExpired
    }
}
