//
//  PlaylistSourceURL.swift
//  Ilumionate
//
//  Validates a pasted playlist link.
//
//  There is no host allowlist here, deliberately: the user chooses the service.
//  What is enforced is that the link is a web address at all, so a pasted
//  `javascript:` or `file:` string can never reach the fetcher.
//

import Foundation

nonisolated enum PlaylistSourceURL {

    /// A pasted link, trimmed and given a scheme if it lacks one.
    ///
    /// Bare hosts are assumed `https` rather than refused: people paste
    /// addresses without a scheme constantly, and defaulting to the secure one
    /// is both kinder and safer than defaulting to `http`.
    static func normalized(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlaylistSourceError.invalidLink }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              !host.isEmpty,
              // A host with no dot and no port is a typo, not an address.
              host.contains("."),
              let url = components.url
        else {
            throw PlaylistSourceError.invalidLink
        }

        return url
    }
}
