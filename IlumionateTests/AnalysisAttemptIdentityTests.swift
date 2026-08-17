//
//  AnalysisAttemptIdentityTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

private func makeAudioFile(id: UUID = UUID()) -> AudioFile {
    AudioFile(
        id: id,
        filename: "test_\(id.uuidString).m4a",
        duration: 300,
        fileSize: 1_024_000,
        createdDate: Date(timeIntervalSince1970: 0)
    )
}

@MainActor
struct AnalysisAttemptIdentityTests {

    @Test func eachActiveAnalysisGetsADistinctAttemptID() {
        let file = makeAudioFile()
        let first = ActiveAnalysis(audioFile: file, stage: .starting, progress: 0)
        let second = ActiveAnalysis(audioFile: file, stage: .starting, progress: 0)
        #expect(first.attemptID != second.attemptID)
    }

    @Test func attemptIDIsStableForTheLifetimeOfTheInstance() {
        let analysis = ActiveAnalysis(audioFile: makeAudioFile(), stage: .starting, progress: 0)
        let captured = analysis.attemptID
        analysis.stage = .transcribing
        analysis.progress = 0.5
        #expect(analysis.attemptID == captured)
    }

    @Test func snapshotCarriesAttemptID() {
        let analysis = ActiveAnalysis(audioFile: makeAudioFile(), stage: .transcribing, progress: 0.5)
        let snapshot = analysis.snapshot
        #expect(snapshot.attemptID == analysis.attemptID)
        #expect(snapshot.audioFileID == analysis.audioFile.id)
        #expect(snapshot.stage == .transcribing)
        #expect(snapshot.progress == 0.5)
    }
}
