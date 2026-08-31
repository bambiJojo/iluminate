//
//  WebReadableTextImporter.swift
//  Ilumionate
//
//  Turns the DOM already loaded in the user-visible browser into a local script.

import Foundation

enum WebReadableTextImportError: LocalizedError, Equatable {
    case unsupportedScheme
    case unloadedPage
    case domExtractionFailed
    case noReadableText

    var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            "Only http and https pages can be imported."
        case .unloadedPage:
            "Wait for a webpage to finish loading, then try again."
        case .domExtractionFailed:
            "The current page could not be read. Try sharing selected text from Safari instead."
        case .noReadableText:
            "No readable story text was found. Try sharing selected text from Safari instead."
        }
    }
}

nonisolated struct WebReadableTextImporter: Sendable {
    func importScript(
        html: String,
        title rawTitle: String,
        sourceURL: URL,
        theme: ScriptTheme = .focus
    ) throws -> TranceScript {
        guard let scheme = sourceURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              sourceURL.host() != nil else {
            throw WebReadableTextImportError.unsupportedScheme
        }
        guard html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw WebReadableTextImportError.unloadedPage
        }

        let readableText: String
        do {
            readableText = try ReadableWebTextExtractor.extract(fromHTML: html)
        } catch ReadableWebTextExtractionError.noReadableText {
            throw WebReadableTextImportError.noReadableText
        }

        let suppliedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = suppliedTitle.isEmpty == false
            ? suppliedTitle
            : ReadableWebTextExtractor.title(fromHTML: html)
                ?? sourceURL.host(percentEncoded: false)
                ?? "Imported Webpage"

        return TranceScript(
            schemaVersion: TranceScriptLibrary.currentSchemaVersion,
            id: "web-\(UUID().uuidString)",
            title: title,
            theme: theme,
            supportedArcs: [.fullText],
            language: "en",
            source: ScriptSource(
                kind: .importedWeb,
                generator: sourceURL.absoluteString,
                reviewed: false
            ),
            segments: [
                TranceScriptSegment(
                    phase: .induction,
                    text: readableText,
                    pacing: SegmentPacing(baseWPM: TextPacingEngine.defaultBaseWPM),
                    arcs: nil,
                    triggersHandoff: nil
                )
            ]
        )
    }
}
