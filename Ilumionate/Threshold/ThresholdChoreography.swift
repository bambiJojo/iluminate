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

    // MARK: - Beat boundaries (seconds from launch)

    private enum Beat {
        static let arrivalEnd: TimeInterval = 0.5
        static let bloomEnd: TimeInterval = 1.6
        static let settleEnd: TimeInterval = 2.2
        static let openingEnd: TimeInterval = 2.6
    }

    private enum ReducedBeat {
        static let fadeInEnd: TimeInterval = 0.4
        static let holdEnd: TimeInterval = 0.6
        static let fadeOutEnd: TimeInterval = 0.9
    }

    /// The orb starts as a dim point rather than nothing, so Bloom reads as
    /// something opening rather than something appearing.
    private static let seedScale = 0.6
    private static let seedOpacity = 0.25
    /// Overshooting rest on the way out is what makes the exit read as the
    /// field opening instead of the orb being taken away.
    private static let liftScale = 1.15

    let motion: Motion

    var totalDuration: TimeInterval {
        switch motion {
        case .full: Beat.openingEnd
        case .reduced: ReducedBeat.fadeOutEnd
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

        if t <= Beat.settleEnd {
            // Nothing moves here but the orb's own breath. That is the point.
            return Frame(orbScale: 1, orbOpacity: 1, vignetteClosure: 1, auroraOpacity: 1)
        }

        let p = progress(t, from: Beat.settleEnd, to: Beat.openingEnd)
        return Frame(
            orbScale: lerp(1.0, Self.liftScale, easeIn(p)),
            orbOpacity: 1 - p,
            vignetteClosure: 1 - easeInOut(p),
            // Held at full. The field underneath must never dip.
            auroraOpacity: 1
        )
    }

    private func reducedFrame(at t: TimeInterval) -> Frame {
        if t <= ReducedBeat.fadeInEnd {
            let p = progress(t, from: 0, to: ReducedBeat.fadeInEnd)
            return Frame(orbScale: 1, orbOpacity: p, vignetteClosure: 0, auroraOpacity: p)
        }

        if t <= ReducedBeat.holdEnd {
            return Frame(orbScale: 1, orbOpacity: 1, vignetteClosure: 0, auroraOpacity: 1)
        }

        let p = progress(t, from: ReducedBeat.holdEnd, to: ReducedBeat.fadeOutEnd)
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
