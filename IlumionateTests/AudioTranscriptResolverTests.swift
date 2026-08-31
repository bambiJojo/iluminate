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

        let resolver = AudioTranscriptResolver(
            catalog: KnownAudioCatalogFixtures.bundledTranscriptCatalog
        )
        let transcription = try await resolver.transcribe(
            filename: KnownAudioCatalogFixtures.recognizedFilename,
            duration: 120
        ) {
            fallbackCallCount += 1
            return fallback
        }

        #expect(fallbackCallCount == 0)
        #expect(transcription.fullText == KnownAudioCatalogFixtures.expectedTranscript)
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
            filename: KnownAudioCatalogFixtures.recognizedFilename,
            duration: 120,
            fileSize: 0
        )

        let analyzer = AudioAnalyzer(
            transcriptCatalog: KnownAudioCatalogFixtures.bundledTranscriptCatalog
        )
        let transcription = try await analyzer.transcribe(
            audioFile: nonexistentKnownFile
        )

        #expect(transcription.fullText == KnownAudioCatalogFixtures.expectedTranscript)
        #expect(transcription.duration == 120)
    }
}
