//
//  DuplicateAudioReviewViewModelTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct DuplicateAudioReviewViewModelTests {

    private func makeFile(_ filename: String, fingerprint: String = "shared") -> AudioFile {
        AudioFile(
            filename: filename,
            duration: 600,
            fileSize: 5_000_000,
            contentFingerprint: fingerprint
        )
    }

    @Test("Only selected groups are merged")
    func mergesOnlySelectedGroups() {
        let a = makeFile("Track.mp3")
        let b = makeFile("Track (1).mp3")
        let c = makeFile("Other.mp3", fingerprint: "other")
        let d = makeFile("Other (1).mp3", fingerprint: "other")

        let model = DuplicateAudioReviewViewModel(audioFiles: [a, b, c, d])
        #expect(model.groups.count == 2)

        let firstGroupID = model.groups[0].id
        model.setSelected(false, groupID: model.groups[1].id)

        let result = model.resolution()

        #expect(result.merged.count == 1)
        #expect(result.removed.count == 1)
        #expect(model.groups[0].id == firstGroupID)
    }

    @Test("A merge removes the redundant rows and keeps the merged keeper")
    func resolutionReplacesTheLibrary() {
        var a = makeFile("Track.mp3")
        a.playCount = 2
        var b = makeFile("Track (1).mp3")
        b.playCount = 3

        let model = DuplicateAudioReviewViewModel(audioFiles: [a, b])
        let result = model.resolution()

        #expect(result.audioFiles.count == 1)
        #expect(result.audioFiles[0].playCount == 5)
        #expect(result.removed.count == 1)
    }

    @Test("Nothing selected means nothing changes")
    func nothingSelectedChangesNothing() {
        let a = makeFile("Track.mp3")
        let b = makeFile("Track (1).mp3")

        let model = DuplicateAudioReviewViewModel(audioFiles: [a, b])
        model.setSelected(false, groupID: model.groups[0].id)

        let result = model.resolution()

        #expect(result.audioFiles.count == 2)
        #expect(result.removed.isEmpty)
        #expect(result.merged.isEmpty)
    }

    @Test("A library with no duplicates offers nothing to do")
    func noDuplicatesOffersNothing() {
        let model = DuplicateAudioReviewViewModel(
            audioFiles: [makeFile("A.mp3", fingerprint: "a"), makeFile("B.mp3", fingerprint: "b")]
        )

        #expect(model.hasDuplicates == false)
        #expect(model.removableCount == 0)
    }
}
