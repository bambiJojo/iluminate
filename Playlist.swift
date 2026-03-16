//
//  Playlist.swift
//  Ilumionate
//
//  Data model for playlists of audio files with light sessions
//

import Foundation

/// A playlist of audio files with their synchronized light sessions
struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var items: [PlaylistItem]
    var smartTransitions: Bool
    let createdDate: Date

    init(id: UUID = UUID(), name: String, items: [PlaylistItem] = [], smartTransitions: Bool = true, createdDate: Date = Date()) {
        self.id = id
        self.name = name
        self.items = items
        self.smartTransitions = smartTransitions
        self.createdDate = createdDate
    }

    // MARK: - Computed Properties

    var totalDuration: TimeInterval {
        items.reduce(0) { $0 + $1.duration }
    }

    var totalDurationFormatted: String {
        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var itemCount: Int { items.count }

    var isEmpty: Bool { items.isEmpty }
}

/// A single item in a playlist, referencing an audio file by ID
struct PlaylistItem: Identifiable, Codable {
    let id: UUID
    let audioFileId: UUID
    let filename: String
    let duration: TimeInterval

    init(id: UUID = UUID(), audioFileId: UUID, filename: String, duration: TimeInterval) {
        self.id = id
        self.audioFileId = audioFileId
        self.filename = filename
        self.duration = duration
    }

    var durationFormatted: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var displayName: String {
        filename
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".m4a", with: "")
            .replacingOccurrences(of: ".wav", with: "")
            .replacingOccurrences(of: ".aac", with: "")
    }
}

// MARK: - Playlist Storage

/// Manages loading and saving playlists to UserDefaults
struct PlaylistStore {
    private static let key = "playlists"

    static func load() -> [Playlist] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let playlists = try? JSONDecoder().decode([Playlist].self, from: data) else {
            return []
        }
        return playlists
    }

    static func save(_ playlists: [Playlist]) {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
