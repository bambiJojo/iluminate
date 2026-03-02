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
class AudioLightSyncPlayer {

    // MARK: - State

    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 0.7

    // MARK: - Private Properties

    private var audioPlayer: AVAudioPlayer?
    private var lightEngine: LightEngine
    private var lightPlayer: LightScorePlayer?
    private var playbackTimer: Timer?
    private var currentAudioFile: AudioFile?
    private var currentLightSession: LightSession?

    // MARK: - Initialization

    init(lightEngine: LightEngine) {
        self.lightEngine = lightEngine
    }

    // MARK: - Public Methods

    /// Load and prepare audio file with its generated light session
    func loadAudioWithLights(audioFile: AudioFile, lightSession: LightSession) async throws {
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
            print("⚠️ Warning: Light session duration (\(lightSession.duration_sec)s) doesn't match audio duration (\(duration)s)")
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

    /// Start synchronized playback
    func play() {
        guard let audioPlayer = audioPlayer,
              let lightPlayer = lightPlayer else {
            print("❌ Cannot play: audio or lights not loaded")
            return
        }

        print("▶️ Starting synchronized playback...")

        // Ensure engine is running
        if !lightEngine.isRunning {
            lightEngine.start()
        }

        // Ensure session is attached
        if !lightEngine.hasActiveSession {
            lightEngine.attachSession(player: lightPlayer)
        }

        // Start audio
        audioPlayer.play()

        // Start lights
        lightPlayer.play()

        // Start playback timer for position tracking
        startPlaybackTimer()

        isPlaying = true
        print("✅ Playback started")
    }

    /// Pause synchronized playback
    func pause() {
        guard isPlaying else { return }

        print("⏸️ Pausing synchronized playback...")

        audioPlayer?.pause()
        lightPlayer?.pause()
        stopPlaybackTimer()

        isPlaying = false
        print("✅ Playback paused at \(Int(currentTime))s")
    }

    /// Stop synchronized playback
    func stop() {
        guard audioPlayer != nil || lightPlayer != nil else { return }

        print("⏹️ Stopping synchronized playback...")

        audioPlayer?.stop()
        audioPlayer?.currentTime = 0

        lightPlayer?.stop()

        // Detach session from engine and stop engine
        lightEngine.detachSession()
        lightEngine.stop()

        stopPlaybackTimer()

        currentTime = 0
        isPlaying = false

        print("✅ Playback stopped")
    }

    /// Seek to specific time in both audio and lights
    func seek(to time: TimeInterval) {
        guard let audioPlayer = audioPlayer,
              let lightPlayer = lightPlayer else {
            return
        }

        let wasPlaying = isPlaying

        // Pause if playing
        if wasPlaying {
            pause()
        }

        // Seek audio
        audioPlayer.currentTime = time

        // Seek lights
        lightPlayer.seek(to: time)

        currentTime = time

        print("⏩ Seeked to \(Int(time))s")

        // Resume if was playing
        if wasPlaying {
            play()
        }
    }

    /// Set volume (0.0 to 1.0)
    func setVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
        audioPlayer?.volume = volume
        print("🔊 Volume set to \(Int(volume * 100))%")
    }

    // MARK: - Private Methods

    private func startPlaybackTimer() {
        stopPlaybackTimer()

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }

                if let audioPlayer = self.audioPlayer {
                    self.currentTime = audioPlayer.currentTime

                    // Check if playback finished
                    if !audioPlayer.isPlaying && self.isPlaying {
                        self.handlePlaybackFinished()
                    }
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func handlePlaybackFinished() {
        print("🏁 Playback finished")
        stop()
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
