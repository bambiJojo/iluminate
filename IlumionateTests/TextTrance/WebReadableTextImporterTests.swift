//
//  WebReadableTextImporterTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct WebReadableTextImporterTests {
    @Test func importsAlreadyLoadedHTMLAsLocalWebScript() throws {
        let url = try #require(URL(string: "https://example.com/story/part-two"))
        let html = """
        <html>
          <head><title>Visible Story</title></head>
          <body><article>
            <p>The current page supplies this useful opening paragraph.</p>
            <p>A second paragraph makes the loaded document readable.</p>
          </article></body>
        </html>
        """

        let script = try WebReadableTextImporter().importScript(
            html: html,
            title: "",
            sourceURL: url,
            theme: .relaxation
        )
        let segment = try #require(script.segments.first)

        #expect(script.title == "Visible Story")
        #expect(script.theme == .relaxation)
        #expect(script.source.kind == .importedWeb)
        #expect(script.source.generator == url.absoluteString)
        #expect(script.source.reviewed == false)
        #expect(script.supportedArcs == [.fullText])
        #expect(segment.text.contains("current page supplies"))
    }

    @Test func visibleBrowserTitleOverridesDocumentTitle() throws {
        let url = try #require(URL(string: "https://example.com/story"))
        let html = """
        <title>Document Title</title>
        <article><p>This article contains enough useful words to become reader content.</p></article>
        """

        let script = try WebReadableTextImporter().importScript(
            html: html,
            title: "Browser Title",
            sourceURL: url
        )

        #expect(script.title == "Browser Title")
    }

    @Test func rejectsNonWebEmptyAndUnreadablePages() throws {
        let webURL = try #require(URL(string: "https://example.com"))
        let fileURL = URL(filePath: "/private/story.html")

        #expect(throws: WebReadableTextImportError.unsupportedScheme) {
            try WebReadableTextImporter().importScript(
                html: "<article>This has enough words to otherwise be imported safely.</article>",
                title: "Story",
                sourceURL: fileURL
            )
        }
        #expect(throws: WebReadableTextImportError.unloadedPage) {
            try WebReadableTextImporter().importScript(
                html: "   ",
                title: "Story",
                sourceURL: webURL
            )
        }
        #expect(throws: WebReadableTextImportError.noReadableText) {
            try WebReadableTextImporter().importScript(
                html: "<nav>Home Search</nav>",
                title: "Story",
                sourceURL: webURL
            )
        }
    }
}
