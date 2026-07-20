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
    var wholeSessionAnalysis: PlaylistWholeSessionAnalysis?
    let createdDate: Date
    /// Optional so playlists saved before artwork selection existed still decode.
    var artworkStyle: PlaylistArtworkStyle?

    init(
        id: UUID = UUID(),
        name: String,
        items: [PlaylistItem] = [],
        smartTransitions: Bool = true,
        wholeSessionAnalysis: PlaylistWholeSessionAnalysis? = nil,
        createdDate: Date = Date(),
        artworkStyle: PlaylistArtworkStyle? = nil
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.smartTransitions = smartTransitions
        self.wholeSessionAnalysis = wholeSessionAnalysis
        self.createdDate = createdDate
        self.artworkStyle = artworkStyle
    }

    /// The artwork to render — falls back to the content-derived mosaic.
    var artwork: PlaylistArtworkStyle {
        artworkStyle ?? .automatic
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

    var sourceSignature: String {
        items.map { item in
            "\(item.audioFileId.uuidString):\(Int(item.duration.rounded()))"
        }
        .joined(separator: "|")
    }

    var hasCurrentWholeSessionAnalysis: Bool {
        wholeSessionAnalysis?.isCurrent(for: self) == true
    }
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

// MARK: - Playlist Whole-Session Analysis

enum PlaylistSessionRole: String, Codable, Sendable, CaseIterable {
    case induction
    case deepening
    case suggestions
    case emergence
    case support

    var displayName: String {
        switch self {
        case .induction: return "Induction"
        case .deepening: return "Deepening"
        case .suggestions: return "Suggestions"
        case .emergence: return "Awakener"
        case .support: return "Support"
        }
    }
}

struct PlaylistWholeSessionPhaseSummary: Identifiable, Codable, Sendable {
    let id: UUID
    let phase: HypnosisMetadata.Phase
    let role: PlaylistSessionRole
    let startTime: TimeInterval
    let endTime: TimeInterval

    init(
        id: UUID = UUID(),
        phase: HypnosisMetadata.Phase,
        role: PlaylistSessionRole,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) {
        self.id = id
        self.phase = phase
        self.role = role
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct PlaylistWholeSessionAnalysis: Codable, Sendable {
    let generatedAt: Date
    let sourceSignature: String
    let duration: TimeInterval
    let trackCount: Int
    let contentType: AudioContentType
    let phases: [PlaylistWholeSessionPhaseSummary]
    let warnings: [String]

    func isCurrent(for playlist: Playlist) -> Bool {
        sourceSignature == playlist.sourceSignature
    }

    var phaseSummary: String {
        let labels = phases.map { $0.phase.displayName }
        let uniqueLabels = labels.reduce(into: [String]()) { result, label in
            if result.last != label {
                result.append(label)
            }
        }
        return uniqueLabels.joined(separator: " -> ")
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
