//  ReadingSource.swift
//  Ilumionate
//
//  Link directory model for externally hosted reading material. These records
//  point users to sources; they do not bundle, scrape, or cache site content.

import Foundation

enum ReadingSourceCategory: String, Codable, CaseIterable, Identifiable {
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
    case adultOnly
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

    /// Reserved for the future M4 "import from web" milestone; unused in the link-only M1.
    var canPlanImport: Bool {
        importPolicy == .userInitiatedImport || importPolicy == .catalogPlanned
    }
}

// MARK: - Adult-gate decision

/// What should happen when the user taps a reading source.
enum ReadingSourceOpenAction: Equatable {
    /// Open the URL in the in-app browser now.
    case browse(URL)
    /// Adult source not yet acknowledged — present the 18+ confirmation first.
    case confirmAdult(URL)
}

/// Decides whether a tapped source opens immediately or must clear the adult gate.
/// Pure so it can be unit-tested without any UI.
func openAction(for source: ReadingSource, adultConfirmed: Bool) -> ReadingSourceOpenAction {
    if source.contentRating == .adultOnly && !adultConfirmed {
        return .confirmAdult(source.url)
    }
    return .browse(source.url)
}

// MARK: - Catalog

enum ReadingSourceCatalog {
    static let curatedSources: [ReadingSource] = [
        ReadingSource(
            id: "project-gutenberg",
            title: "Project Gutenberg",
            url: URL(string: "https://www.gutenberg.org/")!,
            category: .publicDomain,
            summary: "Public-domain books and historical hypnotism/autosuggestion texts.",
            licenseKind: .publicDomain,
            licenseNote: "Most titles are unrestricted in the U.S.; verify each item license before reuse.",
            contentNote: "Older health and hypnosis material may contain outdated claims.",
            importPolicy: .catalogPlanned,
            contentRating: .mixed,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "standard-ebooks",
            title: "Standard Ebooks",
            url: URL(string: "https://standardebooks.org/")!,
            category: .publicDomain,
            summary: "Carefully formatted public-domain books suitable for long-form reading.",
            licenseKind: .publicDomain,
            licenseNote: "Titles are published as U.S. public-domain ebook files.",
            contentNote: "General literature; not hypnosis-specific.",
            importPolicy: .catalogPlanned,
            contentRating: .mixed,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "wikisource",
            title: "Wikisource",
            url: URL(string: "https://en.wikisource.org/")!,
            category: .openLibrary,
            summary: "Free library of public-domain and openly licensed source texts.",
            licenseKind: .creativeCommons,
            licenseNote: "Check each work's copyright tag; Wikimedia text attribution may be required.",
            contentNote: "Large mixed library with historical and reference material.",
            importPolicy: .userInitiatedImport,
            contentRating: .mixed,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "internet-archive-texts",
            title: "Internet Archive Texts",
            url: URL(string: "https://archive.org/details/texts")!,
            category: .openLibrary,
            summary: "Large archive of digitized books, scans, OCR text, and library collections.",
            licenseKind: .thirdPartyTerms,
            licenseNote: "License and access rights vary by item; verify before importing or redistributing.",
            contentNote: "Broad mixed archive; item quality and rights metadata vary.",
            importPolicy: .userInitiatedImport,
            contentRating: .mixed,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "open-library",
            title: "Open Library",
            url: URL(string: "https://openlibrary.org/")!,
            category: .openLibrary,
            summary: "Book discovery and library records from the Internet Archive ecosystem.",
            licenseKind: .thirdPartyTerms,
            licenseNote: "Discovery metadata is useful; text availability and rights vary by item.",
            contentNote: "Best used for finding editions and public-domain leads.",
            importPolicy: .catalogPlanned,
            contentRating: .mixed,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "free-hypnosis-scripts-info",
            title: "Free Hypnosis Scripts",
            url: URL(string: "https://freehypnosisscripts.info/free-hypnosis-scripts/")!,
            category: .scriptDirectory,
            summary: "A large free-to-read hypnosis script directory.",
            licenseKind: .thirdPartyTerms,
            licenseNote: "Link-only until written permission or clear redistribution terms are confirmed.",
            contentNote: "Scripts are user-facing hypnosis material; review before personal use.",
            importPolicy: .linkOnly,
            contentRating: .mixed,
            isCurated: true,
            addedDate: nil
        )
    ]

    static var curatedIDs: Set<String> {
        Set(curatedSources.map(\.id))
    }
}
