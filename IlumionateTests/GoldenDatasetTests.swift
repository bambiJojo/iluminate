//
//  GoldenDatasetTests.swift
//  IlumionateTests
//
//  Step 3.4: Golden-dataset regression tests for the HypnosisPhaseAnalyzer pipeline.
//
//  Each fixture is a canned transcript whose phase structure is well-defined.
//  Tests assert structural properties (phase presence, order, coverage) that
//  act as a regression tripwire: any change to keyword weights, smoothing
//  parameters, or phase-ordering logic that breaks expected output will fail here.
//
//  Fixtures are keyword-dense by design. Each section uses only the vocabulary
//  that belongs to its target phase so keyword-conflict noise is minimised.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Fixture Helpers

private func seg(
    _ text: String,
    at timestamp: Double,
    duration: Double
) -> AudioTranscriptionSegment {
    AudioTranscriptionSegment(
        text: text,
        timestamp: timestamp,
        duration: duration,
        confidence: 0.95
    )
}

// MARK: - Fixture 1: Classic 30-minute Hypnosis (1 800 s)
//
// Seven-phase structure with clear keyword blocks.
// minRun for 1 800 s = max(20, Int(1800 × 0.035)) = 63 s.
// Every phase block is ≥ 90 s so all survive the collapse pass.

private let classicHypnosis: [AudioTranscriptionSegment] = [
    // pre_talk  0–90 s  — rapport / explanation
    seg("Welcome. Before we begin let me explain what hypnosis is. Get comfortable.",
        at: 0, duration: 45),
    seg("Make yourself comfortable. Find a comfortable position. We are ready to begin today.",
        at: 45, duration: 45),

    // induction  90–270 s  — eye closure, breath, body heavy
    // "deep" and "now" are avoided: both trigger non-induction keywords.
    seg("Close your eyes and breathe slowly exhale inhale let go of tension release eyelids heavy relax.",
        at: 90, duration: 60),
    seg("Eyelids heavy count down counting down ten nine eight settle shoulders jaw forehead relax breathe.",
        at: 150, duration: 60),
    seg("Let go letting go count down counting down relax exhale inhale calm quiet gentle release unwind.",
        at: 210, duration: 60),

    // deepening  270–540 s  — going deeper
    seg("Going deeper now. Deeper and deeper. Drift down into relaxation. Float deeper.",
        at: 270, duration: 90),
    seg("Deeper and deeper. Float down. Sinking deeper. Even deeper. Staircase down.",
        at: 360, duration: 90),
    seg("Going down the staircase. Deeper and deeper. Floating. Drifting. Sinking.",
        at: 450, duration: 90),

    // therapy  540–1 200 s  — passive deep trance (avoid induction words)
    seg("Deeply relaxed now. Completely still. Nothing matters right now. Allow this.",
        at: 540, duration: 110),
    seg("You are deeply relaxed. Completely. Deeply relaxed and still. Allow. Notice.",
        at: 650, duration: 110),
    seg("Deeply relaxed. In trance. Completely relaxed. Nothing matters. Allow it.",
        at: 760, duration: 110),
    seg("Deeply relaxed. Absolute stillness. Deeply relaxed completely. Naturally.",
        at: 870, duration: 110),
    seg("Completely still. In trance. Deeply relaxed. Nothing matters. Allow now.",
        at: 980, duration: 110),
    seg("Deeply relaxed. Completely. Notice. Allow. Deeply relaxed. Effortlessly.",
        at: 1090, duration: 110),

    // suggestions  1 200–1 500 s  — active commands
    seg("You will feel confident. You will succeed. You will make positive changes.",
        at: 1200, duration: 100),
    seg("From now on you will wake refreshed. You will feel calm. You will achieve.",
        at: 1300, duration: 100),
    seg("You will believe in yourself. You will choose well. You will feel strong.",
        at: 1400, duration: 100),

    // conditioning  1 500–1 700 s  — anchors and future pacing
    seg("Whenever you feel stress remember this. Remember this calm. Whenever.",
        at: 1500, duration: 100),
    seg("Carry with you this feeling. Take with you this calm. Future pacing now.",
        at: 1600, duration: 100),

    // emergence  1 700–1 800 s  — waking
    seg("Coming back now. Wide awake. Open your eyes. Fully awake and alert.",
        at: 1700, duration: 50),
    seg("Wide awake. Refreshed. Alert. Energized. Well done. How do you feel.",
        at: 1750, duration: 50),
]

// MARK: - Fixture 2: Short Induction Session (600 s)
//
// Ten-minute recording covering only induction and deepening.
// No emergence language anywhere — a regression would be if emergence appears.

