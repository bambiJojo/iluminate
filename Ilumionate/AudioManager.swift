//
//  AudioManager.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation
import os
import AVFoundation
import Observation

/// Manages audio playback and import
@Observable
@MainActor
class AudioManager: NSObject {

    static let shared = AudioManager()

    // MARK: - Published State

    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    // MARK: - Private State

    private var audioPlayer: AVAudioPlayer?
    private var timeUpdateTimer: Timer?
    private var isAudioSessionConfigured = false

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        guard !isAudioSessionConfigured else { return }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            isAudioSessionConfigured = true
            Log.audio.info("✅ Audio session configured")
        } catch {
            Log.audio.info("❌ Failed to setup audio session: \(error)")
        }
        #else
        isAudioSessionConfigured = true
        #endif
    }

    // MARK: - Playback

    func startPlayback(url: URL) {
        setupAudioSession()
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            isPlaying = true
            duration = audioPlayer?.duration ?? 0

            startTimeUpdateTimer()

            Log.audio.info("▶️ Playback started: \(url.lastPathComponent)")
        } catch {
            Log.audio.info("❌ Failed to start playback: \(error)")
        }
    }

    func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false

        // Stop timer immediately to save CPU
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
        Log.audio.info("⏸ Playback paused")
    }

    func resumePlayback() {
        setupAudioSession()
        audioPlayer?.play()
        isPlaying = true

        // Restart timer with current state
        startTimeUpdateTimer()
        Log.audio.info("▶️ Playback resumed")
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
        Log.audio.info("⏹ Playback stopped")
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    // MARK: - Time Update Timer

    private func startTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()

        // Adaptive timer frequency based on playback state
        let updateInterval: TimeInterval = isPlaying ? 0.1 : 0.5

        // Create timer with weak self to prevent retain cycles
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let player = self.audioPlayer,
                      self.isPlaying else { return }
                self.currentTime = player.currentTime
            }
        }

        // Use common run loop mode for consistent updates
        RunLoop.main.add(timeUpdateTimer!, forMode: .common)
    }

    // MARK: - Import Audio

    func importAudio(from url: URL) async -> AudioFile? {
        do {
            let audioFile = try await AudioImportWorker.prepareAudioFile(
                from: url,
                targetFilename: url.lastPathComponent,
                transferMode: .copy,
                durationTimeout: .seconds(3)
            )

            let restoredAudioFile = AnalysisStateManager.shared.restoringCachedData(in: audioFile)
            if restoredAudioFile.isAnalyzed {
                Log.audio.info("⚡ Restored cached analysis for: \(audioFile.filename)")
            }

            Log.audio.info("✅ Imported audio: \(audioFile.filename) (Duration: \(audioFile.duration)s)")
            UsageAnalytics.shared.audioImported(source: .files)
            return restoredAudioFile

        } catch {
            Log.audio.info("❌ Failed to import audio: \(error)")
            UsageAnalytics.shared.errorOccurred(.audioFileImportFailed)
            return nil
        }
    }

    /// Downloads an audio file from a remote URL, saves it locally, and returns an AudioFile object
    func downloadAudio(from sourceURL: URL) async throws -> AudioFile? {
        // Download the file to a temporary location
        let (tempURL, response) = try await URLSession.shared.download(from: sourceURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            throw URLError(.badServerResponse)
        }
        
        let contentType = httpResponse.allHeaderFields["Content-Type"] as? String

        // Verify this is actually audio before it can reach the library. A URL
        // ending in ".mp3" and an audio Content-Type are both only claims; a
        // server that returns a sign-in page or a 404 body makes them both liars.
        // Reading the leading bytes is enough to tell.
        let leadingBytes = (try? FileHandle(forReadingFrom: tempURL).read(upToCount: 64)) ?? Data()
        if let rejection = AudioDownloadValidation.rejectionReason(
            contentType: contentType,
            data: leadingBytes
        ) {
            try? FileManager.default.removeItem(at: tempURL)
            Log.audio.info("❌ Rejected non-audio download from \(sourceURL.absoluteString): \(rejection)")
            UsageAnalytics.shared.errorOccurred(.audioURLServerRejected)
            throw rejection
        }

        // Extract original filename or create a fallback using Content-Type hint
        let originalName = sourceURL.lastPathComponent.components(separatedBy: "?").first ?? ""
        let targetName: String
        let originalExt = URL(fileURLWithPath: originalName).pathExtension.lowercased()
        if !originalName.isEmpty, originalName != "/",
           AudioDownloadValidation.audioExtensions.contains(originalExt) {
            // URL has a recognizable audio extension – use it directly
            targetName = originalName
        } else {
            // Trust the header, then the bytes. Never guess: an extension that
            // does not match the payload is what put HTML in the library.
            let ext = contentType
                .flatMap(AudioDownloadValidation.audioExtension(forContentType:))
                ?? AudioDownloadValidation.inferredExtension(from: leadingBytes)
                ?? "mp3"
            let baseName = originalName.isEmpty || originalName == "/" ? "DownloadedAudio" : (originalName as NSString).deletingPathExtension
            targetName = "\(baseName).\(ext)"
        }

        do {
            let audioFile = try await AudioImportWorker.prepareAudioFile(
                from: tempURL,
                targetFilename: targetName,
                transferMode: .move,
                durationTimeout: .seconds(5)
            )

            let restoredAudioFile = AnalysisStateManager.shared.restoringCachedData(in: audioFile)
            if restoredAudioFile.isAnalyzed {
                Log.audio.info("⚡ Restored cached analysis for downloaded file: \(audioFile.filename)")
            }

            Log.audio.info("✅ Successfully downloaded audio: \(audioFile.filename) (Duration: \(audioFile.duration)s)")
            UsageAnalytics.shared.audioImported(source: .url)
            return restoredAudioFile
            
        } catch {
            Log.audio.info("❌ Failed to move downloaded file to Library: \(error)")
            try? FileManager.default.removeItem(at: tempURL)
            throw error
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
            Log.audio.info("🎵 Playback finished: \(flag ? "success" : "failed")")
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isPlaying = false
            self.timeUpdateTimer?.invalidate()
            self.timeUpdateTimer = nil
            if let error = error {
                Log.audio.info("❌ Playback error: \(error.localizedDescription)")
            }
        }
    }
}
