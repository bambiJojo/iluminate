//
//  AnalysisPresentationTests.swift
//  IlumionateTests
//

import Testing

@testable import Ilumionate

@Suite("Analysis presentation")
struct AnalysisPresentationTests {

    @Test("Built-in results are not credited to AI")
    func builtInResultLabels() {
        let result = makeResult(
            summary: AIGenerationDiagnosis.fallbackSummary(for: .unsupportedOS)
        )

        #expect(AnalysisResultPresentation.sourceLabel(for: result) == "Keyword Analysis")
        #expect(AnalysisResultPresentation.insightsLabel(for: result) == "Built-In Insights")
    }

    @Test("Foundation Models results retain their AI labels")
    func aiResultLabels() {
        let result = makeResult(summary: "A model-generated summary.")

        #expect(AnalysisResultPresentation.sourceLabel(for: result) == "AI Analyzed")
        #expect(AnalysisResultPresentation.insightsLabel(for: result) == "AI Insights")
    }

    private func makeResult(summary: String) -> AnalysisResult {
        AnalysisResult(
            mood: .relaxing,
            energyLevel: 0.2,
            suggestedFrequencyRange: 4...8,
            suggestedIntensity: 0.5,
            keyMoments: [],
            aiSummary: summary,
            recommendedPreset: "Test"
        )
    }
}
