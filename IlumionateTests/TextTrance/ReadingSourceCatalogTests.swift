//  ReadingSourceCatalogTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct ReadingSourceCatalogTests {

    private static func makeSource(
        rating: ReadingSourceContentRating,
        importPolicy: ReadingSourceImportPolicy = .linkOnly
    ) -> ReadingSource {
        ReadingSource(
            id: "test-\(rating.rawValue)",
            title: "Test",
            url: URL(string: "https://example.com/")!,
            category: .scriptDirectory,
            summary: "",
            licenseKind: .thirdPartyTerms,
            licenseNote: "",
            contentNote: "",
            importPolicy: importPolicy,
            contentRating: rating,
            isCurated: true,
            addedDate: nil
        )
    }

    @Test(arguments: [
        (ReadingSourceImportPolicy.linkOnly, false),
        (.userInitiatedImport, true),
        (.catalogPlanned, true)
    ])
    func importPermissionMatchesSourcePolicy(policy: ReadingSourceImportPolicy, expected: Bool) {
        let source = Self.makeSource(rating: .general, importPolicy: policy)
        #expect(source.canImport == expected)
    }

    @Test func shippingCatalogContainsNoBuiltInWebsites() {
        #expect(ReadingSourceCatalog.curatedSources.isEmpty)
        #expect(ReadingSourceCatalog.curatedIDs.isEmpty)
    }
}
