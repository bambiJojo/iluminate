//
//  AudioImportWorkerTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct AudioImportWorkerTests {
    @Test func slowFileTransferDoesNotBlockMainActor() async throws {
        let sourceURL = URL.temporaryDirectory
            .appending(path: "import-source-\(UUID().uuidString).mp3")
        try Data("test audio".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let (transferStarted, startedContinuation) = AsyncStream<Void>.makeStream()
        let clock = ContinuousClock()
        let startedAt = clock.now

        async let importedFile = AudioImportWorker.prepareAudioFile(
            from: sourceURL,
            targetFilename: "import-test-\(UUID().uuidString).mp3",
            transferMode: .copy,
            durationTimeout: .milliseconds(50),
            transferOperation: { source, destination, _ in
                startedContinuation.yield()
                Thread.sleep(forTimeInterval: 0.5)
                try FileManager.default.copyItem(at: source, to: destination)
            }
        )

        for await _ in transferStarted {
            break
        }

        let notificationDelay = startedAt.duration(to: clock.now)
        #expect(notificationDelay < .milliseconds(250))

        let result = try await importedFile
        defer { try? FileManager.default.removeItem(at: result.url) }
        #expect(result.fileSize > 0)
    }
}
