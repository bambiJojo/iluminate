//
//  BambiCloudPlaylistLink.swift
//  Ilumionate
//

import Foundation

/// A validated public BambiCloud playlist link.
///
/// Validation is deliberately strict so a pasted link can never redirect the
/// importer to an arbitrary host.
nonisolated struct BambiCloudPlaylistLink: Equatable, Sendable {
    let playlistID: UUID
    let apiURL: URL

    init(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased() else {
            throw PlaylistLinkImportError.invalidLink
        }

        guard host == "bambicloud.com" || host == "www.bambicloud.com" else {
            throw PlaylistLinkImportError.unsupportedLink
        }

        let pathComponents = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard pathComponents.count == 2,
              pathComponents[0].lowercased() == "playlist",
              let playlistID = UUID(uuidString: pathComponents[1]) else {
            throw PlaylistLinkImportError.invalidLink
        }

        var apiComponents = URLComponents()
        apiComponents.scheme = "https"
        apiComponents.host = "api.bambicloud.com"
        apiComponents.path = "/playlists"
        apiComponents.queryItems = [
            URLQueryItem(
                name: "uuid",
                value: playlistID.uuidString.lowercased()
            )
        ]
        guard let apiURL = apiComponents.url else {
            throw PlaylistLinkImportError.invalidLink
        }

        self.playlistID = playlistID
        self.apiURL = apiURL
    }
}
