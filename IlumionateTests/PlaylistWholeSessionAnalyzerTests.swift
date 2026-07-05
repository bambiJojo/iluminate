//
//  PlaylistWholeSessionAnalyzerTests.swift
//  IlumionateTests
//
//  Verifies fast playlist-level analysis from already analyzed audio files.
//

import Foundation
import Testing
@testable import Ilumionate

struct PlaylistWholeSessionAnalyzerTests {

    @Test func buildsWholeJourneyFromRoleNamedTracks() throws {
        let files = [
            analyzedFile(filename: "calm-induction.m4a", duration: 120),
            analyzedFile(filename: "deepener.m4a", duration: 180),
            analyzedFile(filename: "confidence-suggestions.m4a", duration: 240),
            analyzedFile(filename: "awakener.m4a", duration: 90)
        ]
        let playlist = playlist(named: "DIY Session", files: files)

        let result = try PlaylistWholeSessionAnalyzer().build(
            playlist: playlist,
            audioFiles: files
        )

        let phases = try #require(result.analysis.hypnosisMetadata?.phases.map(\.phase))
        #expect(phases == [.induction, .deepening, .suggestions, .emergence])
        #expect(result.summary.sourceSignature == playlist.sourceSignature)
        #expect(result.summary.trackCount == 4)
        #expect(result.summary.contentType == .hypnosis)
        #expect(result.summary.phaseSummary == "Induction -> Deepening -> Suggestions -> Emergence")
        #expect(result.virtualAudioFile.duration == 630)

        let phaseTimeline = try #require(result.analysis.hypnosisMetadata?.phases)
        #expect(phaseTimeline[0].startTime == 0)
        #expect(phaseTimeline[0].endTime == 120)
        #expect(phaseTimeline[1].startTime == 120)
        #expect(phaseTimeline[1].endTime == 300)
        #expect(phaseTimeline[2].startTime == 300)
        #expect(phaseTimeline[2].endTime == 540)
        #expect(phaseTimeline[3].startTime == 540)
        #expect(phaseTimeline[3].endTime == 630)
    }

    @Test func rejectsPlaylistUntilEveryFileIsAnalyzed() {
        let analyzed = analyzedFile(filename: "induction.m4a", duration: 120)
        var unanalyzed = AudioFile(filename: "suggestions.m4a", duration: 120, fileSize: 1024)
        unanalyzed.analysisResult = nil
        let playlist = playlist(named: "Incomplete", files: [analyzed, unanalyzed])

        #expect(throws: PlaylistWholeSessionAnalysisError.self) {
            try PlaylistWholeSessionAnalyzer().build(
                playlist: playlist,
                audioFiles: [analyzed, unanalyzed]
            )
        }
    }

    @Test func sourceSignatureChangesWhenPlaylistOrderChanges() {
        let induction = analyzedFile(filename: "induction.m4a", duration: 120)
        let suggestions = analyzedFile(filename: "suggestions.m4a", duration: 120)
        let original = playlist(named: "Original", files: [induction, suggestions])
        let reordered = playlist(named: "Reordered", files: [suggestions, induction])

        #expect(original.sourceSignature != reordered.sourceSignature)
    }

    private func analyzedFile(filename: String, duration: TimeInterval) -> AudioFile {
        var file = AudioFile(filename: filename, duration: duration, fileSize: 1024)
        file.analysisResult = AnalysisFixtures.hypnosisAnalysis
        return file
    }

    private func playlist(named name: String, files: [AudioFile]) -> Playlist {
        Playlist(
            name: name,
            items: files.map { file in
                PlaylistItem(
                    audioFileId: file.id,
                    filename: file.filename,
                    duration: file.duration
                )
            }
        )
    }
}
