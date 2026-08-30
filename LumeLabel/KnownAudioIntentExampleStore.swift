//
//  KnownAudioIntentExampleStore.swift
//  LumeLabel
//
//  Converts the bundled Bambi catalog's transcripts and reviewed intentions
//  into semantic examples without requiring an exact audio-file match.
//

import Foundation

nonisolated enum KnownAudioIntentExampleStore {
    enum LoadError: LocalizedError {
        case catalogMissing

        var errorDescription: String? {
            "The bundled known-audio transcript catalog could not be loaded."
        }
    }

    private struct Document: Decodable {
        let entries: [Entry]
    }

    private struct Entry: Decodable {
        let id: String
        let title: String
        let seedProfile: String
        let transcript: String
        let goldLightScore: GoldLightScore
    }

    private struct GoldLightScore: Decodable {
        let designIntent: String
        let evidenceAnchors: [EvidenceAnchor]
    }

    private struct EvidenceAnchor: Decodable {
        let position: Double
        let cue: String
    }

    static func load(bundle: Bundle = .main) throws -> [SemanticPhaseAnalyzer.Example] {
        guard let url = bundle.url(forResource: "KnownAudioCatalog", withExtension: "json"),
              let document = try? JSONDecoder().decode(Document.self, from: Data(contentsOf: url)) else {
            throw LoadError.catalogMissing
        }
        return makeExamples(from: document.entries)
    }

    private static func makeExamples(
        from entries: [Entry]
    ) -> [SemanticPhaseAnalyzer.Example] {
        entries.flatMap { entry in
            let phase = phase(for: entry)
            var examples: [SemanticPhaseAnalyzer.Example] = []
            let intent = entry.goldLightScore.designIntent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if intent.isEmpty == false {
                examples.append(.init(
                    phase: phase,
                    text: "\(entry.title). \(intent)",
                    position: representativePosition(for: entry.seedProfile),
                    sourceFilename: "Known catalog: \(entry.title)"
                ))
            }

            for anchor in entry.goldLightScore.evidenceAnchors.prefix(3) {
                let cue = anchor.cue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cue.isEmpty == false else { continue }
                examples.append(.init(
                    phase: phase,
                    text: cue,
                    position: anchor.position,
                    sourceFilename: "Known catalog: \(entry.title)"
                ))
            }

            examples.append(contentsOf: transcriptExcerpts(from: entry).map { excerpt in
                .init(
                    phase: phase,
                    text: excerpt.text,
                    position: excerpt.position,
                    sourceFilename: "Known transcript: \(entry.title)"
                )
            })
            return examples
        }
    }

    private static func phase(for entry: Entry) -> TrancePhase {
        switch entry.seedProfile {
        case "induction":
            return .induction
        case "deepening", "sleep":
            return .deepening
        case "emergence":
            return .emergence
        default:
            let intent = "\(entry.title) \(entry.goldLightScore.designIntent)".lowercased()
            let brainwashingTerms = [
                "brainwashing", "identity", "mindwipe", "mind wipe", "wipeout",
                "erasure", "erase", "intelligence", "iq ", "amnesia", "takeover",
            ]
            if brainwashingTerms.contains(where: intent.contains) {
                return .brainwashing
            }
            let conditioningTerms = [
                "conditioning", "trigger", "reinforcement", "obedience", "compliance",
                "automatic", "behavior", "trained", "lock", "permanence",
            ]
            if conditioningTerms.contains(where: intent.contains) {
                return .conditioning
            }
            return .suggestions
        }
    }

    private static func representativePosition(for seedProfile: String) -> Double {
        switch seedProfile {
        case "induction": 0.10
        case "deepening": 0.30
        case "emergence": 0.94
        case "sleep": 0.90
        default: 0.65
        }
    }

    private static func transcriptExcerpts(
        from entry: Entry
    ) -> [(text: String, position: Double)] {
        let words = entry.transcript
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { token in
                token.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) == nil
            }
        let excerptWordCount = 40
        guard words.count >= excerptWordCount else { return [] }

        return [0.15, 0.50, 0.85].map { position in
            let center = Int((Double(words.count - 1) * position).rounded())
            let start = min(max(center - excerptWordCount / 2, 0), words.count - excerptWordCount)
            return (
                text: words[start..<(start + excerptWordCount)].joined(separator: " "),
                position: position
            )
        }
    }
}
