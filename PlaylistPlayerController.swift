//
//  PlaylistPlayerController.swift
//  Ilumionate
//
//  Manages sequential (and crossfade) playback through a playlist of audio + light sessions
//

import Foundation
import AVFoundation
import os

@MainActor
@Observable
class PlaylistPlayerController: Sendable {

    // MARK: - Public State

    var isPlaying = false
    var currentItemIndex: Int = 0
    var currentTime: TimeInterval = 0
    var currentItemDuration: TimeInterval = 0
    var smartTransitions: Bool
    var volume: Float = 0.7

    var currentItem: PlaylistItem? {
        guard currentItemIndex >= 0, currentItemIndex < playlist.items.count else { return nil }
        return playlist.items[currentItemIndex]
    }

    var itemCount: Int { playlist.items.count }

    var playlistDuration: TimeInterval {
        playlist.totalDuration
    }

    var currentItemProgress: Double {
        guard currentItemDuration > 0 else { return 0 }
        return currentTime / currentItemDuration
    }

    var isFirstItem: Bool { currentItemIndex == 0 }
    var isLastItem: Bool { currentItemIndex >= playlist.items.count - 1 }

    // MARK: - Private Properties

    private var playlist: Playlist
    private let lightEngine: LightEngine

    private var audioPlayer: AVAudioPlayer?
    private var lightPlayer: LightScorePlayer?
    private var wholePlaylistLightPlayer: LightScorePlayer?
    private var usesWholePlaylistLightSession = false

    // Crossfade state
    private var nextAudioPlayer: AVAudioPlayer?
    private var nextLightPlayer: LightScorePlayer?
    private var isCrossfading = false
    private var crossfadeTimer: Timer?
    private var crossfadeStep = 0
    private var crossfadeTrace: PerformanceInterval?

    private var playbackTimer: Timer?
    private var audioFiles: [UUID: AudioFile] = [:]
    private let storage: AudioLibraryStorage

    // MARK: - Initialization

    init(
        playlist: Playlist,
        engine: LightEngine,
        storage: AudioLibraryStorage = .standard
    ) {
        self.playlist = playlist
        self.lightEngine = engine
        self.storage = storage
        self.smartTransitions = playlist.smartTransitions
        loadWholePlaylistLightSessionIfAvailable()
    }

    // MARK: - Public Methods

    /// Start playback from the beginning or current item
    func startPlayback() async {
        let trace = PerformanceTrace.begin("Playlist Start")
        defer { PerformanceTrace.end(trace) }

        await loadAudioLibrary()

        // Without this the failure below is invisible: `loadAndPlayItem` skips
        // each unresolvable item in turn, so a playlist that resolves nothing
        // silently runs to its last index and stops, looking to the user like
        // playback jumped to the end at 0:00.
        if !playlist.items.isEmpty,
           !playlist.items.contains(where: { audioFile(for: $0) != nil }) {
            Log.audio.error(
                "Playlist '\(self.playlist.name, privacy: .public)' resolved none of its \(self.playlist.items.count) item(s) against a library of \(self.audioFiles.count) file(s) — nothing will play"
            )
        }

        if wholePlaylistLightPlayer == nil {
            loadWholePlaylistLightSessionIfAvailable()
        }

        // Configure audio session
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("⚠️ Failed to setup audio session: \(error)")
        }
        #endif

        // Ensure engine is running
        if !lightEngine.isRunning {
            lightEngine.start()
        }
        if usesWholePlaylistLightSession, let wholePlaylistLightPlayer {
            lightEngine.attachSession(player: wholePlaylistLightPlayer)
            wholePlaylistLightPlayer.seek(to: playlistTimeForCurrentItem())
        }

        // Kick off background dead-time analysis for smart crossfades
        preAnalyzeDeadTime()

