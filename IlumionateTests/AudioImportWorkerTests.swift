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

        guard case .imported(let result) = try await importedFile else {
            Issue.record("Expected the file to be imported")
            return
        }
        defer { try? FileManager.default.removeItem(at: result.url) }
        #expect(result.fileSize > 0)
    }

    @Test("Importing the same file twice does not create a second copy")
    func identicalImportIsRecognized() async throws {
        let documents = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: documents) }

        let source = documents.appending(path: "source.mp3")
        try Data("audio-bytes".utf8).write(to: source)

        let first = try await AudioImportWorker.prepareAudioFile(
            from: source,
            targetFilename: "Track.mp3",
            transferMode: .copy,
            durationTimeout: .seconds(1),
            documentsURL: documents
        )
        guard case .imported(let importedFile) = first else {
            Issue.record("The first import should produce a file")
            return
        }

        let second = try await AudioImportWorker.prepareAudioFile(
            from: source,
            targetFilename: "Track.mp3",
            transferMode: .copy,
            durationTimeout: .seconds(1),
            documentsURL: documents,
            existing: DuplicateAudioIndex([importedFile])
        )

        #expect(second == .alreadyInLibrary(existing: importedFile.id))

        let stored = try FileManager.default.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: nil
        )
        #expect(stored.contains { $0.lastPathComponent == "Track (1).mp3" } == false)
    }
}
