//
//  GenericPlaylistJSON.swift
//  Ilumionate
//
//  Decodes a JSON playlist by recognising its *shape*, not its origin.
//
//  There is no universal JSON playlist standard, but published playlists agree
//  far more than they differ: a titled object holding an array of titled tracks
//  with durations. Matching that agreement — rather than one service's schema —
//  is what lets the user paste any playlist link without the app shipping
//  knowledge of a particular website.
//

import Foundation

nonisolated enum GenericPlaylistJSON {

    /// Keys under which a document may nest the playlist itself.
    private static let collectionKeys = ["playlists", "items", "data", "results", "entries"]
    /// Keys under which a playlist may hold its tracks.
    private static let trackArrayKeys = ["files", "tracks", "items", "entries"]
    private static let titleKeys = ["name", "title"]
    private static let summaryKeys = ["description", "summary"]
    private static let durationKeys = ["duration", "length"]
    private static let trackNumberKeys = ["trackNum", "track", "position", "index"]
    private static let audioURLKeys = ["audioURL", "url", "src", "file", "enclosure"]
    private static let identifierKeys = ["uuid", "id"]

    /// A duration at or above this, read as seconds, is longer than any
    /// plausible single recording — so the source meant milliseconds.
    /// Four hours in seconds; four hours in milliseconds is 14.4 million, well
    /// clear of anything a real track reports.
    private static let millisecondThreshold: Double = 14_400

    // MARK: - Entry point

    static func playlist(from data: Data) throws -> SourcePlaylist {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw PlaylistSourceError.invalidResponse
        }

        guard let object = playlistObject(in: root) else {
            throw PlaylistSourceError.invalidResponse
        }

        let tracks = self.tracks(in: object)
        guard !tracks.isEmpty else { throw PlaylistSourceError.noTracks }

        return SourcePlaylist(
            title: string(in: object, forAnyOf: titleKeys) ?? "Imported Playlist",
            summary: string(in: object, forAnyOf: summaryKeys),
            tracks: tracks
        )
    }

    // MARK: - Locating the playlist

    /// The object that describes the playlist, whether it is the document root
    /// or nested inside a collection.
    private static func playlistObject(in root: Any) -> [String: Any]? {
        if let object = root as? [String: Any] {
            // The root is the playlist when its track array holds leaf tracks.
            // When those elements *themselves* hold track arrays, the key was a
            // collection of playlists — `entries` is legitimately used for both.
            if let candidates = trackArray(in: object),
               !candidates.contains(where: { trackArray(in: $0) != nil }) {
                return object
            }

            for key in collectionKeys {
                if let nested = object[key] as? [Any],
                   let found = firstPlaylist(in: nested) {
                    return found
                }
            }
            return nil
        }

        if let array = root as? [Any] {
            return firstPlaylist(in: array)
        }

        return nil
    }

    private static func firstPlaylist(in array: [Any]) -> [String: Any]? {
        let objects = array.compactMap { $0 as? [String: Any] }
        return objects.first { trackArray(in: $0) != nil } ?? objects.first
    }

    private static func trackArray(in object: [String: Any]) -> [[String: Any]]? {
        for key in trackArrayKeys {
            if let array = object[key] as? [Any] {
                let objects = array.compactMap { $0 as? [String: Any] }
                if !objects.isEmpty { return objects }
            }
        }
        return nil
    }

    // MARK: - Tracks

    private static func tracks(in playlist: [String: Any]) -> [SourcePlaylistTrack] {
        guard let raw = trackArray(in: playlist) else { return [] }

        // A row with no title cannot be matched against the library or shown in
        // review, so it is dropped rather than imported blank.
        let titled = raw.compactMap { element -> ([String: Any], String)? in
            guard let title = string(in: element, forAnyOf: titleKeys) else { return nil }
            return (element, title)
        }

        let declared = titled.map { number(in: $0.0, forAnyOf: trackNumberKeys) }
        let hasDeclaredOrder = declared.allSatisfy { $0 != nil }

        let tracks = titled.enumerated().map { index, entry in
            let (element, title) = entry
            return SourcePlaylistTrack(
                id: string(in: element, forAnyOf: identifierKeys),
                title: title,
                duration: duration(in: element),
                trackNumber: hasDeclaredOrder ? (declared[index] ?? index) : index,
                audioURL: url(in: element, forAnyOf: audioURLKeys)
            )
        }

        return hasDeclaredOrder
            ? tracks.sorted { $0.trackNumber < $1.trackNumber }
            : tracks
    }

    // MARK: - Field readers

    /// Durations arrive in seconds or milliseconds with nothing to say which.
    /// The magnitude is the only available signal, and it is unambiguous in
    /// practice — see `millisecondThreshold`.
    private static func duration(in element: [String: Any]) -> TimeInterval {
        guard let raw = number(asDouble: element, forAnyOf: durationKeys), raw > 0 else {
            return 0
        }
        return raw >= millisecondThreshold ? raw / 1_000 : raw
    }

    private static func string(in object: [String: Any], forAnyOf keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func number(in object: [String: Any], forAnyOf keys: [String]) -> Int? {
        number(asDouble: object, forAnyOf: keys).map(Int.init)
    }

    private static func number(asDouble object: [String: Any], forAnyOf keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? Double { return value }
            if let value = object[key] as? Int { return Double(value) }
            if let value = object[key] as? String, let parsed = Double(value) { return parsed }
        }
        return nil
    }

    private static func url(in object: [String: Any], forAnyOf keys: [String]) -> URL? {
        for key in keys {
            // An RSS-style `enclosure` is an object wrapping the address.
            if let nested = object[key] as? [String: Any],
               let found = url(in: nested, forAnyOf: ["url", "href", "src"]) {
                return found
            }
            guard let value = string(in: object, forAnyOf: [key]),
                  let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { continue }
            return url
        }
        return nil
    }
}
