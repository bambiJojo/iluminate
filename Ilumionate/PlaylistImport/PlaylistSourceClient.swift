//
//  PlaylistSourceClient.swift
//  Ilumionate
//
//  Fetches a user-supplied playlist link and hands the bytes to format
//  detection. Knows nothing about any particular service.
//

import Foundation

nonisolated struct PlaylistSourceClient: Sendable {

    /// A playlist and the address it was actually read from — which is not
    /// always the address the user pasted, because a page may point at its feed.
    /// Downloading is restricted relative to this, so it has to be the resolved
    /// one.
    struct Result: Sendable {
        let playlist: SourcePlaylist
        let sourceURL: URL
    }

    typealias Fetch = @Sendable (URL) async throws -> (Data, URLResponse)

    private let fetch: Fetch

    init(session: URLSession = .shared) {
        fetch = { try await session.data(from: $0) }
    }

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    func playlist(at rawLink: String) async throws -> Result {
        try await playlist(at: PlaylistSourceURL.normalized(rawLink))
    }

    func playlist(at url: URL) async throws -> Result {
        let (data, contentType) = try await load(url)

        do {
            let playlist = try PlaylistSourceDocument.playlist(from: data, contentType: contentType)
            return Result(playlist: playlist, sourceURL: url)
        } catch PlaylistSourceError.looksLikeAWebPage {
            // A page is not necessarily a dead end: the feed-autodiscovery link
            // is a web standard, so honour it before giving up. Exactly one hop
            // — following a chain would let a page walk the app around the web.
            guard let feedURL = Self.advertisedFeed(in: data, relativeTo: url) else {
                throw PlaylistSourceError.looksLikeAWebPage
            }
            let (feedData, feedContentType) = try await load(feedURL)
            let playlist = try PlaylistSourceDocument.playlist(
                from: feedData,
                contentType: feedContentType
            )
            return Result(playlist: playlist, sourceURL: feedURL)
        }
    }

    private func load(_ url: URL) async throws -> (Data, String?) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await fetch(url)
        } catch {
            throw PlaylistSourceError.invalidResponse
        }

        if let http = response as? HTTPURLResponse {
            guard (200...299).contains(http.statusCode) else {
                throw PlaylistSourceError.invalidResponse
            }
            return (data, http.value(forHTTPHeaderField: "Content-Type"))
        }
        return (data, nil)
    }

    // MARK: - Feed autodiscovery

    /// `<link rel="alternate" type="application/rss+xml" href="…">` and its
    /// Atom and JSON-feed equivalents.
    static func advertisedFeed(in data: Data, relativeTo base: URL) -> URL? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        let feedTypes = [
            "application/rss+xml",
            "application/atom+xml",
            "application/feed+json",
            "application/json",
        ]

        for tag in linkTags(in: html) {
            let lowered = tag.lowercased()
            guard lowered.contains("rel=\"alternate\"") || lowered.contains("rel='alternate'")
                    || lowered.contains("rel=alternate") else { continue }
            guard feedTypes.contains(where: { lowered.contains($0) }) else { continue }
            guard let href = attribute("href", in: tag) else { continue }
            if let resolved = URL(string: href, relativeTo: base)?.absoluteURL,
               let scheme = resolved.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                return resolved
            }
        }
        return nil
    }

    private static func linkTags(in html: String) -> [String] {
        var tags: [String] = []
        var remainder = Substring(html)

        while let start = remainder.range(of: "<link", options: .caseInsensitive) {
            let afterStart = remainder[start.lowerBound...]
            guard let end = afterStart.firstIndex(of: ">") else { break }
            tags.append(String(afterStart[..<end]))
            remainder = afterStart[afterStart.index(after: end)...]
        }
        return tags
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        for quote in ["\"", "'"] {
            let needle = "\(name)=\(quote)"
            guard let range = tag.range(of: needle, options: .caseInsensitive) else { continue }
            let rest = tag[range.upperBound...]
            guard let end = rest.firstIndex(of: Character(quote)) else { continue }
            let value = String(rest[..<end]).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }
}
