//  ReadingDocumentStore.swift
//  Ilumionate
//
//  Local library for imported PDF/ePub documents.

import CryptoKit
import Foundation

enum ReadingDocumentStoreError: LocalizedError {
    case missingText
    case couldNotDelete

    var errorDescription: String? {
        switch self {
        case .missingText:
            return "The extracted reader text is missing."
        case .couldNotDelete:
            return "The document could not be deleted."
        }
    }
}

struct ReadingDocumentImportOutcome: Sendable {
    let document: ReadingDocument
    /// True when this import superseded a document already in the library,
    /// matched by content hash or original filename.
    let replacedExisting: Bool
}

@MainActor
@Observable
final class ReadingDocumentStore {
    static let shared = ReadingDocumentStore()

    private(set) var documents: [ReadingDocument] = []

    private let directoryURL: URL
    private let textDirectoryURL: URL
    private let metadataURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL = URL.applicationSupportDirectory.appending(path: "TextTrance/Documents", directoryHint: .isDirectory),
         fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.textDirectoryURL = directoryURL.appending(path: "Text", directoryHint: .isDirectory)
        self.metadataURL = directoryURL.appending(path: "documents.json")
        self.fileManager = fileManager
        load()
    }

    func importDocument(from url: URL, originalFilename: String? = nil) async throws -> ReadingDocument {
        try await importDocumentReportingReplacement(
            from: url,
            originalFilename: originalFilename
        ).document
    }

    func importDocumentReportingReplacement(
        from url: URL,
        originalFilename: String? = nil
    ) async throws -> ReadingDocumentImportOutcome {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }

        let prepared = try await ReadingDocumentImportWorker.prepare(
            sourceURL: url,
            originalFilename: originalFilename,
            textDirectoryURL: textDirectoryURL,
            existingDocuments: documents
        )
        documents.removeAll { prepared.replacedDocumentIDs.contains($0.id) }
        documents.insert(prepared.document, at: 0)
        documents.sort { $0.importedAt > $1.importedAt }
        try persist()
        return ReadingDocumentImportOutcome(
            document: prepared.document,
            replacedExisting: prepared.replacedDocumentIDs.isEmpty == false
        )
    }

    func script(for document: ReadingDocument) throws -> TranceScript {
        let textURL = textDirectoryURL.appending(path: document.textFilename)
        guard let data = try? Data(contentsOf: textURL),
              let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadingDocumentStoreError.missingText
        }

        return TranceScript(
            schemaVersion: TranceScriptLibrary.currentSchemaVersion,
            id: document.scriptID,
            title: document.title,
            theme: .focus,
            supportedArcs: [.fullText],
            language: "en",
            source: ScriptSource(
                kind: .importedDocument,
                generator: document.originalFilename,
                reviewed: false
            ),
            summary: "\(document.kind.displayName) import with \(document.wordCountSummary).",
            segments: [
                TranceScriptSegment(
                    phase: .induction,
                    text: text,
                    pacing: SegmentPacing(baseWPM: 150),
                    arcs: nil,
                    triggersHandoff: nil
                )
            ]
        )
    }

    func delete(_ document: ReadingDocument) throws {
        let textURL = textDirectoryURL.appending(path: document.textFilename)
        do {
            if fileManager.fileExists(atPath: textURL.path) {
                try fileManager.removeItem(at: textURL)
            }
            documents.removeAll { $0.id == document.id }
            try persist()
        } catch {
            throw ReadingDocumentStoreError.couldNotDelete
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([ReadingDocument].self, from: data) else {
            documents = []
            return
        }
        documents = decoded.sorted { $0.importedAt > $1.importedAt }
    }

    private func persist() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(documents)
        try data.write(to: metadataURL, options: .atomic)
    }

}

private nonisolated enum ReadingDocumentImportWorker {
    struct PreparedImport: Sendable {
        let document: ReadingDocument
        let replacedDocumentIDs: Set<String>
    }

    @concurrent
    static func prepare(
        sourceURL: URL,
        originalFilename: String?,
        textDirectoryURL: URL,
        existingDocuments: [ReadingDocument]
    ) async throws -> PreparedImport {
        try Task.checkCancellation()
        let extracted = try ReadingDocumentImporter.extract(from: sourceURL)
        try Task.checkCancellation()

        let id = UUID().uuidString
        let textFilename = "\(id).txt"
        let displayFilename = normalizedOriginalFilename(originalFilename) ?? extracted.originalFilename
        let document = ReadingDocument(
            id: id,
            title: displayTitle(
                extractedTitle: extracted.title,
                sourceURL: sourceURL,
                displayFilename: displayFilename
            ),
            kind: extracted.kind,
            originalFilename: displayFilename,
            importedAt: .now,
            wordCount: ReadingDocumentImporter.wordCount(in: extracted.text),
            characterCount: extracted.text.count,
            contentHash: contentHash(for: extracted.text),
            textFilename: textFilename
        )

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: textDirectoryURL, withIntermediateDirectories: true)
        try Data(extracted.text.utf8).write(
            to: textDirectoryURL.appending(path: textFilename),
            options: .atomic
        )

        let replaced = existingDocuments.filter {
            $0.contentHash == document.contentHash || $0.originalFilename == document.originalFilename
        }
        for oldDocument in replaced {
            try? fileManager.removeItem(at: textDirectoryURL.appending(path: oldDocument.textFilename))
        }
        return PreparedImport(document: document, replacedDocumentIDs: Set(replaced.map(\.id)))
    }

    private static func contentHash(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedOriginalFilename(_ filename: String?) -> String? {
        guard let filename else { return nil }
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    private static func displayTitle(
        extractedTitle: String,
        sourceURL: URL,
        displayFilename: String
    ) -> String {
        let sourceFallback = sourceURL.deletingPathExtension().lastPathComponent
        guard extractedTitle == sourceFallback else { return extractedTitle }
        let filenameTitle = URL(fileURLWithPath: displayFilename)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filenameTitle.isEmpty ? extractedTitle : filenameTitle
    }
}
