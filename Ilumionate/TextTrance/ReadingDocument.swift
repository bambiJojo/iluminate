//  ReadingDocument.swift
//  Ilumionate
//
//  Local document metadata for text, PDF, and ePub reader imports. The extracted text is
//  stored separately so the library can stay light and fast to decode.

import Foundation

enum ReadingDocumentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case pdf
    case epub
    // Added last so the raw values of the cases above are untouched and a
    // previously persisted documents.json still decodes.
    case text

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .pdf:  return "PDF"
        case .epub: return "ePub"
        case .text: return "Text"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .pdf:  return "doc.richtext.fill"
        case .epub: return "book.closed.fill"
        case .text: return "doc.text.fill"
        }
    }

    nonisolated init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "pdf":  self = .pdf
        case "epub": self = .epub
        case "txt", "md", "markdown": self = .text
        default: return nil
        }
    }
}

nonisolated struct ReadingDocument: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var kind: ReadingDocumentKind
    var originalFilename: String
    var importedAt: Date
    var wordCount: Int
    var characterCount: Int
    var contentHash: String
    var textFilename: String

    var scriptID: String { "document-\(id)" }

    var wordCountSummary: String {
        "\(wordCount.formatted(.number)) words"
    }

    var importSummary: String {
        "\(kind.displayName) import"
    }
}

struct ExtractedReadingDocument: Sendable {
    let title: String
    let kind: ReadingDocumentKind
    let originalFilename: String
    let text: String
}
