// Minimal stand-ins for the app's model types, so the REAL algorithm sources in
// Ilumionate/Structure/ compile and run outside the sandboxed test host.
// Field names and semantics mirror AudioFile.swift and WordTimestamp.swift.

import Foundation

struct WordTimestamp: Codable, Sendable {
    let word: String
    let startTime: Double
    let duration: Double
    var endTime: Double { startTime + duration }
    init(word: String, startTime: Double, duration: Double) {
        self.word = word; self.startTime = startTime; self.duration = duration
    }
}

enum PauseCategory: String, Codable, Sendable {
    case natural, deliberate, musicOnly, silence
}

struct DetectedPause: Codable, Sendable {
    let startTime: TimeInterval
    let duration: TimeInterval
    let category: PauseCategory
}

struct ProsodicProfile: Codable, Sendable {
    let windowDuration: TimeInterval
    let speechRateCurve: [Double]
    let volumeCurve: [Double]
    let pitchCurve: [Double]
    let speechSilenceRatio: [Double]
    let pauses: [DetectedPause]
    let totalDuration: TimeInterval
}

/// Mirrors HypnosisPhaseAnalyzer.approximateWordTimestamps(from:) exactly:
/// words are spread evenly across their segment's duration.
enum WordApproximation {
    static func words(fromSegments segments: [(text: String, timestamp: Double, duration: Double)]) -> [WordTimestamp] {
        var result: [WordTimestamp] = []
        for segment in segments {
            let words = segment.text
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            guard !words.isEmpty else { continue }
            let wordDuration = segment.duration / Double(words.count)
            for (index, word) in words.enumerated() {
                result.append(
                    WordTimestamp(
                        word: word,
                        startTime: segment.timestamp + Double(index) * wordDuration,
                        duration: wordDuration
                    )
                )
            }
        }
        return result
    }
}
