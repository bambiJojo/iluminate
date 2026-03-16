//
//  StreamingManager.swift
//  Ilumionate
//
//  Centralized management for all streaming services
//

import Foundation
import SwiftUI

@MainActor
@Observable
class StreamingManager {

    // MARK: - Services

    var soundCloudService: SoundCloudService?

    var availableServices: [any StreamingService] {
        var services: [any StreamingService] = []
        if let soundCloud = soundCloudService { services.append(soundCloud) }
        return services
    }

    // MARK: - State

    var isLoading = false
    var searchResults: [StreamingTrack] = []
    var featuredPlaylists: [StreamingPlaylist] = []
    var errorMessage: String?

    // Enhanced analysis
    private let streamingAnalyzer = StreamingAnalyzer()
    var isAnalyzing: Bool { streamingAnalyzer.isAnalyzing }
    var analysisProgress: Double { streamingAnalyzer.progress }
    var analysisStatus: String { streamingAnalyzer.statusMessage }

    // MARK: - Configuration

    func configure(soundCloudClientId: String? = nil, soundCloudSecret: String? = nil) {

        if let scId = soundCloudClientId, let scSecret = soundCloudSecret {
            soundCloudService = SoundCloudService(clientId: scId, clientSecret: scSecret)
        }

        print("🎵 StreamingManager: Configured SoundCloud service")
    }

    // MARK: - Authentication

    func authenticateAll() async {
        isLoading = true
        errorMessage = nil

        await withTaskGroup(of: Void.self) { group in
            for service in availableServices {
                group.addTask {
                    do {
                        try await service.authenticate()
                        await MainActor.run {
                            print("🎵 \(service.name): Authenticated successfully")
                        }
                    } catch {
                        await MainActor.run {
                            print("🎵 \(service.name): Authentication failed - \(error)")
                            self.errorMessage = "Failed to connect to \(service.name)"
                        }
                    }
                }
            }
        }

        isLoading = false
    }

    // MARK: - Search

    func search(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isLoading = true
        errorMessage = nil
        var allResults: [StreamingTrack] = []

        await withTaskGroup(of: [StreamingTrack].self) { group in
            for service in availableServices where service.isAuthenticated {
                group.addTask {
                    do {
                        return try await service.search(query: query)
                    } catch {
                        await MainActor.run {
                            print("🎵 \(service.name): Search failed - \(error)")
                        }
                        return []
                    }
                }
            }

            for await results in group {
                allResults.append(contentsOf: results)
            }
        }

        searchResults = allResults.sorted { $0.service.displayName < $1.service.displayName }
        isLoading = false
    }

    // MARK: - Curated Content

    func loadFeaturedContent() async {
        isLoading = true
        var playlists: [StreamingPlaylist] = []

        await withTaskGroup(of: [StreamingPlaylist].self) { group in
            for service in availableServices where service.isAuthenticated {
                group.addTask {
                    do {
                        return try await service.getPlaylists()
                    } catch {
                        await MainActor.run {
                            print("🎵 \(service.name): Failed to load playlists - \(error)")
                        }
                        return []
                    }
                }
            }

            for await serviceePlaylists in group {
                playlists.append(contentsOf: serviceePlaylists)
            }
        }

        featuredPlaylists = playlists
        isLoading = false
    }

    // MARK: - Enhanced Integration with Audio System

    func createAudioFileFromTrack(_ track: StreamingTrack) -> AudioFile {
        return AudioFile(streamingTrack: track)
    }

    /// Analyze streaming track and generate optimized light session
    func analyzeAndCreateSession(for track: StreamingTrack) async throws -> (AudioFile, LightSession) {
        print("🎵 Starting enhanced analysis for: \(track.displayName)")

        // Generate optimized light session using streaming analyzer
        let session = try await streamingAnalyzer.analyzeAndGenerateSession(for: track)

        // Create audio file with analysis results
        var audioFile = AudioFile(streamingTrack: track)

        // Store the analysis for future use - this will be replaced by actual session analysis
        let analysis = AnalysisResult(
            mood: .meditative,
            energyLevel: 0.6,
            suggestedFrequencyRange: 4.0...14.0,
            suggestedIntensity: 0.8,
            suggestedColorTemperature: nil,
            keyMoments: [],
            aiSummary: "Streaming content with enhanced analysis",
            recommendedPreset: inferContentType(from: track).rawValue,
            contentType: inferContentType(from: track)
        )
        audioFile.analysisResult = analysis

        return (audioFile, session)
    }

    // MARK: - Wellness Content Discovery

    func searchWellnessContent() async {
        await search("meditation relaxation ambient therapy mindfulness")
    }

    func searchHypnosisContent() async {
        await search("hypnosis guided sleep therapy")
    }

    func searchFocusContent() async {
        await search("focus concentration study ambient")
    }

    // MARK: - Service-specific actions

    func getMeditationTracks() async -> [StreamingTrack] {
        guard let soundCloud = soundCloudService else { return [] }
        do {
            return try await soundCloud.getMeditationTracks()
        } catch {
            print("Failed to get meditation tracks: \(error)")
            return []
        }
    }

    func getWellnessPlaylists() async -> [StreamingPlaylist] {
        // SoundCloud doesn't have specific wellness playlists API
        // but we can search for wellness content
        await search("wellness meditation relaxation therapy")
        return [] // Return empty for now as we focus on search
    }

    // MARK: - Helper Functions for Analysis

    private func inferContentType(from track: StreamingTrack) -> AnalysisResult.ContentType {
        let title = track.title.lowercased()

        if title.contains("hypnosis") || title.contains("trance") { return .hypnosis }
        if title.contains("meditation") || title.contains("mindfulness") { return .meditation }
        if title.contains("guided") || title.contains("visualization") { return .guidedImagery }
        if title.contains("affirmation") || title.contains("positive") { return .affirmations }

        return .music
    }

    private func extractKeywords(from track: StreamingTrack) -> [String] {
        let text = "\(track.title) \(track.artist)".lowercased()
        let keywords = ["relaxation", "calm", "peace", "sleep", "focus", "energy", "meditation", "mindfulness", "healing", "therapy"]
        return keywords.filter { text.contains($0) }
    }
}

// MARK: - AudioFile Extension

extension AudioFile {
    init(streamingTrack: StreamingTrack) {
        self.init(
            filename: "\(streamingTrack.displayName).\(streamingTrack.service.rawValue)",
            duration: streamingTrack.duration,
            fileSize: 0
        )
        self.creator = streamingTrack.artist
        self.streamingTrack = streamingTrack
    }

    // Add streaming track property
    var streamingTrack: StreamingTrack? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "StreamingTrack_\(id.uuidString)"),
                  let track = try? JSONDecoder().decode(StreamingTrack.self, from: data) else {
                return nil
            }
            return track
        }
        set {
            if let track = newValue {
                let data = try? JSONEncoder().encode(track)
                UserDefaults.standard.set(data, forKey: "StreamingTrack_\(id.uuidString)")
            } else {
                UserDefaults.standard.removeObject(forKey: "StreamingTrack_\(id.uuidString)")
            }
        }
    }
}