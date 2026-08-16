//
//  PlaybackRuntime.swift
//  Ilumionate
//
//  One transport Interface over the mode-specific playback Implementations.
//  UnifiedPlayerViewModel owns presentation state; runtimes own clocks and
//  controller choreography.
//

import Foundation

nonisolated struct PlaybackAnalyticsLifecycle: Equatable, Sendable {
    private(set) var hasStarted = false
    private(set) var hasEnded = false

    mutating func prepareForNewAttempt() {
        hasStarted = false
        hasEnded = false
    }

    mutating func markStarted() -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }

    mutating func markEnded() -> Bool {
        guard hasStarted, !hasEnded else { return false }
        hasEnded = true
        return true
    }
}

nonisolated struct PlaybackResumeDecision: Equatable, Sendable {
    let startType: PlaybackStartType
    let startTime: TimeInterval

    init(
        sessionID: String,
        duration: TimeInterval,
        storedSessionID: String,
        storedProgress: Double
    ) {
        guard sessionID == storedSessionID,
              duration > 0,
              storedProgress > 0,
              storedProgress < 1 else {
            startType = .fresh
            startTime = 0
            return
        }

        startType = .resumed
        startTime = duration * storedProgress
    }
}

nonisolated struct PlaybackRuntimeSnapshot: Equatable, Sendable {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let volume: Float
    let hasReachedEnd: Bool
}

@MainActor
protocol PlaybackRuntime: AnyObject {
    func begin()
    func pause()
    func resume()
    func complete()
    func stop()
    func seek(to time: TimeInterval)
    func setVolume(_ volume: Float)
    func snapshot(elapsed: TimeInterval) -> PlaybackRuntimeSnapshot
}

/// Runtime for modes whose visual itself is the clock (color pulse and visual
/// field). Keeping this clock here prevents each view from inventing slightly
/// different pause, seek, and completion rules.
@MainActor
final class ManualPlaybackRuntime: PlaybackRuntime {
    private var currentTime: TimeInterval = 0
    private let duration: TimeInterval
    private var volume: Float
    private var isRunning = false

    init(duration: TimeInterval, volume: Float) {
        self.duration = max(0, duration)
        self.volume = Self.clampedVolume(volume)
    }

    func begin() { isRunning = true }
    func pause() { isRunning = false }
    func resume() { isRunning = true }
    func complete() { isRunning = false }

    func stop() {
        isRunning = false
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        currentTime = clampedTime(time, duration: duration)
    }

    func setVolume(_ volume: Float) {
        self.volume = Self.clampedVolume(volume)
    }

    func snapshot(elapsed: TimeInterval) -> PlaybackRuntimeSnapshot {
        if isRunning {
            currentTime = clampedTime(currentTime + max(0, elapsed), duration: duration)
        }
        return PlaybackRuntimeSnapshot(
            currentTime: currentTime,
            duration: duration,
            volume: volume,
            hasReachedEnd: duration > 0 && currentTime >= duration
        )
    }

    private static func clampedVolume(_ volume: Float) -> Float {
        max(0, min(1, volume))
    }
}

@MainActor
final class SessionPlaybackRuntime: PlaybackRuntime {
    private let scorePlayer: LightScorePlayer
    private let engine: LightEngine
    private let audio: AudioSyncController?
    private let binaural: BinauralBeatsEngine?
    private let isBinauralActive: () -> Bool
    private let duration: TimeInterval
    private var volume: Float

    init(
        scorePlayer: LightScorePlayer,
        engine: LightEngine,
        audio: AudioSyncController?,
        binaural: BinauralBeatsEngine?,
        duration: TimeInterval,
        volume: Float,
        isBinauralActive: @escaping () -> Bool
    ) {
        self.scorePlayer = scorePlayer
        self.engine = engine
        self.audio = audio
        self.binaural = binaural
        self.duration = max(0, duration)
        self.volume = max(0, min(1, volume))
        self.isBinauralActive = isBinauralActive
    }

    func begin() {
        scorePlayer.play()
        engine.resume()
        if audio?.hasAudioLoaded == true { audio?.play() }
        if isBinauralActive() { binaural?.start() }
    }

    func pause() {
        scorePlayer.pause()
        engine.pause()
        audio?.pause()
        binaural?.pause()
    }

    func resume() {
        scorePlayer.play()
        engine.resume()
        if audio?.hasAudioLoaded == true { audio?.play() }
        if isBinauralActive() { binaural?.resume() }
    }

    func complete() { pause() }

    func stop() {
        scorePlayer.stop()
        engine.detachSession()
        engine.stop()
        audio?.stop()
        binaural?.stop()
    }

    func seek(to time: TimeInterval) {
        let time = clampedTime(time, duration: duration)
        scorePlayer.seek(to: time)
        audio?.seek(to: time)
    }

    func setVolume(_ volume: Float) {
        self.volume = max(0, min(1, volume))
        audio?.audioVolume = self.volume
    }

    func snapshot(elapsed: TimeInterval) -> PlaybackRuntimeSnapshot {
        let currentTime = scorePlayer.currentTime
        return PlaybackRuntimeSnapshot(
            currentTime: currentTime,
            duration: duration,
            volume: volume,
            hasReachedEnd: hasReachedEnd(currentTime: currentTime, duration: duration)
        )
    }
}

@MainActor
final class FlashPlaybackRuntime: PlaybackRuntime {
    private let controller: FlashController
    private let binaural: BinauralBeatsEngine?
    private let isBinauralActive: () -> Bool
    private let duration: TimeInterval
    private var volume: Float

