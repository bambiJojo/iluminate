//  ReadingSourceCatalogTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct ReadingSourceCatalogTests {

    // MARK: Gate logic

    private func makeSource(rating: ReadingSourceContentRating) -> ReadingSource {
        ReadingSource(
            id: "test-\(rating.rawValue)",
            title: "Test",
            url: URL(string: "https://example.com/")!,
            category: .scriptDirectory,
            summary: "",
            licenseKind: .thirdPartyTerms,
            licenseNote: "",
            contentNote: "",
            importPolicy: .linkOnly,
            contentRating: rating,
            isCurated: true,
            addedDate: nil
        )
    }

    @Test func adultSourceUnconfirmedRequestsConfirmation() {
        let source = makeSource(rating: .adultOnly)
        #expect(openAction(for: source, adultConfirmed: false) == .confirmAdult(source.url))
    }

    @Test func adultSourceConfirmedBrowsesDirectly() {
        let source = makeSource(rating: .adultOnly)
        #expect(openAction(for: source, adultConfirmed: true) == .browse(source.url))
    }

    @Test func generalSourceBrowsesRegardlessOfConfirmation() {
        let source = makeSource(rating: .general)
        #expect(openAction(for: source, adultConfirmed: false) == .browse(source.url))
        #expect(openAction(for: source, adultConfirmed: true) == .browse(source.url))
    }
}
