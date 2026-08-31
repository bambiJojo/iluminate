//
//  PlaylistSourceDocument.swift
//  Ilumionate
//
//  Turns whatever a user-supplied playlist link returned into a `SourcePlaylist`.
//
//  Dispatch is on the *bytes*, never on the address. That is the whole point:
//  the user chooses the service, and the app only has to recognise the open
//  formats those services publish — M3U, PLS, RSS, and conventional JSON.
//

import Foundation

nonisolated enum PlaylistSourceDocument {

    static func playlist(from data: Data, contentType: String?) throws -> SourcePlaylist {
        guard !data.isEmpty else { throw PlaylistSourceError.invalidResponse }

        // JSON is checked by content rather than by header: plenty of servers
        // send playlist JSON as text/plain or application/octet-stream.
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("#EXTM3U") || trimmed.hasPrefix("#EXTINF") {
                return try m3u(trimmed)
            }
            if trimmed.lowercased().hasPrefix("[playlist]") {
                return try pls(trimmed)
            }
            if isHTML(trimmed, contentType: contentType) {
                throw PlaylistSourceError.looksLikeAWebPage
            }
            if trimmed.hasPrefix("<") {
                return try feed(data)
            }
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                return try GenericPlaylistJSON.playlist(from: data)
            }
        }

        throw PlaylistSourceError.invalidResponse
    }

    private static func isHTML(_ text: String, contentType: String?) -> Bool {
        if let contentType, contentType.lowercased().contains("text/html") { return true }
        let head = text.prefix(512).lowercased()
        return head.hasPrefix("<!doctype html") || head.hasPrefix("<html")
    }

    // MARK: - M3U / M3U8

    /// `#EXTINF:<seconds>,<title>` followed by the address. A bare address with
    /// no preceding directive is still a track; the filename becomes its title.
    private static func m3u(_ text: String) throws -> SourcePlaylist {
        var title: String?
        var pendingName: String?
        var pendingDuration: TimeInterval = 0
        var tracks: [SourcePlaylistTrack] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#PLAYLIST:") {
                title = String(line.dropFirst("#PLAYLIST:".count))
                    .trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("#EXTINF:") {
                let payload = line.dropFirst("#EXTINF:".count)
                let parts = payload.split(separator: ",", maxSplits: 1)
                // A negative or absent length means "unknown", not "zero-length".
                let seconds = parts.first.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                pendingDuration = max(seconds ?? 0, 0)
                pendingName = parts.count > 1
                    ? String(parts[1]).trimmingCharacters(in: .whitespaces)
                    : nil
                continue
            }
            if line.hasPrefix("#") { continue }

            let url = webURL(line)
            tracks.append(
                SourcePlaylistTrack(
                    title: pendingName ?? fallbackTitle(for: line),
                    duration: pendingDuration,
                    trackNumber: tracks.count,
                    audioURL: url
                )
            )
            pendingName = nil
            pendingDuration = 0
        }

        guard !tracks.isEmpty else { throw PlaylistSourceError.noTracks }
        return SourcePlaylist(title: title ?? "Imported Playlist", tracks: tracks)
    }

    // MARK: - PLS

    /// `FileN` / `TitleN` / `LengthN`, keyed by N rather than by line order —
    /// the entries are not required to appear in sequence.
    private static func pls(_ text: String) throws -> SourcePlaylist {
        var files: [Int: String] = [:]
        var titles: [Int: String] = [:]
        var lengths: [Int: Double] = [:]
        var title: String?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }

            if key == "playlistname" { title = value; continue }

            for (prefix, store) in [("file", 0), ("title", 1), ("length", 2)] {
                guard key.hasPrefix(prefix), let index = Int(key.dropFirst(prefix.count)) else {
                    continue
                }
                switch store {
                case 0: files[index] = value
                case 1: titles[index] = value
                default: lengths[index] = max(Double(value) ?? 0, 0)
                }
            }
        }

        let indices = Set(files.keys).union(titles.keys).sorted()
        let tracks = indices.enumerated().compactMap { position, index -> SourcePlaylistTrack? in
            let name = titles[index] ?? files[index].map(fallbackTitle(for:))
            guard let name, !name.isEmpty else { return nil }
            return SourcePlaylistTrack(
                title: name,
                duration: lengths[index] ?? 0,
                trackNumber: position,
                audioURL: files[index].flatMap(webURL)
            )
        }

        guard !tracks.isEmpty else { throw PlaylistSourceError.noTracks }
        return SourcePlaylist(title: title ?? "Imported Playlist", tracks: tracks)
    }

    // MARK: - RSS / Atom

    private static func feed(_ data: Data) throws -> SourcePlaylist {
        let parser = FeedParser()
        guard let playlist = parser.parse(data) else {
            throw PlaylistSourceError.invalidResponse
        }
        guard !playlist.tracks.isEmpty else { throw PlaylistSourceError.noTracks }
        return playlist
    }

    // MARK: - Shared

    private static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// A readable name for a track the source did not title.
    private static func fallbackTitle(for reference: String) -> String {
        let name = (URL(string: reference)?.lastPathComponent ?? reference)
        let stem = (name as NSString).deletingPathExtension
        let cleaned = stem
            .replacing("_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? reference : cleaned
    }
}

/// Minimal RSS/Atom reader: channel title, then one track per item that carries
/// an audio enclosure or link.
private nonisolated final class FeedParser: NSObject, XMLParserDelegate {
    private var playlistTitle: String?
    private var tracks: [SourcePlaylistTrack] = []

    private var elementPath: [String] = []
    private var text = ""
    private var itemTitle: String?
    private var itemURL: URL?
    private var itemDuration: TimeInterval = 0
    private var insideItem = false

    func parse(_ data: Data) -> SourcePlaylist? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return SourcePlaylist(title: playlistTitle ?? "Imported Playlist", tracks: tracks)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let name = elementName.lowercased()
        elementPath.append(name)
        text = ""

        if name == "item" || name == "entry" {
            insideItem = true
            itemTitle = nil
            itemURL = nil
            itemDuration = 0
        }

        if insideItem, name == "enclosure" || name == "link" {
            let address = attributes["url"] ?? attributes["href"]
            let type = attributes["type"]?.lowercased() ?? ""
            let isAudio = type.isEmpty || type.hasPrefix("audio")
            if isAudio, let address, let url = URL(string: address), itemURL == nil {
                itemURL = url
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            if !elementPath.isEmpty { elementPath.removeLast() }
            text = ""
        }

        if name == "title" {
            if insideItem {
                itemTitle = value.isEmpty ? itemTitle : value
            } else if playlistTitle == nil, !value.isEmpty {
                playlistTitle = value
            }
            return
        }

        if insideItem, name.hasSuffix("duration"), !value.isEmpty {
            itemDuration = Self.seconds(from: value)
            return
        }

        if name == "item" || name == "entry" {
            insideItem = false
            guard let itemTitle, !itemTitle.isEmpty else { return }
            tracks.append(
                SourcePlaylistTrack(
                    title: itemTitle,
                    duration: itemDuration,
                    trackNumber: tracks.count,
                    audioURL: itemURL
                )
            )
        }
    }

    /// `itunes:duration` is either plain seconds or `HH:MM:SS`.
    private static func seconds(from value: String) -> TimeInterval {
        if let plain = Double(value) { return max(plain, 0) }
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return 0 }
        return max(parts.reduce(0) { $0 * 60 + $1 }, 0)
    }
}
