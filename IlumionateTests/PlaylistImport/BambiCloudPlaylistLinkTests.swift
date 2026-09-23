import Foundation
import Testing
@testable import Ilumionate

struct BambiCloudPlaylistLinkTests {
    private static let shareLink = "https://bambicloud.com/playlist/69b12112-e603-428a-aeb5-9f204481da13"
    private static let apiAddress = "https://api.bambicloud.com/playlists?uuid=69b12112-e603-428a-aeb5-9f204481da13"

    @Test func convertsPublicShareLinkToAPIAddress() throws {
        let link = try #require(BambiCloudPlaylistLink(Self.shareLink))

        #expect(link.playlistID.uuidString.lowercased() == "69b12112-e603-428a-aeb5-9f204481da13")
        #expect(link.apiURL.absoluteString == Self.apiAddress)
    }

    @Test func rejectsLookalikeHost() {
        let link = BambiCloudPlaylistLink(
            "https://bambicloud.com.attacker.example/playlist/69b12112-e603-428a-aeb5-9f204481da13"
        )

        #expect(link == nil)
    }

    // MARK: - Source client

    /// Mirrors the live API: tracks under `files`, numeric row IDs beside a
    /// `uuid`, millisecond durations, and a declared `trackNum` that is not the
    /// array order.
    @Test func sourceClientUsesBambiAPIForShareLink() async throws {
        let response = Data("""
        {"playlists":[{"id":37276,"uuid":"69b12112-e603-428a-aeb5-9f204481da13","name":"My Bambi Playlist","files":[\
        {"id":1615,"uuid":"8eca4b4a-ba32-480f-b90f-9bd8eb54ebb7","name":"Second Track","duration":452000,"trackNum":8,"audioURL":"https://cdn.bambicloud.com/second.mp3"},\
        {"id":1611,"uuid":"3297832f-cf03-457c-8f15-f8700903b4a5","name":"First Track","duration":154000,"trackNum":0,"audioURL":"https://cdn.bambicloud.com/first.mp3"}\
        ]}],"totalItems":1,"pageSize":12,"pageOffset":0}
        """.utf8)

        let client = PlaylistSourceClient { url in
            #expect(url.absoluteString == Self.apiAddress)
            return try Self.jsonResponse(response, for: url)
        }

        let result = try await client.playlist(at: Self.shareLink)

        #expect(result.playlist.title == "My Bambi Playlist")
        #expect(result.playlist.tracks.map(\.title) == ["First Track", "Second Track"])
        #expect(result.playlist.tracks.first?.duration == 154)
        #expect(result.playlist.tracks.first?.id == "3297832f-cf03-457c-8f15-f8700903b4a5")
        #expect(result.sourceURL.host() == "api.bambicloud.com")
    }

    /// The API answers an unknown or private UUID with an empty list rather
    /// than a 404.
    @Test func unknownPlaylistIsReportedAsNotFound() async throws {
        let response = Data(#"{"playlists":[],"totalItems":0,"pageSize":12,"pageOffset":0}"#.utf8)
        let client = PlaylistSourceClient { url in
            try Self.jsonResponse(response, for: url)
        }

        await #expect(throws: PlaylistSourceError.playlistNotFound) {
            try await client.playlist(at: Self.shareLink)
        }
    }

    @Test(arguments: [
        "bambicloud.com/playlist/69b12112-e603-428a-aeb5-9f204481da13",
        "  www.bambicloud.com/playlist/69b12112-e603-428a-aeb5-9f204481da13/ \n",
        shareLink,
        apiAddress,
    ])
    func normalizedLinksResolveToPlaylistData(_ address: String) async throws {
        let body = Data(#"{"playlists":[{"name":"Shared Playlist","files":[{"name":"Track","duration":9000}]}]}"#.utf8)
        let client = PlaylistSourceClient { url in
            #expect(url.absoluteString == Self.apiAddress)
            return try Self.jsonResponse(body, for: url)
        }
        let result = try await client.playlist(at: address)
        #expect(result.sourceURL.absoluteString == Self.apiAddress)
        #expect(result.playlist.tracks.first?.duration == 9)
    }

    @Test func urlEntryPointResolvesSharePages() async throws {
        let body = Data(#"{"playlists":[{"name":"Shared Playlist","files":[{"name":"Track","duration":9000}]}]}"#.utf8)
        let client = PlaylistSourceClient { url in
            #expect(url.absoluteString == Self.apiAddress)
            return try Self.jsonResponse(body, for: url)
        }
        let url = try #require(URL(string: Self.shareLink))
        let result = try await client.playlist(at: url)
        #expect(result.sourceURL.absoluteString == Self.apiAddress)
        #expect(result.playlist.tracks.first?.duration == 9)
    }

    @Test(arguments: [0, 500, 9000, 14399, 14400, 154000])
    func knownSourceAlwaysUsesMilliseconds(_ milliseconds: Int) async throws {
        let body = Data("""
        {"playlists":[{"name":"Shared Playlist","files":[{"name":"Track","duration":\(milliseconds)}]}]}
        """.utf8)
        let client = PlaylistSourceClient { url in
            try Self.jsonResponse(body, for: url)
        }
        let result = try await client.playlist(at: Self.shareLink)
        #expect(result.playlist.tracks.first?.duration == Double(milliseconds) / 1000)
    }

    @Test func unrelatedJSONSourceKeepsItsSeconds() async throws {
        let body = Data(#"{"name":"Long Playlist","tracks":[{"name":"Track","duration":9000}]}"#.utf8)
        let client = PlaylistSourceClient { url in
            try Self.jsonResponse(body, for: url)
        }
        let result = try await client.playlist(at: "https://example.com/playlist.json")
        #expect(result.playlist.tracks.first?.duration == 9000)
    }

    // MARK: - Browser

    @Test(arguments: [
        shareLink,
        "https://www.bambicloud.com/playlist/69b12112-e603-428a-aeb5-9f204481da13/",
        "https://bambicloud.com/playlist/69b12112-e603-428a-aeb5-9f204481da13?tab=files",
    ])
    func browserOffersImportOnPlaylistPages(_ address: String) throws {
        let url = try #require(URL(string: address))

        #expect(PlaylistLinkBrowserView.isImportable(url))
    }

    @Test(arguments: [
        "https://bambicloud.com",
        "https://bambicloud.com/",
        "https://bambicloud.com/search?q=sleep",
        "https://bambicloud.com/user/bimbodollbambi",
        "https://www.patreon.com/bambicloud",
    ])
    func browserWithholdsImportElsewhere(_ address: String) throws {
        let url = try #require(URL(string: address))

        #expect(PlaylistLinkBrowserView.isImportable(url) == false)
    }

    @Test func browserWithholdsImportBeforeAnyPageLoads() {
        #expect(PlaylistLinkBrowserView.isImportable(nil) == false)
    }

    /// Following a link mid-load cancels the previous navigation; that is not
    /// something to show the user an error page for.
    @Test func cancelledNavigationIsNotAPageFailure() {
        let cancelled = URLError(.cancelled)

        #expect(PlaylistLinkBrowserView.isReportableLoadFailure(cancelled) == false)
    }

    @Test func offlineIsAPageFailure() {
        let offline = URLError(.notConnectedToInternet)

        #expect(PlaylistLinkBrowserView.isReportableLoadFailure(offline))
    }

    // MARK: - Helpers

    private static func jsonResponse(_ data: Data, for url: URL) throws -> (Data, URLResponse) {
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (data, response)
    }
}
