//
//  NowPlayingState.swift
//  Ilumionate
//
//  Singleton tracking active playback so the mini-player bar can display
//  current session info and allow re-presentation of the full player.
//

import SwiftUI

@MainActor
@Observable
final class NowPlayingState {

    static let shared = NowPlayingState()

    // MARK: - Published State

    /// Whether the mini-player should be visible.
    private(set) var isActive = false

    /// Display title for the currently playing item.
    private(set) var currentTitle = ""

    /// Current playback state mirrored from the player view model.
    private(set) var playbackState: PlaybackState = .idle

    /// Normalized progress (0...1) for the thin progress bar.
    private(set) var progress: Double = 0

    /// The mode that was used to launch the player — needed to re-present it.
    private(set) var currentMode: PlayerMode?

    /// The engine associated with the current playback.
    private(set) var engine: LightEngine?

    /// The active player model so the mini-player can reopen the same session.
    private(set) var viewModel: UnifiedPlayerViewModel?

    // MARK: - Init

    private init() {}

    // MARK: - Activation

    /// Call when playback begins in UnifiedPlayerView.
    func activate(
        mode: PlayerMode,
        title: String,
        engine: LightEngine,
        viewModel: UnifiedPlayerViewModel? = nil,
        resetProgress: Bool = true
    ) {
        currentMode = mode
        currentTitle = title
        self.engine = engine
        self.viewModel = viewModel
        if resetProgress {
            progress = 0
        }
        if playbackState == .idle {
            playbackState = .playing
        }
        isActive = true
    }

    /// Call when the user fully stops playback or a session completes.
    func deactivate() {
        isActive = false
        currentMode = nil
        engine = nil
        viewModel = nil
        currentTitle = ""
        playbackState = .idle
        progress = 0
    }

    // MARK: - Updates

    /// Call periodically from the player view model's UI update timer.
    func updateProgress(_ newProgress: Double) {
        progress = newProgress.clamped(to: 0...1)
    }

    /// Mirror playback state changes from the view model.
    func updatePlaybackState(_ state: PlaybackState) {
        playbackState = state
    }
}

// MARK: - Double Clamping

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
