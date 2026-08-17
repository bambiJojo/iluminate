//
//  DuplicateAudioMergeTests.swift
//  IlumionateTests
//
//  Merging must never lose the listener's history. A duplicate group commonly
//  holds one copy with the analysis and another with the play count, because
//  the second copy is what the playlist has been playing.
//

import Foundation
import Testing
@testable import Ilumionate

struct DuplicateAudioMergeTests {

    private func makeFile(
        filename: String,
        fingerprint: String? = "shared",
        createdDaysAgo: Int = 0
    ) -> AudioFile {
        AudioFile(
            filename: filename,
            duration: 600,
            fileSize: 5_000_000,
            createdDate: Date(timeIntervalSince1970: 1_000_000 - Double(createdDaysAgo) * 86_400),
            contentFingerprint: fingerprint
        )
    }

    @Test("Files sharing a fingerprint form one group")
    func groupsByFingerprint() {
        let a = makeFile(filename: "Track.mp3")
        let b = makeFile(filename: "Track (1).mp3")
        let unrelated = makeFile(filename: "Other.mp3", fingerprint: "different")

        let groups = DuplicateAudioGroup.groups(in: [a, b, unrelated])

        #expect(groups.count == 1)
        #expect(groups[0].redundant.count == 1)
        #expect(Set([groups[0].keeper.id] + groups[0].redundant.map(\.id)) == Set([a.id, b.id]))
    }

    // A file whose bytes could not be read has no identity to group by, and
    // must not be pooled with every other such file.
    @Test("A file with no fingerprint is never grouped")
    func ungroupedWithoutFingerprint() {
        let a = makeFile(filename: "Track.mp3", fingerprint: nil)
        let b = makeFile(filename: "Track (1).mp3", fingerprint: nil)

        #expect(DuplicateAudioGroup.groups(in: [a, b]).isEmpty)
    }

    @Test("The transcribed copy is kept")
    func keepsTheRicherCopy() {
        var transcribed = makeFile(filename: "Track (1).mp3")
        transcribed.transcription = "seeded"
        let plain = makeFile(filename: "Track.mp3", createdDaysAgo: 5)

        let groups = DuplicateAudioGroup.groups(in: [plain, transcribed])

        #expect(groups[0].keeper.id == transcribed.id)
    }

    @Test("The keeper absorbs what the redundant copies hold")
    func mergeUnionsUserHistory() {
        var keeper = makeFile(filename: "Track.mp3")
        keeper.transcription = "seeded"
        keeper.playCount = 3
        keeper.lastPlayedDate = Date(timeIntervalSince1970: 100)
        keeper.isFavorite = false

        var other = makeFile(filename: "Track (1).mp3")
        other.playCount = 4
        other.lastPlayedDate = Date(timeIntervalSince1970: 900)
        other.isFavorite = true
        other.rating = 5
        other.tags = ["sleep"]
        other.userTitle = "Bedtime"
        other.sessionNotes = "Works well after midnight"

        let merged = DuplicateAudioGroup(keeper: keeper, redundant: [other]).merged()

        #expect(merged.id == keeper.id)
        #expect(merged.playCount == 7)
        #expect(merged.lastPlayedDate == Date(timeIntervalSince1970: 900))
        #expect(merged.isFavorite == true)
        #expect(merged.rating == 5)
        #expect(merged.tags == ["sleep"])
        #expect(merged.userTitle == "Bedtime")
        #expect(merged.sessionNotes == "Works well after midnight")
        // The keeper's own values are never overwritten.
        #expect(merged.transcription == "seeded")
    }

    @Test("Playlist items repoint to the keeper")
    func playlistItemsRepoint() {
        let keeper = makeFile(filename: "Track.mp3")
        let other = makeFile(filename: "Track (1).mp3")
        let group = DuplicateAudioGroup(keeper: keeper, redundant: [other])

        let items = [
            PlaylistItem(audioFileId: other.id, filename: "Track (1).mp3", duration: 600),
            PlaylistItem(audioFileId: keeper.id, filename: "Track.mp3", duration: 600)
        ]

        let rebound = PlaylistTrackBinding.rebinding(
            items,
            to: [keeper],
            remapping: DuplicateAudioGroup.remap(for: [group])
        )

        #expect(rebound.allSatisfy { $0.audioFileId == keeper.id })
    }
}
