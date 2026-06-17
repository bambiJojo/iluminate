//  WebReadableTextImporter.swift
//  Ilumionate
//
//  Explicit user-initiated webpage import for Text Trance. This fetches a
//  single URL, extracts readable text, and returns an in-memory script.

import Foundation

protocol WebReadableTextFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: WebReadableTextFetching {}

enum WebReadableTextImportError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedScheme
    case emptyResponse
    case textDecodingFailed
    case requestFailed(statusCode: Int)
    case unsupportedContentType(String)
    case noReadableText

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid website address."
        case .unsupportedScheme:
            return "Use an http or https link."
        case .emptyResponse:
            return "The page returned no text."
        case .textDecodingFailed:
            return "The page text could not be decoded."
        case .requestFailed(let statusCode):
            return "The website returned HTTP \(statusCode)."
        case .unsupportedContentType(let contentType):
            return "This page is \(contentType), not readable text."
        case .noReadableText:
            return "No readable article text was found."
        }
    }
}

struct WebReadableTextImporter: Sendable {
    private let fetcher: any WebReadableTextFetching

    init(fetcher: any WebReadableTextFetching = URLSession.shared) {
        self.fetcher = fetcher
    }

    func importScript(from rawURL: String,
                      title rawTitle: String = "",
                      theme: ScriptTheme = .focus) async throws -> TranceScript {
        let url = try Self.normalizedURL(from: rawURL)
        return try await importScript(from: url, title: rawTitle, theme: theme)
    }

    func importScript(from url: URL,
                      title rawTitle: String = "",
                      theme: ScriptTheme = .focus) async throws -> TranceScript {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("text/html,text/plain;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")

        let (data, response) = try await fetcher.data(for: request)
        try validate(response: response)

        guard data.isEmpty == false else {
            throw WebReadableTextImportError.emptyResponse
        }

        let pageText = try decode(data)
        let readableText = try readableText(from: pageText, response: response, url: url)
        let title = Self.scriptTitle(
            rawTitle: rawTitle,
            html: pageText,
            url: url
        )

        return TranceScript(
            schemaVersion: TranceScriptLibrary.currentSchemaVersion,
            id: "web-\(UUID().uuidString)",
            title: title,
            theme: theme,
            supportedArcs: [.fullText],
            language: "en",
            source: ScriptSource(kind: .importedWeb, generator: url.absoluteString, reviewed: false),
            segments: [
                TranceScriptSegment(
                    phase: .induction,
                    text: readableText,
                    pacing: SegmentPacing(baseWPM: 150),
                    arcs: nil,
                    triggersHandoff: nil
                )
            ]
        )
    }

    static func normalizedURL(from rawValue: String) throws -> URL {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { throw WebReadableTextImportError.invalidURL }

        if let explicitScheme = URLComponents(string: value)?.scheme?.lowercased() {
            guard explicitScheme == "http" || explicitScheme == "https" else {
                throw WebReadableTextImportError.unsupportedScheme
            }
        }

        let normalized = value.contains("://") ? value : "https://\(value)"
        guard var components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              host.isEmpty == false else {
            throw WebReadableTextImportError.invalidURL
        }

        components.scheme = scheme
        components.host = host
        guard let url = components.url else {
            throw WebReadableTextImportError.invalidURL
        }
        return url
    }

    private func validate(response: URLResponse) throws {
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw WebReadableTextImportError.requestFailed(statusCode: http.statusCode)
        }
    }

    private func decode(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        throw WebReadableTextImportError.textDecodingFailed
    }

    private func readableText(from pageText: String, response: URLResponse, url: URL) throws -> String {
        let mimeType = response.mimeType?.lowercased()
        if mimeType == nil || mimeType == "text/html" || mimeType == "application/xhtml+xml" {
            return try extractHTML(pageText)
        }
        if mimeType == "text/plain" || url.pathExtension.lowercased() == "txt" {
            return try ReadableWebTextExtractor.normalizePlainText(pageText)
        }
        throw WebReadableTextImportError.unsupportedContentType(mimeType ?? "unknown content")
    }

    private func extractHTML(_ html: String) throws -> String {
        do {
            return try ReadableWebTextExtractor.extract(fromHTML: html)
        } catch ReadableWebTextExtractionError.noReadableText {
            throw WebReadableTextImportError.noReadableText
        }
    }

    private static func scriptTitle(rawTitle: String, html: String, url: URL) -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty == false { return title }
        if let pageTitle = ReadableWebTextExtractor.title(fromHTML: html) {
            return pageTitle
        }
        return url.host(percentEncoded: false) ?? "Imported Webpage"
    }
}