    init(
        controller: FlashController,
        binaural: BinauralBeatsEngine?,
        duration: TimeInterval,
        volume: Float,
        isBinauralActive: @escaping () -> Bool
    ) {
        self.controller = controller
        self.binaural = binaural
        self.duration = max(0, duration)
        self.volume = max(0, min(1, volume))
        self.isBinauralActive = isBinauralActive
    }

    func begin() {
        controller.start()
        if isBinauralActive() { binaural?.start() }
    }

    func pause() {
        controller.pause()
        binaural?.pause()
    }

    func resume() {
        controller.resume()
        if isBinauralActive() { binaural?.resume() }
    }

    func complete() {
        controller.stop()
        binaural?.stop()
    }

    func stop() { complete() }
    func seek(to time: TimeInterval) {
        controller.sessionDuration = clampedTime(time, duration: duration)
    }

    func setVolume(_ volume: Float) {
        self.volume = max(0, min(1, volume))
    }

    func snapshot(elapsed: TimeInterval) -> PlaybackRuntimeSnapshot {
        let currentTime = controller.sessionDuration
        return PlaybackRuntimeSnapshot(
            currentTime: currentTime,
            duration: duration,
            volume: volume,
            hasReachedEnd: hasReachedEnd(currentTime: currentTime, duration: duration)
        )
    }
}

@MainActor
final class VisualFieldPlaybackRuntime: PlaybackRuntime {
    private let clock: ManualPlaybackRuntime
    private let audio: AudioLightSyncPlayer?
    private let binaural: BinauralBeatsEngine?
    private let isBinauralActive: () -> Bool

    init(
        duration: TimeInterval,
        volume: Float,
        audio: AudioLightSyncPlayer?,
        binaural: BinauralBeatsEngine?,
        isBinauralActive: @escaping () -> Bool
    ) {
        clock = ManualPlaybackRuntime(duration: duration, volume: volume)
        self.audio = audio
        self.binaural = binaural
        self.isBinauralActive = isBinauralActive
    }

    func begin() {
        clock.begin()
        if isBinauralActive() { binaural?.start() }
        audio?.play()
    }

    func pause() {
        clock.pause()
        binaural?.pause()
        audio?.pause()
    }

    func resume() {
        clock.resume()
        if isBinauralActive() { binaural?.resume() }
        audio?.play()
    }

    func complete() {
        clock.complete()
        binaural?.stop()
        audio?.pause()
    }

    func stop() {
        clock.stop()
        binaural?.stop()
        audio?.stop()
    }

    func seek(to time: TimeInterval) {
        clock.seek(to: time)
        audio?.seek(to: time)
    }

    func setVolume(_ volume: Float) {
        clock.setVolume(volume)
        audio?.setVolume(volume)
    }

    func snapshot(elapsed: TimeInterval) -> PlaybackRuntimeSnapshot {
        let snapshot = clock.snapshot(elapsed: elapsed)
        return PlaybackRuntimeSnapshot(
            currentTime: snapshot.currentTime,
            duration: snapshot.duration,
            volume: audio?.volume ?? snapshot.volume,
            hasReachedEnd: snapshot.hasReachedEnd
        )
    }
}

@MainActor
final class AudioPlaybackRuntime: PlaybackRuntime {
    private let player: AudioLightSyncPlayer

    init(player: AudioLightSyncPlayer) {
        self.player = player
    }

    func begin() { player.play() }
    func pause() { player.pause() }
    func resume() { player.play() }
    func complete() { player.pause() }
    func stop() { player.stop() }

    func seek(to time: TimeInterval) {
        player.seek(to: clampedTime(time, duration: player.duration))
    }

    func setVolume(_ volume: Float) {
        player.setVolume(max(0, min(1, volume)))
    }

    func snapshot(elapsed: TimeInterval) -> PlaybackRuntimeSnapshot {
        player.refreshPlaybackState()
        return PlaybackRuntimeSnapshot(
            currentTime: player.currentTime,
            duration: player.duration,
            volume: player.volume,
            hasReachedEnd: !player.isPlaying
                && hasReachedEnd(currentTime: player.currentTime, duration: player.duration)
        )
    }
}

@MainActor
final class PlaylistPlaybackRuntime: PlaybackRuntime {
    private let controller: PlaylistPlayerController

    init(controller: PlaylistPlayerController) {
        self.controller = controller
    }

    func begin() {
        Task { await controller.startPlayback() }
    }

    func pause() { controller.pause() }
    func resume() { controller.play() }
    func complete() { controller.pause() }
    func stop() { controller.stop() }
    func seek(to time: TimeInterval) { controller.seek(to: time) }
    func setVolume(_ volume: Float) { controller.setVolume(volume) }

    func snapshot(elapsed: TimeInterval) -> PlaybackRuntimeSnapshot {
        PlaybackRuntimeSnapshot(
            currentTime: controller.currentTime,
            duration: controller.currentItemDuration,
            volume: controller.volume,
            // PlaylistPlayerController advances between tracks itself.
            hasReachedEnd: false
        )
    }
}

private nonisolated func clampedTime(
    _ time: TimeInterval,
    duration: TimeInterval
) -> TimeInterval {
    let lowerBounded = max(0, time)
    guard duration > 0 else { return lowerBounded }
    return min(lowerBounded, duration)
}

private nonisolated func hasReachedEnd(
    currentTime: TimeInterval,
    duration: TimeInterval
) -> Bool {
    PlaybackRetentionPolicy.hasReachedEnd(
        currentTime: currentTime,
        duration: duration,
        state: .playing
    )
}