private let shortInduction: [AudioTranscriptionSegment] = [
    seg("Close your eyes breathe slowly exhale inhale relax letting go eyelids heavy.",
        at: 0, duration: 60),
    seg("Let go of tension eyelids heavy count down counting down ten nine eight seven.",
        at: 60, duration: 60),
    seg("Going deeper. Deeper and deeper. Drift down. Float down.",
        at: 120, duration: 60),
    seg("Deeper and deeper. Even deeper. Sinking. Staircase. Going down.",
        at: 180, duration: 60),
    seg("Deeply relaxed. Completely still. Nothing matters. Allow. Deeply.",
        at: 240, duration: 60),
    seg("Deeply relaxed and completely still. In trance. Allow. Naturally.",
        at: 300, duration: 90),
    seg("Deeply relaxed. Completely. Nothing matters. Deeply relaxed. Allow.",
        at: 390, duration: 90),
    seg("Deeply relaxed completely. In trance. Absolutely still. Notice.",
        at: 480, duration: 120),
]

// MARK: - Fixture 3: Affirmations / Suggestions Session (900 s)
//
// Fifteen-minute recording consisting entirely of suggestion-delivery and
// conditioning language. No induction arc — no deepening words appear.

private let affirmations: [AudioTranscriptionSegment] = [
    seg("You will feel confident and strong. You will succeed every single day.",
        at: 0, duration: 90),
    seg("From now on you will believe in yourself. You will feel powerful.",
        at: 90, duration: 90),
    seg("Whenever you face a challenge you will feel strong. Whenever.",
        at: 180, duration: 90),
    seg("Your subconscious mind accepts these beliefs. Subconscious programming.",
        at: 270, duration: 90),
    seg("You will attract abundance. You will feel motivated. You will thrive.",
        at: 360, duration: 90),
    seg("From now on you will choose health and happiness. You will feel calm.",
        at: 450, duration: 90),
    seg("Whenever you feel doubt you will remember your strength. Whenever.",
        at: 540, duration: 90),
    seg("You will succeed. You will prosper. Your subconscious accepts this.",
        at: 630, duration: 90),
    seg("Remember this. Carry with you this belief. Take with you this strength.",
        at: 720, duration: 90),
    seg("Wide awake. Open your eyes feeling great. Alert. Refreshed. Energized.",
        at: 810, duration: 90),
]

// MARK: - Tests

struct GoldenDatasetTests {

    private let analyzer = HypnosisPhaseAnalyzer()

    // MARK: Fixture 1 — Classic 30-min hypnosis

