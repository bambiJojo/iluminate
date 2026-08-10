//
//  PlaylistTrackBindingTests.swift
//  IlumionateTests
//
//  A playlist must not lose a track just because the library re-registered it
//  under a new identifier.
//

import Foundation
import Testing
@testable import Ilumionate

struct PlaylistTrackBindingTests {

    @Test("An item resolves to the entry it records")
    func resolvesByIdentifier() {
        let file = analyzedFile(filename: "induction.m4a")
        let item = PlaylistItem(audioFileId: file.id, filename: file.filename, duration: 120)

        #expect(PlaylistTrackBinding.resolve(item, in: [file])?.id == file.id)
    }

    /// The reported bug: the Library shows the track analyzed, the playlist
    /// shows it unanalyzed and refuses to build a whole journey, because the
    /// entry the item points at was retired and re-registered under a new UUID.
    @Test("An item orphaned by re-registration resolves by filename")
    func resolvesByFilenameWhenIdentifierIsRetired() {
        let reRegistered = analyzedFile(filename: "induction.m4a")
        let item = PlaylistItem(
            audioFileId: UUID(),
            filename: "induction.m4a",
            duration: 120
        )

        let resolved = PlaylistTrackBinding.resolve(item, in: [reRegistered])

        #expect(resolved?.id == reRegistered.id)
        #expect(resolved?.isAnalyzed == true)
    }

    @Test("Filename matching ignores case and directory")
    func filenameMatchIgnoresCaseAndPath() {
        let stored = analyzedFile(filename: "/Users/someone/Documents/Induction.M4A")
        let item = PlaylistItem(audioFileId: UUID(), filename: "induction.m4a", duration: 120)

        #expect(PlaylistTrackBinding.resolve(item, in: [stored])?.id == stored.id)
    }

    /// A retired entry can outlive its replacement in the stored list. Healing
    /// to the copy without analysis would leave the track looking unanalyzed.
    @Test("A duplicated filename heals to the analyzed copy")
    func prefersTheAnalyzedDuplicate() {
        let stale = AudioFile(filename: "induction.m4a", duration: 120, fileSize: 1024)
        let analyzed = analyzedFile(filename: "induction.m4a")
        let item = PlaylistItem(audioFileId: UUID(), filename: "induction.m4a", duration: 120)

        let resolved = PlaylistTrackBinding.resolve(item, in: [stale, analyzed])

        #expect(resolved?.id == analyzed.id)
    }

    @Test("An item with no counterpart resolves to nothing")
    func returnsNilWhenTheAudioIsGone() {
        let other = analyzedFile(filename: "deepener.m4a")
        let item = PlaylistItem(audioFileId: UUID(), filename: "induction.m4a", duration: 120)

        #expect(PlaylistTrackBinding.resolve(item, in: [other]) == nil)
    }

    @Test("Rebinding heals an orphaned identifier and keeps the item's own id")
    func rebindingHealsOrphanedIdentifiers() {
        let file = analyzedFile(filename: "induction.m4a")
        let item = PlaylistItem(audioFileId: UUID(), filename: "induction.m4a", duration: 120)

        let rebound = PlaylistTrackBinding.rebinding([item], to: [file])

        #expect(rebound.count == 1)
        #expect(rebound[0].audioFileId == file.id)
        #expect(rebound[0].id == item.id)
        #expect(rebound[0].duration == item.duration)
        #expect(rebound[0].filename == item.filename)
    }

    @Test("Rebinding leaves healthy and unresolvable items untouched")
    func rebindingIsInertWhenThereIsNothingToHeal() {
        let file = analyzedFile(filename: "induction.m4a")
        let healthy = PlaylistItem(audioFileId: file.id, filename: file.filename, duration: 120)
        let orphan = PlaylistItem(audioFileId: UUID(), filename: "gone.m4a", duration: 90)

        let rebound = PlaylistTrackBinding.rebinding([healthy, orphan], to: [file])

        #expect(rebound[0].audioFileId == healthy.audioFileId)
        #expect(rebound[1].audioFileId == orphan.audioFileId)
    }

    /// End to end: the whole-journey build is what the listener sees disabled,
    /// so it has to accept a playlist whose identifiers drifted.
    @Test("A whole journey builds across re-registered tracks")
    func wholeJourneyBuildsAfterReRegistration() throws {
        let files = [
            analyzedFile(filename: "calm-induction.m4a", duration: 120),
            analyzedFile(filename: "deepener.m4a", duration: 180)
        ]
        let items = files.map {
            PlaylistItem(
                audioFileId: UUID(),
                filename: $0.filename,
                duration: $0.duration
            )
        }
        let playlist = Playlist(name: "Re-registered", items: items)

        let result = try PlaylistWholeSessionAnalyzer().build(
            playlist: playlist,
            audioFiles: files
        )

        #expect(result.summary.trackCount == 2)
    }

    /// `Dictionary(uniqueKeysWithValues:)` traps on a repeated key, so a library
    /// holding the same identifier twice used to crash the build outright.
    @Test("A duplicated identifier in the library does not trap")
    func duplicateIdentifiersDoNotTrap() throws {
        let file = analyzedFile(filename: "induction.m4a", duration: 120)
        let playlist = Playlist(
            name: "Duplicated",
            items: [PlaylistItem(audioFileId: file.id, filename: file.filename, duration: 120)]
        )

        let result = try PlaylistWholeSessionAnalyzer().build(
            playlist: playlist,
            audioFiles: [file, file]
        )

        #expect(result.summary.trackCount == 1)
    }

    // MARK: - Fixtures

    private func analyzedFile(filename: String, duration: TimeInterval = 120) -> AudioFile {
        var file = AudioFile(filename: filename, duration: duration, fileSize: 1024)
        file.analysisResult = AnalysisFixtures.hypnosisAnalysis
        return file
    }
}
