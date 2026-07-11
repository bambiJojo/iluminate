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
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }

        let extracted = try await Task.detached(priority: .userInitiated) {
            try ReadingDocumentImporter.extract(from: url)
        }.value

        let id = UUID().uuidString
        let textFilename = "\(id).txt"
        let normalizedText = extracted.text
        let displayFilename = normalizedOriginalFilename(originalFilename) ?? extracted.originalFilename
        let document = ReadingDocument(
            id: id,
            title: displayTitle(extractedTitle: extracted.title,
                                sourceURL: url,
                                displayFilename: displayFilename),
            kind: extracted.kind,
            originalFilename: displayFilename,
            importedAt: .now,
            wordCount: ReadingDocumentImporter.wordCount(in: normalizedText),
            characterCount: normalizedText.count,
            contentHash: Self.contentHash(for: normalizedText),
            textFilename: textFilename
        )

        try fileManager.createDirectory(at: textDirectoryURL, withIntermediateDirectories: true)
        try Data(normalizedText.utf8).write(
            to: textDirectoryURL.appending(path: textFilename),
            options: .atomic
        )

        let replacedDocuments = documents.filter { existing in
            existing.contentHash == document.contentHash
                || existing.originalFilename == document.originalFilename
        }
        for replacedDocument in replacedDocuments {
            let textURL = textDirectoryURL.appending(path: replacedDocument.textFilename)
            try? fileManager.removeItem(at: textURL)
        }
        documents.removeAll { replacedDocuments.contains($0) }
        documents.insert(document, at: 0)
        documents.sort { $0.importedAt > $1.importedAt }
        try persist()
        return document
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

    private static func contentHash(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func normalizedOriginalFilename(_ filename: String?) -> String? {
        guard let filename else { return nil }
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    private func displayTitle(extractedTitle: String,
                              sourceURL: URL,
                              displayFilename: String) -> String {
        let sourceFallback = sourceURL.deletingPathExtension().lastPathComponent
        guard extractedTitle == sourceFallback else { return extractedTitle }

        let filenameTitle = URL(fileURLWithPath: displayFilename)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filenameTitle.isEmpty ? extractedTitle : filenameTitle
    }
}
