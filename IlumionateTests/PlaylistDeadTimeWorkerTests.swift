//
//  PlaylistDeadTimeWorkerTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct PlaylistDeadTimeWorkerTests {
    @Test("Dead-time analysis runs off the main thread")
    func analysisRunsOffTheMainThread() async throws {
        let observed = DeadTimeThreadProbe()
        let expected = DeadTimeProfile(
            headDeadTime: 2.5,
            tailDeadTime: 11,
            headClassification: .silence,
            tailClassification: .binaural,
            analysisDate: .now
        )

        let result = try await PlaylistDeadTimeWorker.analyze(
            url: URL.temporaryDirectory.appending(path: "unused.m4a"),
            operation: { _ in
                observed.record(isMain: Thread.isMainThread)
                return expected
            }
        )

        #expect(observed.ranOnMainThread == false)
        #expect(result.tailDeadTime == expected.tailDeadTime)
    }
}

private nonisolated final class DeadTimeThreadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?

    var ranOnMainThread: Bool? {
        lock.withLock { value }
    }

    func record(isMain: Bool) {
        lock.withLock { value = isMain }
    }
}
