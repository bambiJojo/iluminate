//
//  LongFormTranscriptionTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct LongFormTranscriptionTests {
    @Test("One-hour audio is split before conversion and transcription")
    func oneHourAudioUsesTwoBoundedChunks() {
        let chunks = LongFormTranscriptionPlan.chunks(for: 3_600)

        #expect(chunks == [
            TranscriptionChunk(start: 0, duration: 1_800),
            TranscriptionChunk(start: 1_800, duration: 1_800),
        ])
    }

    @Test("Chunk transcripts merge onto the source timeline")
    func chunkTimestampsAreOffsetWhenMerged() throws {
        let first = AudioTranscriptionResult(
            fullText: "Opening words",
            segments: [
                AudioTranscriptionSegment(
                    text: "Opening words",
                    timestamp: 10,
                    duration: 4,
                    confidence: 0.9
                ),
            ],
            duration: 1_800,
            detectedLanguage: "en"
        )
        let second = AudioTranscriptionResult(
            fullText: "Closing words",
            segments: [
                AudioTranscriptionSegment(
                    text: "Closing words",
                    timestamp: 5,
                    duration: 3,
                    confidence: 0.8
                ),
            ],
            duration: 1_800,
            detectedLanguage: "en"
        )

        let merged = try #require(LongFormTranscriptionPlan.merge(
            [
                TranscriptionChunkResult(start: 0, transcription: first),
                TranscriptionChunkResult(start: 1_800, transcription: second),
            ],
            duration: 3_600
        ))

        #expect(merged.fullText == "Opening words Closing words")
        #expect(merged.segments.map(\.timestamp) == [10, 1_805])
        #expect(merged.duration == 3_600)
        #expect(merged.locale == "en")
    }
}
