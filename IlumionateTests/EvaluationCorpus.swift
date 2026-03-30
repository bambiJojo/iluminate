//
//  EvaluationCorpus.swift
//  IlumionateTests
//
//  Ground-truth evaluation cases built from keyword-dense transcripts.
//  Transcripts are designed to trigger specific HypnosisPhaseAnalyzer phases
//  so scores are deterministic and don't require Apple Intelligence.
//

import Foundation
@testable import Ilumionate

// MARK: - Segment helper

private func seg(_ text: String, at timestamp: Double, duration: Double) -> AudioTranscriptionSegment {
    AudioTranscriptionSegment(text: text, timestamp: timestamp, duration: duration, confidence: 0.95)
}

// MARK: - Corpus

enum EvaluationCorpus {

    // MARK: Classic 30-min Hypnosis

    static let classicHypnosis30min = EvaluationCase(
        name: "Classic 30-min Hypnosis",
        transcript: AudioTranscriptionResult(
            fullText: classicHypnosisText,
            segments: classicHypnosisSegments,
            duration: 1800,
            detectedLanguage: "en"
        ),
        audioFile: AudioFile(filename: "classic_hypnosis.m4a", duration: 1800, fileSize: 50_000_000),
        expectedContentType: .hypnosis,
        expectedPhaseOrder: [.induction, .deepening, .therapy, .suggestions, .emergence],
        expectedFrequencyBand: 0.5...10.0
    )

    // MARK: Short Induction

    static let shortInduction10min = EvaluationCase(
        name: "Short Induction (10 min)",
        transcript: AudioTranscriptionResult(
            fullText: shortInductionText,
            segments: shortInductionSegments,
            duration: 600,
            detectedLanguage: "en"
        ),
        audioFile: AudioFile(filename: "short_induction.m4a", duration: 600, fileSize: 16_000_000),
        expectedContentType: .hypnosis,
        expectedPhaseOrder: [.induction, .deepening, .therapy],
        expectedFrequencyBand: 0.5...10.0
    )

    // MARK: Affirmations

    static let affirmationsSession = EvaluationCase(
        name: "Affirmations Session (15 min)",
        transcript: AudioTranscriptionResult(
            fullText: affirmationsText,
            segments: affirmationsSegments,
            duration: 900,
            detectedLanguage: "en"
        ),
        audioFile: AudioFile(filename: "affirmations.m4a", duration: 900, fileSize: 25_000_000),
        expectedContentType: .affirmations,
        expectedPhaseOrder: [],    // no hypnosis phase structure
        expectedFrequencyBand: 8.0...12.0
    )

    // MARK: Meditation (fixture-based)

    static let meditationBodyScan = EvaluationCase(
        name: "Meditation Body Scan",
        transcript: AnalysisFixtures.basicTranscription,
        audioFile: AnalysisFixtures.audioFile(duration: 300, filename: "meditation.m4a"),
        expectedContentType: .meditation,
        expectedPhaseOrder: [],
        expectedFrequencyBand: 4.0...12.0
    )

    // MARK: All cases

    static let all: [EvaluationCase] = [
        classicHypnosis30min,
        shortInduction10min,
        affirmationsSession,
        meditationBodyScan,
    ]
}

// MARK: - Transcript Data (keyword-dense, matches GoldenDatasetTests fixtures)

