//
//  AudioTranscriptResolverTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

@MainActor
struct AudioTranscriptResolverTests {
    @Test
    func knownFilenameUsesBundledTranscriptWithoutCallingFallback() async throws {
        var fallbackCallCount = 0
        let fallback = AudioTranscriptionResult(
            fullText: "Fallback transcript",
            segments: [],
            duration: 1_200,
            detectedLanguage: "en"
        )

        let transcription = try await AudioTranscriptResolver().transcribe(
            filename: "01 - Instant Bimbo Sleepdoll.mp3",
            duration: 1_200
        ) {
            fallbackCallCount += 1
            return fallback
        }

        #expect(fallbackCallCount == 0)
        #expect(transcription.fullText.count > 1_000)
    }

    @Test
    func unknownFilenameUsesFallbackTranscriber() async throws {
        var fallbackCallCount = 0
        let fallback = AudioTranscriptionResult(
            fullText: "User-owned meditation transcript",
            segments: [],
            duration: 600,
            detectedLanguage: "en"
        )

        let transcription = try await AudioTranscriptResolver().transcribe(
            filename: "Evening Rain Meditation.m4a",
            duration: 600
        ) {
            fallbackCallCount += 1
            return fallback
        }

        #expect(fallbackCallCount == 1)
        #expect(transcription.fullText == fallback.fullText)
    }

    @Test
    func audioAnalyzerReturnsBundledTranscriptWithoutReadingAudioFile() async throws {
        let nonexistentKnownFile = AudioFile(
            filename: "01 - Instant Bimbo Sleepdoll.mp3",
            duration: 1_200,
            fileSize: 0
        )

        let transcription = try await AudioAnalyzer().transcribe(
            audioFile: nonexistentKnownFile
        )

        #expect(transcription.fullText.count > 1_000)
        #expect(transcription.duration == 1_200)
    }
}
