//
//  SourcePlaylist.swift
//  Ilumionate
//
//  A playlist as described by an external source, before it becomes a local
//  `Playlist`. Deliberately carries no notion of *which* source: the importer
//  recognises playlist shapes and formats, never hosts.
//

import Foundation

/// One track described by an external playlist source.
///
/// Everything except the title is optional, because the formats this is decoded
/// from disagree about what they publish. A track the user already owns is
/// matched by title and duration, so those two carry the weight.
nonisolated struct SourcePlaylistTrack: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// Seconds. Zero when the source did not say.
    let duration: TimeInterval
    /// Position within the playlist, zero-based.
    let trackNumber: Int
    /// The publisher's own copy, when it offers one. Used to fetch a track the
    /// user is missing; never used to stream playback.
    let audioURL: URL?

    init(
        id: String? = nil,
        title: String,
        duration: TimeInterval = 0,
        trackNumber: Int,
        audioURL: URL? = nil
    ) {
        self.id = id ?? "\(trackNumber)-\(title)"
        self.title = title
        self.duration = max(duration, 0)
        self.trackNumber = trackNumber
        self.audioURL = audioURL
    }
}

/// A playlist described by an external source.
nonisolated struct SourcePlaylist: Equatable, Sendable {
    let title: String
    let summary: String?
    let tracks: [SourcePlaylistTrack]

    /// Total runtime of everything the source described.
    var duration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    init(title: String, summary: String? = nil, tracks: [SourcePlaylistTrack]) {
        self.title = title
        self.summary = summary
        self.tracks = tracks
    }
}

/// Why a user-supplied playlist link could not be turned into a playlist.
///
/// These are shown to the user, so each one has to say what *they* can do about
/// it. "Unsupported" in particular has to explain the data-URL requirement,
/// because pasting a web page is the most likely mistake.
nonisolated enum PlaylistSourceError: LocalizedError, Equatable, Sendable {
    /// The link was not a usable `http`/`https` URL.
    case invalidLink
    /// The response could not be parsed as any playlist format.
    case invalidResponse
    /// The response parsed, but described no tracks.
    case noTracks
    /// The response was a web page rather than playlist data.
    case looksLikeAWebPage

    var errorDescription: String? { failureReason }

    var failureReason: String {
        switch self {
        case .invalidLink:
            "That does not look like a web address. Playlist links must start with https."
        case .invalidResponse:
            "That link did not return a playlist LumeSync can read. It supports M3U, PLS, RSS and JSON playlists."
        case .noTracks:
            "That playlist did not list any tracks."
        case .looksLikeAWebPage:
            "That link is a web page, not playlist data. Paste the playlist's file or feed address instead."
        }
    }
}
