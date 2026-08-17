//
//  AnalysisTaskTests.swift
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

struct AnalysisTaskTests {

    @Test func taskIdentityComesFromAudioFile() {
        let id = UUID()
        let task = AnalysisTask(
            audioFile: makeAudioFile(id: id),
            state: .queued(position: 1),
            lastFailure: nil,
            recovery: .none,
            ready: nil
        )
        #expect(task.id == id)
    }

    /// Guards the SyncPlayerItem trap: two projections of identical state must
    /// compare equal, or every progress tick looks like a full list change.
    @Test func identicalTasksAreEqual() {
        let file = makeAudioFile()
        let ready = AnalysisReadySnapshot(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!,
            readyAt: Date(timeIntervalSince1970: 10)
        )
        let a = AnalysisTask(audioFile: file, state: .ready, lastFailure: nil, recovery: .none, ready: ready)
        let b = AnalysisTask(audioFile: file, state: .ready, lastFailure: nil, recovery: .none, ready: ready)
        #expect(a == b)
    }

    @Test func differingStateBreaksEquality() {
        let file = makeAudioFile()
        let a = AnalysisTask(audioFile: file, state: .queued(position: 1), lastFailure: nil, recovery: .none, ready: nil)
        let b = AnalysisTask(audioFile: file, state: .queued(position: 2), lastFailure: nil, recovery: .none, ready: nil)
        #expect(a != b)
    }
}
