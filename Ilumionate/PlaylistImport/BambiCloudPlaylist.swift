//
//  BambiCloudPlaylist.swift
//  Ilumionate
//

import Foundation

/// The small, stable subset of a public BambiCloud playlist used for import.
nonisolated struct BambiCloudPlaylist: Decodable, Identifiable, Sendable {
    nonisolated struct Track: Decodable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let duration: TimeInterval
        let fileType: String?
        let trackNumber: Int?
        /// The publisher's own copy of the audio. Read so a track the user is
        /// missing can be fetched from source; never used to stream playback.
        let audioURL: URL?

        private enum CodingKeys: String, CodingKey {
            case id = "uuid"
            case name
            case durationMilliseconds = "duration"
            case fileType
            case trackNumber = "trackNum"
            case audioURL
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            let milliseconds = try container.decode(Double.self, forKey: .durationMilliseconds)
            duration = max(milliseconds / 1_000, 0)
            fileType = try container.decodeIfPresent(String.self, forKey: .fileType)
            trackNumber = try container.decodeIfPresent(Int.self, forKey: .trackNumber)
            audioURL = try container
                .decodeIfPresent(String.self, forKey: .audioURL)
                .flatMap(URL.init(string:))
        }
    }

    let id: UUID
    let name: String
    let description: String?
    let experienceLevel: String?
    let tracks: [Track]

    private enum CodingKeys: String, CodingKey {
        case id = "uuid"
        case name
        case description
        case experienceLevel = "expLevel"
        case tracks = "files"
    }

    static func decode(
        from data: Data,
        expectedID: UUID
    ) throws -> BambiCloudPlaylist {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw PlaylistLinkImportError.invalidResponse
        }

        guard let playlist = envelope.playlists.first(where: { $0.id == expectedID }) else {
            throw PlaylistLinkImportError.playlistNotFound
        }
        return playlist
    }

    private struct Envelope: Decodable {
        let playlists: [BambiCloudPlaylist]
    }
}
