//
//  StreamingService.swift
//  Ilumionate
//
//  Streaming service integration for SoundCloud
//

import Foundation
import SwiftUI

// MARK: - Streaming Service Protocol

protocol StreamingService {
    var name: String { get }
    var isAuthenticated: Bool { get }

    func authenticate() async throws
    func search(query: String) async throws -> [StreamingTrack]
    func getPlaylists() async throws -> [StreamingPlaylist]
    func streamTrack(_ track: StreamingTrack) async throws -> StreamingSession
}

// MARK: - Data Models

struct StreamingTrack: Identifiable, Codable {
    let id: String
    let title: String
    let artist: String
    let duration: TimeInterval
    let artworkURL: URL?
    let streamURL: URL?
    let service: StreamingServiceType

    var displayName: String {
        artist.isEmpty ? title : "\(artist) - \(title)"
    }

    var durationFormatted: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct StreamingPlaylist: Identifiable, Codable {
    let id: String
    let name: String
    let trackCount: Int
    let artworkURL: URL?
    let service: StreamingServiceType
}

struct StreamingSession {
    let track: StreamingTrack
    let audioURL: URL
    let expiresAt: Date
}

enum StreamingServiceType: String, CaseIterable, Codable {
    case soundcloud = "soundcloud"

    var displayName: String {
        switch self {
        case .soundcloud: return "SoundCloud"
        }
    }

    var color: Color {
        switch self {
        case .soundcloud: return Color(hex: "FF5500")
        }
    }

    var icon: String {
        switch self {
        case .soundcloud: return "cloud.fill"
        }
    }
}

