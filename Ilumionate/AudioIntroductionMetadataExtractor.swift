//
//  AudioIntroductionMetadataExtractor.swift
//  Ilumionate
//

import Foundation

/// Extracts creator and title announcements from the opening of spoken audio.
nonisolated enum AudioIntroductionMetadataExtractor {
    private static let introCharacterLimit = 1_500

    static func metadata(from transcript: String, filename: String) -> AudioTrackMetadata? {
        let intro = String(transcript.prefix(introCharacterLimit))
        guard !intro.isEmpty else { return nil }

        let pairPatterns = [
            #"\b(?:hello|hi|welcome)?[\s,!.]*(?:this is|i am|i['’]m|my name is)\s+([a-z][a-z .,'’\-]{1,60}?)[,.]?\s+(?:and\s+)?(?:this is|welcome to|you are listening to)\s+([^.!?]{3,100})"#,
            #"\b(?:hello|hi|welcome)?[\s,!.]*(?:this is|i am|i['’]m|my name is)\s+([a-z][a-z .,'’\-]{1,60}?)[.!?]\s*(?:and\s+)?(?:this is|welcome to|you are listening to)\s+([^.!?]{3,100})"#
        ]

        for pattern in pairPatterns {
            if let captures = captures(pattern: pattern, in: intro), captures.count == 2 {
                let creator = cleanCreator(captures[0])
                let title = cleanTitle(captures[1])
                guard creator != nil || title != nil else { continue }

                let filenameMatch = title.map {
                    similarity($0, URL(filePath: filename).deletingPathExtension().lastPathComponent)
                } ?? 0
                return AudioTrackMetadata(
                    generatedTitle: title,
                    creator: creator,
                    confidence: filenameMatch >= 0.55 ? 0.96 : 0.88
                )
            }
        }

        let creator = captures(
            pattern: #"\b(?:hello|hi|welcome)?[\s,!.]*(?:this is|i am|i['’]m|my name is)\s+([^.!?]{2,60}?)(?=[.!?]|\s+(?:and\s+)?welcome\b)"#,
            in: intro
        )?.first.flatMap(cleanCreator)
        let title = captures(
            pattern: #"\b(?:welcome to|you are listening to|the title is|today['’]s (?:audio|session)(?: is)?)\s+([^.!?]{3,100})"#,
            in: intro
        )?.first.flatMap(cleanTitle)

        guard creator != nil || title != nil else { return nil }
        return AudioTrackMetadata(
            generatedTitle: title,
            creator: creator,
            confidence: creator != nil && title != nil ? 0.86 : 0.78
        )
    }

    static func closestMatch(
        to value: String,
        among candidates: [String],
        minimumSimilarity: Double = 0.84
    ) -> String? {
        candidates
            .map { (candidate: $0, score: similarity(value, $0)) }
            .filter { $0.score >= minimumSimilarity }
            .max { $0.score < $1.score }?
            .candidate
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }

        let editScore = 1 - Double(editDistance(left, right)) / Double(max(left.count, right.count))
        let leftWords = Set(left.split(separator: " ").map(String.init))
        let rightWords = Set(right.split(separator: " ").map(String.init))
        let unionCount = leftWords.union(rightWords).count
        let wordScore = unionCount == 0
            ? 0
            : Double(leftWords.intersection(rightWords).count) / Double(unionCount)
        return max(editScore, wordScore)
    }

    private static func captures(pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range) else { return nil }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func cleanCreator(_ value: String) -> String? {
        let cleaned = clean(value)
        guard let cleaned, cleaned.split(separator: " ").count <= 7 else { return nil }
        let normalized = normalized(cleaned)
        let nonNameWords = ["session", "audio", "meditation", "hypnosis", "recording"]
        guard !normalized.hasPrefix("a "),
              !normalized.hasPrefix("an "),
              !nonNameWords.contains(where: { normalized.split(separator: " ").contains(Substring($0)) }) else {
            return nil
        }
        return cleaned
    }

    private static func cleanTitle(_ value: String) -> String? {
        let cleaned = clean(value)
        guard let cleaned, cleaned.split(separator: " ").count <= 16 else { return nil }
        return cleaned
    }

    private static func clean(_ value: String) -> String? {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(Swift.min(
                    current[rightIndex] + 1,
                    Swift.min(
                        previous[rightIndex + 1] + 1,
                        previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                    )
                ))
            }
            previous = current
        }
        return previous[right.count]
    }
}
