//
//  AudioAnalysisEnricherTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct AudioAnalysisEnricherTests {
    @Test func strongTechniqueEvidenceUpgradesUnknownContent() {
        let transcription = AudioTranscriptionResult(
            fullText: """
            Take a deep breath. That's right. Go deeper now. When I say sleep, go deeper.
            Next time you hear my voice, relax now. Let go. Drift deeper. Five four three two one.
            """,
            segments: [
                AudioTranscriptionSegment(
                    text: """
                    Take a deep breath. That's right. Go deeper now. When I say sleep, go deeper.
                    Next time you hear my voice, relax now. Let go. Drift deeper. Five four three two one.
                    """,
                    timestamp: 0,
                    duration: 90,
                    confidence: 0.9
                )
            ],
            duration: 90,
            detectedLanguage: "en"
        )

        let enriched = AudioAnalysisEnricher().enrich(
            AnalysisFixtures.unknownAnalysis,
            transcription: transcription,
            audioFile: AnalysisFixtures.audioFile(duration: 90),
            prosody: nil
        )

        #expect(enriched.contentType == .hypnosis)
        #expect(enriched.hypnosisMetadata?.detectedTechniques.isEmpty == false)
        #expect(enriched.recommendedPreset == "Hypnosis Session")
    }
}
