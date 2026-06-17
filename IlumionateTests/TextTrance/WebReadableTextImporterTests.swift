//  WebReadableTextImporterTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

struct WebReadableTextImporterTests {

    @Test func importsHTMLAsCleanWebScript() async throws {
        let url = try WebReadableTextImporter.normalizedURL(from: "example.com/story")
        let html = """
        <html>
          <head><title>Quiet &amp; Clean</title></head>
          <body>
            <nav>Home Search Login</nav>
            <article>
              <p>The useful paragraph stays inside the reading flow.</p>
              <div class="newsletter">Subscribe for updates</div>
              <p>Another useful paragraph follows with enough words for extraction.</p>
            </article>
          </body>
        </html>
        """
        let importer = WebReadableTextImporter(fetcher: StubFetcher(
            data: Data(html.utf8),
            response: response(url: url, contentType: "text/html")
        ))

        let script = try await importer.importScript(from: "example.com/story")
        let segment = try #require(script.segments.first)

        #expect(script.title == "Quiet & Clean")
        #expect(script.source.kind == .importedWeb)
        #expect(script.source.reviewed == false)
        #expect(script.source.generator == "https://example.com/story")
        #expect(script.supportedArcs == [.fullText])
        #expect(segment.text.contains("The useful paragraph stays"))
        #expect(segment.text.contains("Another useful paragraph follows"))
        #expect(segment.text.localizedCaseInsensitiveContains("Home Search Login") == false)
        #expect(segment.text.localizedCaseInsensitiveContains("Subscribe") == false)
    }

    @Test func customTitleOverridesPageTitle() async throws {
        let url = URL(string: "https://example.com/story")!
        let importer = WebReadableTextImporter(fetcher: StubFetcher(
            data: Data("""
            <article>
              <p>This readable article has enough useful words to become a script.</p>
            </article>
            """.utf8),
            response: response(url: url, contentType: "text/html")
        ))

        let script = try await importer.importScript(from: url, title: "My Session")

        #expect(script.title == "My Session")
    }

    @Test func importCanSetCatalogTheme() async throws {
        let url = URL(string: "https://example.com/sleep")!
        let importer = WebReadableTextImporter(fetcher: StubFetcher(
            data: Data("""
            <article>
              <p>This sleep article has enough useful words to become a script.</p>
            </article>
            """.utf8),
            response: response(url: url, contentType: "text/html")
        ))

        let script = try await importer.importScript(from: url, title: "Sleep Script", theme: .sleep)

        #expect(script.theme == .sleep)
    }

    @Test func importsPlainTextResponses() async throws {
        let url = URL(string: "https://example.com/plain.txt")!
        let importer = WebReadableTextImporter(fetcher: StubFetcher(
            data: Data("A plain text page can become reader text when it has enough words.".utf8),
            response: response(url: url, contentType: "text/plain")
        ))

        let script = try await importer.importScript(from: url)
        let segment = try #require(script.segments.first)

        #expect(segment.text == "A plain text page can become reader text when it has enough words.")
    }

    @Test func normalizesMissingSchemeToHTTPS() throws {
        let url = try WebReadableTextImporter.normalizedURL(from: "Example.com/path")
        #expect(url.absoluteString == "https://example.com/path")
    }

    @Test func rejectsUnsupportedSchemes() {
        #expect(throws: WebReadableTextImportError.unsupportedScheme) {
            try WebReadableTextImporter.normalizedURL(from: "file:///private/tmp/story.html")
        }
    }

    @Test func rejectsHTTPFailures() async {
        let url = URL(string: "https://example.com/missing")!
        let importer = WebReadableTextImporter(fetcher: StubFetcher(
            data: Data("Not found".utf8),
            response: response(url: url, statusCode: 404, contentType: "text/html")
        ))

        await #expect(throws: WebReadableTextImportError.requestFailed(statusCode: 404)) {
            try await importer.importScript(from: url)
        }
    }

    @Test func rejectsUnsupportedContentTypes() async {
        let url = URL(string: "https://example.com/file.pdf")!
        let importer = WebReadableTextImporter(fetcher: StubFetcher(
            data: Data("%PDF".utf8),
            response: response(url: url, contentType: "application/pdf")
        ))

        await #expect(throws: WebReadableTextImportError.unsupportedContentType("application/pdf")) {
            try await importer.importScript(from: url)
        }
    }

    private func response(url: URL,
                          statusCode: Int = 200,
                          contentType: String) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
    }
}

private struct StubFetcher: WebReadableTextFetching {
    let data: Data
    let response: URLResponse

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        (data, response)
    }
}
