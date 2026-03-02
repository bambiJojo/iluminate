//
//  PlaylistPlayerController.swift
//  Ilumionate
//
//  Manages sequential (and crossfade) playback through a playlist of audio + light sessions
//

import Foundation
import AVFoundation

@MainActor
@Observable
class PlaylistPlayerController {

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

    // Crossfade state
    private var nextAudioPlayer: AVAudioPlayer?
    private var nextLightPlayer: LightScorePlayer?
    private var isCrossfading = false
    private var crossfadeTimer: Timer?

    private var playbackTimer: Timer?
    private var audioFiles: [UUID: AudioFile] = [:]

    // MARK: - Initialization

    init(playlist: Playlist, engine: LightEngine) {
        self.playlist = playlist
        self.lightEngine = engine
        self.smartTransitions = playlist.smartTransitions
        loadAudioFileLookup()
    }

    // MARK: - Public Methods

    /// Start playback from the beginning or current item
    func startPlayback() async {
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

        // Kick off background dead-time analysis for smart crossfades
        preAnalyzeDeadTime()

        await loadAndPlayItem(at: currentItemIndex)
    }

    /// Play / resume
    func play() {
        audioPlayer?.play()
        lightPlayer?.play()
        startPlaybackTimer()
        isPlaying = true
    }

    /// Pause playback
    func pause() {
        audioPlayer?.pause()
        lightPlayer?.pause()
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

        lightEngine.detachSession()
        lightEngine.stop()

        isPlaying = false
        currentTime = 0
    }

    /// Skip to next track
    func skipNext() async {
        guard !isLastItem else { return }
        cancelCrossfade()
        stopCurrent()
        currentItemIndex += 1
        await loadAndPlayItem(at: currentItemIndex)
    }

    /// Skip to previous track
    func skipPrevious() async {
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
        cancelCrossfade()
        stopCurrent()
        currentItemIndex = index
        await loadAndPlayItem(at: index)
    }