    /// Core five structural phases must survive minRun collapse.
    @Test func classicHypnosisCorePhasesPresentInOrder() {
        let segments = analyzer.analyze(segments: classicHypnosis, duration: 1800)
        let phases = segments.map(\.phase)

        let required: [HypnosisMetadata.Phase] = [.induction, .deepening, .therapy, .suggestions, .emergence]
        let detected = Set(phases)

        for phase in required {
            #expect(detected.contains(phase),
                "Expected phase '\(phase.rawValue)' missing from golden output: \(phases.map(\.rawValue))")
        }
    }

    /// Output sequence must never skip backward in the canonical ordering.
    @Test func classicHypnosisPhasesAreStrictlyForwardOrdered() {
        let canonical: [HypnosisMetadata.Phase] = [
            .preTalk, .induction, .deepening, .therapy, .suggestions, .conditioning, .emergence
        ]
        let segments = analyzer.analyze(segments: classicHypnosis, duration: 1800)
        let phases = segments.map(\.phase)

        var lastIndex = -1
        for phase in phases {
            if let idx = canonical.firstIndex(of: phase) {
                #expect(idx >= lastIndex,
                    "Phase '\(phase.rawValue)' appeared out of canonical order")
                lastIndex = idx
            }
        }
    }

    /// Emergence should be confined to the final quarter of the session.
    @Test func classicHypnosisEmergenceIsInLastQuarter() {
        let segments = analyzer.analyze(segments: classicHypnosis, duration: 1800)
        if let emergenceStart = segments.first(where: { $0.phase == .emergence })?.startTime {
            #expect(emergenceStart >= 1200,
                "Emergence started too early: \(emergenceStart)s (expected ≥1200s)")
        } else {
            Issue.record("No emergence segment in classic hypnosis golden fixture")
        }
    }

    /// Therapy must straddle the session midpoint (cover both sides of 900 s).
    @Test func classicHypnosisTherapyStraddlesMidpoint() {
        let segments = analyzer.analyze(segments: classicHypnosis, duration: 1800)
        if let therapy = segments.first(where: { $0.phase == .therapy }) {
            #expect(therapy.startTime <= 900,
                "Therapy started after midpoint: \(therapy.startTime)s")
            #expect(therapy.endTime >= 900,
                "Therapy ended before midpoint: \(therapy.endTime)s")
        } else {
            Issue.record("No therapy segment in classic hypnosis golden fixture")
        }
    }

    /// The segmented output must span the full 1 800 s with no gap at either end.
    @Test func classicHypnosisFullCoverage() {
        let segments = analyzer.analyze(segments: classicHypnosis, duration: 1800)
        #expect(!segments.isEmpty)
        let firstStart = segments.first?.startTime ?? 999
        let lastEnd   = segments.last?.endTime   ?? 0
        #expect(firstStart <= 5,    "First segment starts at \(firstStart)s, expected ≤5s")
        #expect(lastEnd   >= 1795,  "Last segment ends at \(lastEnd)s, expected ≥1795s")
    }

    /// Pipeline must be deterministic — two runs on the same input give identical counts.
    @Test func classicHypnosisDeterministic() {
        let run1 = analyzer.analyze(segments: classicHypnosis, duration: 1800)
        let run2 = analyzer.analyze(segments: classicHypnosis, duration: 1800)
        #expect(run1.count == run2.count,
            "Non-deterministic: \(run1.count) segments on run 1, \(run2.count) on run 2")
        let phases1 = run1.map(\.phase)
        let phases2 = run2.map(\.phase)
        #expect(phases1 == phases2,
            "Non-deterministic phase sequences: \(phases1) vs \(phases2)")
    }

    /// Segment count should stay in a sane range for a well-structured 30-min session.
    @Test func classicHypnosisSegmentCountIsReasonable() {
        let segments = analyzer.analyze(segments: classicHypnosis, duration: 1800)
        #expect(segments.count >= 4 && segments.count <= 10,
            "Expected 4–10 segments, got \(segments.count): \(segments.map(\.phase.rawValue))")
    }

    // MARK: Fixture 2 — Short induction (10 min)

    @Test func shortInductionDetectsTrancePhase() {
        let segments = analyzer.analyze(segments: shortInduction, duration: 600)
        let phases = Set(segments.map(\.phase))
        let trancePhases: Set<HypnosisMetadata.Phase> = [.induction, .deepening, .therapy]
        let hasTrance = !trancePhases.isDisjoint(with: phases)
        #expect(hasTrance,
            "No trance phase detected in short induction fixture; got: \(phases.map(\.rawValue))")
    }

    @Test func shortInductionHasNoEmergence() {
        let segments = analyzer.analyze(segments: shortInduction, duration: 600)
        let hasEmergence = segments.contains { $0.phase == .emergence }
        #expect(!hasEmergence,
            "Emergence appeared in short induction fixture (no waking language present)")
    }

    @Test func shortInductionHasNoSuggestions() {
        let segments = analyzer.analyze(segments: shortInduction, duration: 600)
        let hasSuggestions = segments.contains { $0.phase == .suggestions }
        #expect(!hasSuggestions,
            "Suggestions appeared in short induction fixture (no 'you will' language present)")
    }

    @Test func shortInductionFullCoverage() {
        let segments = analyzer.analyze(segments: shortInduction, duration: 600)
        #expect(!segments.isEmpty)
        let lastEnd = segments.last?.endTime ?? 0
        #expect(lastEnd >= 595,
            "Short induction: last segment ends at \(lastEnd)s, expected ≥595s")
    }

    // MARK: Fixture 3 — Affirmations / suggestions (15 min)

    @Test func affirmationsDetectsSuggestionsOrConditioning() {
        let segments = analyzer.analyze(segments: affirmations, duration: 900)
        let phases = Set(segments.map(\.phase))
        let suggestionPhases: Set<HypnosisMetadata.Phase> = [.suggestions, .conditioning]
        let hasAny = !suggestionPhases.isDisjoint(with: phases)
        #expect(hasAny,
            "No suggestion/conditioning phase in affirmations fixture; got: \(phases.map(\.rawValue))")
    }

    @Test func affirmationsHasNoDeepening() {
        let segments = analyzer.analyze(segments: affirmations, duration: 900)
        let hasDeepening = segments.contains { $0.phase == .deepening }
        #expect(!hasDeepening,
            "Deepening appeared in affirmations fixture (no 'deeper/drift/float' language present)")
    }

    @Test func affirmationsFullCoverage() {
        let segments = analyzer.analyze(segments: affirmations, duration: 900)
        #expect(!segments.isEmpty)
        let lastEnd = segments.last?.endTime ?? 0
        #expect(lastEnd >= 895,
            "Affirmations: last segment ends at \(lastEnd)s, expected ≥895s")
    }
}
