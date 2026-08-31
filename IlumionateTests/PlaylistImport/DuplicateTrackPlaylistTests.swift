//
//  DuplicateTrackPlaylistTests.swift
//  IlumionateTests
//
//  A playlist may list the same track more than once. Keying rows by track ID
//  collapsed those into one row: SwiftUI reported duplicate ForEach IDs, and
//  every per-row action silently hit only the first copy.
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct DuplicateTrackPlaylistTests {
    private func playlistRepeatingATrack() throws -> SourcePlaylist {
        let playlistID = UUID()
        let repeatedTrackID = UUID()
        let json = """
        {"playlists":[{"uuid":"\(playlistID.uuidString)","name":"Repeats","files":[
        {"uuid":"\(repeatedTrackID.uuidString)","name":"Fuck Doll","duration":600000,
         "audioURL":"https://cdn.example.com/dup.mp3","trackNum":0},
        {"uuid":"\(UUID().uuidString)","name":"Something Else","duration":300000,
         "audioURL":"https://cdn.example.com/other.mp3","trackNum":1},
        {"uuid":"\(repeatedTrackID.uuidString)","name":"Fuck Doll","duration":600000,
         "audioURL":"https://cdn.example.com/dup.mp3","trackNum":2}
        ]}]}
        """
        return try GenericPlaylistJSON.playlist(from: Data(json.utf8))
    }

    private func plan() throws -> PlaylistImportPlan {
        PlaylistImporter().makePlan(
            for: try playlistRepeatingATrack(),
            availableAudioFiles: []
        )
    }

    /// The ForEach warning in the Mac console came from this.
    @Test func repeatedTrackStillProducesUniqueRowIdentities() throws {
        let plan = try plan()

        #expect(plan.rows.count == 3)
        #expect(Set(plan.rows.map(\.id)).count == 3)
    }

    /// Every repeat must be independently actionable, not just the first.
    @Test func everyRepeatIsOfferedAsDownloadable() throws {
        let plan = try plan()

        #expect(plan.downloadableRows.count == 3)
    }

    /// Choosing a file for the third row must not silently land on the first.
    @Test func selectingOnARepeatUpdatesThatRowOnly() throws {
        var plan = try plan()
        let file = AudioFile(filename: "Fuck Doll.mp3", duration: 600, fileSize: 10)
        plan = PlaylistImporter().makePlan(
            for: try playlistRepeatingATrack(),
            availableAudioFiles: [file]
        )

        let lastRowID = try #require(plan.rows.last?.id)
        plan.select(audioFileID: file.id, forRow: lastRowID)

        #expect(plan.rows.last?.selectedAudioFileID == file.id)
        #expect(plan.rows.last?.status == .manual)
    }

    /// Downloading a repeated track fills every copy of it, so the user is not
    /// asked to fetch the same audio twice.
    @Test func downloadedFileFillsEveryCopyOfThatTrack() throws {
        var plan = try plan()
        let downloaded = AudioFile(
            filename: "Fuck Doll.mp3",
            duration: 600,
            fileSize: 10
        )

        let firstRowID = try #require(plan.rows.first?.id)
        plan.adopt(downloadedFile: downloaded, forRow: firstRowID)

        let repeatedRows = plan.rows.filter { $0.track.title == "Fuck Doll" }
        #expect(repeatedRows.count == 2)
        #expect(repeatedRows.allSatisfy { $0.selectedAudioFileID == downloaded.id })
        #expect(repeatedRows.allSatisfy { $0.status == .downloaded })
        // The unrelated track is untouched.
        #expect(plan.rows[1].selectedAudioFileID == nil)
    }

    /// A repeated track contributes an item per appearance, preserving order.
    @Test func repeatedTrackAppearsTwiceInTheImportedPlaylist() throws {
        var plan = try plan()
        let downloaded = AudioFile(
            filename: "Fuck Doll.mp3",
            duration: 600,
            fileSize: 10
        )
        let firstRowID = try #require(plan.rows.first?.id)
        plan.adopt(downloadedFile: downloaded, forRow: firstRowID)

        let playlist = try #require(plan.makePlaylist())

        #expect(playlist.items.count == 2)
        #expect(playlist.items.allSatisfy { $0.audioFileId == downloaded.id })
    }
}
