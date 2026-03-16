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

        // Stop timer immediately to save CPU
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
        print("⏸ Playback paused")
    }

    func resumePlayback() {
        audioPlayer?.play()
        isPlaying = true

        // Restart timer with current state
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

    /// Create a unique file URL if the destination already exists
    private func makeUniqueFileURL(_ url: URL) -> URL {
        let fileManager = FileManager.default
        var uniqueURL = url
        var counter = 1

        // Keep trying until we find a unique filename
        while fileManager.fileExists(atPath: uniqueURL.path) {
            let nameWithoutExtension = url.deletingPathExtension().lastPathComponent
            let fileExtension = url.pathExtension
            let newName = "\(nameWithoutExtension) (\(counter)).\(fileExtension)"
            uniqueURL = url.deletingLastPathComponent().appending(path: newName)
            counter += 1
        }

        return uniqueURL
    }

    func importAudio(from url: URL) async -> AudioFile? {
        let originalName = url.lastPathComponent
        let destinationURL = URL.documentsDirectory.appending(path: originalName)

        // Check if file already exists and create unique name if needed
        let finalDestinationURL = makeUniqueFileURL(destinationURL)
        let finalFilename = finalDestinationURL.lastPathComponent

        do {
            // Copy file to documents directory
            try FileManager.default.copyItem(at: url, to: finalDestinationURL)
            print("📁 File copied to: \(finalDestinationURL.path)")

            // Get file size first (fast operation)
            let resources = try finalDestinationURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(resources.fileSize ?? 0)

            // Get audio duration with optimized timeout
            let durationSeconds = await withTaskGroup(of: Double?.self) { group in
                // Add duration loading task with timeout
                group.addTask {
                    do {
                        let asset = AVURLAsset(url: finalDestinationURL)
                        // Use optimized loading for better performance

                        print("🔍 Loading audio properties for: \(finalFilename)")
                        let duration = try await asset.load(.duration)
                        let seconds = duration.seconds
                        print("⏱️ Duration loaded: \(seconds) seconds")
                        return seconds.isFinite ? seconds : 0
                    } catch {
                        print("❌ Failed to load duration: \(error)")
                        return 0
                    }
                }

                // Reduced timeout for better UX
                group.addTask {
                    try? await Task.sleep(for: .seconds(3))
                    print("⚠️ Audio loading timeout reached for: \(finalFilename)")
                    return 0
                }

                // Return first completed task
                for await result in group {
                    group.cancelAll()
                    return result ?? 0
                }
                return 0
            }

            // Create AudioFile with calculated or default duration
            let audioFile = AudioFile(
                filename: finalFilename,
                duration: durationSeconds,
                fileSize: fileSize
            )

            print("✅ Imported audio: \(finalFilename) (Duration: \(durationSeconds)s)")
            return audioFile

        } catch {
            print("❌ Failed to import audio: \(error)")
            // Clean up partial file if copy succeeded but metadata failed
            try? FileManager.default.removeItem(at: finalDestinationURL)
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
        
        // Extract original filename or create a fallback using Content-Type hint
        let originalName = sourceURL.lastPathComponent.components(separatedBy: "?").first ?? ""
        let targetName: String
        let originalExt = URL(fileURLWithPath: originalName).pathExtension.lowercased()
        if !originalName.isEmpty, originalName != "/",
           ["mp3", "m4a", "wav", "aac", "flac"].contains(originalExt) {
            // URL has a recognizable audio extension – use it directly
            targetName = originalName
        } else {
            // Sniff Content-Type header to pick the right extension
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String ?? ""
            let ext: String
            if contentType.contains("mpeg") || contentType.contains("mp3") {
                ext = "mp3"
            } else if contentType.contains("m4a") || contentType.contains("mp4") {
                ext = "m4a"
            } else if contentType.contains("wav") {
                ext = "wav"
            } else if contentType.contains("aac") {
                ext = "aac"
            } else if contentType.contains("flac") {
                ext = "flac"
            } else {
                ext = "mp3" // safe fallback
            }
            let baseName = originalName.isEmpty || originalName == "/" ? "DownloadedAudio" : (originalName as NSString).deletingPathExtension
            targetName = "\(baseName).\(ext)"
        }
        
        // Generate final destination path
        let destinationURL = URL.documentsDirectory.appending(path: targetName)
        let finalDestinationURL = makeUniqueFileURL(destinationURL)
        let finalFilename = finalDestinationURL.lastPathComponent
        
        do {
            // Move downloaded temp file to documents directory
            try FileManager.default.moveItem(at: tempURL, to: finalDestinationURL)
            print("📁 File downloaded and saved to: \(finalDestinationURL.path)")
            
            // Get file size
            let resources = try finalDestinationURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(resources.fileSize ?? 0)
            
            // Get audio duration with timeout
            let durationSeconds = await withTaskGroup(of: Double?.self) { group in
                group.addTask {
                    do {
                        let asset = AVURLAsset(url: finalDestinationURL)
                        print("🔍 Loading audio properties for downloaded file: \(finalFilename)")
                        let duration = try await asset.load(.duration)
                        let seconds = duration.seconds
                        print("⏱️ Duration loaded: \(seconds) seconds")
                        return seconds.isFinite ? seconds : 0
                    } catch {
                        print("❌ Failed to load duration: \(error)")
                        return 0
                    }
                }
                
                group.addTask {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    print("⚠️ Audio loading timeout reached for downloaded file: \(finalFilename)")
                    return 0
                }
                
                if let result = await group.next() {
                    group.cancelAll()
                    return result ?? 0
                }
                return 0
            }
            
            let audioFile = AudioFile(
                filename: finalFilename,
                duration: durationSeconds,
                fileSize: fileSize
            )

            print("✅ Successfully downloaded audio: \(finalFilename) (Duration: \(durationSeconds)s)")
            return audioFile
            
        } catch {
            print("❌ Failed to move downloaded file to Library: \(error)")
            // Clean up files on error
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: finalDestinationURL)
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