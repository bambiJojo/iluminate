//
//  LibraryBrowseFilter.swift
//  Ilumionate
//
//  Pure search + quick-filter logic shared by the Library tab's search-first
//  header and the pushed browse screen. Kept UI-free so matching rules, chip
//  derivation, and counts stay unit-testable.
//

import Foundation

// MARK: - Quick Filter

/// A one-tap narrowing applied on top of the search query. Content-type cases
/// are data-driven: only types actually present in the library become chips.
nonisolated enum LibraryQuickFilter: Hashable, Identifiable, Sendable {
    case all
    case favorites
    case analyzed
    case needsAnalysis
    case contentType(AudioContentType)

    var id: String {
        switch self {
        case .all:                  "all"
        case .favorites:            "favorites"
        case .analyzed:             "analyzed"
        case .needsAnalysis:        "needsAnalysis"
        case .contentType(let type): "type.\(type.rawValue)"
        }
    }

    var label: String {
        switch self {
        case .all:                   "All"
        case .favorites:             "Favorites"
        case .analyzed:              "Analyzed"
        case .needsAnalysis:         "Needs Analysis"
        case .contentType(let type): type.displayName
        }
    }

    var systemImage: String {
        switch self {
        case .all:                   "square.grid.2x2"
        case .favorites:             "heart.fill"
        case .analyzed:              "checkmark.seal.fill"
        case .needsAnalysis:         "waveform.badge.exclamationmark"
        case .contentType(let type): ContentTypeStyle.icon(for: type)
        }
    }

    /// Whether a file survives this filter. `.all` admits everything.
    func admits(_ file: AudioFile) -> Bool {
        switch self {
        case .all:                   true
        case .favorites:             file.favorite
        case .analyzed:              file.isAnalyzed
        case .needsAnalysis:         file.isAnalyzed == false
        case .contentType(let type): file.analysisResult?.contentType == type
        }
    }
}

/// A filter chip plus the number of files it would yield — the count is what
/// makes a chip row worth tapping instead of guessing.
nonisolated struct LibraryFilterChip: Identifiable, Equatable, Sendable {
    let filter: LibraryQuickFilter
    let count: Int
    var id: String { filter.id }
}

// MARK: - Browse Filter

nonisolated enum LibraryBrowseFilter {

    /// Chips shown above a browse list: the fixed status filters (only when they
    /// would match something) followed by the content types actually present,
    /// most-populated first. `.all` always leads.
    static func chips(for files: [AudioFile]) -> [LibraryFilterChip] {
        guard files.isEmpty == false else { return [] }

        var chips = [LibraryFilterChip(filter: .all, count: files.count)]

        for status in [LibraryQuickFilter.favorites, .analyzed, .needsAnalysis] {
            let count = files.count { status.admits($0) }
            if count > 0 {
                chips.append(LibraryFilterChip(filter: status, count: count))
            }
        }

        let typeCounts = files.reduce(into: [AudioContentType: Int]()) { counts, file in
            guard let type = file.analysisResult?.contentType, type != .unknown else { return }
            counts[type, default: 0] += 1
        }
        chips.append(contentsOf:
            typeCounts
                .sorted { lhs, rhs in
                    lhs.value == rhs.value
                        ? lhs.key.displayName.localizedStandardCompare(rhs.key.displayName) == .orderedAscending
                        : lhs.value > rhs.value
                }
                .map { LibraryFilterChip(filter: .contentType($0.key), count: $0.value) }
        )

        return chips
    }

    /// Whether an audio file matches a free-text query. Matches the title the
    /// listener actually sees, the creator, discovered themes, and the content
    /// type's display name — an empty query matches everything.
    static func matches(_ file: AudioFile, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }

        if file.displayName.localizedStandardContains(trimmed) { return true }
        if file.filename.localizedStandardContains(trimmed) { return true }
        if file.creatorDisplayName?.localizedStandardContains(trimmed) == true { return true }
        if file.discoveredThemes.contains(where: { $0.localizedStandardContains(trimmed) }) { return true }
        if let type = file.analysisResult?.contentType,
           type.displayName.localizedStandardContains(trimmed) { return true }
        return false
    }

    /// Whether a playlist matches a free-text query — its name or any track title.
    static func matches(_ playlist: Playlist, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }

        if playlist.name.localizedStandardContains(trimmed) { return true }
        return playlist.items.contains { $0.displayName.localizedStandardContains(trimmed) }
    }

    /// Search + quick filter + sort, in that order, uncapped.
    static func apply(
        to files: [AudioFile],
        query: String = "",
        filter: LibraryQuickFilter = .all,
        sort: LibrarySortOption = .newest
    ) -> [AudioFile] {
        let narrowed = files.filter { filter.admits($0) && matches($0, query: query) }
        return LibraryShelfContent.sortedFiles(from: narrowed, by: sort)
    }

    /// Playlists matching a query, in stored order.
    static func apply(to playlists: [Playlist], query: String = "") -> [Playlist] {
        playlists.filter { matches($0, query: query) }
    }

    /// True when the listener has narrowed the library and expects a flat result
    /// list instead of the browse shelves.
    static func isSearching(query: String, filter: LibraryQuickFilter) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || filter != .all
    }
}

// MARK: - Playlist Sorting

nonisolated enum PlaylistSortOption: String, CaseIterable, Sendable {
    case name
    case newest
    case trackCount
    case duration

    var label: String {
        switch self {
        case .name:       "Name"
        case .newest:     "Newest"
        case .trackCount: "Most Tracks"
        case .duration:   "Longest"
        }
    }

    func sorted(_ playlists: [Playlist]) -> [Playlist] {
        playlists.sorted { lhs, rhs in
            switch self {
            case .name:       lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .newest:     lhs.createdDate > rhs.createdDate
            case .trackCount: lhs.itemCount > rhs.itemCount
            case .duration:   lhs.totalDuration > rhs.totalDuration
            }
        }
    }
}
