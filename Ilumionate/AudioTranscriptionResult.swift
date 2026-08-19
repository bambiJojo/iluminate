//
//  AudioTranscriptionResult.swift
//  Ilumionate
//
//  The transcript value types, independent of how a transcript is produced.
//
//  Extracted from AudioAnalyzer.swift, which imports WhisperKit. Every tool that
//  reads a cached transcript — the labelling app, the corpus harnesses, the
//  evaluation baseline — needs these types and none of them need a speech
//  recogniser to be linkable.
//

import Foundation

/// Result of audio transcription
nonisolated struct AudioTranscriptionResult: Codable, Sendable {
    let fullText: String
    let segments: [AudioTranscriptionSegment]
    let duration: TimeInterval
    let locale: String

    /// - Parameter detectedLanguage: ISO 639-1 language code returned by WhisperKit (e.g. "en", "fr").
    nonisolated init(fullText: String, segments: [AudioTranscriptionSegment], duration: TimeInterval, detectedLanguage: String) {
        self.fullText = Self.sanitizedTranscriptText(fullText)
        self.segments = segments.compactMap { segment in
            let sanitizedText = Self.sanitizedTranscriptText(segment.text)
            guard !sanitizedText.isEmpty else { return nil }
            return AudioTranscriptionSegment(
                id: segment.id,
                text: sanitizedText,
                timestamp: segment.timestamp,
                duration: segment.duration,
                confidence: segment.confidence
            )
        }
        self.duration = duration
        self.locale = detectedLanguage
    }

    nonisolated var wordCount: Int {
        fullText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    nonisolated static func sanitizedTranscriptText(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"<\|[^>]*\|>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[\u{00A0}\s]+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var averageConfidence: Double {
        guard !segments.isEmpty else { return 0 }
        return segments.map { $0.confidence }.reduce(0, +) / Double(segments.count)
    }
}

/// A segment of transcribed text with timing information
nonisolated struct AudioTranscriptionSegment: Codable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Double

    nonisolated init(id: UUID = UUID(), text: String, timestamp: TimeInterval, duration: TimeInterval, confidence: Double) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.confidence = confidence
    }
}
