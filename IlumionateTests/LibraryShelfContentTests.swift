//
//  LibraryShelfContentTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct LibraryShelfContentTests {

    private func makeFile(
        filename: String,
        createdDate: Date = Date(),
        lastPlayed: Date? = nil,
        favorite: Bool = false,
        creator: String? = nil,
        analyzed: Bool = false
    ) -> AudioFile {
        var file = AudioFile(
            filename: filename,
            duration: 300,
            fileSize: 1_024,
            createdDate: createdDate,
            isFavorite: favorite,
            lastPlayedDate: lastPlayed
        )
        file.creator = creator
        if analyzed { file.analysisResult = AnalysisFixtures.hypnosisAnalysis }
        return file
    }

    // MARK: - Recents

    @Test
    func recents_ordersByLastPlayedDescendingAndExcludesNeverPlayed() {
        let now = Date()
        let files = [
            makeFile(filename: "old.m4a", lastPlayed: now.addingTimeInterval(-3_600)),
            makeFile(filename: "never.m4a"),
            makeFile(filename: "new.m4a", lastPlayed: now)
        ]

        let recents = LibraryShelfContent.recents(from: files)

        #expect(recents.map(\.filename) == ["new.m4a", "old.m4a"])
    }

    @Test
    func recents_capsAtShelfCap() {
        let now = Date()
        let files = (0..<25).map { index in
            makeFile(filename: "file\(index).m4a",
                     lastPlayed: now.addingTimeInterval(-Double(index)))
        }

        let recents = LibraryShelfContent.recents(from: files)

        #expect(recents.count == LibraryShelfContent.shelfCap)
        #expect(recents.first?.filename == "file0.m4a")
    }

    @Test
    func recents_emptyInputReturnsEmpty() {
        #expect(LibraryShelfContent.recents(from: []).isEmpty)
    }

    // MARK: - Favorites

    @Test
    func favorites_filtersToFavoritesInFilenameOrder() {
        let files = [
            makeFile(filename: "b.m4a", favorite: true),
            makeFile(filename: "plain.m4a"),
            makeFile(filename: "a.m4a", favorite: true)
        ]

        let favorites = LibraryShelfContent.favorites(from: files)

        #expect(favorites.map(\.filename) == ["a.m4a", "b.m4a"])
    }

    @Test
    func favorites_capsAtShelfCap() {
        let files = (0..<15).map { index in
            makeFile(filename: String(format: "fav%02d.m4a", index), favorite: true)
        }

        let favorites = LibraryShelfContent.favorites(from: files)

        #expect(favorites.count == LibraryShelfContent.shelfCap)
    }

    // MARK: - Playlists

    @Test
    func shelfPlaylists_preservesStoredOrderAndCaps() {
        let playlists = (0..<12).map { Playlist(name: "List \($0)") }

        let shelf = LibraryShelfContent.shelfPlaylists(from: playlists)

        #expect(shelf.count == LibraryShelfContent.shelfCap)
        #expect(shelf.first?.name == "List 0")
        #expect(shelf.last?.name == "List 9")
    }

    @Test
    func shelfPlaylists_emptyInputReturnsEmpty() {
        #expect(LibraryShelfContent.shelfPlaylists(from: []).isEmpty)
    }

    // MARK: - Artists

    @Test
    func artists_groupsByCreatorSortedByNameAndExcludesUnknown() {
        let files = [
            makeFile(filename: "b1.m4a", creator: "Bella"),
            makeFile(filename: "a1.m4a", creator: "Anders"),
            makeFile(filename: "b2.m4a", creator: "Bella"),
            makeFile(filename: "none.m4a")
        ]

        let artists = LibraryShelfContent.artists(from: files)

        #expect(artists == [
            LibraryArtist(name: "Anders", fileCount: 1),
            LibraryArtist(name: "Bella", fileCount: 2)
        ])
    }

    @Test
    func artists_capsAtShelfCap() {
        let files = (0..<14).map { index in
            makeFile(filename: "f\(index).m4a", creator: String(format: "Artist %02d", index))
        }

        #expect(LibraryShelfContent.artists(from: files).count == LibraryShelfContent.shelfCap)
    }

    // MARK: - Analyzed

    @Test
    func analyzed_filtersToAnalyzedNewestFirst() {
        let now = Date()
        let files = [
            makeFile(filename: "old.m4a", createdDate: now.addingTimeInterval(-100), analyzed: true),
            makeFile(filename: "raw.m4a", createdDate: now),
            makeFile(filename: "new.m4a", createdDate: now, analyzed: true)
        ]

        let analyzed = LibraryShelfContent.analyzed(from: files)

        #expect(analyzed.map(\.filename) == ["new.m4a", "old.m4a"])
    }

    // MARK: - All Files

    @Test
    func allFiles_ordersNewestFirstAndCaps() {
        let now = Date()
        let files = (0..<12).map { index in
            makeFile(filename: "f\(index).m4a", createdDate: now.addingTimeInterval(-Double(index)))
        }

        let shelf = LibraryShelfContent.allFiles(from: files)

        #expect(shelf.count == LibraryShelfContent.shelfCap)
        #expect(shelf.first?.filename == "f0.m4a")
        #expect(shelf.last?.filename == "f9.m4a")
    }

    @Test
    func recommendationsPreferUnplayedMatchingCreator() {
        let now = Date()
        let recent = makeFile(filename: "recent.m4a", lastPlayed: now, creator: "Guide")
        let matching = makeFile(filename: "matching.m4a", creator: "Guide")
        let unrelated = makeFile(filename: "unrelated.m4a", favorite: true, creator: "Other")

        let recommendations = LibraryShelfContent.recommendedNext(
            from: [recent, unrelated, matching]
        )

        #expect(recommendations.first?.id == matching.id)
        #expect(recommendations.contains(where: { $0.id == recent.id }) == false)
    }

    // MARK: - Sorted Files

    @Test
    func sortedFiles_sortsByEachOption() {
        let now = Date()
        let files = [
            makeFile(filename: "beta.m4a", createdDate: now.addingTimeInterval(-10),
                     lastPlayed: now, favorite: false),
            makeFile(filename: "alpha.m4a", createdDate: now,
                     lastPlayed: now.addingTimeInterval(-50), favorite: true)
        ]

        #expect(LibraryShelfContent.sortedFiles(from: files, by: .newest).map(\.filename)
                == ["alpha.m4a", "beta.m4a"])
        #expect(LibraryShelfContent.sortedFiles(from: files, by: .name).map(\.filename)
                == ["alpha.m4a", "beta.m4a"])
        #expect(LibraryShelfContent.sortedFiles(from: files, by: .lastPlayed).map(\.filename)
                == ["beta.m4a", "alpha.m4a"])
        #expect(LibraryShelfContent.sortedFiles(from: files, by: .favorites).map(\.filename)
                == ["alpha.m4a", "beta.m4a"])
    }
}