        await loadAndPlayItem(at: currentItemIndex)
    }

    /// Play / resume
    func play() {
        audioPlayer?.play()
        activeLightPlayer?.play()
        startPlaybackTimer()
        isPlaying = true
    }

    /// Pause playback
    func pause() {
        audioPlayer?.pause()
        activeLightPlayer?.pause()
        cancelCrossfade()
        stopPlaybackTimer()
        isPlaying = false
    }

    /// Stop playback completely
    func stop() {
        cancelCrossfade()
        stopPlaybackTimer()

        audioPlayer?.stop()
        audioPlayer = nil

        nextAudioPlayer?.stop()
        nextAudioPlayer = nil

        lightPlayer?.stop()
        lightPlayer = nil
        nextLightPlayer = nil
        wholePlaylistLightPlayer?.stop()
        wholePlaylistLightPlayer = nil
        usesWholePlaylistLightSession = false

        lightEngine.detachSession()
        lightEngine.stop()

        isPlaying = false
        currentTime = 0
    }

    /// Skip to next track
    func skipNext() async {
        guard !isLastItem else { return }
        PerformanceTrace.event("Playlist Skip Next")
        cancelCrossfade()
        stopCurrent()
        currentItemIndex += 1
        await loadAndPlayItem(at: currentItemIndex)
    }

    /// Skip to previous track
    func skipPrevious() async {
        PerformanceTrace.event("Playlist Skip Previous")
        // If more than 3 seconds in, restart current track
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !isFirstItem else {
            seek(to: 0)
            return
        }
        cancelCrossfade()
        stopCurrent()
        currentItemIndex -= 1
        await loadAndPlayItem(at: currentItemIndex)
    }

    /// Jump to a specific track
    func jumpToItem(at index: Int) async {
        guard index >= 0, index < playlist.items.count else { return }
        PerformanceTrace.event("Playlist Jump To Track")
        cancelCrossfade()
        stopCurrent()
        currentItemIndex = index
        await loadAndPlayItem(at: index)
    }

    /// Seek within current track
    func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, currentItemDuration))
        audioPlayer?.currentTime = clampedTime
        if usesWholePlaylistLightSession {
            wholePlaylistLightPlayer?.seek(to: playlistTimeForCurrentItem() + clampedTime)
        } else {
            lightPlayer?.seek(to: clampedTime)
        }
        currentTime = clampedTime
    }

    /// Set audio volume
    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        audioPlayer?.volume = volume
    }

    /// Format time as M:SS
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Private: Loading & Playback

    /// Reads the audio library that playlist items are resolved against.
    ///
    /// Called from `startPlayback` rather than `init` for two reasons. The
    /// library lives in a file now, not `UserDefaults`, and decoding it is
    /// expensive enough that `AudioLibraryStore.allFiles` is `@concurrent` —
    /// awaiting it here keeps that work off the main actor while the player is
    /// appearing. It also means a track imported since the controller was
    /// constructed is still found.
    ///
    /// Reading `UserDefaults` directly, as this used to, silently stopped
    /// working the moment the library migrated to disk and the old key was
    /// cleared: the lookup came back empty, no item resolved, and the playlist
    /// ran itself to its last index and stopped. See ERRORS.md ERR-011.
    func loadAudioLibrary() async {
        let files = await AudioLibraryStore.allFiles(storage: storage)
        audioFiles = files.reduce(into: [:]) { lookup, file in
            lookup[file.id] = file
        }
    }

    /// The library entry backing a playlist item, or `nil` when the playlist
    /// references audio the library no longer holds.
    func audioFile(for item: PlaylistItem) -> AudioFile? {
        audioFiles[item.audioFileId]
    }

    private var activeLightPlayer: LightScorePlayer? {
        usesWholePlaylistLightSession ? wholePlaylistLightPlayer : lightPlayer
    }

    private func loadWholePlaylistLightSessionIfAvailable() {
        guard playlist.hasCurrentWholeSessionAnalysis,
              let session = PlaylistGeneratedSessionStore.shared.load(for: playlist) else {
            return
        }

        wholePlaylistLightPlayer = LightScorePlayer(session: session)
        usesWholePlaylistLightSession = true
    }

    private func playlistTimeForCurrentItem() -> TimeInterval {
        guard currentItemIndex > 0 else { return 0 }
        return playlist.items.prefix(currentItemIndex).reduce(0) { $0 + $1.duration }
    }

    /// Analyze playlist audio files for dead time in the background.
    /// Results are cached on the AudioFile model and persisted to the library.
    private func preAnalyzeDeadTime() {
        let itemIds = playlist.items.map(\.audioFileId)
        let filesToAnalyze = itemIds.compactMap { id -> (UUID, URL)? in
            guard let file = audioFiles[id], file.deadTimeProfile == nil else { return nil }
            return (id, file.url)
        }

        guard !filesToAnalyze.isEmpty else { return }
        print("🔍 Analyzing \(filesToAnalyze.count) tracks for dead-time detection...")

        let storage = storage
        Task(priority: .utility) { [weak self] in
            for (id, url) in filesToAnalyze {
                do {
                    let profile = try await PlaylistDeadTimeWorker.analyze(url: url)
                    self?.audioFiles[id]?.deadTimeProfile = profile
                    await AudioLibraryStore.saveDeadTimeProfile(
                        profile,
                        audioFileID: id,
                        storage: storage
                    )
                    let tail = profile.tailDeadTime.formatted(.number.precision(.fractionLength(1)))
                    let head = profile.headDeadTime.formatted(.number.precision(.fractionLength(1)))
                    Log.audio.debug(
                        "Dead-time: tail=\(tail)s (\(profile.tailClassification.rawValue)), head=\(head)s (\(profile.headClassification.rawValue))"
                    )
                } catch {
                    Log.audio.error(
                        "Dead-time analysis failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }

    private func loadAndPlayItem(at index: Int) async {
        let trace = PerformanceTrace.begin("Playlist Load Track")
        defer { PerformanceTrace.end(trace) }

        guard index < playlist.items.count else {
            // End of playlist
            stop()
            return
        }

        let item = playlist.items[index]

        guard let audioFile = audioFile(for: item) else {
            Log.audio.error(
                "Audio file not found for playlist item: \(item.filename, privacy: .public)"
            )
            // Skip to next
            if !isLastItem {
                currentItemIndex += 1
                await loadAndPlayItem(at: currentItemIndex)
            } else {
                stop()
            }
            return
        }

        // Load audio
        do {
            let player = try AVAudioPlayer(contentsOf: audioFile.url)
            player.prepareToPlay()
            player.volume = volume
            audioPlayer = player
            currentItemDuration = player.duration
        } catch {
            print("❌ Failed to load audio: \(error)")
            if !isLastItem {
                currentItemIndex += 1
                await loadAndPlayItem(at: currentItemIndex)
            } else {
                stop()
            }
            return
        }

        // Load light session
        if usesWholePlaylistLightSession {
            lightPlayer = nil
            wholePlaylistLightPlayer?.seek(to: playlistTimeForCurrentItem())
            if let wholePlaylistLightPlayer {
                lightEngine.attachSession(player: wholePlaylistLightPlayer)
            }
        } else if let lightSession = loadGeneratedSession(for: audioFile) {
            let lp = LightScorePlayer(session: lightSession)
            lightPlayer = lp
            lightEngine.attachSession(player: lp)
        } else {
            print("⚠️ No light session for: \(item.filename)")
            lightPlayer = nil
        }

        // Start playback
        audioPlayer?.play()
        activeLightPlayer?.play()
        startPlaybackTimer()
        isPlaying = true
        currentTime = 0

        print("▶️ Playing [\(index + 1)/\(playlist.items.count)] \(item.filename)")
    }

    private func loadGeneratedSession(for audioFile: AudioFile) -> LightSession? {
        GeneratedSessionStore.shared.load(for: audioFile)
    }

    /// Stop current item without fully stopping the controller
    private func stopCurrent() {
        stopPlaybackTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        if usesWholePlaylistLightSession {
            lightPlayer = nil
        } else {
            lightPlayer?.stop()
            lightPlayer = nil
            lightEngine.detachSession()
        }
        currentTime = 0
    }

    // MARK: - Crossfade Logic

    private func startCrossfade() {
        guard smartTransitions, !isLastItem else { return }
        guard !isCrossfading else { return }

        let nextIndex = currentItemIndex + 1
        let nextItem = playlist.items[nextIndex]

        guard let nextAudioFile = audioFile(for: nextItem) else { return }
        let trace = PerformanceTrace.begin("Playlist Crossfade")

        // Determine crossfade duration based on session content
        let crossfadeDuration = determineCrossfadeDuration()

        // Pre-load next audio
        guard let nextAudio = try? AVAudioPlayer(contentsOf: nextAudioFile.url) else {
            PerformanceTrace.end(trace)
            return
        }
        nextAudio.prepareToPlay()
        nextAudio.volume = 0 // Start silent
        nextAudioPlayer = nextAudio

        // Pre-load next light session
        if !usesWholePlaylistLightSession, let nextSession = loadGeneratedSession(for: nextAudioFile) {
            nextLightPlayer = LightScorePlayer(session: nextSession)
        }

        // Skip dead time at the beginning of the next track
        if let headDead = nextAudioFile.deadTimeProfile?.headDeadTime, headDead > 0.5 {
            nextAudio.currentTime = headDead
            nextLightPlayer?.seek(to: headDead)
        }

        isCrossfading = true
        crossfadeTrace = trace
        nextAudio.play()
        if !usesWholePlaylistLightSession {
            nextLightPlayer?.play()
        }

        print("🔄 Crossfading to next track over \(crossfadeDuration)s")

        // Animate volume crossfade
        let steps = 30 // number of steps for crossfade
        let interval = crossfadeDuration / Double(steps)
        crossfadeStep = 0

        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.crossfadeStep += 1
                let progress = Double(self.crossfadeStep) / Double(steps)

                // Fade out current, fade in next
                self.audioPlayer?.volume = self.volume * Float(1.0 - progress)
                self.nextAudioPlayer?.volume = self.volume * Float(progress)

                // At midpoint, swap light players
                if !self.usesWholePlaylistLightSession && self.crossfadeStep == steps / 2 {
                    if let nextLP = self.nextLightPlayer {
                        self.lightEngine.detachSession()
                        self.lightEngine.attachSession(player: nextLP)
                    }
                }

                // Crossfade complete
                if self.crossfadeStep >= steps {
                    self.crossfadeTimer?.invalidate()
                    self.finishCrossfade()
                }
            }
        }
    }

    private func finishCrossfade() {
        // Stop old players
        audioPlayer?.stop()
        if !usesWholePlaylistLightSession {
            lightPlayer?.stop()
        }

        // Promote next to current
        audioPlayer = nextAudioPlayer
        if !usesWholePlaylistLightSession {
            lightPlayer = nextLightPlayer
        }
        audioPlayer?.volume = volume

        nextAudioPlayer = nil
        nextLightPlayer = nil

        currentItemIndex += 1
        currentItemDuration = audioPlayer?.duration ?? 0
        currentTime = audioPlayer?.currentTime ?? 0
        isCrossfading = false
        crossfadeTimer = nil
        if let crossfadeTrace {
            PerformanceTrace.end(crossfadeTrace)
            self.crossfadeTrace = nil
        }

        print("✅ Crossfade complete, now playing [\(currentItemIndex + 1)/\(playlist.items.count)]")
    }

    private func cancelCrossfade() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        nextAudioPlayer?.stop()
        nextAudioPlayer = nil
        nextLightPlayer?.stop()
        nextLightPlayer = nil
        isCrossfading = false
        if let crossfadeTrace {
            PerformanceTrace.end(crossfadeTrace)
            self.crossfadeTrace = nil
        }
    }

    /// Determine crossfade duration using dead-time analysis + light session data.
    private func determineCrossfadeDuration() -> TimeInterval {
        let nextIndex = currentItemIndex + 1
        guard nextIndex < playlist.items.count else { return 8.0 }

        let currentFile = audioFile(for: playlist.items[currentItemIndex])
        let nextFile = audioFile(for: playlist.items[nextIndex])

        // Dead-time-based duration: cover all dead air plus a 3s musical overlap
        let tailDead = currentFile?.deadTimeProfile?.tailDeadTime ?? 0
        let headDead = nextFile?.deadTimeProfile?.headDeadTime ?? 0
        let deadTimeBased = tailDead + headDead + 3.0

        // Light-session-based duration (original heuristic as secondary signal)
        let lightBased = determineLightSessionCrossfade()

        // Use the larger of the two, clamped to 3–30 seconds
        return max(3.0, min(30.0, max(deadTimeBased, lightBased)))
    }

    /// Dead time at the end of the currently playing track.
    private func currentTrackTailDeadTime() -> TimeInterval {
        guard let item = currentItem,
              let file = audioFile(for: item) else { return 0 }
        return file.deadTimeProfile?.tailDeadTime ?? 0
    }

    /// Original light-session-based crossfade heuristic.
    private func determineLightSessionCrossfade() -> TimeInterval {
        if usesWholePlaylistLightSession {
            return 8.0
        }
        guard let currentSession = lightPlayer?.session else { return 8.0 }

        let nextIndex = currentItemIndex + 1
        guard nextIndex < playlist.items.count,
              let nextAudioFile = audioFile(for: playlist.items[nextIndex]),
              let nextSession = loadGeneratedSession(for: nextAudioFile) else {
            return 8.0
        }

        let currentMoments = currentSession.light_score
        let nextMoments = nextSession.light_score
        let endingIntensity = currentMoments.last?.intensity ?? 0.5
        let endingFreq = currentMoments.last?.frequency ?? 10
        let startingFreq = nextMoments.first?.frequency ?? 10

        if endingFreq < 6 && startingFreq < 6 && endingIntensity > 0.6 {
            return 15.0 // seamless deep blend
        }
        if endingFreq > 10 && startingFreq > 8 {
            return 5.0 // quick transition
        }
        return 8.0 // moderate default
    }

    // MARK: - Playback Timer

    private func startPlaybackTimer() {
        stopPlaybackTimer()

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let audioPlayer = self.audioPlayer {
                    self.currentTime = audioPlayer.currentTime

                    // Check for crossfade trigger
                    if self.smartTransitions && !self.isCrossfading && !self.isLastItem {
                        let crossfadeDuration = self.determineCrossfadeDuration()
                        let tailDead = self.currentTrackTailDeadTime()
                        // Start crossfade when we reach the dead zone or crossfadeDuration
                        // before end — whichever is larger — so we never play dead air.
                        let effectiveTrigger = max(crossfadeDuration, tailDead + 2.0)
                        let timeRemaining = self.currentItemDuration - self.currentTime
                        if timeRemaining <= effectiveTrigger && timeRemaining > 0 {
                            self.startCrossfade()
                        }
                    }

                    // Check if track finished (only if not crossfading — crossfade handles transition)
                    if !audioPlayer.isPlaying && self.isPlaying && !self.isCrossfading {
                        if self.currentTime >= self.currentItemDuration - 0.5 {
                            self.handleTrackFinished()
                        }
                    }
                }
            }
        }

        // Ensure timer continues during UI interactions
        RunLoop.main.add(playbackTimer!, forMode: .common)
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func handleTrackFinished() {
        PerformanceTrace.event("Playlist Track Finished")
        print("🏁 Track finished: \(currentItem?.filename ?? "?")")

        if isLastItem {
            stop()
        } else {
            // Move to next track (no crossfade — it's disabled or was skipped)
            stopCurrent()
            currentItemIndex += 1
            Task {
                await loadAndPlayItem(at: currentItemIndex)
            }
        }
    }
}
