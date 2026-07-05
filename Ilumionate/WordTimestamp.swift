//
//  WordTimestamp.swift
//  Ilumionate
//
//  Extracted from HypnosisPhaseAnalyzer.swift (structural decomposition).
//

import Foundation

// MARK: - Word Timestamp

/// A single word with its approximate position in the audio timeline.
/// Derived from WhisperKit segment output by distributing words evenly
/// across each segment's time span.
struct WordTimestamp: Identifiable, Codable, Sendable {
    let id: UUID
    let word: String
    let startTime: Double  // seconds from audio start
    let duration: Double

    nonisolated var endTime: Double { startTime + duration }

    nonisolated init(id: UUID = UUID(), word: String, startTime: Double, duration: Double) {
        self.id = id
        self.word = word
        self.startTime = startTime
        self.duration = duration
    }
}
