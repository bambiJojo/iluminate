//
//  ExpertAnalysisBuilderTests.swift
//  IlumionateTests
//
//  Regression tests for analyzer-quality diagnostics.
//

import Foundation
import Testing
@testable import Ilumionate

struct ExpertAnalysisBuilderTests {

    @Test func strongHypnosisEvidenceProducesProductionReadyVerdict() {
        let expert = ExpertAnalysisBuilder().build(
            analysis: AnalysisFixtures.hypnosisAnalysis,
            audioDuration: 300,
            transcription: AnalysisFixtures.basicTranscription,
            prosody: AnalysisFixtures.prosodicProfile,
            techniqueDetection: TechniqueDetectionResult(
                techniques: [],
                markers: [
                    LinguisticMarker(
                        type: .progressiveRelaxation,
                        timestamp: 30,
                        textSnippet: "Close your eyes",
                        strength: 0.9
                    )
                ]
            )
        )

        #expect(expert.verdict == .productionReady)
        #expect(expert.qualityScore >= 0.85)
        #expect(expert.improvementActions.contains { $0.title.contains("positive regression") })
    }

    @Test func weakCoverageProducesReviewActionsAndMoments() {
        let weakAnalysis = AnalysisResult(
            mood: .meditative,
            energyLevel: 0.2,
            suggestedFrequencyRange: 4.0...8.0,
            suggestedIntensity: 0.45,
            keyMoments: [],
            aiSummary: "Weakly labeled hypnosis fixture",
            recommendedPreset: "Review",
            contentType: .hypnosis,
            hypnosisMetadata: HypnosisMetadata(
                phases: [
                    PhaseSegment(
                        phase: .deepening,
                        startTime: 60,
                        endTime: 100,
                        characteristics: "Short deepening island",
                        tranceDepthEstimate: 0.6,
                        confidenceLevel: .low
                    )
                ],
                inductionStyle: nil,
                estimatedTranceDeph: .medium,
                suggestionDensity: nil,
                languagePatterns: [],
                detectedTechniques: []
            )
        )

        let expert = ExpertAnalysisBuilder().build(
            analysis: weakAnalysis,
            audioDuration: 300
        )

        #expect(expert.verdict != .productionReady)
        #expect(expert.findings.contains { $0.title == "Phase coverage is incomplete" })
        #expect(expert.improvementActions.contains { $0.title == "Review uncovered timeline spans" })
        #expect(expert.reviewMoments.isEmpty == false)
    }
}
