//
//  AudioManager.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation
import AVFoundation
import Observation

/// Manages audio playback and import
@Observable
@MainActor
class AudioManager: NSObject {

    // MARK: - Published State

    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    // MARK: - Private State

    private var audioPlayer: AVAudioPlayer?
    private var timeUpdateTimer: Timer?

    // MARK: - Audio Session Setup

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            print("✅ Audio session configured")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Playback

    func startPlayback(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            isPlaying = true
            duration = audioPlayer?.duration ?? 0

            startTimeUpdateTimer()

            print("▶️ Playback started: \(url.lastPathComponent)")
        } catch {
            print("❌ Failed to start playback: \(error)")
        }
    }

    func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
        print("⏸ Playback paused")
    }

    func resumePlayback() {
        audioPlayer?.play()
        isPlaying = true
        startTimeUpdateTimer()
        print("▶️ Playback resumed")
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
        print("⏹ Playback stopped")
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    // MARK: - Time Update Timer

    private func startTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()

        // Create timer on main queue to ensure proper MainActor context
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
            }
        }

        // Ensure timer runs on main run loop for UI responsiveness
        RunLoop.main.add(timeUpdateTimer!, forMode: .common)
    }

    // MARK: - Import Audio

    func importAudio(from url: URL) async -> AudioFile? {
        let filename = "imported_\(Date().timeIntervalSince1970)_\(url.lastPathComponent)"
        let destinationURL = URL.documentsDirectory.appending(path: filename)

        do {
            // Copy file to documents directory
            try FileManager.default.copyItem(at: url, to: destinationURL)

            // Get audio properties
            let asset = AVURLAsset(url: destinationURL)
            let duration = try await asset.load(.duration)
            let durationSeconds = duration.seconds

            // Get file size
            let resources = try destinationURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(resources.fileSize ?? 0)

            // Create AudioFile
            let audioFile = AudioFile(
                filename: filename,
                url: destinationURL,
                duration: durationSeconds,
                fileSize: fileSize
            )

            print("✅ Imported audio: \(filename)")
            return audioFile

        } catch {
            print("❌ Failed to import audio: \(error)")
            return nil
        }
    }

    // MARK: - Cleanup

    /// Cleanup audio resources - call this explicitly when done with AudioManager
    func cleanup() {
        stopPlayback()
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
        audioPlayer = nil
    }

    deinit {
        // Cleanup non-MainActor resources
        // MainActor properties cannot be accessed from deinit in Swift 6
        // Timer and player will be cleaned up automatically when references are released
    }

}

// MARK: - AVAudioPlayerDelegate

extension AudioManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isPlaying = false
            self.currentTime = 0
            self.timeUpdateTimer?.invalidate()
            self.timeUpdateTimer = nil
            print("🎵 Playback finished: \(flag ? "success" : "failed")")
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isPlaying = false
            self.timeUpdateTimer?.invalidate()
            self.timeUpdateTimer = nil
            if let error = error {
                print("❌ Playback error: \(error.localizedDescription)")
            }
        }
    }
}