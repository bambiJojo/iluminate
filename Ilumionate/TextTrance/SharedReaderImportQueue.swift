//  SharedReaderImportQueue.swift
//  Ilumionate
//
//  Host-app side of the App Group queue written by the Share extension.

import Foundation

enum SharedReaderImportKind: String, Codable, Sendable {
    case webURL
    case file
    case plainText
}

struct SharedReaderImportItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let kind: SharedReaderImportKind
    let title: String?
    let sourceURLString: String?
    let fileName: String?
    let originalFilename: String?
    let text: String?
    let createdAt: Date
}

struct SharedReaderImportResult: Equatable, Sendable {
    var importedCount = 0
    var failureMessages: [String] = []
}

enum SharedReaderImportQueue {
    static let appGroupIdentifier = "group.com.byronquine.lumenSync"
    static let deepLinkURL = URL(string: "ilumionate://shared-import")!

    private static let directoryName = "SharedReaderImports"
    private static let filesDirectoryName = "Files"
    private static let queueFilename = "imports.json"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return url
        }
        return URL.applicationSupportDirectory.appending(path: directoryName, directoryHint: .isDirectory)
    }

    static var queueURL: URL {
        containerURL.appending(path: queueFilename)
    }

    static var filesDirectoryURL: URL {
        containerURL.appending(path: filesDirectoryName, directoryHint: .isDirectory)
    }

    static func pendingItems() -> [SharedReaderImportItem] {
        guard let data = try? Data(contentsOf: queueURL),
              let items = try? JSONDecoder().decode([SharedReaderImportItem].self, from: data) else {
            return []
        }
        return items.sorted { $0.createdAt < $1.createdAt }
    }

    static func remove(_ importedItems: [SharedReaderImportItem]) {
        guard !importedItems.isEmpty else { return }
        let importedIDs = Set(importedItems.map(\.id))
        let remaining = pendingItems().filter { !importedIDs.contains($0.id) }
        persist(remaining)

        for item in importedItems where item.kind == .file {
            guard let fileName = item.fileName else { continue }
            try? FileManager.default.removeItem(at: filesDirectoryURL.appending(path: fileName))
        }
    }

    private static func persist(_ items: [SharedReaderImportItem]) {
        do {
            try FileManager.default.createDirectory(
                at: containerURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: queueURL, options: .atomic)
        } catch {
            // Non-fatal. The library import surfaces failures when it can.
        }
    }
}

@MainActor
struct SharedReaderImportCoordinator {
    var importedStore: ImportedTranceScriptStore = .shared
    var documentStore: ReadingDocumentStore = .shared

    func drainPendingImports() async -> SharedReaderImportResult {
        let items = SharedReaderImportQueue.pendingItems()
        guard !items.isEmpty else { return SharedReaderImportResult() }

        var imported: [SharedReaderImportItem] = []
        var result = SharedReaderImportResult()

        for item in items {
            do {
                switch item.kind {
                case .webURL:
                    // Remove URL items left by pre-release builds. The App Store
                    // release accepts files and shared text, never webpage downloads.
                    imported.append(item)
                    result.failureMessages.append("Web links are not imported in this version.")
                    continue
                case .file:
                    guard let fileName = item.fileName else {
                        throw ReadingDocumentImportError.unsupportedFileType
                    }
                    _ = try await documentStore.importDocument(
                        from: SharedReaderImportQueue.filesDirectoryURL.appending(path: fileName),
                        originalFilename: item.originalFilename
                    )
                case .plainText:
                    let script = try script(fromPlainTextItem: item)
                    try importedStore.save(script)
                }

                imported.append(item)
                result.importedCount += 1
            } catch {
                result.failureMessages.append(error.localizedDescription)
            }
        }

        SharedReaderImportQueue.remove(imported)
        return result
    }

    private func script(fromPlainTextItem item: SharedReaderImportItem) throws -> TranceScript {
        let text = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard ReadingDocumentImporter.wordCount(in: text) >= 8 else {
            throw SharedReaderImportError.noReadableText
        }

        return TranceScript(
            schemaVersion: TranceScriptLibrary.currentSchemaVersion,
            id: "shared-text-\(item.id)",
            title: item.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? item.title!
                : "Shared Text",
            theme: .focus,
            supportedArcs: [.fullText],
            language: "en",
            source: ScriptSource(kind: .importedDocument, generator: nil, reviewed: false),
            summary: "Share Sheet text import.",
            segments: [
                TranceScriptSegment(
                    phase: .induction,
                    text: text,
                    pacing: SegmentPacing(baseWPM: TextPacingEngine.defaultBaseWPM),
                    arcs: nil,
                    triggersHandoff: nil
                )
            ]
        )
    }
}

private enum SharedReaderImportError: LocalizedError {
    case noReadableText

    var errorDescription: String? {
        "The shared text does not contain enough readable words."
    }
}