private let classicHypnosisSegments: [AudioTranscriptionSegment] = [
    seg("Welcome. Before we begin let me explain what hypnosis is. Get comfortable.", at: 0,    duration: 45),
    seg("Make yourself comfortable. Find a comfortable position. We are ready to begin today.",  at: 45,   duration: 45),
    seg("Close your eyes and breathe slowly exhale inhale let go of tension release eyelids heavy relax.", at: 90, duration: 60),
    seg("Eyelids heavy count down counting down ten nine eight settle shoulders jaw forehead relax breathe.", at: 150, duration: 60),
    seg("Let go letting go count down counting down relax exhale inhale calm quiet gentle release unwind.", at: 210, duration: 60),
    seg("Going deeper now. Deeper and deeper. Drift down into relaxation. Float deeper.",       at: 270,  duration: 90),
    seg("Deeper and deeper. Float down. Sinking deeper. Even deeper. Staircase down.",          at: 360,  duration: 90),
    seg("Going down the staircase. Deeper and deeper. Floating. Drifting. Sinking.",            at: 450,  duration: 90),
    seg("Deeply relaxed now. Completely still. Nothing matters right now. Allow this.",         at: 540,  duration: 110),
    seg("You are deeply relaxed. Completely. Deeply relaxed and still. Allow. Notice.",         at: 650,  duration: 110),
    seg("Deeply relaxed. In trance. Completely relaxed. Nothing matters. Allow it.",            at: 760,  duration: 110),
    seg("Deeply relaxed. Absolute stillness. Deeply relaxed completely. Naturally.",            at: 870,  duration: 110),
    seg("Completely still. In trance. Deeply relaxed. Nothing matters. Allow now.",             at: 980,  duration: 110),
    seg("Deeply relaxed. Completely. Notice. Allow. Deeply relaxed. Effortlessly.",             at: 1090, duration: 110),
    seg("You will feel confident. You will succeed. You will make positive changes.",           at: 1200, duration: 100),
    seg("From now on you will wake refreshed. You will feel calm. You will achieve.",           at: 1300, duration: 100),
    seg("You will believe in yourself. You will choose well. You will feel strong.",            at: 1400, duration: 100),
    seg("Whenever you feel stress remember this. Remember this calm. Whenever.",                at: 1500, duration: 100),
    seg("Carry with you this feeling. Take with you this calm. Future pacing now.",             at: 1600, duration: 100),
    seg("Coming back now. Wide awake. Open your eyes. Fully awake and alert.",                  at: 1700, duration: 50),
    seg("Wide awake. Refreshed. Alert. Energized. Well done. How do you feel.",                 at: 1750, duration: 50),
]

private let classicHypnosisText = classicHypnosisSegments.map(\.text).joined(separator: " ")

private let shortInductionSegments: [AudioTranscriptionSegment] = [
    seg("Close your eyes breathe slowly exhale inhale relax letting go eyelids heavy.", at: 0,   duration: 60),
    seg("Let go of tension eyelids heavy count down counting down ten nine eight seven.", at: 60,  duration: 60),
    seg("Going deeper. Deeper and deeper. Drift down. Float down.",                      at: 120, duration: 60),
    seg("Deeper and deeper. Even deeper. Sinking. Staircase. Going down.",               at: 180, duration: 60),
    seg("Deeply relaxed. Completely still. Nothing matters. Allow. Deeply.",             at: 240, duration: 60),
    seg("Deeply relaxed and completely still. In trance. Allow. Naturally.",             at: 300, duration: 90),
    seg("Deeply relaxed. Completely. Nothing matters. Deeply relaxed. Allow.",           at: 390, duration: 90),
    seg("Deeply relaxed completely. In trance. Absolutely still. Notice.",               at: 480, duration: 120),
]

private let shortInductionText = shortInductionSegments.map(\.text).joined(separator: " ")

private let affirmationsSegments: [AudioTranscriptionSegment] = [
    seg("You will feel confident and strong. You will succeed every single day.",        at: 0,   duration: 90),
    seg("From now on you will believe in yourself. You will feel powerful.",             at: 90,  duration: 90),
    seg("Whenever you face a challenge you will feel strong. Whenever.",                 at: 180, duration: 90),
    seg("Your subconscious mind accepts these beliefs. Subconscious programming.",       at: 270, duration: 90),
    seg("You will attract abundance. You will feel motivated. You will thrive.",         at: 360, duration: 90),
    seg("From now on you will choose health and happiness. You will feel calm.",         at: 450, duration: 90),
    seg("Whenever you feel doubt you will remember your strength. Whenever.",            at: 540, duration: 90),
    seg("You will succeed. You will prosper. Your subconscious accepts this.",           at: 630, duration: 90),
    seg("Remember this. Carry with you this belief. Take with you this strength.",      at: 720, duration: 90),
    seg("Wide awake. Open your eyes feeling great. Alert. Refreshed. Energized.",       at: 810, duration: 90),
]

private let affirmationsText = affirmationsSegments.map(\.text).joined(separator: " ")
