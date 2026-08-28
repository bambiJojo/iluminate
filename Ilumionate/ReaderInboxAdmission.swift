//
//  ReaderInboxAdmission.swift
//  Ilumionate
//

import Foundation

/// The result of offering one inbox file to the reader library.
nonisolated enum ReaderInboxOutcome: Sendable, Equatable {
    case imported(ReadingDocument)
    /// The document was already in the library, matched by content or filename.
    case duplicate
    /// The file cannot be read as a document. Retrying would produce the same
    /// answer, so it belongs in `_Needs Review` rather than in the inbox.
    case rejected
    /// The store or the disk failed. This may succeed on the next scan, so the
    /// file is left where it was found.
    case failed(String)
}

/// Admits a single reader document, isolating the main-actor hop to
/// `ReadingDocumentStore` behind an injectable closure so the cable service can
/// be tested without a real store.
nonisolated struct ReaderInboxAdmission: Sendable {
    typealias Importer = @MainActor @Sendable (URL, String?) async throws -> ReadingDocumentImportOutcome

    private let importDocument: Importer

    init(importDocument: @escaping Importer = { url, originalFilename in
        try await ReadingDocumentStore.shared.importDocumentReportingReplacement(
            from: url,
            originalFilename: originalFilename
        )
    }) {
        self.importDocument = importDocument
    }

    func admit(_ url: URL) async -> ReaderInboxOutcome {
        do {
            let outcome = try await importDocument(url, url.lastPathComponent)
            return outcome.replacedExisting ? .duplicate : .imported(outcome.document)
        } catch is ReadingDocumentImportError {
            // Every case of this error describes the file's *content*. None of
            // them get better by trying again.
            return .rejected
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
