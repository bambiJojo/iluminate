//  ReadingSourceCatalogTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct ReadingSourceCatalogTests {

    // MARK: Gate logic

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

    @Test func adultSourceUnconfirmedRequestsConfirmation() {
        let source = Self.makeSource(rating: .adultOnly)
        #expect(openAction(for: source, adultConfirmed: false) == .confirmAdult(source.url))
    }

    @Test func adultSourceConfirmedBrowsesDirectly() {
        let source = Self.makeSource(rating: .adultOnly)
        #expect(openAction(for: source, adultConfirmed: true) == .browse(source.url))
    }

    @Test func generalSourceBrowsesRegardlessOfConfirmation() {
        let source = Self.makeSource(rating: .general)
        #expect(openAction(for: source, adultConfirmed: false) == .browse(source.url))
        #expect(openAction(for: source, adultConfirmed: true) == .browse(source.url))
    }

    @Test func mixedSourceBrowsesRegardlessOfConfirmation() {
        let source = Self.makeSource(rating: .mixed)
        #expect(openAction(for: source, adultConfirmed: false) == .browse(source.url))
        #expect(openAction(for: source, adultConfirmed: true) == .browse(source.url))
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

    // MARK: New adult directories

    private static let newAdultIDs = [
        "mc-stories",
        "spirals-nightclub",
        "nimja-hypno",
        "literotica-mc",
        "warpmymind",
        "hypnohub",
        "hypnotube-stories",
        "reddit-hypnautimagery"
    ]

    @Test func newAdultDirectoriesArePresent() {
        let ids = Set(ReadingSourceCatalog.curatedSources.map(\.id))
        for id in Self.newAdultIDs {
            #expect(ids.contains(id), "missing curated source: \(id)")
        }
    }

    @Test func newAdultDirectoriesAreAdultLinkOnly() {
        let byID = Dictionary(
            uniqueKeysWithValues: ReadingSourceCatalog.curatedSources.map { ($0.id, $0) }
        )
        for id in Self.newAdultIDs {
            let source = byID[id]
            #expect(source?.contentRating == .adultOnly, "\(id) should be adultOnly")
            #expect(source?.importPolicy == .linkOnly, "\(id) should be linkOnly")
        }
    }

    @Test func everyCuratedSourceHasWebURL() {
        for source in ReadingSourceCatalog.curatedSources {
            let scheme = source.url.scheme?.lowercased()
            #expect(scheme == "https" || scheme == "http", "\(source.id) has non-web URL")
            #expect(source.url.host(percentEncoded: false)?.isEmpty == false, "\(source.id) has empty host")
        }
    }

    @Test func fragileAdultDirectoriesUseVerifiedLandingPages() {
        let byID = Dictionary(
            uniqueKeysWithValues: ReadingSourceCatalog.curatedSources.map { ($0.id, $0) }
        )

        #expect(byID["spirals-nightclub"]?.url.absoluteString == "https://www.spiralsnightclub.com/")
        #expect(byID["literotica-mc"]?.url.absoluteString == "https://www.literotica.com/c/mind-control")
        #expect(byID["hypnohub"]?.url.absoluteString == "https://hypnohub.net/index.php?page=post&s=list&tags=story")
    }
}
