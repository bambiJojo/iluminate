//
//  TranscriptionTypes.swift
//  AnalyzerImprover
//
//  Shared transcript models used by the analyzer optimizer when running from
//  cached transcript exports.
//

import Foundation

struct AudioTranscriptionResult: Codable, Sendable {
    let fullText: String
    let segments: [AudioTranscriptionSegment]
    let duration: TimeInterval
    let locale: String

    init(
        fullText: String,
        segments: [AudioTranscriptionSegment],
        duration: TimeInterval,
        detectedLanguage: String
    ) {
        self.fullText = fullText
        self.segments = segments
        self.duration = duration
        self.locale = detectedLanguage
    }

    var wordCount: Int {
        fullText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    var averageConfidence: Double {
        guard !segments.isEmpty else { return 0 }
        return segments.map(\.confidence).reduce(0, +) / Double(segments.count)
    }
}

struct AudioTranscriptionSegment: Codable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Double

    init(
        id: UUID = UUID(),
        text: String,
        timestamp: TimeInterval,
        duration: TimeInterval,
        confidence: Double
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.confidence = confidence
    }
}

enum AnalyzerError: LocalizedError {
    case whisperKitNotInitialized
    case transcriptionFailed(Error)
    case audioFileInvalid
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .whisperKitNotInitialized:
            return "WhisperKit is not initialized. Please wait for the model to load."
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .audioFileInvalid:
            return "The audio file is invalid or corrupted"
        case .noAudioData:
            return "No audio data found"
        }
    }
}
