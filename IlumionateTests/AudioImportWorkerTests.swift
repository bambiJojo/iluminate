//
//  AudioImportWorkerTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct AudioImportWorkerTests {
    // Asserts the property directly — the transfer runs off the main actor —
    // rather than timing how quickly the main actor notices. The timed version
    // measured the machine, not the code: under the full suite, where dozens of
    // `@MainActor` suites queue on one actor, it recorded a 22-second delay and
    // failed while the code under test was behaving perfectly.
    @Test func fileTransferRunsOffTheMainActor() async throws {
        let sourceURL = URL.temporaryDirectory
            .appending(path: "import-source-\(UUID().uuidString).mp3")
        try Data("test audio".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let documents = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: documents) }

        let observed = TransferThreadProbe()

        let outcome = try await AudioImportWorker.prepareAudioFile(
            from: sourceURL,
            targetFilename: "off-main.mp3",
            transferMode: .copy,
            durationTimeout: .milliseconds(50),
            documentsURL: documents,
            transferOperation: { source, destination, _ in
                observed.record(isMain: Thread.isMainThread)
                try FileManager.default.copyItem(at: source, to: destination)
            }
        )

        guard case .imported = outcome else {
            Issue.record("Expected the file to be imported")
            return
        }
        #expect(observed.ranOnMainThread == false)
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

    @Test("A publisher identity prevents downloading the same remote track twice")
    func remoteIdentityIsRecognizedBeforeTransfer() async throws {
        let source = RemoteAudioSource(
            service: "soundcloud",
            trackID: "track-42",
            url: URL(string: "https://api.soundcloud.com/tracks/42/stream")!
        )
        let existing = AudioFile(
            filename: "Existing.mp3",
            duration: 120,
            fileSize: 1_024,
            remoteSource: source
        )
        let input = URL.temporaryDirectory.appending(path: "unread-source.mp3")
        let transfer = TransferThreadProbe()

        let outcome = try await AudioImportWorker.prepareAudioFile(
            from: input,
            targetFilename: "Remote Track.mp3",
            transferMode: .move,
            durationTimeout: .milliseconds(50),
            existing: DuplicateAudioIndex([existing]),
            remoteSource: source,
            creator: "Remote Artist",
            transferOperation: { _, _, _ in transfer.record(isMain: Thread.isMainThread) }
        )

        #expect(outcome == .alreadyInLibrary(existing: existing.id))
        #expect(transfer.ranOnMainThread == nil)
    }

    @Test("Remote provenance survives admission to the library")
    func importedRemoteMetadataIsPreserved() async throws {
        let documents = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: documents) }

        let input = documents.appending(path: "source.mp3")
        try Data("remote-audio".utf8).write(to: input)
        let source = RemoteAudioSource(
            service: "soundcloud",
            trackID: "track-7",
            url: URL(string: "https://api.soundcloud.com/tracks/7/stream")!
        )

        let outcome = try await AudioImportWorker.prepareAudioFile(
            from: input,
            targetFilename: "Remote Track.mp3",
            transferMode: .copy,
            durationTimeout: .milliseconds(50),
            documentsURL: documents,
            remoteSource: source,
            creator: "Remote Artist"
        )

        guard case .imported(let imported) = outcome else {
            Issue.record("Expected the remote track to be imported")
            return
        }
        #expect(imported.remoteSource == source)
        #expect(imported.creator == "Remote Artist")
    }
}

/// Records which thread the injected transfer ran on. A plain `var` captured by
/// the `@Sendable` transfer closure will not compile under strict concurrency.
private nonisolated final class TransferThreadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var wasMain: Bool?

    func record(isMain: Bool) {
        lock.lock()
        wasMain = isMain
        lock.unlock()
    }

    var ranOnMainThread: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return wasMain
    }
}
