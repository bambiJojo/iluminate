//
//  ThresholdChoreography.swift
//  Ilumionate
//
//  The launch threshold's arc, as a pure function of elapsed time.
//
//  A spinner loops; a threshold progresses. Every constant here serves that
//  one distinction — a single unrepeated growth beat, a flat plateau the eye
//  reads as an ending, and an exit that inverts the entrance.
//
//  No SwiftUI, no timers, no clock. Given a number of seconds, it returns the
//  frame that belongs at that moment. That is the whole type.
//

import Foundation

struct ThresholdChoreography: Sendable {

    enum Motion: Sendable, Equatable {
        case full
        /// Same four-beat structure, expressed only in opacity.
        case reduced
    }

    /// Everything the view needs to draw one moment of the arc.
    struct Frame: Equatable, Sendable {
        /// Choreographed scale applied *on top of* LumeOrb's own breath.
        var orbScale: Double
        var orbOpacity: Double
        /// 0 = wide open, 1 = fully closed in around the centre.
        var vignetteClosure: Double
        var auroraOpacity: Double
    }

    // MARK: - Beat boundaries (seconds from the start of the arc)

    /// Arrival, Bloom and Opening keep these *absolute* lengths at every
    /// requested duration. Settle is the one beat that stretches — it is
    /// derived in `init` as whatever is left between Bloom ending and
    /// Opening's fixed final span.
    private enum Beat {
        static let arrivalEnd: TimeInterval = 0.5
        static let bloomEnd: TimeInterval = 1.6
        static let openingSpan: TimeInterval = 0.4
        /// Below this, Bloom (ending at 1.6s) and Opening's fixed 0.4s alone
        /// would leave Settle with negative width. Requests under the floor
        /// clamp up to it, so the arc degrades to its natural proportions —
        /// the same shape as the default 2.6s arc — rather than inverting.
        static let minimumDuration: TimeInterval = 2.6
    }

    /// Same shape as `Beat`, for the opacity-only Reduce Motion variant: a
    /// fixed fade in and fade out with the hold absorbing the remainder.
    private enum ReducedBeat {
        static let fadeInSpan: TimeInterval = 0.4
        static let fadeOutSpan: TimeInterval = 0.3
        /// Mirrors `Beat.minimumDuration`: below this the fade in and fade
        /// out alone would leave the hold with negative width.
        static let minimumDuration: TimeInterval = 0.9
    }

    /// The orb starts as a dim point rather than nothing, so Bloom reads as
    /// something opening rather than something appearing.
    private static let seedScale = 0.6
    private static let seedOpacity = 0.25
    /// Overshooting rest on the way out is what makes the exit read as the
    /// field opening instead of the orb being taken away.
    private static let liftScale = 1.15

    let motion: Motion

    /// The arc's effective length. Equal to the requested `duration`, unless
    /// that duration fell under the degenerate floor, in which case it is
    /// the floor itself.
    let totalDuration: TimeInterval

    /// Where the flat central beat ends and the final transition begins:
    /// Settle → Opening for `.full`, hold → fade-out for `.reduced`. This is
    /// the only boundary a duration change actually moves.
    private let plateauEnd: TimeInterval

    /// - Parameters:
    ///   - duration: the total time the arc should fill. Defaults to 2.6s,
    ///     the arc's natural length. Settle (or the reduced-motion hold)
    ///     absorbs any amount above the degenerate floor; see `Beat` and
    ///     `ReducedBeat` for that floor.
    init(motion: Motion, duration: TimeInterval = 2.6) {
        self.motion = motion
        switch motion {
        case .full:
            let clamped = max(duration, Beat.minimumDuration)
            self.totalDuration = clamped
            self.plateauEnd = clamped - Beat.openingSpan
        case .reduced:
            let clamped = max(duration, ReducedBeat.minimumDuration)
            self.totalDuration = clamped
            self.plateauEnd = clamped - ReducedBeat.fadeOutSpan
        }
    }

    // MARK: - The arc

    func frame(atElapsed elapsed: TimeInterval) -> Frame {
        let t = min(max(elapsed, 0), totalDuration)
        return switch motion {
        case .full: fullFrame(at: t)
        case .reduced: reducedFrame(at: t)
        }
    }

    private func fullFrame(at t: TimeInterval) -> Frame {
        if t <= Beat.arrivalEnd {
            let p = progress(t, from: 0, to: Beat.arrivalEnd)
            return Frame(
                orbScale: Self.seedScale,
                orbOpacity: Self.seedOpacity * p,
                vignetteClosure: easeInOut(p),
                auroraOpacity: 0
            )
        }

        if t <= Beat.bloomEnd {
            let p = progress(t, from: Beat.arrivalEnd, to: Beat.bloomEnd)
            let eased = easeOut(p)
            return Frame(
                orbScale: lerp(Self.seedScale, 1.0, eased),
                orbOpacity: lerp(Self.seedOpacity, 1.0, eased),
                vignetteClosure: 1,
                auroraOpacity: p
            )
        }

        if t <= plateauEnd {
            // Nothing moves here but the orb's own breath. That is the point.
            return Frame(orbScale: 1, orbOpacity: 1, vignetteClosure: 1, auroraOpacity: 1)
        }

        let p = progress(t, from: plateauEnd, to: totalDuration)
        return Frame(
            orbScale: lerp(1.0, Self.liftScale, easeIn(p)),
            orbOpacity: 1 - p,
            vignetteClosure: 1 - easeInOut(p),
            // Held at full. The field underneath must never dip.
            auroraOpacity: 1
        )
    }

    private func reducedFrame(at t: TimeInterval) -> Frame {
        if t <= ReducedBeat.fadeInSpan {
            let p = progress(t, from: 0, to: ReducedBeat.fadeInSpan)
            return Frame(orbScale: 1, orbOpacity: p, vignetteClosure: 0, auroraOpacity: p)
        }

        if t <= plateauEnd {
            return Frame(orbScale: 1, orbOpacity: 1, vignetteClosure: 0, auroraOpacity: 1)
        }

        let p = progress(t, from: plateauEnd, to: totalDuration)
        return Frame(orbScale: 1, orbOpacity: 1 - p, vignetteClosure: 0, auroraOpacity: 1)
    }

    // MARK: - Skip

    /// Interpolates from a captured frame to the resting frame, so a skip eases
    /// out from wherever the arc happened to be rather than snapping.
    func exitFrame(from captured: Frame, progress: Double) -> Frame {
        let p = min(max(progress, 0), 1)
        let rest = frame(atElapsed: totalDuration)
        return Frame(
            orbScale: lerp(captured.orbScale, rest.orbScale, p),
            orbOpacity: lerp(captured.orbOpacity, rest.orbOpacity, p),
            vignetteClosure: lerp(captured.vignetteClosure, rest.vignetteClosure, p),
            auroraOpacity: lerp(captured.auroraOpacity, rest.auroraOpacity, p)
        )
    }

    /// How long a skip takes to ease out.
    static let skipDuration: TimeInterval = 0.35

    // MARK: - Curves

    private func progress(_ t: TimeInterval, from: TimeInterval, to: TimeInterval) -> Double {
        guard to > from else { return 1 }
        return min(max((t - from) / (to - from), 0), 1)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private func easeIn(_ t: Double) -> Double {
        t * t * t
    }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
