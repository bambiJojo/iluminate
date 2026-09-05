//
//  AnalysisPresentationTests.swift
//  IlumionateTests
//

import Foundation
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

    /// The wording has to hold on both analysis engines. iOS 26 picks the
    /// temperature with Foundation Models; iOS 18 reaches the same setting
    /// through keyword heuristics. Naming either one makes the copy wrong on
    /// the other platform, which is the rule in CLAUDE.md about never labelling
    /// keyword work as AI.
    ///
    /// Asserting the exact sentence pinned an editorial choice rather than that
    /// rule: it failed every copy change alike, so it could not tell a harmless
    /// rewording from one that names an engine, and a reviewer had no signal
    /// beyond "the string moved". This checks the property the test is named
    /// for instead.
    @Test("Automatic color temperature describes both analysis engines")
    func automaticColorTemperatureDescriptionIsSourceNeutral() {
        let description = ColorTempMode.auto.description

        #expect(description.localizedStandardContains("analysis"))

        // Matched as whole words. A substring test reports "available" as an
        // AI reference, which is the same false positive that made an unrelated
        // release scan flag this app's amplitude maths as an analytics SDK.
        let words = Set(
            description
                .lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
        )
        for engine in ["ai", "whisper", "keyword", "keywords"] {
            #expect(!words.contains(engine), "\(engine) names one engine; the copy must hold on both")
        }
        for phrase in ["Foundation Models", "Apple Intelligence"] {
            #expect(!description.localizedStandardContains(phrase))
        }
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
