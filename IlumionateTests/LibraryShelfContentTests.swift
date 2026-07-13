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
        lastPlayed: Date? = nil,
        favorite: Bool = false
    ) -> AudioFile {
        AudioFile(
            filename: filename,
            duration: 300,
            fileSize: 1_024,
            isFavorite: favorite,
            lastPlayedDate: lastPlayed
        )
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
}
