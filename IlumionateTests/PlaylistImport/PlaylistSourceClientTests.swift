//
//  PlaylistSourceClientTests.swift
//  IlumionateTests
//
//  Link validation and fetching. No network: every case injects its response.
//

import Foundation
import Testing
@testable import Ilumionate

@Suite("Playlist source link handling")
struct PlaylistSourceURLTests {

    @Test("A bare host is normalised to https")
    func bareHostBecomesHTTPS() throws {
        let url = try PlaylistSourceURL.normalized("example.com/list.json")

        #expect(url.scheme == "https")
        #expect(url.host() == "example.com")
    }

    @Test("Surrounding whitespace is ignored")
    func whitespaceIsTrimmed() throws {
        let url = try PlaylistSourceURL.normalized("  https://example.com/a.m3u \n")

        #expect(url.absoluteString == "https://example.com/a.m3u")
    }

    @Test("http is accepted as well as https")
    func httpIsAccepted() throws {
        let url = try PlaylistSourceURL.normalized("http://example.com/a.pls")

        #expect(url.scheme == "http")
    }

    @Test("Non-web schemes are refused", arguments: [
        "javascript:alert(1)",
        "data:text/plain,hello",
        "file:///etc/passwd",
        "ftp://example.com/a.mp3",
    ])
    func nonWebSchemesAreRefused(link: String) {
        #expect(throws: PlaylistSourceError.invalidLink) {
            try PlaylistSourceURL.normalized(link)
        }
    }

    @Test("Empty and hostless links are refused", arguments: ["", "   ", "https://", "not a url at all"])
    func emptyLinksAreRefused(link: String) {
        #expect(throws: PlaylistSourceError.invalidLink) {
            try PlaylistSourceURL.normalized(link)
        }
    }
}

@Suite("Playlist source fetching")
struct PlaylistSourceClientTests {

    private func client(
        _ handler: @escaping @Sendable (URL) async throws -> (Data, HTTPURLResponse)
    ) -> PlaylistSourceClient {
        PlaylistSourceClient { url in
            let (data, response) = try await handler(url)
            return (data, response)
        }
    }

    private func response(_ url: URL, status: Int = 200, contentType: String? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: contentType.map { ["Content-Type": $0] }
        )!
    }

    @Test("A JSON playlist is fetched and decoded")
    func fetchesAndDecodesJSON() async throws {
        let body = Data(#"{ "name": "Set", "tracks": [ { "name": "T", "duration": 60 } ] }"#.utf8)
        let client = client { url in (body, self.response(url, contentType: "application/json")) }

        let result = try await client.playlist(at: "https://example.com/list.json")

        #expect(result.playlist.title == "Set")
        #expect(result.playlist.tracks.count == 1)
        #expect(result.sourceURL.host() == "example.com")
    }

    @Test("A non-success status is reported as an unreadable response")
    func nonSuccessStatusThrows() async {
        let client = client { url in (Data(), self.response(url, status: 404)) }

        await #expect(throws: PlaylistSourceError.invalidResponse) {
            try await client.playlist(at: "https://example.com/missing.json")
        }
    }

    @Test("A page advertising a feed is followed to that feed")
    func followsFeedAutodiscovery() async throws {
        let page = """
        <!DOCTYPE html><html><head>
        <link rel="alternate" type="application/rss+xml" href="https://example.com/feed.xml">
        </head><body>a page</body></html>
        """
        let feed = """
        <rss version="2.0"><channel><title>Discovered</title>
        <item><title>One</title><enclosure url="https://example.com/1.mp3" type="audio/mpeg"/></item>
        </channel></rss>
        """
        let client = client { url in
            if url.lastPathComponent == "feed.xml" {
                return (Data(feed.utf8), self.response(url, contentType: "application/rss+xml"))
            }
            return (Data(page.utf8), self.response(url, contentType: "text/html"))
        }

        let result = try await client.playlist(at: "https://example.com/show")

        #expect(result.playlist.title == "Discovered")
        #expect(result.playlist.tracks.count == 1)
        // Provenance must follow the feed, since that is where the media lives.
        #expect(result.sourceURL.lastPathComponent == "feed.xml")
    }

    @Test("A relative feed address is resolved against the page")
    func resolvesRelativeFeedAddress() async throws {
        let page = #"<html><head><link rel="alternate" type="application/json" href="/data.json"></head></html>"#
        let json = #"{ "name": "Rel", "tracks": [ { "name": "T" } ] }"#
        let client = client { url in
            if url.path.hasSuffix("data.json") {
                return (Data(json.utf8), self.response(url, contentType: "application/json"))
            }
            return (Data(page.utf8), self.response(url, contentType: "text/html"))
        }

        let result = try await client.playlist(at: "https://example.com/deep/page")

        #expect(result.playlist.title == "Rel")
        #expect(result.sourceURL.absoluteString == "https://example.com/data.json")
    }

    @Test("A page with no feed is reported as a web page, and is not fetched twice")
    func pageWithoutFeedIsReported() async throws {
        let page = "<!DOCTYPE html><html><head><title>Nothing here</title></head></html>"
        let calls = Counter()
        let client = client { url in
            await calls.increment()
            return (Data(page.utf8), self.response(url, contentType: "text/html"))
        }

        await #expect(throws: PlaylistSourceError.looksLikeAWebPage) {
            try await client.playlist(at: "https://example.com/page")
        }
        #expect(await calls.value == 1)
    }

    @Test("Autodiscovery does not recurse: a feed link pointing at another page gives up")
    func autodiscoveryDoesNotRecurse() async {
        let page = #"<html><head><link rel="alternate" type="application/rss+xml" href="https://example.com/other"></head></html>"#
        let client = client { url in (Data(page.utf8), self.response(url, contentType: "text/html")) }

        await #expect(throws: PlaylistSourceError.looksLikeAWebPage) {
            try await client.playlist(at: "https://example.com/page")
        }
    }

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }
}
