//
//  BundledAudioTranscriptCatalog.swift
//  Ilumionate
//

import Foundation

/// Target-neutral access to analyzer-ready transcripts bundled with the app.
///
/// This deliberately depends only on the filename, duration, and transcription
/// models so both Ilumionate and LumeLabel can use it before loading WhisperKit.
nonisolated struct BundledAudioTranscriptCatalog: Sendable {
    static let shared = BundledAudioTranscriptCatalog()

    private let entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries
    }

    init(
        bundle: Bundle = .main,
        resourceName: String = "KnownAudioCatalog"
    ) {
        guard let url = Self.resourceURL(
            named: resourceName,
            in: bundle
        ),
        let data = try? Data(contentsOf: url),
        let document = try? JSONDecoder().decode(Document.self, from: data),
        document.schemaVersion == 1 else {
            entries = []
            return
        }

        entries = document.entries
    }

    func transcription(
        filename: String,
        duration: TimeInterval
    ) -> AudioTranscriptionResult? {
        guard let entry = bestMatch(for: filename),
              entry.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        return TimestampedTranscriptBuilder().makeResult(
            transcript: entry.transcript,
            duration: duration
        )
    }

    private func bestMatch(for filename: String) -> Entry? {
        let candidate = Self.normalized(filename)
        guard candidate.count >= 6 else {
            return nil
        }

        return entries
            .compactMap { entry -> (entry: Entry, confidence: Double)? in
                let confidence = (entry.aliases + [entry.title])
                    .map(Self.normalized)
                    .map {
                        Self.matchConfidence(
                            candidate: candidate,
                            alias: $0
                        )
                    }
                    .max() ?? 0
                guard confidence >= 0.90 else {
                    return nil
                }
                return (entry, confidence)
            }
            .max { $0.confidence < $1.confidence }?
            .entry
    }

    private static func matchConfidence(
        candidate: String,
        alias: String
    ) -> Double {
        guard !alias.isEmpty else {
            return 0
        }
        if candidate == alias {
            return 1
        }

        let aliasTokens = alias.split(separator: " ")
        if aliasTokens.count >= 3, candidate.hasSuffix(" \(alias)") {
            return 0.98
        }

        let candidateTokens = Set(candidate.split(separator: " ").map(String.init))
        let expectedTokens = Set(aliasTokens.map(String.init))
        guard expectedTokens.count >= 3 else {
            return 0
        }

        let coverage = Double(candidateTokens.intersection(expectedTokens).count)
            / Double(expectedTokens.count)
        let extraTokenCount = candidateTokens.subtracting(expectedTokens).count
        return coverage == 1 && extraTokenCount <= 4 ? 0.92 : 0
    }

    private static func normalized(_ value: String) -> String {
        let filename = URL(filePath: value)
            .deletingPathExtension()
            .lastPathComponent
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()

        var tokens = filename
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: " ",
                options: .regularExpression
            )
            .split(separator: " ")
            .map(String.init)

        if let first = tokens.first,
           let trackNumber = Int(first),
           (0...99).contains(trackNumber) {
            tokens.removeFirst()
        }

        let disposableSuffixes: Set<String> = [
            "audio", "final", "hq", "official", "remastered",
            "mp3", "m4a", "wav", "v2", "320kbps"
        ]
        while let last = tokens.last, disposableSuffixes.contains(last) {
            tokens.removeLast()
        }

        return tokens.joined(separator: " ")
    }

    private static func resourceURL(
        named resourceName: String,
        in preferredBundle: Bundle
    ) -> URL? {
        if let url = preferredBundle.url(
            forResource: resourceName,
            withExtension: "json"
        ) {
            return url
        }

        return (Bundle.allBundles + Bundle.allFrameworks)
            .lazy
            .compactMap {
                $0.url(forResource: resourceName, withExtension: "json")
            }
            .first
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let entries: [Entry]
    }

    struct Entry: Decodable, Sendable {
        let title: String
        let aliases: [String]
        let transcript: String
    }
}

/// Resolves a transcript from bundled data first and invokes the supplied
/// transcriber only when the filename is not recognized.
@MainActor
struct AudioTranscriptResolver {
    private let catalog: BundledAudioTranscriptCatalog

    init(catalog: BundledAudioTranscriptCatalog = .shared) {
        self.catalog = catalog
    }

    func transcribe(
        filename: String,
        duration: TimeInterval,
        fallback: () async throws -> AudioTranscriptionResult
    ) async throws -> AudioTranscriptionResult {
        if let bundled = catalog.transcription(
            filename: filename,
            duration: duration
        ) {
            return bundled
        }

        return try await fallback()
    }
}
