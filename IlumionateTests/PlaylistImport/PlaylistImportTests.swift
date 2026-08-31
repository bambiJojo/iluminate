//
//  PlaylistImportTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct PlaylistImportTests {
    @Test func emptyLibraryCanStartPlaylistImport() {
        let route = PlaylistImportContentRoute.resolve(hasPlan: false)

        #expect(route == .linkEntry)
    }

    @Test func emptyLibraryCanReviewLoadedPlaylist() {
        let route = PlaylistImportContentRoute.resolve(hasPlan: true)

        #expect(route == .review)
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

        let playlist = try GenericPlaylistJSON.playlist(from: data)

        #expect(playlist.title == "Shared Journey")
        #expect(playlist.tracks.map(\.title) == ["First Track", "Second Track"])
        #expect(playlist.tracks.map(\.duration) == [876, 1_390])
    }

    @Test func clientLoadsAValidatedSharedPlaylist() async throws {
        let data = Data(
            """
            {
              "playlists": [{
                "uuid": "69b12112-e603-428a-aeb5-9f204481da13",
                "name": "Fetched Journey",
                "files": [{
                  "uuid": "c311778b-d79b-4f3a-8729-3474cda134b4",
                  "name": "Opening Track",
                  "duration": 162000
                }]
              }]
            }
            """.utf8
        )
        let responseURL = try #require(
            URL(string: "https://api.example.com/playlists")
        )
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        let client = PlaylistSourceClient { requestURL in
            #expect(requestURL.host() == "api.example.com")
            return (data, response)
        }

        // The address the user pastes is the address that is fetched. Deriving
        // a data endpoint from a page address was site knowledge and is gone.
        let result = try await client.playlist(
            at: "https://api.example.com/playlists?uuid=69b12112-e603-428a-aeb5-9f204481da13"
        )

        #expect(result.playlist.title == "Fetched Journey")
        #expect(result.sourceURL.host() == "api.example.com")
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

        let plan = PlaylistImporter().makePlan(
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

        var plan = PlaylistImporter().makePlan(
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
    ) throws -> SourcePlaylist {
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
        return try GenericPlaylistJSON.playlist(from: data)
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
             "duration":600000,"audioURL":"https://cdn.example.com/shared.mp3","trackNum":1}]}]}
            """.utf8
        )
        let playlist = try GenericPlaylistJSON.playlist(from: data)

        var owned = AudioFile(
            filename: "Something The Matcher Will Never Guess.mp3",
            duration: 600,
            fileSize: 5_000_000
        )
        let sharedURL = try #require(URL(string: "https://cdn.example.com/shared.mp3"))
        owned.remoteSource = RemoteAudioSource(
            service: RemoteAudioSource.service(for: sharedURL),
            trackID: trackID.uuidString,
            url: sharedURL
        )

        let model = PlaylistImportViewModel(
            availableAudioFiles: [owned],
            downloader: PlaylistTrackDownloader(
                documentsURL: URL.temporaryDirectory,
                playlistSource: URL(string: "https://api.example.com/list.json")
            ) { _ in
                Issue.record("A track already in the library was downloaded again")
                throw PlaylistTrackDownloadError.networkUnavailable
            },
            isAutoAnalyseEnabled: { false }
        )
        model.adoptPlanForTesting(
            PlaylistImporter().makePlan(
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
        let playlist = try GenericPlaylistJSON.playlist(from: data)

        let first = AudioFile(filename: "01 Bambi Sleep.mp3", duration: 600, fileSize: 1)
        let second = AudioFile(filename: "02 Bambi Sleep.mp3", duration: 600, fileSize: 2)

        let plan = PlaylistImporter().makePlan(
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
              "audioURL":"https://cdn.example.com/bs-uniform-acceptance.mp3","trackNum":1}
            ]}]}
            """.utf8
        )
        let playlist = try GenericPlaylistJSON.playlist(from: data)

        let local = AudioFile(
            filename: "bs-uniform-acceptance.mp3",
            duration: 600,
            fileSize: 1
        )

        let plan = PlaylistImporter().makePlan(
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
              "audioURL":"https://cdn.example.com/x.mp3","trackNum":1}
            ]}]}
            """.utf8
        )
        let playlist = try GenericPlaylistJSON.playlist(from: data)

        // Same byte size and duration — strong, but not conclusive.
        let owned = AudioFile(
            filename: "Original Name.mp3",
            duration: 600,
            fileSize: 5_000_000
        )

        let model = PlaylistImportViewModel(
            availableAudioFiles: [owned],
            downloader: PlaylistTrackDownloader(
                documentsURL: URL.temporaryDirectory,
                playlistSource: URL(string: "https://api.example.com/list.json"),
                probe: { _ in
                    (Data(), URLResponse(
                        url: URL(string: "https://cdn.example.com/x.mp3")!,
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
            PlaylistImporter().makePlan(
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
              "audioURL":"https://cdn.example.com/x.mp3","trackNum":1}]}]}
            """.utf8
        )
        let playlist = try GenericPlaylistJSON.playlist(from: data)

        var plan = PlaylistImporter().makePlan(
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
        let playlist = try GenericPlaylistJSON.playlist(from: data)

        let first = AudioFile(filename: "01 Rapid Induction.mp3", duration: 162, fileSize: 1)
        let second = AudioFile(filename: "02 Bubble Induction.mp3", duration: 300, fileSize: 2)

        let plan = PlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: [first, second]
        )

        #expect(plan.rows[0].selectedAudioFileID == first.id)
        #expect(plan.rows[1].selectedAudioFileID == second.id)
    }
}
