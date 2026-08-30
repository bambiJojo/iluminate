//
//  CableFileRootInboxTests.swift
//  IlumionateTests
//
//  Finder's device Files tab drops onto the app row, which lands in the
//  Documents *root* — it cannot deliver into a subfolder. So the root is the
//  real inbox, and it is shared space: TrainingCorpus/, TrainingOutput/, and
//  _Needs Review/ all live there. Admitting audio from it must not disturb
//  anything else.
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct CableFileRootInboxTests {

    @Test("A drop at the Documents root is admitted")
    func importsDropAtDocumentsRoot() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.rootInboxURL.appending(path: "Platinum Focus 1.mp3")
        try fixture.validMP3Data.write(to: sourceURL)

        let result = await fixture.makeService().importAvailableFiles()

        let imported = try #require(result.imported.first)
        #expect(result.imported.count == 1)
        #expect(imported.storageLocation == .managed)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
    }

    /// The root is shared with other subsystems, so an unrecognised file is not
    /// a failed import — it is somebody else's data. Moving it to _Needs Review
    /// would be the bug.
    @Test("An unsupported file at the root is left where it is")
    func ignoresUnsupportedFileAtRoot() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let strayURL = fixture.rootInboxURL.appending(path: "AnalyzerConfig.json")
        try Data(#"{"a":1}"#.utf8).write(to: strayURL)

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.rejected.isEmpty)
        #expect(result.imported.isEmpty)
        #expect(result.importedDocuments.isEmpty)
        #expect(FileManager.default.fileExists(atPath: strayURL.path))
    }

    /// App-owned directories are off limits — moving a file out of the training
    /// corpus would be the bug.
    @Test(
        "App-owned directories at the root are never descended into",
        arguments: ["TrainingCorpus", "TrainingOutput", "GeneratedSessions", "Inbox"]
    )
    func doesNotDescendIntoAppOwnedDirectories(directoryName: String) async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let ownedURL = fixture.rootInboxURL.appending(
            path: directoryName,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: ownedURL, withIntermediateDirectories: true)
        let ownedAudio = ownedURL.appending(path: "Corpus Sample.mp3")
        try fixture.validMP3Data.write(to: ownedAudio)

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.imported.isEmpty)
        #expect(FileManager.default.fileExists(atPath: ownedAudio.path))
    }

    /// Dragging twenty files usually means dragging the folder holding them.
    /// A flatly non-recursive root scan makes that batch invisible.
    @Test("Audio inside a dropped folder is admitted")
    func importsAudioInsideADroppedFolder() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let droppedFolder = fixture.rootInboxURL.appending(
            path: "Sleep Sessions",
            directoryHint: .isDirectory
        )
        let nested = droppedFolder.appending(path: "Volume 2", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        // Distinct bytes: identical content would be correctly rejected as a
        // duplicate, which would mask whether the walk found both files.
        try fixture.mp3Data(distinguishedBy: 0x01)
            .write(to: droppedFolder.appending(path: "One.mp3"))
        try fixture.mp3Data(distinguishedBy: 0x02)
            .write(to: nested.appending(path: "Two.mp3"))

        let result = await fixture.makeService().importAvailableFiles()

        #expect(Set(result.imported.map(\.filename.lastPathSegment)) == ["One.mp3", "Two.mp3"])
    }

    /// Import moves the originals, so a dropped folder is emptied and its
    /// layout is not preserved. The result has to carry that count or the alert
    /// cannot explain where the user's folder went.
    @Test("Audio taken out of a dropped folder is counted as relocated")
    func countsAudioMovedOutOfADroppedFolder() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let droppedFolder = fixture.rootInboxURL.appending(
            path: "Sleep Sessions",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: droppedFolder, withIntermediateDirectories: true)
        try fixture.mp3Data(distinguishedBy: 0x01)
            .write(to: droppedFolder.appending(path: "One.mp3"))
        try fixture.mp3Data(distinguishedBy: 0x02)
            .write(to: droppedFolder.appending(path: "Two.mp3"))

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.imported.count == 2)
        #expect(result.movedFromSubfolderCount == 2)
    }

    /// The Finder drop lands in the Documents root itself, which is the common
    /// case. Nothing was flattened, so nothing should be reported.
    @Test("Audio dropped at the root is not counted as relocated")
    func doesNotCountAudioDroppedAtTheRoot() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        try fixture.validMP3Data
            .write(to: fixture.rootInboxURL.appending(path: "Platinum Focus 1.mp3"))

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.imported.count == 1)
        #expect(result.movedFromSubfolderCount == 0)
    }

    /// migrateLegacyAudio sweeps `.documents` entries into managed storage, but
    /// ordering against a cable scan is not guaranteed. Re-importing a file the
    /// library already owns would move it out from under its own row.
    @Test("Audio already registered in the library is left alone")
    func skipsAudioAlreadyRegisteredInTheLibrary() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.rootInboxURL.appending(path: "Legacy Session.mp3")
        try fixture.validMP3Data.write(to: sourceURL)

        // An absolute filename makes `AudioFile.url` resolve to exactly this
        // path, which is how a row can point at a file sitting in the intake
        // directory. A relative name would resolve against the real Documents
        // directory and never match the fixture.
        let existing = AudioFile(
            filename: sourceURL.path,
            duration: 120,
            fileSize: Int64(fixture.validMP3Data.count),
            createdDate: Date(timeIntervalSince1970: 0)
        )
        _ = await AudioLibraryStore.add(existing, storage: fixture.libraryStorage)

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.imported.isEmpty)
        #expect(result.duplicates.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    /// Moving a file while Finder is still working through a batch makes the
    /// whole transfer fail with "required file cannot be found". Two snapshots
    /// a second apart are not enough: a file that finished moments ago looks
    /// stable in both. Nothing is touched until it has sat still for a while.
    @Test("A file that only just arrived is left alone")
    func doesNotTouchAFileThatJustArrived() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.rootInboxURL.appending(path: "Just Landed.mp3")
        try fixture.validMP3Data.write(to: sourceURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: sourceURL.path
        )

        let result = await fixture.makeService(minimumSettleAge: .seconds(5))
            .importAvailableFiles()

        #expect(result.imported.isEmpty)
        #expect(result.pending == ["Just Landed.mp3"])
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    /// Per-file age is not enough. A twenty-file copy takes a minute, so file
    /// one is "old" while file twenty is still arriving — and moving file one
    /// mid-batch is exactly what breaks the drag. While the directory is still
    /// changing, nothing in it is touched.
    @Test("A settled file is deferred while the batch is still arriving")
    func defersSettledFileWhileTheBatchIsStillArriving() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let settledURL = fixture.rootInboxURL.appending(path: "First Of Twenty.mp3")
        try fixture.mp3Data(distinguishedBy: 0x01).write(to: settledURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -600)],
            ofItemAtPath: settledURL.path
        )

        let arrivingURL = fixture.rootInboxURL.appending(path: "Twentieth.mp3")
        try fixture.mp3Data(distinguishedBy: 0x02).write(to: arrivingURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: arrivingURL.path
        )

        let result = await fixture.makeService(minimumSettleAge: .seconds(5))
            .importAvailableFiles()

        #expect(result.imported.isEmpty)
        #expect(Set(result.pending) == ["First Of Twenty.mp3", "Twentieth.mp3"])
        #expect(FileManager.default.fileExists(atPath: settledURL.path))
    }

    @Test("A file that has settled is admitted")
    func admitsAFileThatHasSettled() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.rootInboxURL.appending(path: "Settled.mp3")
        try fixture.validMP3Data.write(to: sourceURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -600)],
            ofItemAtPath: sourceURL.path
        )

        let result = await fixture.makeService(minimumSettleAge: .seconds(5))
            .importAvailableFiles()

        #expect(result.imported.count == 1)
        #expect(result.pending.isEmpty)
    }

    /// The dedicated subfolder is still reachable from the iOS Files app, and
    /// there an invalid recognized document is a failed import.
    @Test("The dedicated inbox routes invalid documents to Needs Review")
    func dedicatedInboxStillRejectsToNeedsReview() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let strayURL = fixture.dedicatedInboxURL.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: strayURL)

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.rejected == ["notes.txt"])
        #expect(FileManager.default.fileExists(atPath: strayURL.path) == false)
        #expect(FileManager.default.fileExists(
            atPath: fixture.reviewURL
                .appending(path: "Invalid Documents")
                .appending(path: "notes.txt")
                .path
        ))
    }

    @Test("The review directory is not re-scanned as intake")
    func reviewDirectoryIsNotRescanned() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let parked = fixture.reviewURL.appending(
            path: "Duplicates",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: parked, withIntermediateDirectories: true)
        let parkedAudio = parked.appending(path: "Parked.mp3")
        try fixture.validMP3Data.write(to: parkedAudio)

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.imported.isEmpty)
        #expect(FileManager.default.fileExists(atPath: parkedAudio.path))
    }

    @Test("App-owned output directories are never descended into")
    func skipsOwnOutputDirectories() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        for directory in ["_Imported", "_Needs Review"] {
            let nested = fixture.rootInboxURL.appending(path: directory, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try fixture.validMP3Data.write(to: nested.appending(path: "Already Handled.mp3"))
        }

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.imported.isEmpty)
        #expect(result.duplicates.isEmpty)
        #expect(result.rejected.isEmpty)
        for directory in ["_Imported", "_Needs Review"] {
            #expect(FileManager.default.fileExists(
                atPath: fixture.rootInboxURL
                    .appending(path: "\(directory)/Already Handled.mp3")
                    .path
            ))
        }
    }

    /// `Incoming Text` is excluded from the root walk, then scanned separately
    /// with dedicated-inbox policy. If the root walk reaches it first, this
    /// unsupported file is incorrectly left alone instead of being surfaced.
    @Test("The text inbox is walked as dedicated intake")
    func textInboxUsesDedicatedPolicy() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.textInboxURL.appending(path: "notes.rtf")
        try Data("Not a supported cable import.".utf8).write(to: sourceURL)

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.rejected == ["notes.rtf"])
        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
        #expect(FileManager.default.fileExists(
            atPath: fixture.reviewURL
                .appending(path: "Unsupported Files/notes.rtf")
                .path
        ))
    }

    @Test("A text file dropped at the Documents root reaches the reader")
    func admitsTextFromTheDocumentsRoot() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.rootInboxURL.appending(path: "Root Script.txt")
        try Data("Let your shoulders drop and your breathing slow right down now.".utf8)
            .write(to: sourceURL)

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.importedDocuments.count == 1)
        #expect(result.rejected.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
        #expect(FileManager.default.fileExists(
            atPath: fixture.importedURL.appending(path: "Root Script.txt").path
        ))
    }
}

