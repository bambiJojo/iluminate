import Foundation
import Testing
@testable import Ilumionate

struct BambiCloudPlaylistLinkTests {
    @Test func convertsPublicShareLinkToAPIAddress() throws {
        let link = try #require(
            BambiCloudPlaylistLink(
                "https://bambicloud.com/playlist/69b12112-e603-428a-aeb5-9f204481da13"
            )
        )

        #expect(link.playlistID.uuidString.lowercased() == "69b12112-e603-428a-aeb5-9f204481da13")
        #expect(
            link.apiURL.absoluteString
                == "https://api.bambicloud.com/playlists?uuid=69b12112-e603-428a-aeb5-9f204481da13"
        )
    }

    @Test func rejectsLookalikeHost() {
        let link = BambiCloudPlaylistLink(
            "https://bambicloud.com.attacker.example/playlist/69b12112-e603-428a-aeb5-9f204481da13"
        )

        #expect(link == nil)
    }

    @Test func sourceClientUsesBambiAPIForShareLink() async throws {
        let expectedID = UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13")!
        let response = """
        {"playlists":[{"id":"\(expectedID.uuidString.lowercased())","name":"My Bambi Playlist","tracks":[{"id":"track-1","name":"First Track","duration":120000,"audioURL":"https://cdn.bambicloud.com/first.mp3","trackNum":1}]}]}
        """.data(using: .utf8)!

        let client = PlaylistSourceClient { url in
            #expect(
                url.absoluteString
                    == "https://api.bambicloud.com/playlists?uuid=69b12112-e603-428a-aeb5-9f204481da13"
            )
            return (
                response,
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }

        let result = try await client.playlist(
            at: "https://bambicloud.com/playlist/69b12112-e603-428a-aeb5-9f204481da13"
        )

        #expect(result.playlist.title == "My Bambi Playlist")
        #expect(result.playlist.tracks.count == 1)
        #expect(result.sourceURL.host() == "api.bambicloud.com")
    }
}
