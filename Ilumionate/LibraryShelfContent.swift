//
//  LibraryShelfContent.swift
//  Ilumionate
//
//  Pure derivation of the Library tab's shelf contents from stored data.
//  Kept UI-free so shelf ordering, filtering, and caps stay unit-testable.
//

import Foundation

nonisolated enum LibraryShelfContent {

    /// Maximum cards a shelf shows; the full set lives behind "See all"
    /// or the Audio Files list.
    static let shelfCap = 10

    /// Played files, most recently played first.
    static func recents(from files: [AudioFile]) -> [AudioFile] {
        Array(
            files
                .filter { $0.lastPlayedDate != nil }
                .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
                .prefix(shelfCap)
        )
    }

    /// Favorited files in filename order (matches the Favorites screen sort).
    static func favorites(from files: [AudioFile]) -> [AudioFile] {
        Array(
            files
                .filter(\.favorite)
                .sorted { $0.filename < $1.filename }
                .prefix(shelfCap)
        )
    }

    /// Stored playlists capped for the shelf, in stored order.
    static func shelfPlaylists(from playlists: [Playlist]) -> [Playlist] {
        Array(playlists.prefix(shelfCap))
    }
}
