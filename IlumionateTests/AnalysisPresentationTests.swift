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

    @Test("Built-in results do not produce an AI-named light session")
    func builtInSessionName() {
        let result = makeResult(
            summary: AIGenerationDiagnosis.fallbackSummary(for: .unsupportedOS)
        )

        #expect(
            AnalysisResultPresentation.sessionName(audioTitle: "Evening Calm", result: result)
                == "Evening Calm — Built-In Light Session"
        )
    }

    @Test("Foundation Models results retain the AI light-session name")
    func aiSessionName() {
        let result = makeResult(summary: "A model-generated summary.")

        #expect(
            AnalysisResultPresentation.sessionName(audioTitle: "Evening Calm", result: result)
                == "Evening Calm — AI Light Session"
        )
    }

    @Test("Settings name the built-in analysis path on older systems")
    func builtInSettingsLabels() {
        #expect(
            AnalysisAvailabilityPresentation.cardLabel(supportsFoundationModels: false)
                == "Light Sync Analysis"
        )
        #expect(
            AnalysisAvailabilityPresentation.sectionTitle(supportsFoundationModels: false)
                == "Built-In Analysis"
        )
    }

    @Test("Settings retain their AI labels when Foundation Models is supported")
    func aiSettingsLabels() {
        #expect(
            AnalysisAvailabilityPresentation.cardLabel(supportsFoundationModels: true)
                == "Light Sync AI"
        )
        #expect(
            AnalysisAvailabilityPresentation.sectionTitle(supportsFoundationModels: true)
                == "AI Analysis"
        )
    }

    @Test("Automatic color temperature describes both analysis engines")
    func automaticColorTemperatureDescriptionIsSourceNeutral() {
        #expect(ColorTempMode.auto.description == "Analysis selects the best temperature")
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
