//
//  SystemNowPlayingPublishPolicy.swift
//  Ilumionate
//
//  Decides when the system Now Playing dictionary is actually worth rebuilding.
//
//  The player pushes an update on every UI tick (4–10 Hz). MediaPlayer already
//  extrapolates elapsed time from the last reported position and playback rate,
//  so re-publishing that same steady advance is pure overhead — and on the lock
//  screen it can make the scrubber stutter. This keeps the policy as a value
//  type so the rule is testable without a live MPNowPlayingInfoCenter.
//

import Foundation

nonisolated struct SystemNowPlayingPublishPolicy {

    /// How far the real position may drift from the rate-based extrapolation
    /// before a fresh push is warranted. Below this is ordinary playback
    /// advance; above it means the position jumped, which is a seek.
    static let driftTolerance: TimeInterval = 2

    /// The subset of Now Playing state that determines whether a push is needed.
    struct State: Equatable, Sendable {
        let title: String
        let isPlaying: Bool
        let currentTime: TimeInterval
        let duration: TimeInterval
    }

    private var published: (state: State, at: TimeInterval)?

    init() {}

    /// Forget the last push, so the next update always publishes. Call when a
    /// session starts or ends — otherwise a new session that happens to match
    /// the previous one's title and state would be silently skipped.
    mutating func reset() {
        published = nil
    }

    /// Whether `state` must be handed to MediaPlayer, recording it as published
    /// when so. Returns true for anything the system cannot infer on its own:
    /// a different item, a changed play state, or a seek.
    mutating func shouldPublish(_ state: State, at now: TimeInterval) -> Bool {
        guard let published else {
            self.published = (state, now)
            return true
        }

        let isSameItem = published.state.title == state.title
            && published.state.isPlaying == state.isPlaying
            && published.state.duration == state.duration

        if isSameItem {
            let extrapolated = published.state.isPlaying
                ? published.state.currentTime + (now - published.at)
                : published.state.currentTime
            guard abs(state.currentTime - extrapolated) > Self.driftTolerance else {
                return false
            }
        }

        self.published = (state, now)
        return true
    }
}
