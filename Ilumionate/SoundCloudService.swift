//
//  SoundCloudService.swift
//  Ilumionate
//
//  SoundCloud API integration for streaming audio content
//

import Foundation

@MainActor
@Observable
class SoundCloudService: StreamingService, Sendable {

    let name = "SoundCloud"
    var isAuthenticated = false

    private let clientId: String
    private let clientSecret: String
    private var accessToken: String?

    private let baseURL = "https://api.soundcloud.com"

    // MARK: - Configuration

    /// Initialize with your SoundCloud app credentials
    /// Register at: https://soundcloud.com/you/apps/new
    init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        loadStoredToken()
    }

    // MARK: - Authentication

    func authenticate() async throws {
        // For production, implement OAuth flow
        // For now, using client credentials flow for public content

        let url = URL(string: "\(baseURL)/oauth2/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "client_credentials",
            "client_id": clientId,
            "client_secret": clientSecret
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StreamingError.authenticationFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = tokenResponse.access_token
        isAuthenticated = true

        // Store token securely
        storeToken(tokenResponse.access_token)

        print("🎵 SoundCloud: Authentication successful")
    }

    // MARK: - Search

    func search(query: String) async throws -> [StreamingTrack] {
        guard let token = accessToken else {
            throw StreamingError.notAuthenticated
        }

        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "\(baseURL)/tracks?q=\(encodedQuery)&limit=20&access_token=\(token)"

        guard let url = URL(string: urlString) else {
            throw StreamingError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let tracks = try JSONDecoder().decode([SoundCloudTrack].self, from: data)

        return tracks.compactMap { track in
            guard track.streamable,
                  let streamURL = track.stream_url else { return nil }

            return StreamingTrack(
                id: String(track.id),
                title: track.title,
                artist: track.user.username,
                duration: TimeInterval(track.duration / 1000), // Convert from ms
                artworkURL: track.artwork_url.flatMap(URL.init),
                streamURL: URL(string: "\(streamURL)?client_id=\(clientId)"),
                service: .soundcloud
            )
        }
    }

    // MARK: - Playlists

    func getPlaylists() async throws -> [StreamingPlaylist] {
        guard let token = accessToken else {
            throw StreamingError.notAuthenticated
        }

        // Get user's playlists - requires user authentication
        let urlString = "\(baseURL)/me/playlists?access_token=\(token)"
        guard let url = URL(string: urlString) else {
            throw StreamingError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let playlists = try JSONDecoder().decode([SoundCloudPlaylist].self, from: data)

        return playlists.map { playlist in
            StreamingPlaylist(
                id: String(playlist.id),
                name: playlist.title,
                trackCount: playlist.track_count,
                artworkURL: playlist.artwork_url.flatMap(URL.init),
                service: .soundcloud
            )
        }
    }

    // MARK: - Streaming

    func streamTrack(_ track: StreamingTrack) async throws -> StreamingSession {
        guard let streamURL = track.streamURL else {
            throw StreamingError.invalidTrack
        }

        // SoundCloud streams expire after some time
        let expiresAt = Date().addingTimeInterval(3600) // 1 hour

        return StreamingSession(
            track: track,
            audioURL: streamURL,
            expiresAt: expiresAt
        )
    }

    // MARK: - Token Management

    private func loadStoredToken() {
        if let token = UserDefaults.standard.string(forKey: "SoundCloud_AccessToken") {
            accessToken = token
            isAuthenticated = true
        }
    }

    private func storeToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: "SoundCloud_AccessToken")
    }

    // MARK: - Search Suggestions

    func getPopularTracks() async throws -> [StreamingTrack] {
        return try await search(query: "meditation ambient therapy")
    }

    func getMeditationTracks() async throws -> [StreamingTrack] {
        return try await search(query: "meditation mindfulness relaxation")
    }

    func getHypnosisTracks() async throws -> [StreamingTrack] {
        return try await search(query: "hypnosis guided sleep")
    }
}

// MARK: - Data Models

private struct TokenResponse: Codable {
    let access_token: String
    let token_type: String
}

private struct SoundCloudTrack: Codable {
    let id: Int
    let title: String
    let duration: Int // in milliseconds
    let streamable: Bool
    let stream_url: String?
    let artwork_url: String?
    let user: SoundCloudUser
}

private struct SoundCloudUser: Codable {
    let id: Int
    let username: String
}

private struct SoundCloudPlaylist: Codable {
    let id: Int
    let title: String
    let track_count: Int
    let artwork_url: String?
}

// MARK: - Errors

enum StreamingError: LocalizedError {
    case notAuthenticated
    case authenticationFailed
    case invalidURL
    case invalidTrack
    case networkError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to access streaming content"
        case .authenticationFailed:
            return "Failed to authenticate with streaming service"
        case .invalidURL:
            return "Invalid URL"
        case .invalidTrack:
            return "Track is not available for streaming"
        case .networkError:
            return "Network error occurred"
        }
    }
}