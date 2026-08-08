//
//  ThresholdController.swift
//  Ilumionate
//
//  Owns the launch threshold's clock, its phase, and the decision about
//  whether it should run at all.
//
//  The controller takes an injected `now` on every call rather than reading the
//  clock itself, so the whole phase machine is testable without waiting.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class ThresholdController {

    enum Phase: Equatable {
        case running(start: Date)
        case exiting(from: ThresholdChoreography.Frame, start: Date)
        case finished
    }

    private let choreography: ThresholdChoreography
    private(set) var phase: Phase

    /// - Parameters:
    ///   - isSuppressed: when true the threshold never appears. See
    ///     `prefersNumericCountdown` for the case that sets it.
    ///   - motion: `.reduced` mirrors the Reduce Motion accessibility setting.
    ///   - duration: the countdown budget the arc should fill. Whoever builds
    ///     the controller knows both the user's countdown setting and the
    ///     accessibility environment, so both are settled here rather than
    ///     swapped in later.
    init(
        isSuppressed: Bool,
        motion: ThresholdChoreography.Motion,
        duration: TimeInterval = 2.6,
        now: Date = .now
    ) {
        self.choreography = ThresholdChoreography(motion: motion, duration: duration)
        self.phase = isSuppressed ? .finished : .running(start: now)
    }

    var isPresenting: Bool {
        phase != .finished
    }

    var isExiting: Bool {
        if case .exiting = phase { return true }
        return false
    }

    var totalDuration: TimeInterval {
        choreography.totalDuration
    }

    /// Restarts the clock. The view calls this on appear so the arc is timed
    /// from the first frame actually drawn, not from init.
    func begin(at now: Date) {
        guard case .running = phase else { return }
        phase = .running(start: now)
    }

    /// Captures the current frame and eases out from it. A no-op unless the
    /// arc is still running, so a double tap cannot restart the interpolation.
    func skip(now: Date) {
        guard case .running = phase else { return }
        phase = .exiting(from: frame(at: now), start: now)
    }

    func finish() {
        phase = .finished
    }

    func frame(at now: Date) -> ThresholdChoreography.Frame {
        switch phase {
        case .running(let start):
            choreography.frame(atElapsed: now.timeIntervalSince(start))
        case .exiting(let captured, let start):
            choreography.exitFrame(
                from: captured,
                progress: now.timeIntervalSince(start) / ThresholdChoreography.skipDuration
            )
        case .finished:
            choreography.frame(atElapsed: choreography.totalDuration)
        }
    }

    /// True once the current phase has run its course at `now`.
    func hasElapsed(at now: Date) -> Bool {
        switch phase {
        case .running(let start):
            now.timeIntervalSince(start) >= choreography.totalDuration
        case .exiting(_, let start):
            now.timeIntervalSince(start) >= ThresholdChoreography.skipDuration
        case .finished:
            true
        }
    }

    // MARK: - Suppression

    /// True when the numeric countdown should run instead of the wordless
    /// arc, at session entry on either platform.
    ///
    /// This is the same mechanism the old launch-time `shouldSuppress` used,
    /// but its meaning inverts: at launch, VoiceOver meant skipping the
    /// intro outright, because a decorative animation with nothing to
    /// announce was just delay. At session entry the countdown carries
    /// information — "3, 2, 1" — that a screen reader user needs, and the
    /// wordless arc announces nothing. So under VoiceOver we keep the
    /// numeric fallback rather than drop the intro entirely.
    static var prefersNumericCountdown: Bool {
        PlatformAccessibility.isVoiceOverRunning
    }
}
