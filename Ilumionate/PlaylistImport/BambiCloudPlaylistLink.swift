//
//  BambiCloudPlaylistLink.swift
//  Ilumionate
//
//  Personal-build compatibility for BambiCloud share links.
//

import Foundation

/// Converts a public BambiCloud playlist page into its JSON API address.
/// Validation is deliberately strict so the importer cannot be redirected to
/// an arbitrary host by a malformed share link.
nonisolated struct BambiCloudPlaylistLink: Equatable, Sendable {
    let playlistID: UUID
    let apiURL: URL

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              host == "bambicloud.com" || host == "www.bambicloud.com"
        else { return nil }

        let pathComponents = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard pathComponents.count == 2,
              pathComponents[0].lowercased() == "playlist",
              let playlistID = UUID(uuidString: pathComponents[1])
        else { return nil }

        var apiComponents = URLComponents()
        apiComponents.scheme = "https"
        apiComponents.host = "api.bambicloud.com"
        apiComponents.path = "/playlists"
        apiComponents.queryItems = [
            URLQueryItem(name: "uuid", value: playlistID.uuidString.lowercased())
        ]
        guard let apiURL = apiComponents.url else { return nil }

        self.playlistID = playlistID
        self.apiURL = apiURL
    }
}
