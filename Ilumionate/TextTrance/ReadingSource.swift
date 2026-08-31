//  ReadingSource.swift
//  Ilumionate
//
//  User-managed links for externally hosted reading material.

import Foundation

enum ReadingSourceCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case publicDomain
    case openLibrary
    case scriptDirectory
    case userAdded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .publicDomain:    return "Public Domain"
        case .openLibrary:     return "Libraries"
        case .scriptDirectory: return "Scripts"
        case .userAdded:       return "Custom"
        }
    }
}

enum ReadingSourceLicenseKind: String, Codable, Sendable {
    case publicDomain
    case creativeCommons
    case thirdPartyTerms
    case userProvided
}

enum ReadingSourceImportPolicy: String, Codable, Sendable {
    /// Open the website only. Future text extraction should stay disabled.
    case linkOnly
    /// User may explicitly import readable text after reviewing source terms.
    case userInitiatedImport
    /// Source has enough structure to support a future first-party catalog.
    case catalogPlanned
}

enum ReadingSourceContentRating: String, Codable, Sendable {
    case general
    case mixed
}

struct ReadingSource: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var url: URL
    var category: ReadingSourceCategory
    var summary: String
    var licenseKind: ReadingSourceLicenseKind
    var licenseNote: String
    var contentNote: String
    var importPolicy: ReadingSourceImportPolicy
    var contentRating: ReadingSourceContentRating
    var isCurated: Bool
    var addedDate: Date?

    var canImport: Bool {
        importPolicy == .userInitiatedImport || importPolicy == .catalogPlanned
    }
}

// MARK: - Catalog

enum ReadingSourceCatalog {
    /// Intentionally empty. LumeSync does not ship recommended or preconfigured
    /// websites; every source is supplied and managed by the user.
    static let curatedSources: [ReadingSource] = []

    static var curatedIDs: Set<String> {
        Set(curatedSources.map(\.id))
    }
}

nonisolated enum ReadingSourceSearch {
    static func filter(_ sources: [ReadingSource], query rawQuery: String) -> [ReadingSource] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return sources }

        return sources.filter { source in
            source.title.localizedStandardContains(query)
                || source.summary.localizedStandardContains(query)
                || source.url.absoluteString.localizedStandardContains(query)
        }
    }
}
