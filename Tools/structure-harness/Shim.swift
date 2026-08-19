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
    let id: UUID
    let startTime: TimeInterval
    let duration: TimeInterval
    let precedingText: String?
    let followingText: String?
    let category: PauseCategory

    init(id: UUID = UUID(), startTime: TimeInterval, duration: TimeInterval,
         precedingText: String? = nil, followingText: String? = nil,
         category: PauseCategory = .natural) {
        self.id = id; self.startTime = startTime; self.duration = duration
        self.precedingText = precedingText; self.followingText = followingText
        self.category = category
    }
}

struct ProsodicProfile: Codable, Sendable {
    init(windowDuration: TimeInterval, speechRateCurve: [Double], volumeCurve: [Double],
         pitchCurve: [Double], speechSilenceRatio: [Double], pauses: [DetectedPause],
         totalDuration: TimeInterval) {
        self.windowDuration = windowDuration; self.speechRateCurve = speechRateCurve
        self.volumeCurve = volumeCurve; self.pitchCurve = pitchCurve
        self.speechSilenceRatio = speechSilenceRatio; self.pauses = pauses
        self.totalDuration = totalDuration
    }

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

// MARK: - Additions for compiling the real ProsodyAnalyzer

struct AudioTranscriptionSegment: Codable, Sendable {
    let id: UUID
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Double
    init(id: UUID = UUID(), text: String, timestamp: TimeInterval, duration: TimeInterval, confidence: Double) {
        self.id = id; self.text = text; self.timestamp = timestamp
        self.duration = duration; self.confidence = confidence
    }
}

/// Only the one static the prosody analyser calls.
enum HypnosisPhaseAnalyzer {
    nonisolated static func approximateWordTimestamps(
        from segments: [AudioTranscriptionSegment]
    ) -> [WordTimestamp] {
        WordApproximation.words(
            fromSegments: segments.map { ($0.text, $0.timestamp, $0.duration) }
        )
    }
}

/// The analyser only reads these five values through its Config bridge.
enum AnalyzerConfig {
    struct Prosody: Sendable {
        var speechRateWindowSeconds: TimeInterval = 3.0
        var pauseThresholdSeconds: TimeInterval = 1.0
        var deliberatePauseMinSeconds: TimeInterval = 3.0
        var musicOnlyPauseMinSeconds: TimeInterval = 5.0
    }
}

/// `ProsodyAnalyzer` declares conformance; nothing here calls through it.
protocol ProsodyAnalyzingService: Sendable {}
