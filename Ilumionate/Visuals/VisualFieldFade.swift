//  VisualFieldFade.swift
//  Ilumionate
//
//  How a timed Visual Field session ends: by receding, not by cutting to black.
//
//  Pure arithmetic, kept out of the view for the same reason as
//  ReaderVisualStrength and DragValueMapper — the behaviour at the edges is
//  testable rather than something only a stopwatch and a device can tell you.

import Foundation

enum VisualFieldFade {

    /// How long the field takes to recede at the end of a timed session.
    static let window: TimeInterval = 20

    /// Strength multiplier, 1…0. Always 1 for an open-ended session.
    static func multiplier(elapsed: TimeInterval, duration: TimeInterval?) -> Double {
        guard let duration, duration > 0, duration.isFinite else { return 1 }
        guard elapsed.isFinite else { return 1 }

        let remaining = duration - max(elapsed, 0)
        guard remaining > 0 else { return 0 }

        // A session shorter than the window fades across its whole length rather
        // than starting below full strength.
        let window = min(Self.window, duration)
        guard remaining < window else { return 1 }
        return min(max(remaining / window, 0), 1)
    }

    static func isComplete(elapsed: TimeInterval, duration: TimeInterval?) -> Bool {
        guard let duration, duration > 0, duration.isFinite, elapsed.isFinite else {
            return false
        }
        return elapsed >= duration
    }
}
