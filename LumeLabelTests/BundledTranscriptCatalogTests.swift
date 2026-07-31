//
//  BundledTranscriptCatalogTests.swift
//  LumeLabelTests
//

import Testing
import XCTest
import Foundation
@testable import LumeLabel

private struct TranscriptCacheFixture: Encodable {
    let schemaVersion: Int
    let cachedAt: Date
    let exampleID: UUID
    let audioSHA256: String
    let transcription: AudioTranscriptionResult
}

struct BundledTranscriptCatalogTests {
    @Test
    func knownFilenameReturnsBundledTranscript() throws {
        let transcription = try #require(
            BundledAudioTranscriptCatalog.shared.transcription(
                filename: "01 - Instant Bimbo Sleepdoll.mp3",
                duration: 1_200
            )
        )

        #expect(transcription.fullText.count > 1_000)
        #expect(transcription.duration == 1_200)
        #expect(!transcription.segments.isEmpty)
    }

    @Test
    @MainActor
    func unknownFilenameStillUsesFallbackTranscriber() async throws {
        var fallbackCallCount = 0
        let fallback = AudioTranscriptionResult(
            fullText: "Fallback transcript",
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
    @MainActor
    func openingRecognizedFileAutomaticallyLoadsBundledTranscript() async throws {
        let corpusDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: corpusDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: corpusDirectory)
        }

        let corpus = TrainingCorpusManager(
            baseDirectory: corpusDirectory,
            autoLoad: false
        )
        let file = LabeledFile(
            originalFilename: "01 - Instant Bimbo Sleepdoll.mp3",
            storedAudioFilename: "stored-audio.mp3",
            audioDuration: 1_200,
            audioSHA256: "known-audio-fixture",
            expectedContentType: .hypnosis,
            expectedFrequencyBand: .init(lower: 1, upper: 8),
            phases: [],
            techniques: [],
            labeledAt: .now,
            labelerNotes: ""
        )
        let editor = LabelingDetailEditor(file: file, corpus: corpus)

        await editor.loadTranscriptIfAvailable()

        #expect(editor.hasTranscript)
        #expect(editor.transcription?.fullText.count ?? 0 > 1_000)
        #expect(editor.transcriptStatusMessage == "Official transcript loaded from the bundled catalog.")
    }

}

@MainActor
final class OfficialTranscriptCachePrecedenceTests: XCTestCase {
    func testOpeningRecognizedFileReplacesOlderCachedTranscript() async throws {
        let corpusDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cacheDirectory = corpusDirectory
            .appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
            .appending(path: "cache", directoryHint: .isDirectory)
            .appending(path: "transcripts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: corpusDirectory)
        }

        let corpus = TrainingCorpusManager(
            baseDirectory: corpusDirectory,
            autoLoad: false
        )
        let file = LabeledFile(
            originalFilename: "10 Bambi Awakens.mp3",
            storedAudioFilename: "stored-audio.mp3",
            audioDuration: 600,
            audioSHA256: "known-audio-with-stale-cache",
            expectedContentType: .hypnosis,
            expectedFrequencyBand: .init(lower: 1, upper: 8),
            phases: [],
            techniques: [],
            labeledAt: .now,
            labelerNotes: ""
        )
        let staleTranscription = AudioTranscriptionResult(
            fullText: "Old Whisper transcript with recognition mistakes.",
            segments: [],
            duration: file.audioDuration,
            detectedLanguage: "en"
        )
        let stalePayload = TranscriptCacheFixture(
            schemaVersion: 1,
            cachedAt: .now,
            exampleID: file.id,
            audioSHA256: file.audioSHA256,
            transcription: staleTranscription
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(stalePayload).write(
            to: cacheDirectory.appending(path: "\(file.audioSHA256).json"),
            options: .atomic
        )

        let editor = LabelingDetailEditor(file: file, corpus: corpus)
        await editor.loadTranscriptIfAvailable()

        XCTAssertNotEqual(editor.transcription?.fullText, staleTranscription.fullText)
        XCTAssertTrue(
            editor.transcription?.fullText.hasPrefix(
                "Soon it will be time for you to awaken Bambi"
            ) == true
        )
        XCTAssertEqual(
            editor.transcriptStatusMessage,
            "Official transcript loaded from the bundled catalog."
        )
    }
}
