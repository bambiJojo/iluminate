//
//  AudioSyncController.swift
//  Ilumionate
//
//  Created by AI Assistant on 2/24/26.
//

import Foundation
import os
import AVFoundation
import Observation

/// Manages synchronized playback of audio and light sessions
@Observable
@MainActor
class AudioSyncController {

    // MARK: - State

    var isPlaying = false
    var currentTime: TimeInterval = 0.0
    var duration: TimeInterval = 0.0
    var audioVolume: Float = 1.0 {
        didSet {
            audioPlayer?.volume = audioVolume
        }
    }

    // MARK: - Private State

    private var audioPlayer: AVAudioPlayer?
    private var audioFileURL: URL?
    private var updateTimer: Timer?

    // MARK: - Callbacks

    var onTimeUpdate: ((TimeInterval) -> Void)?
    var onPlaybackFinished: (() -> Void)?

    // MARK: - Initialization

    init() {
        setupAudioSession()
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        #if !os(macOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            Log.audio.info("✅ Audio session configured for playback")
        } catch {
            Log.audio.info("❌ Failed to setup audio session: \(error)")
        }
        #else
        // macOS doesn't use AVAudioSession
        Log.audio.info("✅ Running on macOS - no audio session setup needed")
        #endif
    }

    // MARK: - Audio Loading

    func loadAudio(from url: URL) throws {
        Log.audio.info("🎵 Loading audio from: \(url.lastPathComponent)")

        // Stop any existing playback
        stop()

        // Create audio player
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = audioVolume

            audioFileURL = url
            duration = audioPlayer?.duration ?? 0.0
            currentTime = 0.0

            Log.audio.info("✅ Audio loaded, duration: \(self.duration)s")
        } catch {
            Log.audio.info("❌ Failed to load audio: \(error)")
            throw AudioSyncError.failedToLoadAudio(error)
        }
    }

    /// Asynchronous audio loading to prevent UI blocking
    func loadAudioAsync(from url: URL) async throws {
        Log.audio.info("🎵 Loading audio asynchronously from: \(url.lastPathComponent)")

        // Stop any existing playback on main actor
        await MainActor.run {
            stop()
        }

        // Load audio with proper concurrency isolation
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                do {
                    // Create audio player safely
                    let player = try AVAudioPlayer(contentsOf: url)

                    // Update properties on MainActor
                    await MainActor.run { [weak self] in
                        guard let self = self else {
                            continuation.resume(throwing: AudioSyncError.failedToLoadAudio(NSError(domain: "AudioSync", code: -1)))
                            return
                        }
                        self.audioPlayer = player
                        self.audioPlayer?.prepareToPlay()
                        self.audioPlayer?.volume = self.audioVolume

                        self.audioFileURL = url
                        self.duration = self.audioPlayer?.duration ?? 0.0
                        self.currentTime = 0.0

                        Log.audio.info("✅ Audio loaded asynchronously, duration: \(self.duration)s")
                        continuation.resume()
                    }
                } catch {
                    Log.audio.info("❌ Failed to load audio asynchronously: \(error)")
                    continuation.resume(throwing: AudioSyncError.failedToLoadAudio(error))
                }
            }
        }
    }

    // MARK: - Playback Control

    func play() {
        guard let player = audioPlayer else {
            Log.audio.info("⚠️ No audio loaded")
            return
        }

        player.play()
        isPlaying = true
        startTimer()

        Log.audio.info("▶️ Audio playback started")
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()

        Log.audio.info("⏸️ Audio playback paused")
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0.0
        isPlaying = false
        stopTimer()

        Log.audio.info("⏹️ Audio playback stopped")
    }

    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }

        let clampedTime = max(0, min(time, duration))
        player.currentTime = clampedTime
        currentTime = clampedTime

        onTimeUpdate?(currentTime)

        Log.audio.info("⏩ Seeked to \(clampedTime)s")
    }

    // MARK: - Time Tracking

    private func startTimer() {
        stopTimer()

        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateTime()
            }
        }

        // Ensure timer runs during scrolling and other UI interactions
        RunLoop.main.add(updateTimer!, forMode: .common)
    }

    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateTime() async {
        guard let player = audioPlayer else { return }

        currentTime = player.currentTime
        onTimeUpdate?(currentTime)

        // Check if finished
        if !player.isPlaying && currentTime >= duration - 0.1 {
            await handlePlaybackFinished()
        }
    }

    private func handlePlaybackFinished() async {
        isPlaying = false
        stopTimer()
        onPlaybackFinished?()

        Log.audio.info("🏁 Audio playback finished")
    }

    // MARK: - Utility

    var hasAudioLoaded: Bool {
        audioPlayer != nil
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Errors

enum AudioSyncError: LocalizedError {
    case failedToLoadAudio(Error)
    case noAudioFile
    case audioSessionError

    var errorDescription: String? {
        switch self {
        case .failedToLoadAudio(let error):
            return "Failed to load audio file: \(error.localizedDescription)"
        case .noAudioFile:
            return "No audio file specified"
        case .audioSessionError:
            return "Failed to configure audio session"
        }
    }
}
