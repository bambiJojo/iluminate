//
//  AnalysisFixtures.swift
//  IlumionateTests
//
//  In-memory canned data used across all pipeline tests.
//  No disk access, no real audio files, no ML calls required.
//

import Foundation
@testable import Ilumionate

// MARK: - Fixtures

enum AnalysisFixtures {

    // MARK: AudioFile

    static func audioFile(
        duration: TimeInterval = 300,
        filename: String = "fixture.m4a"
    ) -> AudioFile {
        AudioFile(filename: filename, duration: duration, fileSize: 1_024_000)
    }

    // MARK: Transcription

    static let basicTranscription = AudioTranscriptionResult(
        fullText: "Close your eyes and breathe slowly. Going deeper and deeper. You will feel confident. Wide awake.",
        segments: [
            AudioTranscriptionSegment(
                text: "Close your eyes and breathe slowly.",
                timestamp: 0, duration: 5, confidence: 0.95
            ),
            AudioTranscriptionSegment(
                text: "Going deeper and deeper.",
                timestamp: 5, duration: 4, confidence: 0.95
            ),
            AudioTranscriptionSegment(
                text: "You will feel confident.",
                timestamp: 9, duration: 4, confidence: 0.95
            ),
            AudioTranscriptionSegment(
                text: "Wide awake.",
                timestamp: 13, duration: 3, confidence: 0.95
            ),
        ],
        duration: 300,
        detectedLanguage: "en"
    )

    // MARK: Analysis Results

    static let hypnosisAnalysis = AnalysisResult(
        mood: .meditative,
        energyLevel: 0.2,
        suggestedFrequencyRange: 4.0...8.0,
        suggestedIntensity: 0.6,
        suggestedColorTemperature: 2800,
        keyMoments: [
            KeyMoment(time: 30,  description: "Induction begins", action: .deepen),
            KeyMoment(time: 120, description: "Deepening phase",  action: .deepen),
            KeyMoment(time: 240, description: "Emergence",        action: .energize),
        ],
        aiSummary: "Classic hypnosis session with full induction arc.",
        recommendedPreset: "Deep Theta",
        contentType: .hypnosis,
        hypnosisMetadata: HypnosisMetadata(
            phases: [
                PhaseSegment(phase: .induction,  startTime: 0,   endTime: 90,
                             characteristics: "Eye closure, breath focus",
                             tranceDepthEstimate: 0.3),
                PhaseSegment(phase: .deepening,  startTime: 90,  endTime: 180,
                             characteristics: "Counting down, going deeper",
                             tranceDepthEstimate: 0.6),
                PhaseSegment(phase: .therapy,    startTime: 180, endTime: 240,
                             characteristics: "Deep therapeutic work",
                             tranceDepthEstimate: 0.8),
                PhaseSegment(phase: .emergence,  startTime: 240, endTime: 300,
                             characteristics: "Counting up, wide awake",
                             tranceDepthEstimate: 0.1),
            ],
            inductionStyle: .permissive,
            estimatedTranceDeph: .medium,
            suggestionDensity: 0.5,
            languagePatterns: ["pacing", "leading"],
            detectedTechniques: []
        )
    )

    static let meditationAnalysis = AnalysisResult(
        mood: .meditative,
        energyLevel: 0.15,
        suggestedFrequencyRange: 6.0...10.0,
        suggestedIntensity: 0.5,
        suggestedColorTemperature: 3200,
        keyMoments: [
            KeyMoment(time: 30, description: "Body scan begins", action: .deepen),
        ],
        aiSummary: "Body scan meditation.",
        recommendedPreset: "Alpha Calm",
        contentType: .meditation
    )

    static let musicAnalysis = AnalysisResult(
        mood: .energizing,
        energyLevel: 0.7,
        suggestedFrequencyRange: 14.0...20.0,
        suggestedIntensity: 0.8,
        keyMoments: [
            KeyMoment(time: 60, description: "Peak energy", action: .energize),
        ],
        aiSummary: "Upbeat music track.",
        recommendedPreset: "Beta Active",
        contentType: .music
    )

    static let affirmationsAnalysis = AnalysisResult(
        mood: .uplifting,
        energyLevel: 0.4,
        suggestedFrequencyRange: 9.0...11.0,
        suggestedIntensity: 0.6,
        keyMoments: [
            KeyMoment(time: 0, description: "Opening affirmation", action: .increaseIntensity),
        ],
        aiSummary: "Positive affirmations session.",
        recommendedPreset: "Alpha Suggestion",
        contentType: .affirmations
    )

    static let unknownAnalysis = AnalysisResult(
        mood: .neutral,
        energyLevel: 0.5,
        suggestedFrequencyRange: 10.0...14.0,
        suggestedIntensity: 0.7,
        keyMoments: [],
        aiSummary: "Unknown content type.",
        recommendedPreset: "Default",
        contentType: .unknown
    )

    // MARK: Light Session

    static let hypnosisSession = LightSession(
        id: UUID(),
        session_name: "Test Hypnosis Session",
        duration_sec: 300,
        light_score: [
            LightMoment(time: 0,   frequency: 14, intensity: 0.8, waveform: .sine),
            LightMoment(time: 90,  frequency: 7,  intensity: 0.6, waveform: .sine),
            LightMoment(time: 240, frequency: 4,  intensity: 0.5, waveform: .sine),
            LightMoment(time: 300, frequency: 14, intensity: 0.9, waveform: .sine),
        ]
    )
}
