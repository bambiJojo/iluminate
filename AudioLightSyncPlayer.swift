//
//  AudioLightSyncPlayer.swift
//  Ilumionate
//
//  Synchronized playback of audio files with their generated light sessions
//

import Foundation
import AVFoundation

enum AudioLightSyncPlayerError: Error {
    case lightSessionLoadFailed
    case audioLoadFailed
}

/// Manages synchronized playback of audio and light sessions
@MainActor
@Observable
class AudioLightSyncPlayer: Sendable {

    // MARK: - State

    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 0.7

    // MARK: - Private Properties

    private var audioPlayer: AVAudioPlayer?
    private var lightEngine: LightEngine
    private var lightPlayer: LightScorePlayer?
    private var currentAudioFile: AudioFile?
    private var currentLightSession: LightSession?

    // MARK: - Initialization

    init(lightEngine: LightEngine) {
        self.lightEngine = lightEngine
    }

    // MARK: - Public Methods

    /// Whether a light session is currently loaded
    var hasLightSync: Bool { lightPlayer != nil }

    /// Load audio only — no light session required. Light sync can be enabled later via enableLightSync(_:).
    func loadAudio(audioFile: AudioFile) async throws {
        let trace = PerformanceTrace.begin("Audio Player Load")
        defer { PerformanceTrace.end(trace) }

        stop()

        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("⚠️ Failed to setup audio session: \(error)")
        }
        #endif

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioFile.url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = volume
            duration = audioPlayer?.duration ?? 0
            currentAudioFile = audioFile
            print("✅ Audio loaded (audio-only mode): \(Int(duration)) seconds")
        } catch {
            throw AudioLightSyncError.audioLoadFailed(error)
        }
    }

    /// Attach a light session to a running audio player and start syncing lights.
    func enableLightSync(lightSession: LightSession) {
        let trace = PerformanceTrace.begin("Light Sync Attach")
        defer { PerformanceTrace.end(trace) }

        let wasPlaying = isPlaying
        let currentPos = audioPlayer?.currentTime ?? currentTime
        currentTime = currentPos

        if wasPlaying {
            audioPlayer?.pause()
            isPlaying = false
        }

        let player = LightScorePlayer(session: lightSession)
        player.seek(to: currentPos)
        lightPlayer = player
        currentLightSession = lightSession

        lightEngine.attachSession(player: player)
        if !lightEngine.isRunning {
            lightEngine.start()
        }

        if wasPlaying {
            audioPlayer?.play()
            player.play()
            isPlaying = true
        }
        print("💡 Light sync enabled")
    }

    /// Detach the current light session, leaving audio playing.
    func disableLightSync() {
        lightEngine.detachSession()
        lightEngine.stop()
        lightPlayer?.stop()
        lightPlayer = nil
        currentLightSession = nil
        print("💡 Light sync disabled")
    }

    /// Load and prepare audio file with its generated light session
    func loadAudioWithLights(audioFile: AudioFile, lightSession: LightSession) async throws {
        let trace = PerformanceTrace.begin("Audio Player Load With Lights")
        defer { PerformanceTrace.end(trace) }

        print("🎵🔆 Loading synchronized playback...")
        print("📄 Audio: \(audioFile.filename)")
        print("💡 Session: \(lightSession.session_name)")

        // Stop any current playback
        stop()

        // Configure audio session for playback
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            print("✅ Audio session configured for playback")
        } catch {
            print("⚠️ Failed to setup audio session: \(error)")
        }
        #endif

        // Load audio
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioFile.url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = volume

            duration = audioPlayer?.duration ?? 0
            currentAudioFile = audioFile

            print("✅ Audio loaded: \(Int(duration)) seconds")
        } catch {
            print("❌ Failed to load audio: \(error)")
            throw AudioLightSyncError.audioLoadFailed(error)
        }

        // Verify light session duration matches audio
        let timeDifference = abs(lightSession.duration_sec - duration)
        if timeDifference > 5.0 { // Allow 5 second tolerance
            print("⚠️ Warning: Light session duration (\(Int(lightSession.duration_sec))s) " +
                  "doesn't match audio duration (\(Int(duration))s)")
        }

        // Create light player
        lightPlayer = LightScorePlayer(session: lightSession)
        currentLightSession = lightSession

        // Attach player to engine
        guard let player = lightPlayer else {
            throw AudioLightSyncPlayerError.lightSessionLoadFailed
        }
        lightEngine.attachSession(player: player)

        // Start engine if not running
        if !lightEngine.isRunning {
            lightEngine.start()
        }

        print("✅ Light session loaded with \(lightSession.light_score.count) moments")
        print("🎬 Ready for synchronized playback")
    }

    /// Start playback. Works in audio-only mode (no light session required).
    func play() {
        guard let audioPlayer = audioPlayer else {
            print("❌ Cannot play: audio not loaded")
            return
        }

        if let lightPlayer = lightPlayer {
            if !lightEngine.isRunning { lightEngine.start() }
            if !lightEngine.hasActiveSession { lightEngine.attachSession(player: lightPlayer) }
            lightPlayer.play()
            lightEngine.resume()
        }

        audioPlayer.play()
        isPlaying = true
        print("▶️ Playback started")
    }

    /// Pause playback.
    func pause() {
        guard isPlaying else { return }
        currentTime = audioPlayer?.currentTime ?? currentTime
        audioPlayer?.pause()
        lightPlayer?.pause()
        if lightPlayer != nil { lightEngine.pause() }
        isPlaying = false
        print("⏸️ Playback paused at \(Int(currentTime))s")
    }

    /// Stop and reset playback.
    func stop() {
        guard audioPlayer != nil else { return }
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        if lightPlayer != nil {
            lightPlayer?.stop()
            lightEngine.detachSession()
            lightEngine.stop()
        }
        currentTime = 0
        isPlaying = false
        print("⏹️ Playback stopped")
    }

    /// Seek to a specific time in audio and (if loaded) lights.
    func seek(to time: TimeInterval) {
        guard let audioPlayer = audioPlayer else { return }
        let wasPlaying = isPlaying
        if wasPlaying { pause() }
        audioPlayer.currentTime = time
        lightPlayer?.seek(to: time)
        currentTime = time
        print("⏩ Seeked to \(Int(time))s")
        if wasPlaying { play() }
    }

    /// Set volume (0.0 to 1.0)
    func setVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
        audioPlayer?.volume = volume
        print("🔊 Volume set to \(Int(volume * 100))%")
    }

    // MARK: - Playback Snapshot

    /// Pulls the authoritative AVAudioPlayer clock when the owning runtime
    /// publishes UI state. AudioLightSyncPlayer previously ran a second 10 Hz
    /// timer alongside UnifiedPlayerViewModel's clock, doubling wakeups and
    /// observable writes for the same playback position.
    func refreshPlaybackState() {
        guard let audioPlayer else { return }
        currentTime = audioPlayer.currentTime
        if !audioPlayer.isPlaying && isPlaying {
            handlePlaybackFinished()
        }
    }

    private func handlePlaybackFinished() {
        print("🏁 Playback finished")
        // Preserve the terminal position. Resetting to zero here made the
        // outer runtime observe an idle track instead of a completed one, so
        // the player never entered its completion state.
        audioPlayer?.currentTime = duration
        lightPlayer?.seek(to: duration)
        currentTime = duration
        isPlaying = false
    }

    // MARK: - Helper Methods

    /// Get current playback position as percentage (0.0 to 1.0)
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    /// Format time as MM:SS
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Error Types

enum AudioLightSyncError: LocalizedError {
    case audioLoadFailed(Error)
    case lightSessionMismatch
    case noFileLoaded

    var errorDescription: String? {
        switch self {
        case .audioLoadFailed(let error):
            return "Failed to load audio: \(error.localizedDescription)"
        case .lightSessionMismatch:
            return "Light session duration doesn't match audio duration"
        case .noFileLoaded:
            return "No audio or light session loaded"
        }
    }
}