    /// Seek within current track
    func seek(to time: TimeInterval) {
        let clampedTime = max(0, min(time, currentItemDuration))
        audioPlayer?.currentTime = clampedTime
        lightPlayer?.seek(to: clampedTime)
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

    private func loadAudioFileLookup() {
        if let data = UserDefaults.standard.data(forKey: "audioFiles"),
           let files = try? JSONDecoder().decode([AudioFile].self, from: data) {
            for file in files {
                audioFiles[file.id] = file
            }
        }
    }

    /// Analyze playlist audio files for dead time in the background.
    /// Results are cached on the AudioFile model and persisted to UserDefaults.
    private func preAnalyzeDeadTime() {
        let itemIds = playlist.items.map(\.audioFileId)
        let filesToAnalyze = itemIds.compactMap { id -> (UUID, URL)? in
            guard let file = audioFiles[id], file.deadTimeProfile == nil else { return nil }
            return (id, file.url)
        }

        guard !filesToAnalyze.isEmpty else { return }
        print("🔍 Analyzing \(filesToAnalyze.count) tracks for dead-time detection...")

        Task.detached {
            let analyzer = AudioEnergyAnalyzer()
            for (id, url) in filesToAnalyze {
                do {
                    let profile = try analyzer.analyze(url: url)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.audioFiles[id]?.deadTimeProfile = profile
                        self.persistAudioFileUpdate(id: id)
                        let tail = String(format: "%.1f", profile.tailDeadTime)
                        let head = String(format: "%.1f", profile.headDeadTime)
                        print("  ✅ Dead-time: tail=\(tail)s (\(profile.tailClassification)), head=\(head)s (\(profile.headClassification))")
                    }
                } catch {
                    print("  ⚠️ Dead-time analysis failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Persist a single AudioFile update back to the shared UserDefaults store.
    private func persistAudioFileUpdate(id: UUID) {
        // Reload the full list, update the matching entry, and re-save
        guard let data = UserDefaults.standard.data(forKey: "audioFiles"),
              var files = try? JSONDecoder().decode([AudioFile].self, from: data) else { return }

        if let idx = files.firstIndex(where: { $0.id == id }),
           let updated = audioFiles[id] {
            files[idx] = updated
            if let encoded = try? JSONEncoder().encode(files) {
                UserDefaults.standard.set(encoded, forKey: "audioFiles")
            }
        }
    }

    private func loadAndPlayItem(at index: Int) async {
        guard index < playlist.items.count else {
            // End of playlist
            stop()
            return
        }

        let item = playlist.items[index]

        guard let audioFile = audioFiles[item.audioFileId] else {
            print("❌ Audio file not found for playlist item: \(item.filename)")
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
        if let lightSession = loadGeneratedSession(for: audioFile) {
            let lp = LightScorePlayer(session: lightSession)
            lightPlayer = lp
            lightEngine.attachSession(player: lp)
        } else {
            print("⚠️ No light session for: \(item.filename)")
            lightPlayer = nil
        }

        // Start playback
        audioPlayer?.play()
        lightPlayer?.play()
        startPlaybackTimer()
        isPlaying = true
        currentTime = 0

        print("▶️ Playing [\(index + 1)/\(playlist.items.count)] \(item.filename)")
    }

    private func loadGeneratedSession(for audioFile: AudioFile) -> LightSession? {
        let documentsURL = URL.documentsDirectory
        let sessionsURL = documentsURL.appendingPathComponent("GeneratedSessions", isDirectory: true)
        let baseName = audioFile.filename
            .replacing(".mp3", with: "")
            .replacing(".m4a", with: "")
            .replacing(".wav", with: "")
        let sessionFile = sessionsURL.appendingPathComponent("\(baseName)_session.json")

        guard FileManager.default.fileExists(atPath: sessionFile.path) else { return nil }
        return try? LightScoreReader.loadSession(from: sessionFile)
    }

    /// Stop current item without fully stopping the controller
    private func stopCurrent() {
        stopPlaybackTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        lightPlayer?.stop()
        lightPlayer = nil
        lightEngine.detachSession()
        currentTime = 0
    }

    // MARK: - Crossfade Logic

    private func startCrossfade() {
        guard smartTransitions, !isLastItem else { return }
        guard !isCrossfading else { return }

        let nextIndex = currentItemIndex + 1
        let nextItem = playlist.items[nextIndex]

        guard let nextAudioFile = audioFiles[nextItem.audioFileId] else { return }

        // Determine crossfade duration based on session content
        let crossfadeDuration = determineCrossfadeDuration()

        // Pre-load next audio
        guard let nextAudio = try? AVAudioPlayer(contentsOf: nextAudioFile.url) else { return }
        nextAudio.prepareToPlay()
        nextAudio.volume = 0 // Start silent
        nextAudioPlayer = nextAudio

        // Pre-load next light session
        if let nextSession = loadGeneratedSession(for: nextAudioFile) {
            nextLightPlayer = LightScorePlayer(session: nextSession)
        }

        // Skip dead time at the beginning of the next track
        if let headDead = nextAudioFile.deadTimeProfile?.headDeadTime, headDead > 0.5 {
            nextAudio.currentTime = headDead
            nextLightPlayer?.seek(to: headDead)
        }

        isCrossfading = true
        nextAudio.play()
        nextLightPlayer?.play()

        print("🔄 Crossfading to next track over \(crossfadeDuration)s")

        // Animate volume crossfade
        let steps = 30 // number of steps for crossfade
        let interval = crossfadeDuration / Double(steps)
        var step = 0

        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                step += 1
                let progress = Double(step) / Double(steps)

                // Fade out current, fade in next
                self.audioPlayer?.volume = self.volume * Float(1.0 - progress)
                self.nextAudioPlayer?.volume = self.volume * Float(progress)

                // At midpoint, swap light players
                if step == steps / 2 {
                    if let nextLP = self.nextLightPlayer {
                        self.lightEngine.detachSession()
                        self.lightEngine.attachSession(player: nextLP)
                    }
                }

                // Crossfade complete
                if step >= steps {
                    self.crossfadeTimer?.invalidate()
                    self.finishCrossfade()
                }
            }
        }
    }

    private func finishCrossfade() {
        // Stop old players
        audioPlayer?.stop()
        lightPlayer?.stop()

        // Promote next to current
        audioPlayer = nextAudioPlayer
        lightPlayer = nextLightPlayer
        audioPlayer?.volume = volume

        nextAudioPlayer = nil
        nextLightPlayer = nil

        currentItemIndex += 1
        currentItemDuration = audioPlayer?.duration ?? 0
        currentTime = audioPlayer?.currentTime ?? 0
        isCrossfading = false
        crossfadeTimer = nil

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
    }

    /// Determine crossfade duration using dead-time analysis + light session data.
    private func determineCrossfadeDuration() -> TimeInterval {
        let nextIndex = currentItemIndex + 1
        guard nextIndex < playlist.items.count else { return 8.0 }

        let currentFile = audioFiles[playlist.items[currentItemIndex].audioFileId]
        let nextFile = audioFiles[playlist.items[nextIndex].audioFileId]

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
              let file = audioFiles[item.audioFileId] else { return 0 }
        return file.deadTimeProfile?.tailDeadTime ?? 0
    }

    /// Original light-session-based crossfade heuristic.
    private func determineLightSessionCrossfade() -> TimeInterval {
        guard let currentSession = lightPlayer?.session else { return 8.0 }

        let nextIndex = currentItemIndex + 1
        guard nextIndex < playlist.items.count,
              let nextAudioFile = audioFiles[playlist.items[nextIndex].audioFileId],
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
                guard let self else { return }

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
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func handleTrackFinished() {
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
