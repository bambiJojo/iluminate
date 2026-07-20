//
//  PlaylistArtworkStyleTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

struct PlaylistArtworkStyleTests {

    @Test("Default style is the content-derived mosaic")
    func defaultIsAutomatic() {
        #expect(PlaylistArtworkStyle().motif == .auto)
        #expect(PlaylistArtworkStyle.automatic.motif == .auto)
    }

    @Test("Gallery offers Auto plus every motif in every colorway")
    func galleryCoversEveryCombination() {
        let gallery = PlaylistArtworkStyle.gallery
        let drawnMotifs = PlaylistArtworkMotif.allCases.filter { $0 != .auto }
        let expected = 1 + drawnMotifs.count * PlaylistArtworkPalette.allCases.count

        #expect(gallery.count == expected)
        #expect(gallery.first == .automatic)

        // Exactly one Auto entry, and no duplicates anywhere.
        #expect(gallery.filter { $0.motif == .auto }.count == 1)
        #expect(Set(gallery.map(\.id)).count == gallery.count)

        for motif in drawnMotifs {
            for palette in PlaylistArtworkPalette.allCases {
                #expect(gallery.contains(PlaylistArtworkStyle(motif: motif, palette: palette)))
            }
        }
    }

    @Test("Every colorway supplies enough ink colors for the motifs",
          arguments: PlaylistArtworkPalette.allCases)
    func palettesHaveColors(palette: PlaylistArtworkPalette) throws {
        #expect(palette.colors.count >= 2)
        #expect(!palette.displayName.isEmpty)
    }

    @Test("Playlists saved before artwork selection still decode")
    func legacyPlaylistDecoding() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Night Drift","items":[],
         "smartTransitions":true,"createdDate":760000000}
        """.data(using: .utf8)!

        let playlist = try JSONDecoder().decode(Playlist.self, from: legacy)
        #expect(playlist.artworkStyle == nil)
        #expect(playlist.artwork == .automatic)
        #expect(playlist.name == "Night Drift")
    }

    @Test("A chosen style survives an encode/decode round trip")
    func styleRoundTrips() throws {
        let chosen = PlaylistArtworkStyle(motif: .spiral, palette: .ember)
        let playlist = Playlist(name: "Deep Spiral", artworkStyle: chosen)

        let data = try JSONEncoder().encode(playlist)
        let restored = try JSONDecoder().decode(Playlist.self, from: data)

        #expect(restored.artworkStyle == chosen)
        #expect(restored.artwork.motif == .spiral)
        #expect(restored.artwork.palette == .ember)
    }
}
