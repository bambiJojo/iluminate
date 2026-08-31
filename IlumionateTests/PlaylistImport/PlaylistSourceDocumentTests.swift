//
//  PlaylistSourceDocumentTests.swift
//  IlumionateTests
//
//  Format dispatch. Every case here is decided by the bytes, never by where
//  they came from — there is no host anywhere in these tests by design.
//

import Foundation
import Testing
@testable import Ilumionate

@Suite("Playlist source format dispatch")
struct PlaylistSourceDocumentTests {

    // MARK: - M3U

    @Test("An extended M3U decodes titles and durations")
    func extendedM3UDecodes() throws {
        let m3u = """
        #EXTM3U
        #PLAYLIST:Evening Set
        #EXTINF:162,Rapid Induction
        https://example.com/one.mp3
        #EXTINF:1049,Bubble Induction
        https://example.com/two.mp3
        """

        let playlist = try PlaylistSourceDocument.playlist(from: Data(m3u.utf8), contentType: nil)

        #expect(playlist.title == "Evening Set")
        #expect(playlist.tracks.map(\.title) == ["Rapid Induction", "Bubble Induction"])
        #expect(abs(playlist.tracks[0].duration - 162) < 0.001)
        #expect(playlist.tracks[1].audioURL?.lastPathComponent == "two.mp3")
    }

    @Test("A plain M3U with no directives still yields tracks")
    func plainM3UDecodes() throws {
        let m3u = """
        #EXTM3U
        https://example.com/first-track.mp3
        https://example.com/second-track.mp3
        """

        let playlist = try PlaylistSourceDocument.playlist(from: Data(m3u.utf8), contentType: nil)

        #expect(playlist.tracks.count == 2)
        #expect(playlist.tracks[0].title == "first-track")
    }

    @Test("An unknown M3U duration of -1 is treated as no duration")
    func m3uUnknownDurationIsZero() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1,Live Stream
        https://example.com/live.mp3
        """

        let playlist = try PlaylistSourceDocument.playlist(from: Data(m3u.utf8), contentType: nil)

        #expect(playlist.tracks[0].duration == 0)
    }

    // MARK: - PLS

    @Test("A PLS playlist decodes in declared order")
    func plsDecodes() throws {
        let pls = """
        [playlist]
        NumberOfEntries=2
        File2=https://example.com/b.mp3
        Title2=Second
        Length2=200
        File1=https://example.com/a.mp3
        Title1=First
        Length1=100
        """

        let playlist = try PlaylistSourceDocument.playlist(from: Data(pls.utf8), contentType: nil)

        #expect(playlist.tracks.map(\.title) == ["First", "Second"])
        #expect(abs(playlist.tracks[1].duration - 200) < 0.001)
    }

    // MARK: - RSS

    @Test("A podcast feed decodes enclosures as tracks")
    func rssDecodes() throws {
        let rss = """
        <?xml version="1.0"?>
        <rss version="2.0">
          <channel>
            <title>A Feed</title>
            <item>
              <title>Episode One</title>
              <enclosure url="https://example.com/e1.mp3" type="audio/mpeg"/>
            </item>
            <item>
              <title>Episode Two</title>
              <enclosure url="https://example.com/e2.mp3" type="audio/mpeg"/>
            </item>
          </channel>
        </rss>
        """

        let playlist = try PlaylistSourceDocument.playlist(from: Data(rss.utf8), contentType: nil)

        #expect(playlist.title == "A Feed")
        #expect(playlist.tracks.map(\.title) == ["Episode One", "Episode Two"])
        #expect(playlist.tracks[0].audioURL?.lastPathComponent == "e1.mp3")
    }

    // MARK: - JSON

    @Test("JSON is routed to the shape-driven decoder")
    func jsonIsRouted() throws {
        let json = #"{ "name": "S", "tracks": [ { "name": "T", "duration": 60 } ] }"#

        let playlist = try PlaylistSourceDocument.playlist(from: Data(json.utf8), contentType: nil)

        #expect(playlist.title == "S")
        #expect(playlist.tracks.count == 1)
    }

    // MARK: - Failure surfaces

    @Test("A web page is reported as a web page, not as a broken playlist")
    func htmlIsRecognised() {
        let html = "<!DOCTYPE html><html><head><title>A page</title></head><body>hi</body></html>"

        #expect(throws: PlaylistSourceError.looksLikeAWebPage) {
            try PlaylistSourceDocument.playlist(from: Data(html.utf8), contentType: "text/html")
        }
    }

    @Test("The web-page error tells the user to paste the data address")
    func webPageErrorIsActionable() {
        #expect(PlaylistSourceError.looksLikeAWebPage.failureReason.contains("web page"))
        #expect(PlaylistSourceError.looksLikeAWebPage.failureReason.localizedStandardContains("paste"))
    }

    @Test("Bytes matching no known format are rejected")
    func unknownFormatIsRejected() {
        #expect(throws: PlaylistSourceError.self) {
            try PlaylistSourceDocument.playlist(from: Data("just some prose".utf8), contentType: nil)
        }
    }

    @Test("An empty response is rejected")
    func emptyResponseIsRejected() {
        #expect(throws: PlaylistSourceError.self) {
            try PlaylistSourceDocument.playlist(from: Data(), contentType: nil)
        }
    }

    // MARK: - Neutrality invariant

    @Test("No shipped playlist-import source names a playlist host")
    func noHardcodedPlaylistHost() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PlaylistImport
            .deletingLastPathComponent()   // IlumionateTests
            .deletingLastPathComponent()   // repo root
            .appending(path: "Ilumionate/PlaylistImport")

        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        #expect(!files.isEmpty, "the importer sources must be where this test looks")

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8).lowercased()
            #expect(
                !contents.contains("bambicloud"),
                "\(file.lastPathComponent) names a specific service"
            )
        }
    }
}
