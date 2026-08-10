//
//  BambiCloudPlaylistImportTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct BambiCloudPlaylistImportTests {
    @Test func sharedPlaylistLinkProducesPublicAPIRequest() throws {
        let link = try BambiCloudPlaylistLink(
            "https://bambicloud.com/playlist/69b12112-e603-428a-aeb5-9f204481da13"
        )

        #expect(link.playlistID.uuidString.lowercased() == "69b12112-e603-428a-aeb5-9f204481da13")
        #expect(
            link.apiURL.absoluteString
                == "https://api.bambicloud.com/playlists?uuid=69b12112-e603-428a-aeb5-9f204481da13"
        )
    }

    @Test func lookalikeHostIsRejectedBeforeAnyNetworkRequest() {
        #expect(throws: PlaylistLinkImportError.unsupportedLink) {
            try BambiCloudPlaylistLink(
                "https://bambicloud.com.attacker.example/playlist/69b12112-e603-428a-aeb5-9f204481da13"
            )
        }
    }

    @Test func publicAPIResponsePreservesTrackOrderAndConvertsDurations() throws {
        let playlistID = try #require(
            UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13")
        )
        let data = Data(
            """
            {
              "playlists": [{
                "uuid": "\(playlistID.uuidString.lowercased())",
                "name": "Shared Journey",
                "description": "A public playlist",
                "expLevel": "Beginner",
                "files": [
                  {
                    "uuid": "c311778b-d79b-4f3a-8729-3474cda134b4",
                    "name": "First Track",
                    "duration": 876000,
                    "fileType": "induction",
                    "trackNum": 1
                  },
                  {
                    "uuid": "fae12a04-ddf7-41a8-a448-e124282fdf34",
                    "name": "Second Track",
                    "duration": 1390000,
                    "fileType": "deepener",
                    "trackNum": 2
                  }
                ]
              }]
            }
            """.utf8
        )

        let playlist = try BambiCloudPlaylist.decode(
            from: data,
            expectedID: playlistID
        )

        #expect(playlist.name == "Shared Journey")
        #expect(playlist.tracks.map(\.name) == ["First Track", "Second Track"])
        #expect(playlist.tracks.map(\.duration) == [876, 1_390])
    }

    @Test func clientLoadsAValidatedSharedPlaylist() async throws {
        let data = Data(
            """
            {
              "playlists": [{
                "uuid": "69b12112-e603-428a-aeb5-9f204481da13",
                "name": "Fetched Journey",
                "files": []
              }]
            }
            """.utf8
        )
        let responseURL = try #require(
            URL(string: "https://api.bambicloud.com/playlists")
        )
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        let client = BambiCloudPlaylistClient { request in
            #expect(request.url?.host() == "api.bambicloud.com")
            return (data, response)
        }

        let playlist = try await client.fetchPlaylist(
            from: "https://bambicloud.com/playlist/69b12112-e603-428a-aeb5-9f204481da13"
        )

        #expect(playlist.name == "Fetched Journey")
    }

    @Test func importerKeepsRemoteOrderAndUsesOnlyMatchedLocalAudio() throws {
        let remotePlaylist = try decodePlaylist(
            name: "Imported Journey",
            tracks: [
                (
                    "c311778b-d79b-4f3a-8729-3474cda134b4",
                    "Instant Bimbo Sleepdoll",
                    876_000
                ),
                (
                    "b4375398-85e1-4708-93c0-a7cd5c820a6d",
                    "A Track The User Does Not Own",
                    200_000
                ),
                (
                    "8eca4b4a-ba32-480f-b90f-9bd8eb54ebb7",
                    "Bimbodoll Sleepener",
                    452_000
                )
            ]
        )
        let firstID = UUID()
        let finalID = UUID()
        let localFiles = [
            AudioFile(
                id: finalID,
                filename: "08 - Bimbodoll Sleepener.m4a",
                duration: 452,
                fileSize: 2_000
            ),
            AudioFile(
                id: firstID,
                filename: "01 - Instant Bimbo Sleepdoll.mp3",
                duration: 875.5,
                fileSize: 3_000
            )
        ]

        let plan = BambiCloudPlaylistImporter().makePlan(
            for: remotePlaylist,
            availableAudioFiles: localFiles
        )
        let playlist = try #require(plan.makePlaylist())

        #expect(plan.rows.map(\.status) == [.exact, .missing, .exact])
        #expect(plan.rows.map(\.selectedAudioFileID) == [firstID, nil, finalID])
        #expect(playlist.name == "Imported Journey")
        #expect(playlist.items.map(\.audioFileId) == [firstID, finalID])
    }

    @Test func duplicateLocalTitlesWaitForManualSelection() throws {
        let remotePlaylist = try decodePlaylist(
            name: "Ambiguous Journey",
            tracks: [
                (
                    "c311778b-d79b-4f3a-8729-3474cda134b4",
                    "Instant Bimbo Sleepdoll",
                    876_000
                )
            ]
        )
        let first = AudioFile(
            filename: "Instant Bimbo Sleepdoll.mp3",
            duration: 876,
            fileSize: 1_000
        )
        let second = AudioFile(
            filename: "Instant Bimbo Sleepdoll copy.m4a",
            duration: 876,
            fileSize: 1_000,
            userTitle: "Instant Bimbo Sleepdoll"
        )

        var plan = BambiCloudPlaylistImporter().makePlan(
            for: remotePlaylist,
            availableAudioFiles: [first, second]
        )

        #expect(plan.rows.first?.status == .needsReview)
        #expect(plan.rows.first?.selectedAudioFileID == nil)

        let firstRowID = try #require(plan.rows.first?.id)
        plan.select(audioFileID: second.id, forRow: firstRowID)

        #expect(plan.rows.first?.status == .manual)
        #expect(plan.makePlaylist()?.items.map(\.audioFileId) == [second.id])
    }

    private func decodePlaylist(
        name: String,
        tracks: [(id: String, name: String, duration: Int)]
    ) throws -> BambiCloudPlaylist {
        let playlistID = try #require(
            UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13")
        )
        let trackJSON = tracks.map { track in
            """
            {
              "uuid": "\(track.id)",
              "name": "\(track.name)",
              "duration": \(track.duration)
            }
            """
        }
        .joined(separator: ",")
        let data = Data(
            """
            {
              "playlists": [{
                "uuid": "\(playlistID.uuidString.lowercased())",
                "name": "\(name)",
                "files": [\(trackJSON)]
              }]
            }
            """.utf8
        )
        return try BambiCloudPlaylist.decode(
            from: data,
            expectedID: playlistID
        )
    }

    // The user's actual complaint: a second playlist sharing tracks with the
    // first re-downloaded every one of them. Provenance makes that free.
    @Test func aPreviouslyDownloadedTrackIsNotRequestedAgain() async throws {
        let playlistID = try #require(UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13"))
        let trackID = try #require(UUID(uuidString: "c311778b-d79b-4f3a-8729-3474cda134b4"))
        let data = Data(
            """
            {"playlists":[{"uuid":"\(playlistID.uuidString.lowercased())","name":"Second",
             "files":[{"uuid":"\(trackID.uuidString.lowercased())","name":"Shared Track",
             "duration":600000,"audioURL":"https://cdn.bambicloud.com/shared.mp3","trackNum":1}]}]}
            """.utf8
        )
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        var owned = AudioFile(
            filename: "Something The Matcher Will Never Guess.mp3",
            duration: 600,
            fileSize: 5_000_000
        )
        owned.remoteSource = RemoteAudioSource(
            service: RemoteAudioSource.bambiCloudService,
            trackID: trackID.uuidString,
            url: try #require(URL(string: "https://cdn.bambicloud.com/shared.mp3"))
        )

        let model = BambiCloudPlaylistImportViewModel(
            availableAudioFiles: [owned],
            downloader: PlaylistTrackDownloader(
                documentsURL: URL.temporaryDirectory
            ) { _ in
                Issue.record("A track already in the library was downloaded again")
                throw PlaylistTrackDownloadError.networkUnavailable
            },
            isAutoAnalyseEnabled: { false }
        )
        model.adoptPlanForTesting(
            BambiCloudPlaylistImporter().makePlan(
                for: playlist,
                availableAudioFiles: [owned]
            )
        )

        let row = try #require(model.plan?.rows.first)
        await model.downloadRow(row)

        #expect(model.plan?.rows.first?.selectedAudioFileID == owned.id)
        #expect(model.plan?.rows.first?.status == .exact)
        #expect(model.downloadErrors.isEmpty)
    }

    // With the old normalizer both local files reduced to "bambi sleep", so
    // row 01 claimed one, row 02 found it taken, and row 02 was downloaded.
    @Test func aNumberedSeriesMatchesRowForRow() throws {
        let playlistID = try #require(UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13"))
        let data = Data(
            """
            {"playlists":[{"uuid":"\(playlistID.uuidString.lowercased())","name":"Series","files":[
             {"uuid":"\(UUID().uuidString)","name":"01 Bambi Sleep","duration":600000,"trackNum":1},
             {"uuid":"\(UUID().uuidString)","name":"02 Bambi Sleep","duration":600000,"trackNum":2}
            ]}]}
            """.utf8
        )
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        let first = AudioFile(filename: "01 Bambi Sleep.mp3", duration: 600, fileSize: 1)
        let second = AudioFile(filename: "02 Bambi Sleep.mp3", duration: 600, fileSize: 2)

        let plan = BambiCloudPlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: [first, second]
        )

        #expect(plan.rows[0].selectedAudioFileID == first.id)
        #expect(plan.rows[1].selectedAudioFileID == second.id)
        #expect(plan.downloadableRows.isEmpty)
    }

    @Test func theSourceFilenameMatchesWhenTheTitleDoesNot() throws {
        let playlistID = try #require(UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13"))
        let data = Data(
            """
            {"playlists":[{"uuid":"\(playlistID.uuidString.lowercased())","name":"P","files":[
             {"uuid":"\(UUID().uuidString)","name":"Bambi Sleep — Uniform Acceptance",
              "duration":600000,
              "audioURL":"https://cdn.bambicloud.com/bs-uniform-acceptance.mp3","trackNum":1}
            ]}]}
            """.utf8
        )
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        let local = AudioFile(
            filename: "bs-uniform-acceptance.mp3",
            duration: 600,
            fileSize: 1
        )

        let plan = BambiCloudPlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: [local]
        )

        #expect(plan.rows[0].selectedAudioFileID == local.id)
    }

    @Test func aLikelyDuplicateIsOfferedRatherThanDownloaded() async throws {
        let playlistID = try #require(UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13"))
        let data = Data(
            """
            {"playlists":[{"uuid":"\(playlistID.uuidString.lowercased())","name":"P","files":[
             {"uuid":"\(UUID().uuidString)","name":"Renamed Beyond Recognition","duration":600000,
              "audioURL":"https://cdn.bambicloud.com/x.mp3","trackNum":1}
            ]}]}
            """.utf8
        )
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        // Same byte size and duration — strong, but not conclusive.
        let owned = AudioFile(
            filename: "Original Name.mp3",
            duration: 600,
            fileSize: 5_000_000
        )

        let model = BambiCloudPlaylistImportViewModel(
            availableAudioFiles: [owned],
            downloader: PlaylistTrackDownloader(
                documentsURL: URL.temporaryDirectory,
                probe: { _ in
                    (Data(), URLResponse(
                        url: URL(string: "https://cdn.bambicloud.com/x.mp3")!,
                        mimeType: nil,
                        expectedContentLength: 5_000_000,
                        textEncodingName: nil
                    ))
                }
            ) { _ in
                Issue.record("A likely duplicate was downloaded without asking")
                throw PlaylistTrackDownloadError.networkUnavailable
            },
            isAutoAnalyseEnabled: { false }
        )
        model.adoptPlanForTesting(
            BambiCloudPlaylistImporter().makePlan(
                for: playlist,
                availableAudioFiles: [owned]
            )
        )

        let row = try #require(model.plan?.rows.first)
        await model.requestDownload(of: row)

        #expect(model.plan?.rows.first?.status == .possibleDuplicate(existing: owned.id))
        #expect(model.plan?.rows.first?.selectedAudioFileID == nil)
    }

    @Test func useExistingResolvesAPossibleDuplicate() throws {
        let owned = AudioFile(filename: "Original Name.mp3", duration: 600, fileSize: 5_000_000)
        let playlistID = try #require(UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13"))
        let data = Data(
            """
            {"playlists":[{"uuid":"\(playlistID.uuidString.lowercased())","name":"P","files":[
             {"uuid":"\(UUID().uuidString)","name":"Renamed Beyond Recognition","duration":600000,
              "audioURL":"https://cdn.bambicloud.com/x.mp3","trackNum":1}]}]}
            """.utf8
        )
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        var plan = BambiCloudPlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: [owned]
        )
        let rowID = try #require(plan.rows.first?.id)

        plan.markPossibleDuplicate(existing: owned.id, forRow: rowID)
        #expect(plan.rows[0].status == .possibleDuplicate(existing: owned.id))

        plan.select(audioFileID: owned.id, forRow: rowID)
        #expect(plan.rows[0].selectedAudioFileID == owned.id)
        #expect(plan.downloadableRows.isEmpty)
    }

    // BambiCloud numbers its tracks from zero, so a user's 1-based "01 …"
    // filename prefix is a different namespace from `trackNum`. Comparing the
    // two made every file conflict with the track it belonged to, rejecting a
    // whole numbered library at once.
    @Test func aZeroBasedPublisherNumberIsNotComparedToAFilenamePrefix() throws {
        let playlistID = try #require(UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13"))
        let data = Data(
            """
            {"playlists":[{"uuid":"\(playlistID.uuidString.lowercased())","name":"P","files":[
             {"uuid":"\(UUID().uuidString)","name":"Rapid Induction","duration":162000,"trackNum":0},
             {"uuid":"\(UUID().uuidString)","name":"Bubble Induction","duration":300000,"trackNum":1}
            ]}]}
            """.utf8
        )
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        let first = AudioFile(filename: "01 Rapid Induction.mp3", duration: 162, fileSize: 1)
        let second = AudioFile(filename: "02 Bubble Induction.mp3", duration: 300, fileSize: 2)

        let plan = BambiCloudPlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: [first, second]
        )

        #expect(plan.rows[0].selectedAudioFileID == first.id)
        #expect(plan.rows[1].selectedAudioFileID == second.id)
    }
}
