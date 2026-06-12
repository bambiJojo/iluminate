//  ReadingSourceStoreTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct ReadingSourceStoreTests {

    @Test func curatedSourcesHaveStableSafeShape() {
        let sources = ReadingSourceCatalog.curatedSources
        let allSourcesAreCurated = sources.allSatisfy { $0.isCurated }
        let allSourcesAvoidAdultOnlyRating = sources.allSatisfy { $0.contentRating != .adultOnly }
        let allSourcesUseWebURLs = sources.allSatisfy { source in
            let scheme = source.url.scheme?.lowercased()
            return scheme == "https" || scheme == "http"
        }

        #expect(sources.count >= 5)
        #expect(Set(sources.map(\.id)).count == sources.count)
        #expect(allSourcesAreCurated)
        #expect(allSourcesAvoidAdultOnlyRating)
        #expect(allSourcesUseWebURLs)
    }

    @Test func customSourceNormalizesAndPersists() throws {
        let defaults = makeDefaults()
        let key = "readingSources"
        let store = ReadingSourceStore(defaults: defaults, storageKey: key)

        let source = try store.addCustomSource(
            title: " Example Scripts ",
            urlString: "Example.com/stories/",
            summary: " Personal source "
        )

        #expect(source.title == "Example Scripts")
        #expect(source.url.absoluteString == "https://example.com/stories/")
        #expect(source.summary == "Personal source")
        #expect(source.category == .userAdded)
        #expect(source.isCurated == false)

        let reloaded = ReadingSourceStore(defaults: defaults, storageKey: key)
        #expect(reloaded.customSources.count == 1)
        #expect(reloaded.customSources[0].url.absoluteString == "https://example.com/stories/")
    }

    @Test func duplicateCustomURLIsRejectedAcrossCuratedAndCustomSources() throws {
        let store = ReadingSourceStore(defaults: makeDefaults(), storageKey: "readingSources")

        try store.addCustomSource(title: "One", urlString: "https://example.com")
        #expect(throws: ReadingSourceStoreError.duplicateURL) {
            try store.addCustomSource(title: "Two", urlString: "https://example.com/")
        }
        #expect(throws: ReadingSourceStoreError.duplicateURL) {
            try store.addCustomSource(title: "Gutenberg Copy", urlString: "https://www.gutenberg.org")
        }
    }

    @Test func invalidURLsAreRejected() {
        let store = ReadingSourceStore(defaults: makeDefaults(), storageKey: "readingSources")

        #expect(throws: ReadingSourceStoreError.emptyTitle) {
            try store.addCustomSource(title: "   ", urlString: "https://example.com")
        }
        #expect(throws: ReadingSourceStoreError.invalidURL) {
            try store.addCustomSource(title: "Bad", urlString: "   ")
        }
        #expect(throws: ReadingSourceStoreError.unsupportedScheme) {
            try store.addCustomSource(title: "FTP", urlString: "ftp://example.com")
        }
        // Scheme-bypass regression: dangerous non-http(s) schemes must not slip through.
        #expect(throws: ReadingSourceStoreError.unsupportedScheme) {
            try store.addCustomSource(title: "JS", urlString: "javascript:alert(1)")
        }
        #expect(throws: ReadingSourceStoreError.unsupportedScheme) {
            try store.addCustomSource(title: "Data", urlString: "data:text/html,<script>")
        }
        #expect(throws: ReadingSourceStoreError.unsupportedScheme) {
            try store.addCustomSource(title: "File", urlString: "file:///etc/passwd")
        }
    }

    @Test func deletingCustomSourceDoesNotAffectCuratedSources() throws {
        let store = ReadingSourceStore(defaults: makeDefaults(), storageKey: "readingSources")
        let source = try store.addCustomSource(title: "One", urlString: "https://example.com")

        store.deleteCustomSource(id: source.id)

        #expect(store.customSources.isEmpty)
        #expect(store.allSources.count == ReadingSourceCatalog.curatedSources.count)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ReadingSourceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
