//
//  GenericPlaylistJSONTests.swift
//  IlumionateTests
//
//  The decoder must recognise a conventional playlist *shape*, never a
//  particular service. These tests pin both halves of that: a real published
//  response still imports, and it does so through rules that other services
//  satisfy too.
//

import Foundation
import Testing
@testable import Ilumionate

@Suite("Generic JSON playlist decoding")
struct GenericPlaylistJSONTests {

    // MARK: - Compatibility guarantee

    /// The captured response from the service the user actually imports from.
    ///
    /// This is the regression test for "neutral, but still works". It decodes
    /// through the same shape rules as every other case below — there is no
    /// branch anywhere that names a host.
    @Test("A real published response decodes with no site-specific handling")
    func realPublishedResponseDecodes() throws {
        let playlist = try GenericPlaylistJSON.playlist(from: Self.publishedResponse)

        #expect(playlist.title == "Bambi Bimbodoll Conditioning")
        #expect(playlist.tracks.count == 11)
        #expect(playlist.tracks.first?.title == "Rapid Induction")
        #expect(playlist.tracks.last?.title == "Bambi Awakens")
    }

    @Test("Millisecond durations are converted, not taken literally")
    func realResponseDurationsAreSeconds() throws {
        let playlist = try GenericPlaylistJSON.playlist(from: Self.publishedResponse)
        let first = try #require(playlist.tracks.first)

        // 162000 in the payload is 2m42s, not 45 hours.
        #expect(abs(first.duration - 162) < 0.001)
        #expect(playlist.duration > 0)
    }

    @Test("Tracks are ordered by their declared track number")
    func realResponseKeepsDeclaredOrder() throws {
        let playlist = try GenericPlaylistJSON.playlist(from: Self.publishedResponse)

        #expect(playlist.tracks.map(\.trackNumber) == Array(0..<11))
    }

    // MARK: - Shape rules, proven on other vocabularies

    @Test("A top-level playlist with `title`/`tracks`/`url` decodes identically")
    func alternateKeyVocabularyDecodes() throws {
        let json = Data("""
        {
          "title": "Evening Set",
          "tracks": [
            { "title": "One", "duration": 90, "url": "https://example.com/1.mp3" },
            { "title": "Two", "duration": 30 }
          ]
        }
        """.utf8)

        let playlist = try GenericPlaylistJSON.playlist(from: json)

        #expect(playlist.title == "Evening Set")
        #expect(playlist.tracks.map(\.title) == ["One", "Two"])
        #expect(abs(playlist.tracks[0].duration - 90) < 0.001)
        #expect(playlist.tracks[0].audioURL?.lastPathComponent == "1.mp3")
        #expect(playlist.tracks[1].audioURL == nil)
    }

    @Test("Second-scale durations are left alone")
    func secondScaleDurationsAreNotRescaled() throws {
        let json = Data("""
        { "name": "S", "tracks": [ { "name": "T", "duration": 245 } ] }
        """.utf8)

        let playlist = try GenericPlaylistJSON.playlist(from: json)

        #expect(abs(playlist.tracks[0].duration - 245) < 0.001)
    }

    @Test("A playlist nested under a collection key is found")
    func nestedCollectionIsFound() throws {
        for key in ["playlists", "items", "data", "results", "entries"] {
            let json = Data("""
            { "\(key)": [ { "name": "N", "files": [ { "name": "T", "duration": 60 } ] } ] }
            """.utf8)

            let playlist = try GenericPlaylistJSON.playlist(from: json)
            #expect(playlist.title == "N", "collection key \(key)")
            #expect(playlist.tracks.count == 1, "collection key \(key)")
        }
    }

    @Test("Array order is the fallback when no track number is declared")
    func arrayOrderIsTheFallback() throws {
        let json = Data("""
        { "name": "S", "tracks": [ { "name": "A" }, { "name": "B" }, { "name": "C" } ] }
        """.utf8)

        let playlist = try GenericPlaylistJSON.playlist(from: json)

        #expect(playlist.tracks.map(\.title) == ["A", "B", "C"])
        #expect(playlist.tracks.map(\.trackNumber) == [0, 1, 2])
    }

    // MARK: - Failure surfaces

    @Test("Malformed JSON reports a decoding failure rather than crashing")
    func malformedJSONThrows() {
        #expect(throws: PlaylistSourceError.self) {
            try GenericPlaylistJSON.playlist(from: Data("not json".utf8))
        }
    }

    @Test("Valid JSON with no recognisable track list is rejected")
    func jsonWithoutTracksThrows() {
        let json = Data(#"{ "name": "Empty", "somethingElse": 3 }"#.utf8)

        #expect(throws: PlaylistSourceError.self) {
            try GenericPlaylistJSON.playlist(from: json)
        }
    }

    @Test("A track with no usable title is skipped rather than importing blank rows")
    func untitledTracksAreSkipped() throws {
        let json = Data("""
        { "name": "S", "tracks": [ { "name": "Real" }, { "duration": 10 }, { "name": "  " } ] }
        """.utf8)

        let playlist = try GenericPlaylistJSON.playlist(from: json)

        #expect(playlist.tracks.map(\.title) == ["Real"])
    }

    // MARK: - Fixture

    private static var publishedResponse: Data {
        get throws {
            let url = try #require(
                Bundle(for: BundleMarker.self).url(
                    forResource: "Fixtures_JSONPlaylistResponse",
                    withExtension: "json"
                ),
                "the JSON playlist fixture must be in the test bundle"
            )
            return try Data(contentsOf: url)
        }
    }

    private final class BundleMarker {}
}
