//
//  LongFormTranscription.swift
//  Ilumionate
//

import Foundation

/// A bounded slice of the source timeline. Timestamps produced while
/// transcribing the slice are relative to `start`.
nonisolated struct TranscriptionChunk: Equatable, Sendable {
    let start: TimeInterval
    let duration: TimeInterval
}

nonisolated struct TranscriptionChunkResult: Sendable {
    let start: TimeInterval
    let transcription: AudioTranscriptionResult
}

/// Keeps conversion and speech recognition away from the whole-file path that
/// fails on hour-long imports, while preserving a single continuous transcript
/// for downstream analysis.
nonisolated enum LongFormTranscriptionPlan {
    static let longFormThreshold: TimeInterval = 60 * 60
    static let maximumChunkDuration: TimeInterval = 30 * 60

    static func chunks(for duration: TimeInterval) -> [TranscriptionChunk] {
        guard duration > 0 else { return [] }
        guard duration >= longFormThreshold else {
            return [TranscriptionChunk(start: 0, duration: duration)]
        }

        var chunks: [TranscriptionChunk] = []
        var start: TimeInterval = 0
        while start < duration {
            let chunkDuration = min(maximumChunkDuration, duration - start)
            chunks.append(TranscriptionChunk(start: start, duration: chunkDuration))
            start += chunkDuration
        }
        return chunks
    }

    static func merge(
        _ chunks: [TranscriptionChunkResult],
        duration: TimeInterval
    ) -> AudioTranscriptionResult? {
        guard duration > 0 else { return nil }

        let fullText = AudioTranscriptionResult.sanitizedTranscriptText(
            chunks.map(\.transcription.fullText).joined(separator: " ")
        )
        guard !fullText.isEmpty else { return nil }

        let segments = chunks.flatMap { chunk in
            chunk.transcription.segments.compactMap { segment -> AudioTranscriptionSegment? in
                let timestamp = max(0, chunk.start + segment.timestamp)
                guard timestamp < duration else { return nil }
                let segmentDuration = min(max(0, segment.duration), duration - timestamp)
                return AudioTranscriptionSegment(
                    id: segment.id,
                    text: segment.text,
                    timestamp: timestamp,
                    duration: segmentDuration,
                    confidence: segment.confidence
                )
            }
        }
        let detectedLanguage = chunks
            .map(\.transcription.locale)
            .first(where: { !$0.isEmpty })
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"

        return AudioTranscriptionResult(
            fullText: fullText,
            segments: segments,
            duration: duration,
            detectedLanguage: detectedLanguage
        )
    }
}
