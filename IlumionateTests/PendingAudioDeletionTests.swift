//
//  PendingAudioDeletionTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct PendingAudioDeletionTests {

    // MARK: - Fixture

    /// A temp root holding a fake Documents directory and a staging directory.
    private struct Fixture {
        let root: URL
        let documentsURL: URL
        let stagingURL: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }

        /// Writes a real file on disk and returns an AudioFile pointing at it by
        /// absolute path, so `file.url` resolves inside the fixture rather than
        /// the app's real Documents directory.
        func makeFile(named name: String, contents: String = "audio") throws -> AudioFile {
            let url = documentsURL.appending(path: name)
            try Data(contents.utf8).write(to: url)
            return AudioFile(filename: url.path, duration: 60, fileSize: 5)
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PendingAudioDeletionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let documentsURL = root.appending(path: "Documents", directoryHint: .isDirectory)
        let stagingURL = root.appending(path: "Staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        return Fixture(root: root, documentsURL: documentsURL, stagingURL: stagingURL)
    }

    private func makeSubject(
        _ fixture: Fixture,
        onDeleteSession: @escaping @MainActor (AudioFile) -> Void = { _ in }
    ) -> PendingAudioDeletion {
        PendingAudioDeletion(
            stagingRoot: fixture.stagingURL,
            deleteGeneratedSession: onDeleteSession
        )
    }

    // MARK: - Tests

    @Test
    func stagingMovesTheFileOutOfItsOriginalLocation() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)
        let file = try fixture.makeFile(named: "one.mp3")

        let staged = subject.stage([
            StagedAudioFile(file: file, originalURL: file.url, originalIndex: 0)
        ])

        #expect(staged.count == 1)
        #expect(subject.staged.count == 1)
        #expect(FileManager.default.fileExists(atPath: file.url.path) == false)
    }

    @Test
    func restoreReturnsTheFileToItsExactOriginalURL() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)
        let file = try fixture.makeFile(named: "one.mp3", contents: "original bytes")
        let originalURL = file.url

        subject.stage([StagedAudioFile(file: file, originalURL: originalURL, originalIndex: 3)])
        let recovered = subject.restore()

        #expect(recovered.count == 1)
        #expect(recovered.first?.originalIndex == 3)
        #expect(FileManager.default.fileExists(atPath: originalURL.path))
        let contents = try String(contentsOf: originalURL, encoding: .utf8)
        #expect(contents == "original bytes")
        #expect(subject.staged.isEmpty)
    }

    @Test
    func twoFilesSharingALastPathComponentBothSurvive() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)

        // Same filename, different directories — a real possibility because
        // training and migration flows store absolute paths.
        let nested = fixture.documentsURL.appending(path: "nested", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let first = try fixture.makeFile(named: "same.mp3", contents: "first")
        let secondURL = nested.appending(path: "same.mp3")
        try Data("second".utf8).write(to: secondURL)
        let second = AudioFile(filename: secondURL.path, duration: 60, fileSize: 6)

        subject.stage([
            StagedAudioFile(file: first, originalURL: first.url, originalIndex: 0),
            StagedAudioFile(file: second, originalURL: second.url, originalIndex: 1)
        ])
        let recovered = subject.restore()

        #expect(recovered.count == 2)
        #expect(try String(contentsOf: first.url, encoding: .utf8) == "first")
        #expect(try String(contentsOf: second.url, encoding: .utf8) == "second")
    }

    @Test
    func restoreReturnsEntriesInAscendingOriginalIndexOrder() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)

        let a = try fixture.makeFile(named: "a.mp3")
        let b = try fixture.makeFile(named: "b.mp3")
        let c = try fixture.makeFile(named: "c.mp3")

        subject.stage([
            StagedAudioFile(file: c, originalURL: c.url, originalIndex: 7),
            StagedAudioFile(file: a, originalURL: a.url, originalIndex: 1),
            StagedAudioFile(file: b, originalURL: b.url, originalIndex: 4)
        ])

        #expect(subject.restore().map(\.originalIndex) == [1, 4, 7])
    }

    @Test
    func aFileThatCannotBeStagedIsNotReportedAsStaged() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)

        let real = try fixture.makeFile(named: "real.mp3")
        // Never written to disk — the move must fail.
        let missingURL = fixture.documentsURL.appending(path: "ghost.mp3")
        let ghost = AudioFile(filename: missingURL.path, duration: 60, fileSize: 0)

        let staged = subject.stage([
            StagedAudioFile(file: real, originalURL: real.url, originalIndex: 0),
            StagedAudioFile(file: ghost, originalURL: ghost.url, originalIndex: 1)
        ])

        #expect(staged.count == 1)
        #expect(staged.first?.file.id == real.id)
        #expect(subject.staged.count == 1)
    }

    // MARK: - Commit

    @Test
    func commitDeletesTheStagedFileAndItsGeneratedSession() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var sessionsDeleted: [AudioFile.ID] = []
        let subject = makeSubject(fixture) { sessionsDeleted.append($0.id) }
        let file = try fixture.makeFile(named: "one.mp3")

        subject.stage([StagedAudioFile(file: file, originalURL: file.url, originalIndex: 0)])
        subject.commit()

        #expect(subject.staged.isEmpty)
        #expect(sessionsDeleted == [file.id])
        #expect(FileManager.default.fileExists(atPath: file.url.path) == false)
        // Nothing left behind in staging.
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: fixture.stagingURL,
            includingPropertiesForKeys: nil
        )
        #expect(leftovers.isEmpty)
    }

    @Test
    func stagingANewBatchCommitsThePreviousOne() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var sessionsDeleted: [AudioFile.ID] = []
        let subject = makeSubject(fixture) { sessionsDeleted.append($0.id) }
        let first = try fixture.makeFile(named: "first.mp3")
        let second = try fixture.makeFile(named: "second.mp3")

        subject.stage([StagedAudioFile(file: first, originalURL: first.url, originalIndex: 0)])
        subject.stage([StagedAudioFile(file: second, originalURL: second.url, originalIndex: 0)])

        // The first batch is gone for good; only the second is recoverable.
        #expect(sessionsDeleted == [first.id])
        #expect(subject.staged.map(\.file.id) == [second.id])

        let recovered = subject.restore()
        #expect(recovered.count == 1)
        #expect(FileManager.default.fileExists(atPath: second.url.path))
        #expect(FileManager.default.fileExists(atPath: first.url.path) == false)
    }

    @Test
    func generatedSessionSurvivesUntilCommit() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var sessionsDeleted: [AudioFile.ID] = []
        let subject = makeSubject(fixture) { sessionsDeleted.append($0.id) }
        let file = try fixture.makeFile(named: "one.mp3")

        subject.stage([StagedAudioFile(file: file, originalURL: file.url, originalIndex: 0)])
        #expect(sessionsDeleted.isEmpty, "the light session must outlive the undo window")

        subject.restore()
        #expect(sessionsDeleted.isEmpty, "undo must not destroy the light session")
    }

    // MARK: - Launch cleanup

    @Test
    func sweepOrphansEmptiesTheStagingDirectory() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        // Simulate a batch left over from a killed session.
        let orphan = fixture.stagingURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: orphan.appending(path: "stale.mp3"))

        let subject = makeSubject(fixture)
        subject.sweepOrphans()

        let leftovers = try FileManager.default.contentsOfDirectory(
            at: fixture.stagingURL,
            includingPropertiesForKeys: nil
        )
        #expect(leftovers.isEmpty)
    }

    @Test
    func sweepOrphansLeavesALiveBatchAlone() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let subject = makeSubject(fixture)
        let file = try fixture.makeFile(named: "one.mp3")

        subject.stage([StagedAudioFile(file: file, originalURL: file.url, originalIndex: 0)])
        subject.sweepOrphans()

        // Still recoverable — sweeping must never eat a pending undo.
        #expect(subject.restore().count == 1)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test
    func sweepOrphansOnAMissingDirectoryIsHarmless() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        // stagingURL was never created — nothing has been staged yet.
        makeSubject(fixture).sweepOrphans()
    }
}
