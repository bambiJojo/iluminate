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

    /// Creators with at least one file, name-sorted; unknown/empty creators excluded.
    static func artists(from files: [AudioFile]) -> [LibraryArtist] {
        let named = files.compactMap { file -> String? in
            guard let name = file.creatorDisplayName, !name.isEmpty else { return nil }
            return name
        }
        let grouped = Dictionary(grouping: named) { $0 }
        return Array(
            grouped
                .map { LibraryArtist(name: $0.key, fileCount: $0.value.count) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .prefix(shelfCap)
        )
    }

    /// Analyzed files, newest first.
    static func analyzed(from files: [AudioFile]) -> [AudioFile] {
        Array(
            files
                .filter(\.isAnalyzed)
                .sorted { $0.createdDate > $1.createdDate }
                .prefix(shelfCap)
        )
    }

    /// Every file, newest first, capped for the shelf.
    static func allFiles(from files: [AudioFile]) -> [AudioFile] {
        Array(files.sorted { $0.createdDate > $1.createdDate }.prefix(shelfCap))
    }

    /// Files paired with their user-generated light score, most recent first.
    /// `sessionLookup` is injected (rather than reaching for
    /// `GeneratedSessionStore.shared` here) so this stays pure and testable;
    /// callers pass the store's `load(for:)` in production.
    /// Newest first, capped like every other shelf.
    ///
    /// `hasSession` is the cheap existence check and `sessionLookup` the
    /// expensive decode. Filtering and capping before the decode means a
    /// library of any size costs a handful of reads instead of one per file —
    /// the shelf only ever shows `limit` of them anyway.
    static func generatedSessions(
        from files: [AudioFile],
        limit: Int = shelfCap,
        hasSession: (AudioFile) -> Bool,
        sessionLookup: (AudioFile) -> LightSession?
    ) -> [GeneratedSessionItem] {
        files
            .sorted { $0.createdDate > $1.createdDate }
            .lazy
            .filter(hasSession)
            .prefix(limit)
            .compactMap { file in
                guard let session = sessionLookup(file) else { return nil }
                return GeneratedSessionItem(audioFile: file, session: session)
            }
    }

    /// Chooses a small next-listen set using only local behavior. Matching the
    /// most recent creator/content type wins, followed by favorites and items
    /// the listener has not played yet.
    static func recommendedNext(from files: [AudioFile], limit: Int = 3) -> [AudioFile] {
        guard files.isEmpty == false else { return [] }
        let mostRecent = files
            .filter { $0.lastPlayedDate != nil }
            .max { ($0.lastPlayedDate ?? .distantPast) < ($1.lastPlayedDate ?? .distantPast) }

        return Array(
            files
                .filter { $0.id != mostRecent?.id }
                .sorted { lhs, rhs in
                    let lhsScore = recommendationScore(lhs, relativeTo: mostRecent)
                    let rhsScore = recommendationScore(rhs, relativeTo: mostRecent)
                    if lhsScore == rhsScore { return lhs.createdDate > rhs.createdDate }
                    return lhsScore > rhsScore
                }
                .prefix(max(0, limit))
        )
    }

    private static func recommendationScore(_ file: AudioFile, relativeTo recent: AudioFile?) -> Int {
        var score = 0
        if file.lastPlayedDate == nil { score += 3 }
        if file.favorite { score += 2 }
        if file.isAnalyzed { score += 1 }
        if file.creatorDisplayName != nil,
           file.creatorDisplayName == recent?.creatorDisplayName { score += 4 }
        if file.analysisResult?.contentType == recent?.analysisResult?.contentType { score += 3 }
        return score
    }

    /// Full-list sorting for the Audio Files screen (uncapped).
    static func sortedFiles(from files: [AudioFile], by option: LibrarySortOption) -> [AudioFile] {
        files.sorted { lhs, rhs in
            switch option {
            case .newest:     return lhs.createdDate > rhs.createdDate
            case .name:       return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            case .lastPlayed: return (lhs.lastPlayedDate ?? .distantPast) > (rhs.lastPlayedDate ?? .distantPast)
            case .favorites:  return lhs.favorite && !rhs.favorite
            }
        }
    }
}

/// A creator/narrator group shown on the Artists shelf.
nonisolated struct LibraryArtist: Identifiable, Equatable {
    let name: String
    let fileCount: Int
    var id: String { name }
}

// MARK: - Sort Options

nonisolated enum LibrarySortOption: String, CaseIterable {
    case newest     = "newest"
    case name       = "name"
    case lastPlayed = "lastPlayed"
    case favorites  = "favorites"

    var label: String {
        switch self {
        case .newest:     "Newest"
        case .name:       "Name"
        case .lastPlayed: "Recently Played"
        case .favorites:  "Favorites First"
        }
    }
}
