//  ReadingDocumentImporterTests.swift
//  IlumionateTests

import Compression
import Foundation
import Testing
@testable import Ilumionate

struct ReadingDocumentImporterTests {

    @Test func extractsStoredEPUBSpineText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "focus.epub")
        try makeStoredZip(entries: [
            "mimetype": Data("application/epub+zip".utf8),
            "META-INF/container.xml": Data("""
            <?xml version="1.0"?>
            <container version="1.0">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """.utf8),
            "OEBPS/content.opf": Data("""
            <?xml version="1.0"?>
            <package version="3.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
              <metadata>
                <dc:title>Focus &amp; Flow</dc:title>
              </metadata>
              <manifest>
                <item id="chapter-one" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="chapter-one"/>
              </spine>
            </package>
            """.utf8),
            "OEBPS/chapter1.xhtml": Data("""
            <html xmlns="http://www.w3.org/1999/xhtml">
              <head><title>Chapter One</title></head>
              <body>
                <h1>Chapter One</h1>
                <p>Let attention settle on the next useful sentence.</p>
                <p>The reader should preserve this document text for playback.</p>
              </body>
            </html>
            """.utf8)
        ], to: url)

        let extracted = try ReadingDocumentImporter.extract(from: url)

        #expect(extracted.kind == .epub)
        #expect(extracted.title == "Focus & Flow")
        #expect(extracted.text.contains("Chapter One"))
        #expect(extracted.text.contains("Let attention settle"))
        #expect(extracted.text.contains("preserve this document text"))
        #expect(ReadingDocumentImporter.wordCount(in: extracted.text) >= 16)
    }

    @MainActor
    @Test func documentStorePersistsImportedDocumentAndCreatesScript() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let epubURL = directory.appending(path: "library.epub")
        try makeStoredZip(entries: [
            "META-INF/container.xml": Data("""
            <container>
              <rootfiles>
                <rootfile full-path="content.opf"/>
              </rootfiles>
            </container>
            """.utf8),
            "content.opf": Data("""
            <package xmlns:dc="http://purl.org/dc/elements/1.1/">
              <metadata><dc:title>Library Import</dc:title></metadata>
              <manifest>
                <item id="main" href="chapter.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine><itemref idref="main"/></spine>
            </package>
            """.utf8),
            "chapter.xhtml": Data("""
            <html>
              <body>
                <h1>Saved Chapter</h1>
                <p>This imported document should become a reader script.</p>
                <p>Its extracted text should survive a metadata reload.</p>
              </body>
            </html>
            """.utf8)
        ], to: epubURL)

        let storeDirectory = directory.appending(path: "store", directoryHint: .isDirectory)
        let store = ReadingDocumentStore(directoryURL: storeDirectory)
        let document = try await store.importDocument(from: epubURL)
        let script = try store.script(for: document)
        let reloaded = ReadingDocumentStore(directoryURL: storeDirectory)

        #expect(document.title == "Library Import")
        #expect(script.id == document.scriptID)
        #expect(script.source.kind == .importedDocument)
        #expect(script.segments.first?.text.contains("Saved Chapter") == true)
        #expect(reloaded.documents.map(\.id) == [document.id])
    }

    @MainActor
    @Test func documentStoreUsesOriginalFilenameForStagedSharedFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let stagedURL = directory.appending(path: "staged-queue-file.epub")
        try makeStoredZip(entries: [
            "META-INF/container.xml": Data("""
            <container>
              <rootfiles>
                <rootfile full-path="content.opf"/>
              </rootfiles>
            </container>
            """.utf8),
            "content.opf": Data("""
            <package xmlns:dc="http://purl.org/dc/elements/1.1/">
              <metadata></metadata>
              <manifest>
                <item id="main" href="chapter.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine><itemref idref="main"/></spine>
            </package>
            """.utf8),
            "chapter.xhtml": Data("""
            <html>
              <body>
                <p>This staged shared document should keep the sender filename.</p>
                <p>The generated title should not expose the queue storage name.</p>
              </body>
            </html>
            """.utf8)
        ], to: stagedURL)

        let store = ReadingDocumentStore(directoryURL: directory.appending(path: "store", directoryHint: .isDirectory))
        let document = try await store.importDocument(from: stagedURL, originalFilename: "Real Book.epub")

        #expect(document.originalFilename == "Real Book.epub")
        #expect(document.title == "Real Book")
    }

    // Real-world ePubs store their XHTML with DEFLATE (method 8), exercising the
    // importer's hand-rolled inflate path that the stored-entry tests skip.
    @Test func extractsDeflateCompressedEPUBText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "compressed.epub")
        let body = String(
            repeating: "The reader should decompress this deflated chapter cleanly. ",
            count: 40
        )
        try makeDeflatedZip(entries: [
            ("META-INF/container.xml", Data("""
            <?xml version="1.0"?>
            <container version="1.0">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """.utf8)),
            ("OEBPS/content.opf", Data("""
            <?xml version="1.0"?>
            <package version="3.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
              <metadata><dc:title>Deep Focus</dc:title></metadata>
              <manifest>
                <item id="chapter-one" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine><itemref idref="chapter-one"/></spine>
            </package>
            """.utf8)),
            ("OEBPS/chapter1.xhtml", Data("""
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body><h1>Deep Focus</h1><p>\(body)</p></body>
            </html>
            """.utf8))
        ], to: url)

        let extracted = try ReadingDocumentImporter.extract(from: url)

        #expect(extracted.kind == .epub)
        #expect(extracted.title == "Deep Focus")
        #expect(extracted.text.contains("decompress this deflated chapter cleanly"))
        #expect(ReadingDocumentImporter.wordCount(in: extracted.text) >= 100)
    }

    @Test func extractsPlainTextFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "Evening Script.txt")
        try Data("Let your shoulders drop and your breathing slow right down now.".utf8)
            .write(to: url)

        let extracted = try ReadingDocumentImporter.extract(from: url)

        #expect(extracted.kind == .text)
        #expect(extracted.title == "Evening Script")
        #expect(extracted.originalFilename == "Evening Script.txt")
        #expect(extracted.text == "Let your shoulders drop and your breathing slow right down now.")
    }

    @Test func rejectsPlainTextWithTooFewWords() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "Stub.txt")
        try Data("Too short.".utf8).write(to: url)

        #expect(throws: ReadingDocumentImportError.noReadableText) {
            try ReadingDocumentImporter.extract(from: url)
        }
    }

    @Test func cleansMarkdownSyntaxOnImport() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "Session.md")
        try Data("""
        # Deep Rest

        You feel **calm** and _steady_ as the whole room grows quiet.
        """.utf8).write(to: url)

        let extracted = try ReadingDocumentImporter.extract(from: url)

        #expect(extracted.kind == .text)
        #expect(extracted.text.contains("**") == false)
        #expect(extracted.text.contains("#") == false)
        #expect(extracted.text.contains("You feel calm and steady as the whole room grows quiet."))
    }

    /// `.txt` is passed through untouched — an asterisk in a plain text file is
    /// an asterisk, not emphasis.
    @Test func leavesPlainTextSyntaxUntouched() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "Literal.txt")
        try Data("Multiply 2 * 3 and note the **stars** stay exactly where they are.".utf8)
            .write(to: url)

        let extracted = try ReadingDocumentImporter.extract(from: url)

        #expect(extracted.text.contains("**stars**"))
    }

    @Test func refusesOversizedPlainText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "Huge.txt")
        let sentence = "the quiet settles over everything around you now and again "
        let repeats = (ReadingDocumentImporter.maximumPlainTextByteCount / sentence.utf8.count) + 2
        try Data(String(repeating: sentence, count: repeats).utf8).write(to: url)

        #expect(throws: ReadingDocumentImportError.textFileTooLarge) {
            try ReadingDocumentImporter.extract(from: url)
        }
    }

    @MainActor
    @Test func reportsWhenAnImportReplacesAnExistingDocument() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ReadingDocumentStore(
            directoryURL: directory.appending(path: "Documents", directoryHint: .isDirectory)
        )
        let url = directory.appending(path: "Script.txt")
        try Data("Let your shoulders drop and your breathing slow right down now.".utf8)
            .write(to: url)

        let first = try await store.importDocumentReportingReplacement(from: url)
        #expect(first.replacedExisting == false)

        let second = try await store.importDocumentReportingReplacement(from: url)
        #expect(second.replacedExisting)
        #expect(store.documents.count == 1)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "reading-document-importer-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeStoredZip(entries: [String: Data], to url: URL) throws {
        var archive = Data()
        var centralDirectory = Data()

        for (path, contents) in entries {
            let localHeaderOffset = UInt32(archive.count)
            let pathData = Data(path.utf8)
            archive.appendUInt32(0x04034b50)
            archive.appendUInt16(20)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt32(0)
            archive.appendUInt32(UInt32(contents.count))
            archive.appendUInt32(UInt32(contents.count))
            archive.appendUInt16(UInt16(pathData.count))
            archive.appendUInt16(0)
            archive.append(pathData)
            archive.append(contents)

            centralDirectory.appendUInt32(0x02014b50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(UInt32(contents.count))
            centralDirectory.appendUInt32(UInt32(contents.count))
            centralDirectory.appendUInt16(UInt16(pathData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(localHeaderOffset)
            centralDirectory.append(pathData)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendUInt32(0x06054b50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt32(UInt32(centralDirectory.count))
        archive.appendUInt32(centralDirectoryOffset)
        archive.appendUInt16(0)
        try archive.write(to: url, options: .atomic)
    }

    private func makeDeflatedZip(entries: [(String, Data)], to url: URL) throws {
        var archive = Data()
        var centralDirectory = Data()

        for (path, contents) in entries {
            let compressed = try deflate(contents)
            let localHeaderOffset = UInt32(archive.count)
            let pathData = Data(path.utf8)
            archive.appendUInt32(0x04034b50)
            archive.appendUInt16(20)
            archive.appendUInt16(0)
            archive.appendUInt16(8)                          // method: DEFLATE
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt32(0)
            archive.appendUInt32(UInt32(compressed.count))
            archive.appendUInt32(UInt32(contents.count))
            archive.appendUInt16(UInt16(pathData.count))
            archive.appendUInt16(0)
            archive.append(pathData)
            archive.append(compressed)

            centralDirectory.appendUInt32(0x02014b50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(8)                 // method: DEFLATE
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(UInt32(compressed.count))
            centralDirectory.appendUInt32(UInt32(contents.count))
            centralDirectory.appendUInt16(UInt16(pathData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(localHeaderOffset)
            centralDirectory.append(pathData)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendUInt32(0x06054b50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt32(UInt32(centralDirectory.count))
        archive.appendUInt32(centralDirectoryOffset)
        archive.appendUInt16(0)
        try archive.write(to: url, options: .atomic)
    }

    // Raw DEFLATE (no zlib header), matching the importer's COMPRESSION_ZLIB decode.
    private func deflate(_ data: Data) throws -> Data {
        let capacity = data.count + data.count / 2 + 256
        var destination = Data(count: capacity)
        let written = destination.withUnsafeMutableBytes { destinationBuffer in
            data.withUnsafeBytes { sourceBuffer in
                compression_encode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    capacity,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        #expect(written > 0)
        destination.removeSubrange(written..<destination.count)
        return destination
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0x00ff))
        append(UInt8((value >> 8) & 0x00ff))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0x000000ff))
        append(UInt8((value >> 8) & 0x000000ff))
        append(UInt8((value >> 16) & 0x000000ff))
        append(UInt8((value >> 24) & 0x000000ff))
    }
}
