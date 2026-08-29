//
//  IOS18AnalysisFallbackTests.swift
//  IlumionateTests
//
//  Verifies the shipping analysis path on systems that do not include Apple's
//  Foundation Models framework at runtime.
//

import Testing

@testable import Ilumionate

@Suite("iOS 18 analysis fallback")
struct IOS18AnalysisFallbackTests {

    @Test("A transcript still produces an attributed analysis before iOS 26")
    func transcriptUsesBuiltInAnalysis() async throws {
        guard #unavailable(iOS 26.0, macOS 26.0) else { return }

        let manager = AIAnalysisManager()
        let result = try await manager.analyzeContent(
            transcription: AnalysisFixtures.basicTranscription,
            audioFile: AnalysisFixtures.audioFile(
                duration: AnalysisFixtures.basicTranscription.duration,
                filename: "Deep Sleep Hypnosis.m4a"
            ),
            onProgress: { _ in }
        )

        #expect(result.aiFallbackKind == .unsupportedOS)
        #expect(result.usedKeywordFallback)
        #expect(result.contentType == .sleepHypnosis)
        #expect(result.keyMoments.isEmpty == false)
        #expect(result.recommendedPreset.isEmpty == false)
        #expect(result.keywordFallbackReason?.contains("iOS 26") == true)
    }

    @Test("Audio without a transcript still produces a session recipe before iOS 26")
    func audioFeaturesUseBuiltInAnalysis() async throws {
        guard #unavailable(iOS 26.0, macOS 26.0) else { return }

        let manager = AIAnalysisManager()
        let result = try await manager.analyzeWithoutTranscription(
            audioFile: AnalysisFixtures.audioFile(
                duration: 600,
                filename: "Evening Meditation.m4a"
            ),
            audioFeatures: AudioFeatures(
                averageTempo: 55,
                averageEnergy: 0.2,
                dynamicRange: "low"
            ),
            onProgress: { _ in }
        )

        #expect(result.aiFallbackKind == .unsupportedOS)
        #expect(result.usedKeywordFallback)
        #expect(result.contentType == .meditation)
        #expect(result.keyMoments.count >= 4)
        #expect(result.suggestedFrequencyRange == 6.0...8.0)
    }
}
