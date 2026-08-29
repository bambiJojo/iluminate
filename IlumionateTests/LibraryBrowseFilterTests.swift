//
//  LibraryBrowseFilterTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct LibraryBrowseFilterTests {

    private func makeFile(
        filename: String,
        createdDate: Date = Date(),
        favorite: Bool = false,
        creator: String? = nil,
        contentType: AudioContentType? = nil,
        userTitle: String? = nil
    ) -> AudioFile {
        var file = AudioFile(
            filename: filename,
            duration: 300,
            fileSize: 1_024,
            createdDate: createdDate,
            isFavorite: favorite,
            userTitle: userTitle
        )
        file.creator = creator
        if let contentType {
            file.analysisResult = AnalysisFixtures.analysis(contentType: contentType)
        }
        return file
    }

    // MARK: - Text Matching

    @Test
    func matches_emptyQueryAdmitsEverything() {
        let file = makeFile(filename: "anything.m4a")

        #expect(LibraryBrowseFilter.matches(file, query: ""))
        #expect(LibraryBrowseFilter.matches(file, query: "   "))
    }

    @Test
    func matches_findsDisplayNameCaseAndDiacriticInsensitively() {
        let file = makeFile(filename: "Bubble Induction.mp3")

        #expect(LibraryBrowseFilter.matches(file, query: "bubble"))
        #expect(LibraryBrowseFilter.matches(file, query: "INDUCTION"))
        #expect(LibraryBrowseFilter.matches(file, query: "zebra") == false)
    }

    @Test
    func matches_findsCreator() {
        let file = makeFile(filename: "track.m4a", creator: "Bambi Prime")

        #expect(LibraryBrowseFilter.matches(file, query: "bambi"))
        #expect(LibraryBrowseFilter.matches(file, query: "prime"))
    }

    @Test
    func matches_findsContentTypeDisplayName() {
        let file = makeFile(filename: "track.m4a", contentType: .sleepHypnosis)

        #expect(LibraryBrowseFilter.matches(file, query: "sleep"))
    }

    @Test
    func matches_prefersUserTitleOverFilename() {
        let file = makeFile(filename: "raw-export-0043.m4a", userTitle: "Velvet Descent")

        #expect(LibraryBrowseFilter.matches(file, query: "velvet"))
    }

    @Test
    func matches_playlistFindsNameAndTrackTitles() {
        var playlist = Playlist(name: "Nightly Wind Down")
        playlist.items = [
            PlaylistItem(audioFileId: UUID(), filename: "Bubble Induction.mp3", duration: 60)
        ]

        #expect(LibraryBrowseFilter.matches(playlist, query: "nightly"))
        #expect(LibraryBrowseFilter.matches(playlist, query: "bubble"))
        #expect(LibraryBrowseFilter.matches(playlist, query: "gamma") == false)
    }

    // MARK: - Quick Filters

    @Test
    func quickFilter_admitsByStatus() {
        let favorite = makeFile(filename: "fav.m4a", favorite: true)
        let analyzed = makeFile(filename: "done.m4a", contentType: .hypnosis)
        let raw = makeFile(filename: "raw.m4a")

        #expect(LibraryQuickFilter.favorites.admits(favorite))
        #expect(LibraryQuickFilter.favorites.admits(raw) == false)
        #expect(LibraryQuickFilter.analyzed.admits(analyzed))
        #expect(LibraryQuickFilter.analyzed.admits(raw) == false)
        #expect(LibraryQuickFilter.needsAnalysis.admits(raw))
        #expect(LibraryQuickFilter.needsAnalysis.admits(analyzed) == false)
    }

    @Test
    func quickFilter_admitsByContentType() {
        let sleep = makeFile(filename: "sleep.m4a", contentType: .sleepHypnosis)
        let meditation = makeFile(filename: "med.m4a", contentType: .meditation)

        #expect(LibraryQuickFilter.contentType(.sleepHypnosis).admits(sleep))
        #expect(LibraryQuickFilter.contentType(.sleepHypnosis).admits(meditation) == false)
    }

    @Test
    func quickFilter_allAdmitsEverything() {
        #expect(LibraryQuickFilter.all.admits(makeFile(filename: "x.m4a")))
    }

    // MARK: - Chips

    @Test
    func chips_emptyLibraryProducesNoChips() {
        #expect(LibraryBrowseFilter.chips(for: []).isEmpty)
    }

    @Test
    func chips_leadWithAllAndCountTotal() {
        let files = [
            makeFile(filename: "a.m4a", contentType: .hypnosis),
            makeFile(filename: "b.m4a")
        ]

        let chips = LibraryBrowseFilter.chips(for: files)

        #expect(chips.first?.filter == .all)
        #expect(chips.first?.count == 2)
    }

    @Test
    func chips_omitStatusFiltersThatWouldMatchNothing() {
        // Every file is analyzed, so "Needs Analysis" must not appear; none are
        // favorited, so "Favorites" must not appear either.
        let files = [
            makeFile(filename: "a.m4a", contentType: .hypnosis),
            makeFile(filename: "b.m4a", contentType: .hypnosis)
        ]

        let filters = LibraryBrowseFilter.chips(for: files).map(\.filter)

        #expect(filters.contains(.needsAnalysis) == false)
        #expect(filters.contains(.favorites) == false)
        #expect(filters.contains(.analyzed))
    }

    @Test
    func chips_orderContentTypesByPopulationThenName() {
        let files = [
            makeFile(filename: "h1.m4a", contentType: .hypnosis),
            makeFile(filename: "h2.m4a", contentType: .hypnosis),
            makeFile(filename: "h3.m4a", contentType: .hypnosis),
            makeFile(filename: "m1.m4a", contentType: .meditation),
            makeFile(filename: "m2.m4a", contentType: .meditation),
            makeFile(filename: "a1.m4a", contentType: .asmr)
        ]

        let typeChips = LibraryBrowseFilter.chips(for: files).compactMap { chip -> (AudioContentType, Int)? in
            guard case .contentType(let type) = chip.filter else { return nil }
            return (type, chip.count)
        }

        #expect(typeChips.map(\.0) == [.hypnosis, .meditation, .asmr])
        #expect(typeChips.map(\.1) == [3, 2, 1])
    }

    @Test
    func chips_excludeUnknownContentType() {
        let files = [makeFile(filename: "u.m4a", contentType: .unknown)]

        let filters = LibraryBrowseFilter.chips(for: files).map(\.filter)

        #expect(filters.contains(.contentType(.unknown)) == false)
    }

    // MARK: - Apply

    @Test
    func apply_combinesSearchFilterAndSort() {
        let now = Date()
        let files = [
            makeFile(filename: "Bubble Deepener.m4a", createdDate: now.addingTimeInterval(-100),
                     favorite: true, contentType: .hypnosis),
            makeFile(filename: "Bubble Induction.m4a", createdDate: now,
                     favorite: true, contentType: .hypnosis),
            makeFile(filename: "Bubble Bath.m4a", favorite: false, contentType: .music),
            makeFile(filename: "Gamma Clarity.m4a", favorite: true, contentType: .hypnosis)
        ]

        let results = LibraryBrowseFilter.apply(
            to: files,
            query: "bubble",
            filter: .favorites,
            sort: .name
        )

        #expect(results.map(\.filename) == ["Bubble Deepener.m4a", "Bubble Induction.m4a"])
    }

    @Test
    func apply_noMatchesReturnsEmpty() {
        let files = [makeFile(filename: "a.m4a")]

        #expect(LibraryBrowseFilter.apply(to: files, query: "nothing here").isEmpty)
    }

    @Test
    func apply_defaultsReturnEverythingNewestFirst() {
        let now = Date()
        let files = [
            makeFile(filename: "old.m4a", createdDate: now.addingTimeInterval(-100)),
            makeFile(filename: "new.m4a", createdDate: now)
        ]

        #expect(LibraryBrowseFilter.apply(to: files).map(\.filename) == ["new.m4a", "old.m4a"])
    }

    @Test
    func apply_filtersPlaylistsByQuery() {
        let playlists = [Playlist(name: "Morning Focus"), Playlist(name: "Deep Sleep Stack")]

        let results = LibraryBrowseFilter.apply(to: playlists, query: "sleep")

        #expect(results.map(\.name) == ["Deep Sleep Stack"])
    }

    // MARK: - Searching State

    @Test
    func isSearching_trueWhenQueryOrFilterNarrowsTheLibrary() {
        #expect(LibraryBrowseFilter.isSearching(query: "", filter: .all) == false)
        #expect(LibraryBrowseFilter.isSearching(query: "   ", filter: .all) == false)
        #expect(LibraryBrowseFilter.isSearching(query: "bubble", filter: .all))
        #expect(LibraryBrowseFilter.isSearching(query: "", filter: .favorites))
    }

    // MARK: - Playlist Sorting

    @Test
    func playlistSort_ordersByEachOption() {
        let now = Date()
        var short = Playlist(name: "Alpha", createdDate: now)
        short.items = [PlaylistItem(audioFileId: UUID(), filename: "a.mp3", duration: 60)]
        var long = Playlist(name: "Zeta", createdDate: now.addingTimeInterval(-100))
        long.items = [
            PlaylistItem(audioFileId: UUID(), filename: "b.mp3", duration: 600),
            PlaylistItem(audioFileId: UUID(), filename: "c.mp3", duration: 600)
        ]
        let playlists = [long, short]

        #expect(PlaylistSortOption.name.sorted(playlists).map(\.name) == ["Alpha", "Zeta"])
        #expect(PlaylistSortOption.newest.sorted(playlists).map(\.name) == ["Alpha", "Zeta"])
        #expect(PlaylistSortOption.trackCount.sorted(playlists).map(\.name) == ["Zeta", "Alpha"])
        #expect(PlaylistSortOption.duration.sorted(playlists).map(\.name) == ["Zeta", "Alpha"])
    }

    @MainActor
    @Test("The legacy audio-library sorter does not claim built-in confidence is AI")
    func audioLibraryConfidenceLabelIsSourceNeutral() {
        #expect(AudioLibraryView.SortOption.confidence.rawValue == "Analysis Confidence")
    }
}