private extension String {
    /// `AudioFile.filename` may be a stored relative path; the leaf is what the
    /// import was named.
    var lastPathSegment: String {
        split(separator: "/").last.map(String.init) ?? self
    }
}

private struct RootInboxFixture {
    let containerURL: URL
    /// Stands in for Documents root.
    let rootInboxURL: URL
    let dedicatedInboxURL: URL
    let textInboxURL: URL
    let importedURL: URL
    let reviewURL: URL
    let managedAudioURL: URL
    let libraryStorage: AudioLibraryStorage
    let documentStore: ReadingDocumentStore

    let validMP3Data = Data([
        0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ])

    /// Keeps the ID3 signature the validator checks while giving the file a
    /// unique fingerprint.
    func mp3Data(distinguishedBy marker: UInt8) -> Data {
        validMP3Data + Data(repeating: marker, count: 16)
    }

    @MainActor
    init() throws {
        containerURL = URL.temporaryDirectory.appending(
            path: "CableRootInboxTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        rootInboxURL = containerURL.appending(path: "Documents", directoryHint: .isDirectory)
        dedicatedInboxURL = rootInboxURL.appending(path: "Incoming Audio", directoryHint: .isDirectory)
        textInboxURL = rootInboxURL.appending(path: "Incoming Text", directoryHint: .isDirectory)
        importedURL = rootInboxURL.appending(path: "_Imported", directoryHint: .isDirectory)
        reviewURL = rootInboxURL.appending(path: "_Needs Review", directoryHint: .isDirectory)
        managedAudioURL = containerURL.appending(path: "Managed Audio", directoryHint: .isDirectory)
        libraryStorage = AudioLibraryStorage(
            fileURL: containerURL.appending(path: "library.json"),
            legacyDefaults: nil
        )
        documentStore = ReadingDocumentStore(
            directoryURL: containerURL.appending(path: "Reader", directoryHint: .isDirectory)
        )

        for url in [rootInboxURL, dedicatedInboxURL, textInboxURL, managedAudioURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: containerURL)
    }

    func makeService(minimumSettleAge: Duration = .zero) -> CableFileImportService {
        CableFileImportService(
            rootInboxURL: rootInboxURL,
            dedicatedInboxURL: dedicatedInboxURL,
            textInboxURL: textInboxURL,
            reviewURL: reviewURL,
            importedURL: importedURL,
            managedAudioURL: managedAudioURL,
            readerAdmission: ReaderInboxAdmission { [documentStore] url, originalFilename in
                try await documentStore.importDocumentReportingReplacement(
                    from: url,
                    originalFilename: originalFilename
                )
            },
            libraryStorage: libraryStorage,
            stabilityDelay: .zero,
            minimumSettleAge: minimumSettleAge,
            wait: { _ in }
        )
    }
}
