//  ReadingScriptCatalogTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

struct ReadingScriptCatalogTests {

    @Test func catalogHasUniqueWebURLs() {
        let entries = ReadingScriptCatalog.curatedEntries
        let ids = Set(entries.map(\.id))
        let urls = Set(entries.map { $0.url.absoluteString })

        #expect(ids.count == entries.count)
        #expect(urls.count == entries.count)

        for entry in entries {
            let scheme = entry.url.scheme?.lowercased()
            #expect(scheme == "https" || scheme == "http", "\(entry.id) has non-web URL")
            #expect(entry.url.host(percentEncoded: false)?.isEmpty == false, "\(entry.id) has empty host")
        }
    }

    @Test func searchMatchesTitleSummaryAndTags() {
        #expect(ReadingScriptCatalog.entries(query: "insomnia").map(\.id) == ["fhs-insomnia"])
        #expect(ReadingScriptCatalog.entries(query: "body scan").map(\.id) == ["fhs-progressive-relaxation"])
        #expect(ReadingScriptCatalog.entries(query: "stress").contains { $0.id == "fhs-self-hypnosis-stress-management" })
    }

    @Test func filtersByKindAndThemeTogether() {
        let sleepSubjects = ReadingScriptCatalog.entries(kind: .subject, theme: .sleep)

        #expect(sleepSubjects.map(\.id) == ["fhs-insomnia", "fhs-sleep-easy"])
        #expect(ReadingScriptCatalog.entries(kind: .induction, theme: .sleep).isEmpty)
    }
}
