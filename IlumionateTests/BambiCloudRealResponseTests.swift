//
//  BambiCloudRealResponseTests.swift
//  IlumionateTests
//
//  Pins the importer against a captured response from the live public API so
//  schema drift and matcher regressions surface here rather than on device.
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct BambiCloudRealResponseTests {
    private static let playlistID = UUID(uuidString: "e5dd01c7-960a-4ccd-8a7f-e6b60c56ed42")!

    private func realResponseData() throws -> Data {
        let url = Bundle(for: BundleMarker.self)
            .url(forResource: "Fixtures_BambiCloudPlaylistResponse", withExtension: "json")
        let resolved = try #require(url)
        return try Data(contentsOf: resolved)
    }

    @Test func liveResponseSchemaStillDecodes() throws {
        let playlist = try BambiCloudPlaylist.decode(
            from: realResponseData(),
            expectedID: Self.playlistID
        )

        #expect(playlist.name == "Bambi Bimbodoll Conditioning")
        #expect(playlist.tracks.count == 11)
        #expect(playlist.tracks.first?.name == "Rapid Induction")
        // Durations arrive as whole milliseconds and must land as seconds.
        #expect(playlist.tracks.first?.duration == 162)
        #expect(playlist.tracks.last?.name == "Bambi Awakens")
    }

    /// Files named exactly like the remote tracks are the easy case.
    @Test func exactlyNamedLocalFilesAllMatch() throws {
        let playlist = try BambiCloudPlaylist.decode(
            from: realResponseData(),
            expectedID: Self.playlistID
        )
        let localFiles = playlist.tracks.map { track in
            AudioFile(
                filename: "\(track.name).mp3",
                duration: track.duration,
                fileSize: 1_000
            )
        }

        let plan = BambiCloudPlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: localFiles
        )

        #expect(plan.matchedCount == 11)
    }

    /// The realistic cases: the same tracks saved with a series prefix, a track
    /// number, or a trailing tag. Two-word titles are most of this catalog, so
    /// they have to survive decoration that carries no matching signal.
    @Test(
        "Decorated filenames still match",
        arguments: [
            "Bambi Sleep - %@.mp3",
            "%@ (Bambi Sleep).mp3",
            "Bambi Sleep %@ [320kbps].mp3"
        ]
    )
    func decoratedLocalFilesStillMatch(pattern: String) throws {
        let playlist = try BambiCloudPlaylist.decode(
            from: realResponseData(),
            expectedID: Self.playlistID
        )
        let localFiles = playlist.tracks.map { track in
            AudioFile(
                filename: String(format: pattern, track.name),
                duration: track.duration,
                fileSize: 1_000
            )
        }

        let plan = BambiCloudPlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: localFiles
        )

        let unmatched = plan.rows.filter { $0.selectedAudioFileID == nil }
        #expect(
            plan.matchedCount == 11,
            "Unmatched with \(pattern): \(unmatched.map(\.track.name))"
        )
    }

    /// Titles here overlap heavily ("Bambi … Lock" three times), so the looser
    /// containment rule must not start assigning the wrong file.
    @Test func numberedLocalFilesMatchTheirOwnTrack() throws {
        let playlist = try BambiCloudPlaylist.decode(
            from: realResponseData(),
            expectedID: Self.playlistID
        )
        let localFiles = playlist.tracks.enumerated().map { index, track in
            AudioFile(
                filename: String(format: "%02d %@.mp3", index + 1, track.name),
                duration: track.duration,
                fileSize: 1_000
            )
        }

        let plan = BambiCloudPlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: localFiles
        )

        #expect(plan.matchedCount == 11)
        for row in plan.rows {
            let selected = localFiles.first { $0.id == row.selectedAudioFileID }
            #expect(
                selected?.filename.contains(row.track.name) == true,
                "\(row.track.name) resolved to \(selected?.filename ?? "nothing")"
            )
        }
    }
}

private final class BundleMarker {}
