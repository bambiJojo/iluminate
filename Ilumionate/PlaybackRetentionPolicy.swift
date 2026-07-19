//
//  PlaybackRetentionPolicy.swift
//  Ilumionate
//

import Foundation

nonisolated enum PlaybackInterruptionAction: Equatable, Sendable {
    case none
    case pause
    case cancelPendingStart
}

/// Pure lifecycle decisions shared by the player and its regression tests.
nonisolated enum PlaybackRetentionPolicy {

    static func interruptionAction(for state: PlaybackState) -> PlaybackInterruptionAction {
        switch state {
        case .playing:
            return .pause
        case .countdown:
            return .cancelPendingStart
        case .idle, .paused, .complete:
            return .none
        }
    }

    static func hasReachedEnd(
        currentTime: TimeInterval,
        duration: TimeInterval,
        state: PlaybackState,
        tolerance: TimeInterval = 0.5
    ) -> Bool {
        guard state == .playing, duration > 0 else { return false }
        return currentTime >= max(0, duration - tolerance)
    }
}
