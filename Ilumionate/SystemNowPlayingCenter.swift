//
//  SystemNowPlayingCenter.swift
//  Ilumionate
//
//  Bridges the active session to the system Now Playing surfaces — lock
//  screen, Control Center, and hardware transport keys.
//
//  These controls let users manage playback outside the app. Audible
//  background playback itself is provided by the player's audio session.
//
//  `NowPlayingState` is the in-app mini-player; this is its system-facing
//  counterpart. They are deliberately separate — one drives SwiftUI, the
//  other drives MediaPlayer.
//

import Foundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// Transport actions the owning player exposes to the system.
@MainActor
struct SystemNowPlayingHandlers {
    let play: () -> Void
    let pause: () -> Void
    let togglePlayPause: () -> Void
    let seek: (TimeInterval) -> Void
    let skipForward: () -> Void
    let skipBackward: () -> Void
}

@MainActor
final class SystemNowPlayingCenter {

    static let shared = SystemNowPlayingCenter()

    /// Seconds the lock-screen skip buttons jump, matching the in-app controls.
    static let skipInterval: TimeInterval = 15

    private var handlers: SystemNowPlayingHandlers?
    private var hasRegisteredCommands = false
    private var policy = SystemNowPlayingPublishPolicy()

    private init() {}

    // MARK: - Session lifecycle

    /// Take ownership of the system transport for a newly started session.
    func begin(title: String, duration: TimeInterval, handlers: SystemNowPlayingHandlers) {
        self.handlers = handlers
        policy.reset()
        registerCommandsIfNeeded()
        update(title: title, isPlaying: true, currentTime: 0, duration: duration)
    }

    /// Push the current position and play state to the lock screen. Called on
    /// every transport change and on the player's periodic update, so a
    /// scrubbed or paused session stays truthful outside the app.
    func update(title: String, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) {
        let state = SystemNowPlayingPublishPolicy.State(
            title: title,
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration
        )
        guard policy.shouldPublish(state, at: ProcessInfo.processInfo.systemUptime) else { return }

        #if canImport(MediaPlayer)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "LumeSync",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, currentTime),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]
        // A zero duration renders as an unusable scrubber, so only advertise a
        // real one. Visual-only modes with no fixed length fall through here.
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS) || targetEnvironment(macCatalyst)
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #endif
        #endif
    }

    /// Release the system transport when the session ends.
    func end() {
        handlers = nil
        policy.reset()
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS) || targetEnvironment(macCatalyst)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
        #endif
    }

    // MARK: - Remote commands

    /// Handlers are registered once and dispatch through `handlers`, so a new
    /// session swaps the target without stacking duplicate command targets —
    /// the classic cause of a single lock-screen tap firing several times.
    private func registerCommandsIfNeeded() {
        #if canImport(MediaPlayer)
        guard !hasRegisteredCommands else { return }
        hasRegisteredCommands = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let handlers = self?.handlers else { return .noActionableNowPlayingItem }
            handlers.play()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let handlers = self?.handlers else { return .noActionableNowPlayingItem }
            handlers.pause()
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let handlers = self?.handlers else { return .noActionableNowPlayingItem }
            handlers.togglePlayPause()
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let handlers = self?.handlers,
                  let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .noActionableNowPlayingItem
            }
            handlers.seek(event.positionTime)
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let handlers = self?.handlers else { return .noActionableNowPlayingItem }
            handlers.skipForward()
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let handlers = self?.handlers else { return .noActionableNowPlayingItem }
            handlers.skipBackward()
            return .success
        }

        // Never offered: this app has no notion of a previous/next track
        // outside playlists, and an enabled command that does nothing is worse
        // than an absent one.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        #endif
    }
}
