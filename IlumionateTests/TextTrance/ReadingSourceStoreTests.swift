//
//  ReadingSourceStoreTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct ReadingSourceStoreTests {
    @Test func freshStoreContainsNoSources() throws {
        let (defaults, key) = try makeDefaults()
        let store = ReadingSourceStore(defaults: defaults, storageKey: key)

        #expect(store.customSources.isEmpty)
        #expect(store.allSources.isEmpty)
    }

    @Test func customSourceNormalizesPersistsAndAllowsExplicitImport() throws {
        let (defaults, key) = try makeDefaults()
        let store = ReadingSourceStore(defaults: defaults, storageKey: key)

        let source = try store.addCustomSource(
            title: " My Reading Site ",
            urlString: "Example.com/stories/",
            summary: " Private note "
        )

        #expect(source.title == "My Reading Site")
        #expect(source.url.absoluteString == "https://example.com/stories/")
        #expect(source.summary == "Private note")
        #expect(source.category == .userAdded)
        #expect(source.isCurated == false)
        #expect(source.canImport)

        let reloaded = ReadingSourceStore(defaults: defaults, storageKey: key)
        #expect(reloaded.customSources.count == 1)
        #expect(reloaded.customSources.first?.url == source.url)
        #expect(reloaded.customSources.first?.canImport == true)
    }

    @Test func duplicateAndNonWebSourcesAreRejected() throws {
        let (defaults, key) = try makeDefaults()
        let store = ReadingSourceStore(defaults: defaults, storageKey: key)

        try store.addCustomSource(title: "One", urlString: "https://example.com")

        #expect(throws: ReadingSourceStoreError.duplicateURL) {
            try store.addCustomSource(title: "Two", urlString: "https://EXAMPLE.com/")
        }
        #expect(throws: ReadingSourceStoreError.emptyTitle) {
            try store.addCustomSource(title: "   ", urlString: "https://example.net")
        }
        #expect(throws: ReadingSourceStoreError.invalidURL) {
            try store.addCustomSource(title: "Empty", urlString: "   ")
        }
        for address in [
            "javascript:alert(1)",
            "data:text/html,content",
            "file:///private/story.txt",
            "ftp://example.net/story"
        ] {
            #expect(throws: ReadingSourceStoreError.unsupportedScheme) {
                try store.addCustomSource(title: "Unsupported", urlString: address)
            }
        }
    }

    @Test func deletingOneSourceLeavesTheOthersUntouched() throws {
        let (defaults, key) = try makeDefaults()
        let store = ReadingSourceStore(defaults: defaults, storageKey: key)
        let first = try store.addCustomSource(title: "First", urlString: "first.example")
        let second = try store.addCustomSource(title: "Second", urlString: "second.example")

        store.deleteCustomSource(id: first.id)

        #expect(store.customSources.map(\.id) == [second.id])
    }

    @Test func legacyCustomLinksBecomeImportableWithoutAddingCatalogEntries() throws {
        let (defaults, key) = try makeDefaults()
        let legacyURL = try #require(URL(string: "https://legacy.example/story"))
        let legacy = ReadingSource(
            id: "custom-legacy",
            title: "Legacy Source",
            url: legacyURL,
            category: .userAdded,
            summary: "",
            licenseKind: .userProvided,
            licenseNote: "",
            contentNote: "",
            importPolicy: .linkOnly,
            contentRating: .mixed,
            isCurated: false,
            addedDate: Date(timeIntervalSince1970: 100)
        )
        defaults.set(try JSONEncoder().encode([legacy]), forKey: key)

        let store = ReadingSourceStore(defaults: defaults, storageKey: key)

        #expect(store.customSources.first?.id == legacy.id)
        #expect(store.customSources.first?.canImport == true)
        #expect(ReadingSourceCatalog.curatedSources.isEmpty)
    }

    @Test func searchUsesTitleNoteAndAddress() throws {
        let (defaults, key) = try makeDefaults()
        let store = ReadingSourceStore(defaults: defaults, storageKey: key)
        try store.addCustomSource(
            title: "Evening Reading",
            urlString: "library.example/collection",
            summary: "A PRIVATE note"
        )

        #expect(ReadingSourceSearch.filter(store.customSources, query: "evening").count == 1)
        #expect(ReadingSourceSearch.filter(store.customSources, query: "private").count == 1)
        #expect(ReadingSourceSearch.filter(store.customSources, query: "collection").count == 1)
        #expect(ReadingSourceSearch.filter(store.customSources, query: "missing").isEmpty)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "ReadingSourceStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, "readingSourceCustomLinks")
    }
}
