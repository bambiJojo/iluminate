//
//  AnalysisResultCopyTests.swift
//  IlumionateTests
//
//  `AnalysisResult` is reconstructed field-by-field in five files. Every one of
//  those sites silently drops any field it does not name, and `aiFallbackKind`
//  has now been lost that way twice — once in `makeKeywordFallbackResult`, and
//  once in `AudioAnalysisEnricher`, where it made every rate-limited file clear
//  its checkpoint instead of deferring.
//
//  These cover the copy helper that exists so rebuild sites stop calling `init`.
//

import Testing
import Foundation
@testable import Ilumionate

struct AnalysisResultCopyTests {

    private var fallbackResult: AnalysisResult {
        AnalysisResult(
            mood: .relaxing,
            energyLevel: 0.2,
            suggestedFrequencyRange: 8...12,
            suggestedIntensity: 0.5,
            keyMoments: [],
            aiSummary: AIGenerationDiagnosis.fallbackSummary(for: .rateLimited),
            recommendedPreset: "Alpha Relaxation",
            contentType: .hypnosis,
            aiFallbackKind: .rateLimited
        )
    }

    @Test("A copy keeps the fields it was not asked to change")
    func copyPreservesUnnamedFields() {
        let copied = fallbackResult.with(recommendedPreset: "Something Else")

        #expect(copied.recommendedPreset == "Something Else")
        #expect(copied.aiFallbackKind == .rateLimited)
        #expect(copied.contentType == .hypnosis)
        #expect(copied.aiSummary == fallbackResult.aiSummary)
    }

    @Test("A copy applies every override it is given")
    func copyAppliesOverrides() {
        let copied = fallbackResult.with(
            recommendedPreset: "Deep Session",
            contentType: .meditation
        )

        #expect(copied.recommendedPreset == "Deep Session")
        #expect(copied.contentType == .meditation)
        #expect(copied.aiFallbackKind == .rateLimited)
    }

    /// The site that actually caused the bug: enrichment runs on every analysis,
    /// including the keyword fallback, and dropping the kind here meant the
    /// checkpoint was cleared and the file could never be retried.
    @Test("Enrichment preserves the reason a fallback happened")
    func enrichmentPreservesFallbackKind() {
        let enriched = AudioAnalysisEnricher().enrich(
            fallbackResult,
            transcription: AnalysisFixtures.basicTranscription,
            audioFile: AnalysisFixtures.audioFile(filename: "Deferred.mp3"),
            prosody: nil
        )

        #expect(enriched.aiFallbackKind == .rateLimited)
        #expect(DeferredAIAnalysisPolicy.retainsCheckpoint(after: enriched.aiFallbackKind!))
    }

    @Test("Enrichment of a model-produced result records no fallback kind")
    func enrichmentLeavesSuccessfulResultsAlone() {
        let successful = AnalysisResult(
            mood: .relaxing,
            energyLevel: 0.2,
            suggestedFrequencyRange: 8...12,
            suggestedIntensity: 0.5,
            keyMoments: [],
            aiSummary: "A real model summary",
            recommendedPreset: "Alpha Relaxation",
            contentType: .hypnosis
        )

        let enriched = AudioAnalysisEnricher().enrich(
            successful,
            transcription: AnalysisFixtures.basicTranscription,
            audioFile: AnalysisFixtures.audioFile(filename: "Analysed.mp3"),
            prosody: nil
        )

        #expect(enriched.aiFallbackKind == nil)
    }
}
