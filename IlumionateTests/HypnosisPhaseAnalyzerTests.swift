//
//  HypnosisPhaseAnalyzerTests.swift
//  IlumionateTests
//
//  Tests for Step 3.1: HypnosisPhaseAnalyzer pure functions.
//  All functions under test are deterministic and have no side effects.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Helpers

private func makeWord(_ text: String, at time: Double, dur: Double = 1.0) -> WordTimestamp {
    WordTimestamp(word: text, startTime: time, duration: dur)
}

private func makeSegment(text: String, start: Double, duration: Double) -> AudioTranscriptionSegment {
    AudioTranscriptionSegment(text: text, timestamp: start, duration: duration, confidence: 1.0)
}

private func phaseScores(
    _ values: [HypnosisMetadata.Phase: Double]
) -> [Double] {
    HypnosisMetadata.Phase.orderedHypnosisPhases.map { values[$0] ?? 0 }
}

// MARK: - PhaseSequenceResolver Tests

struct PhaseSequenceResolverTests {
    private let resolver = PhaseSequenceResolver()

    @Test func transitionPriorsDoNotCauseOscillationWithoutNewEvidence() {
        let chosen = resolver.resolve(
            emissionScores: [
                phaseScores([.deepening: 1.0]),
                phaseScores([.deepening: 0.5, .suggestions: 0.5]),
                phaseScores([.deepening: 0.5, .suggestions: 0.5]),
                phaseScores([.deepening: 0.5, .suggestions: 0.5])
            ],
            transitionPriors: [
                .deepening: [.suggestions: 1.0],
                .suggestions: [.deepening: 1.0]
            ],
            transitionPriorMultiplier: 1.0
        )
        let phases = chosen.map { HypnosisMetadata.Phase.orderedHypnosisPhases[$0] }

        #expect(phases == [.deepening, .deepening, .deepening, .deepening])
    }

    @Test func sustainedEvidenceCanStillCreateARecurrentPhase() {
        let chosen = resolver.resolve(
            emissionScores: [
                phaseScores([.deepening: 1.0]),
                phaseScores([.deepening: 0.1, .suggestions: 0.9]),
                phaseScores([.deepening: 0.9, .suggestions: 0.1])
            ],
            transitionPriors: [
                .deepening: [.suggestions: 1.0],
                .suggestions: [.deepening: 1.0]
            ],
            transitionPriorMultiplier: 1.0
        )
        let phases = chosen.map { HypnosisMetadata.Phase.orderedHypnosisPhases[$0] }

        #expect(phases == [.deepening, .suggestions, .deepening])
    }
}

// MARK: - approximateWordTimestamps Tests

struct ApproximateWordTimestampsTests {

    private let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)

    @Test func emptySegmentsReturnsEmpty() {
        let result = analyzer.approximateWordTimestamps(from: [])
        #expect(result.isEmpty)
    }

    @Test func singleWordSegmentProducesOneTimestamp() {
        let seg = makeSegment(text: "relax", start: 0, duration: 2.0)
        let result = analyzer.approximateWordTimestamps(from: [seg])
        #expect(result.count == 1)
        #expect(result[0].word == "relax")
        #expect(abs(result[0].startTime - 0.0) < 0.001)
    }

    @Test func twoWordSegmentDistributesEvenly() {
        let seg = makeSegment(text: "deeply relax", start: 10.0, duration: 4.0)
        let result = analyzer.approximateWordTimestamps(from: [seg])
        #expect(result.count == 2)
        // Each word gets 4.0/2 = 2.0 seconds
        #expect(abs(result[0].startTime - 10.0) < 0.001)
        #expect(abs(result[1].startTime - 12.0) < 0.001)
    }

    @Test func multipleSegmentsProduceConcatenatedTimestamps() {
        let segments = [
            makeSegment(text: "relax now", start: 0, duration: 2.0),
            makeSegment(text: "breathe deeply", start: 5.0, duration: 4.0)
        ]
        let result = analyzer.approximateWordTimestamps(from: segments)
        #expect(result.count == 4)
    }

    @Test func emptyTextSegmentIsSkipped() {
        let segments = [
            makeSegment(text: "", start: 0, duration: 1.0),
            makeSegment(text: "relax", start: 2.0, duration: 1.0)
        ]
        let result = analyzer.approximateWordTimestamps(from: segments)
        #expect(result.count == 1)
    }
}

// MARK: - enforcePhaseOrdering Tests

struct EnforcePhaseOrderingTests {

    private let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)

    @Test func alreadyOrderedTimelinePassesThrough() {
        let timeline: [HypnosisMetadata.Phase?] = [.preTalk, .induction, .deepening, .therapy, .emergence]
        let result = analyzer.enforcePhaseOrdering(timeline: timeline)
        #expect(result == [.induction, .induction, .deepening, .suggestions, .emergence])
    }

    @Test func sustainedBackwardTransitionIsPreserved() {
        // Real sessions commonly return from suggestions to deepening.
        let timeline: [HypnosisMetadata.Phase?] = [.suggestions, .deepening]
        let result = analyzer.enforcePhaseOrdering(timeline: timeline)
        #expect(result == timeline)
    }

    @Test func nilBucketsArePreserved() {
        let timeline: [HypnosisMetadata.Phase?] = [.preTalk, nil, .induction]
        let result = analyzer.enforcePhaseOrdering(timeline: timeline)
        #expect(result[1] == nil, "nil buckets must remain nil")
    }

    @Test func backwardTransitionAcrossNilGapIsPreserved() {
        let timeline: [HypnosisMetadata.Phase?] = [.suggestions, nil, .deepening]
        let result = analyzer.enforcePhaseOrdering(timeline: timeline)
        #expect(result == timeline)
    }

    @Test func emptyTimelineReturnsEmpty() {
        let result = analyzer.enforcePhaseOrdering(timeline: [])
        #expect(result.isEmpty)
    }

    @Test func backwardSegmentTransitionIsPreserved() {
        let segments = [
            PhaseSegment(
                phase: .suggestions,
                startTime: 0,
                endTime: 30,
                characteristics: "Suggestions",
                tranceDepthEstimate: 0.72
            ),
            PhaseSegment(
                phase: .deepening,
                startTime: 30,
                endTime: 60,
                characteristics: "Deepening",
                tranceDepthEstimate: 0.62
            ),
            PhaseSegment(
                phase: .suggestions,
                startTime: 60,
                endTime: 90,
                characteristics: "Suggestions",
                tranceDepthEstimate: 0.7
            )
        ]

        let result = analyzer.enforcePhaseOrdering(phaseSegments: segments)

        #expect(result.map(\.phase) == [.suggestions, .deepening, .suggestions])
        #expect(result[0].startTime == 0)
        #expect(result[0].endTime == 30)
    }
}

// MARK: - majorityVoteSmooth Tests

struct MajorityVoteSmoothTests {

    private let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)

    @Test func singleIsolatedPhaseSurroundedByDominantIsReplaced() {
        // Single .induction spike surrounded by .therapy
        let timeline: [HypnosisMetadata.Phase?] = [
            .therapy, .therapy, .induction, .therapy, .therapy
        ]
        let result = analyzer.majorityVoteSmooth(timeline: timeline, windowSize: 5)
        #expect(result[2] == .therapy, "single spike must be smoothed to dominant")
    }

    @Test func windowSizeOneReturnsIdentical() {
        let timeline: [HypnosisMetadata.Phase?] = [.preTalk, .induction, .therapy]
        let result = analyzer.majorityVoteSmooth(timeline: timeline, windowSize: 1)
        #expect(result == timeline)
    }

    @Test func nilGapsAreForwardFilled() {
        // Forward-fill only runs when windowSize > 1
        let timeline: [HypnosisMetadata.Phase?] = [.therapy, nil, nil, nil]
        let result = analyzer.majorityVoteSmooth(timeline: timeline, windowSize: 5)
        // After majority-vote + forward-fill, nils should be filled by therapy
        #expect(result.allSatisfy { $0 == .therapy })
    }

    @Test func emptyTimelineReturnsEmpty() {
        let result = analyzer.majorityVoteSmooth(timeline: [], windowSize: 5)
        #expect(result.isEmpty)
    }
}

// MARK: - Fractionation Cycle Gate Tests

struct FractionationCycleGateTests {

    @Test func repeatedInteriorWakeAndDropCyclesBecomeOneFractionationSection() {
        let timeline: [HypnosisMetadata.Phase?] =
            Array(repeating: .induction, count: 20)
            + Array(repeating: .emergence, count: 10)
            + Array(repeating: .induction, count: 25)
            + Array(repeating: .suggestions, count: 20)
            + Array(repeating: .conditioning, count: 15)
            + Array(repeating: .emergence, count: 10)
            + Array(repeating: .induction, count: 25)
            + Array(repeating: .suggestions, count: 20)
            + Array(repeating: .emergence, count: 15)

        let result = ChunkedPhaseAnalyzer.flagFractionationCycles(in: timeline)

        #expect(result[0..<125].allSatisfy { $0 == .fractionation })
        #expect(result[125..<145].allSatisfy { $0 == .suggestions })
        #expect(result[145..<160].allSatisfy { $0 == .emergence })
    }

    @Test func sparseClassificationsCarryFractionationToTheNextObservedPhase() {
        var timeline = [HypnosisMetadata.Phase?](repeating: nil, count: 200)
        set(.induction, in: 0..<15, on: &timeline)
        set(.emergence, in: 30..<45, on: &timeline)
        set(.induction, in: 60..<75, on: &timeline)
        set(.suggestions, in: 90..<105, on: &timeline)
        set(.emergence, in: 120..<135, on: &timeline)
        set(.induction, in: 150..<165, on: &timeline)
        set(.suggestions, in: 180..<195, on: &timeline)

        let result = ChunkedPhaseAnalyzer.flagFractionationCycles(in: timeline)

        #expect(result[0..<180].allSatisfy { $0 == .fractionation })
        #expect(result[180..<195].allSatisfy { $0 == .suggestions })
    }

    @Test func oneInteriorWakeAndReturnDoesNotTriggerFractionation() {
        let timeline: [HypnosisMetadata.Phase?] =
            Array(repeating: .induction, count: 20)
            + Array(repeating: .emergence, count: 10)
            + Array(repeating: .induction, count: 25)
            + Array(repeating: .suggestions, count: 30)
            + Array(repeating: .emergence, count: 15)

        let result = ChunkedPhaseAnalyzer.flagFractionationCycles(in: timeline)

        #expect(result == timeline)
    }

    @Test func backToBackWakeAndDropCyclesAreSufficient() {
        let timeline: [HypnosisMetadata.Phase?] =
            Array(repeating: .induction, count: 20)
            + Array(repeating: .emergence, count: 10)
            + Array(repeating: .induction, count: 20)
            + Array(repeating: .emergence, count: 10)
            + Array(repeating: .induction, count: 20)
            + Array(repeating: .emergence, count: 20)

        let result = ChunkedPhaseAnalyzer.flagFractionationCycles(in: timeline)

        #expect(result[0..<80].allSatisfy { $0 == .fractionation })
        #expect(result[80..<100].allSatisfy { $0 == .emergence })
    }

    @Test func laterWakeAndDropCyclesStartAfterPrecedingSuggestions() {
        let timeline: [HypnosisMetadata.Phase?] =
            Array(repeating: .suggestions, count: 30)
            + Array(repeating: .emergence, count: 5)
            + Array(repeating: .induction, count: 15)
            + Array(repeating: .emergence, count: 5)
            + Array(repeating: .induction, count: 15)
            + Array(repeating: .deepening, count: 20)

        let result = ChunkedPhaseAnalyzer.flagFractionationCycles(in: timeline)

        #expect(result[0..<30].allSatisfy { $0 == .suggestions })
        #expect(result[30..<70].allSatisfy { $0 == .fractionation })
        #expect(result[70..<90].allSatisfy { $0 == .deepening })
    }

    @Test func transcriptWakeAndDropCyclesProduceFractionationWithoutPhaseLabels() throws {
        let words =
            timedWords("continue with these suggestions", at: 0)
            + timedWords("open those eyes up for me", at: 100)
            + timedWords("and sleep all the way down", at: 110)
            + timedWords("open your eyes now", at: 140)
            + timedWords("and sleep all the way down", at: 150)
            + timedWords("continue deeper now", at: 180)

        let spans = ChunkedPhaseAnalyzer.detectFractionationSpans(
            in: words,
            duration: 220
        )
        #expect(spans.count == 1)
        let span = try #require(spans.first)

        #expect(span.startTime == 100)
        #expect(span.endTime == 152)
        #expect(span.cycleCount == 2)
    }

    @Test func secondPassRemovesLocalFractionationGuessWithoutAnAwakener() {
        let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)
        let transcription = AudioTranscriptionResult(
            fullText: "Aware but unaware, relaxing and drifting more deeply.",
            segments: [
                makeSegment(
                    text: "Aware but unaware, relaxing and drifting more deeply.",
                    start: 0,
                    duration: 120
                )
            ],
            duration: 120,
            detectedLanguage: "en"
        )
        let initial = [
            PhaseSegment(phase: .induction, startTime: 0, endTime: 30, characteristics: "", tranceDepthEstimate: 0.3),
            PhaseSegment(phase: .fractionation, startTime: 30, endTime: 70, characteristics: "", tranceDepthEstimate: 0.4),
            PhaseSegment(phase: .deepening, startTime: 70, endTime: 120, characteristics: "", tranceDepthEstimate: 0.6)
        ]

        let result = analyzer.applyFractionationSecondPass(in: initial, transcription: transcription)

        #expect(result.contains { $0.phase == .fractionation } == false)
    }

    @Test func secondPassCanIntroduceFractionationFromOneInteriorAwakener() {
        let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)
        let transcriptSegments = [
            makeSegment(text: "Continue relaxing deeply.", start: 0, duration: 120),
            makeSegment(text: "Eyes open, come back up for me now.", start: 200, duration: 10),
            makeSegment(text: "And continue going deeper.", start: 210, duration: 90),
            makeSegment(text: "Accept these suggestions easily.", start: 300, duration: 200),
            makeSegment(text: "One two three four five, wide awake.", start: 560, duration: 40)
        ]
        let transcription = AudioTranscriptionResult(
            fullText: transcriptSegments.map(\.text).joined(separator: " "),
            segments: transcriptSegments,
            duration: 600,
            detectedLanguage: "en"
        )
        let initial = [
            PhaseSegment(phase: .induction, startTime: 0, endTime: 120, characteristics: "", tranceDepthEstimate: 0.3),
            PhaseSegment(phase: .deepening, startTime: 120, endTime: 300, characteristics: "", tranceDepthEstimate: 0.6),
            PhaseSegment(phase: .suggestions, startTime: 300, endTime: 560, characteristics: "", tranceDepthEstimate: 0.7),
            PhaseSegment(phase: .emergence, startTime: 560, endTime: 600, characteristics: "", tranceDepthEstimate: 0.2)
        ]

        let result = analyzer.applyFractionationSecondPass(in: initial, transcription: transcription)
        let phaseAtAwakener = result.first { 200 >= $0.startTime && 200 < $0.endTime }?.phase

        #expect(phaseAtAwakener == .fractionation)
        #expect(result.last?.phase == .emergence)
    }

    @Test func keywordAnalyzerAppliesTranscriptFractionationEvidence() throws {
        let words =
            timedWords("continue with these suggestions", at: 0)
            + timedWords("open those eyes up for me", at: 100)
            + timedWords("and sleep all the way down", at: 110)
            + timedWords("open your eyes now", at: 140)
            + timedWords("and sleep all the way down", at: 150)
            + timedWords("continue deeper now", at: 180)

        let segments = HypnosisPhaseAnalyzer(corpusKnowledge: .empty).analyze(
            wordTimestamps: words,
            duration: 220
        )
        let fractionation = try #require(segments.first { $0.phase == .fractionation })

        #expect(fractionation.startTime == 100)
        #expect(fractionation.endTime == 152)
    }

    @Test func hybridSelectionCannotEraseTranscriptFractionationEvidence() throws {
        let transcriptSegments = [
            makeSegment(text: "continue with these suggestions", start: 0, duration: 8),
            makeSegment(text: "open those eyes up for me", start: 100, duration: 6),
            makeSegment(text: "and sleep all the way down", start: 110, duration: 6),
            makeSegment(text: "open your eyes now", start: 140, duration: 5),
            makeSegment(text: "and sleep all the way down", start: 150, duration: 6),
            makeSegment(text: "continue deeper now", start: 180, duration: 6),
        ]
        let transcription = AudioTranscriptionResult(
            fullText: transcriptSegments.map(\.text).joined(separator: " "),
            segments: transcriptSegments,
            duration: 220,
            detectedLanguage: "en"
        )
        let collapsed = [
            PhaseSegment(
                phase: .suggestions,
                startTime: 0,
                endTime: 220,
                characteristics: "Suggestions",
                tranceDepthEstimate: TrancePhase.suggestions.tranceDepthEstimate
            ),
        ]
        let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)

        let selected = analyzer.selectPreferredPhases(
            keywordPhases: collapsed,
            chunkedPhases: collapsed,
            transcription: transcription
        )

        #expect(selected.phases.contains { $0.phase == .fractionation })
    }

    @Test func fractionationRecoveryUsesMeaningBeforeTerminalEmergence() throws {
        let transcriptSegments = [
            makeSegment(text: "fractionation begins now", start: 0, duration: 5),
            makeSegment(text: "open those eyes", start: 10, duration: 4),
            makeSegment(text: "and sleep all the way down", start: 20, duration: 5),
            makeSegment(text: "open those eyes", start: 30, duration: 4),
            makeSegment(text: "and sleep all the way down", start: 40, duration: 5),
            makeSegment(text: "sink deeper and deeper, relaxing completely into profound trance", start: 50, duration: 15),
            makeSegment(text: "my suggestions fill your mind and become automatic", start: 70, duration: 20),
            makeSegment(text: "in a moment, not just yet, I am going to count and you will come back", start: 120, duration: 20),
            makeSegment(text: "one, two, three, come back into the room, four, five, wide awake", start: 150, duration: 20),
        ]
        let transcription = AudioTranscriptionResult(
            fullText: transcriptSegments.map(\.text).joined(separator: " "),
            segments: transcriptSegments,
            duration: 180,
            detectedLanguage: "en"
        )
        let collapsed = [
            PhaseSegment(
                phase: .therapy,
                startTime: 0,
                endTime: 180,
                characteristics: "Collapsed model output",
                tranceDepthEstimate: TrancePhase.therapy.tranceDepthEstimate
            )
        ]
        let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)

        let selected = analyzer.selectPreferredPhases(
            keywordPhases: collapsed,
            chunkedPhases: collapsed,
            transcription: transcription
        ).phases
        func phase(at time: TimeInterval) -> HypnosisMetadata.Phase? {
            selected.first { time >= $0.startTime && time < $0.endTime }?.phase
        }

        #expect(phase(at: 55) == .deepening)
        #expect(phase(at: 80) == .suggestions)
        #expect(phase(at: 130) == .suggestions)
        #expect(phase(at: 160) == .emergence)
    }

    @Test func longFractionationTranscriptSeparatesTwoCycleSections() throws {
        let words =
            timedWords("fractionation begins", at: 0)
            + timedWords("open your eyes", at: 305)
            + timedWords("and sleep", at: 315)
            + timedWords("open your eyes", at: 462)
            + timedWords("and sleep", at: 470)
            + timedWords("open your eyes", at: 610)
            + timedWords("and sleep", at: 618)
            + timedWords("open your eyes", at: 760)
            + timedWords("and sleep", at: 768)
            + timedWords("open your eyes", at: 900)
            + timedWords("and sleep", at: 908)
            + timedWords("open your eyes", at: 1018)
            + timedWords("and sleep", at: 1027)
            + timedWords("continue with suggestions", at: 1178)
            + timedWords("open your eyes", at: 1306)
            + timedWords("and sleep", at: 1310)
            + timedWords("open your eyes", at: 1403)
            + timedWords("and sleep", at: 1412)
            + timedWords("open your eyes", at: 1476)
            + timedWords("and sleep", at: 1483)

        let spans = ChunkedPhaseAnalyzer.detectFractionationSpans(
            in: words,
            duration: 1_704
        )

        #expect(spans.count == 2)
        #expect(spans[0].startTime == 0)
        #expect(spans[0].endTime == 1029)
        #expect(spans[1].startTime == 1306)
        #expect(spans[1].endTime == 1485)
    }

    @Test func sparseASRWakeCuesBridgeOneFractionationEpisodeButRespectItsExit() throws {
        let words =
            timedWords("fractionation begins", at: 0)
            + timedWords("open those eyes", at: 170)
            + timedWords("eyes open", at: 216)
            + timedWords("open those eyes", at: 305)
            + timedWords("open those eyes", at: 462)
            + timedWords("open those eyes", at: 497)
            + timedWords("open those eyes", at: 533)
            + timedWords("eyes close", at: 540)
            + timedWords("open those eyes", at: 560)
            + timedWords("eyes close", at: 606)
            + timedWords("open those eyes", at: 616)
            + timedWords("open those eyes", at: 700)
            + timedWords("eyes open", at: 809)
            + timedWords("eyes open", at: 909)
            + timedWords("those eyes close", at: 929)
            + timedWords("eyes open", at: 958)
            + timedWords("open those eyes", at: 1_000)
            + timedWords("eyes close", at: 1_027)
            + timedWords("open those eyes", at: 1_077)
            + timedWords("open those eyes", at: 1_237)
            + timedWords("and sleep", at: 1_259)
            + timedWords("open those eyes", at: 1_306)
            + timedWords("and sleep", at: 1_310)
            + timedWords("fractionation feels good", at: 1_324)
            + timedWords("open those eyes", at: 1_337)
            + timedWords("and sleep", at: 1_344)
            + timedWords("open those eyes", at: 1_403)
            + timedWords("and sleep", at: 1_412)
            + timedWords("open those eyes", at: 1_476)
            + timedWords("and sleep", at: 1_483)
            + timedWords("eyes open keep them open wait for my cue", at: 1_497)
            + timedWords("open those eyes and sleep", at: 1_535)

        let spans = ChunkedPhaseAnalyzer.detectFractionationSpans(
            in: words,
            duration: 1_704
        )

        #expect(spans.count == 2)
        #expect(spans[0].startTime == 0)
        #expect(spans[0].endTime == 1_029)
        #expect(spans[1].startTime == 1_311)
        #expect(spans[1].endTime == 1_485)
    }

    private func set(
        _ phase: HypnosisMetadata.Phase,
        in range: Range<Int>,
        on timeline: inout [HypnosisMetadata.Phase?]
    ) {
        for index in range {
            timeline[index] = phase
        }
    }

    private func timedWords(_ text: String, at startTime: TimeInterval) -> [WordTimestamp] {
        text.split(separator: " ").enumerated().map { index, word in
            WordTimestamp(
                word: String(word),
                startTime: startTime + Double(index),
                duration: 1
            )
        }
    }
}

// MARK: - Final Timeline Stability Tests

struct FinalTimelineStabilityTests {

    private let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)

    @Test func futureAwakeningAnnouncementDoesNotStartTerminalEmergence() throws {
        let transcriptSegments = [
            makeSegment(
                text: "Continue integrating these suggestions while you rest deeply.",
                start: 0,
                duration: 100
            ),
            makeSegment(
                text: "Until then allow these suggestions to settle into your mind.",
                start: 100,
                duration: 40
            ),
            makeSegment(
                text: "I'm going to wake you soon, but continue resting deeply for now.",
                start: 140,
                duration: 10
            ),
            makeSegment(
                text: "One, two, three, feeling yourself come back into the room, four, five, wide awake.",
                start: 150,
                duration: 30
            ),
        ]
        let transcription = AudioTranscriptionResult(
            fullText: transcriptSegments.map(\.text).joined(separator: " "),
            segments: transcriptSegments,
            duration: 180,
            detectedLanguage: "en"
        )
        let primary = [
            PhaseSegment(
                phase: .suggestions,
                startTime: 0,
                endTime: 180,
                characteristics: "Suggestions",
                tranceDepthEstimate: TrancePhase.suggestions.tranceDepthEstimate
            )
        ]

        let result = analyzer.adaptPredictedPhases(primary, transcription: transcription)
        let emergence = try #require(result.first { $0.phase == .emergence })

        #expect(emergence.startTime == 150)
    }

    @Test func prematurePredictedEmergenceMovesToTheActiveWakeCue() throws {
        let transcriptSegments = [
            makeSegment(text: "Continue integrating these suggestions while you rest deeply.", start: 0, duration: 100),
            makeSegment(text: "Until then allow these suggestions to settle into your mind.", start: 100, duration: 40),
            makeSegment(text: "I'm going to wake you soon, but continue resting deeply for now.", start: 140, duration: 10),
            makeSegment(text: "Wake now, coming back into the room, alert and fully awake.", start: 150, duration: 30)
        ]
        let transcription = AudioTranscriptionResult(
            fullText: transcriptSegments.map(\.text).joined(separator: " "),
            segments: transcriptSegments,
            duration: 180,
            detectedLanguage: "en"
        )
        let premature = [
            PhaseSegment(phase: .suggestions, startTime: 0, endTime: 100, characteristics: "", tranceDepthEstimate: 0.7),
            PhaseSegment(phase: .emergence, startTime: 100, endTime: 180, characteristics: "", tranceDepthEstimate: 0.2)
        ]

        let result = analyzer.adaptPredictedPhases(premature, transcription: transcription)
        let emergence = try #require(result.first { $0.phase == .emergence })

        #expect(emergence.startTime == 150)
    }

    @Test func adaptationDoesNotReintroduceRapidPhaseChanges() {
        let transcriptionSegments = [
            makeSegment(text: "Take a slow breath and relax now.", start: 0, duration: 6),
            makeSegment(text: "You will accept every suggestion.", start: 6, duration: 6),
            makeSegment(text: "Going deeper now, deeper and deeper.", start: 12, duration: 6),
            makeSegment(text: "You will feel this change automatically.", start: 18, duration: 6),
            makeSegment(text: "Relax and drift deeper with every breath.", start: 24, duration: 6),
            makeSegment(text: "Every time you hear these words you respond.", start: 30, duration: 6),
            makeSegment(text: "Sink deeper and let your body relax.", start: 36, duration: 6),
            makeSegment(text: "From now on this response becomes automatic.", start: 42, duration: 6),
            makeSegment(text: "Breathe slowly and continue relaxing.", start: 48, duration: 6),
            makeSegment(text: "You will accept these suggestions easily.", start: 54, duration: 6)
        ]
        let transcription = AudioTranscriptionResult(
            fullText: transcriptionSegments.map(\.text).joined(separator: " "),
            segments: transcriptionSegments,
            duration: 60,
            detectedLanguage: "en"
        )
        let primary = [
            PhaseSegment(
                phase: .induction,
                startTime: 0,
                endTime: 60,
                characteristics: "Induction",
                tranceDepthEstimate: TrancePhase.induction.tranceDepthEstimate
            )
        ]

        let result = analyzer.adaptPredictedPhases(primary, transcription: transcription)
        let runs = result
            .map { "\($0.phase.rawValue) \($0.startTime)-\($0.endTime)" }
            .joined(separator: ", ")

        #expect(
            result.allSatisfy { $0.endTime - $0.startTime >= 20 },
            "Final adaptation must honor the configured 20-second minimum: \(runs)"
        )
    }

    @Test func adaptationRejectsBriefSuggestionIslandInsideStableInduction() {
        let transcriptSegments = [
            makeSegment(
                text: "Take a slow breath, close your eyes, and let your whole body relax comfortably.",
                start: 0,
                duration: 163
            ),
            makeSegment(
                text: "You will notice calm confidence growing naturally within you.",
                start: 163,
                duration: 59
            ),
            makeSegment(
                text: "Continue breathing slowly, remaining deeply relaxed and comfortably settled.",
                start: 222,
                duration: 1_355
            )
        ]
        let transcription = AudioTranscriptionResult(
            fullText: transcriptSegments.map(\.text).joined(separator: " "),
            segments: transcriptSegments,
            duration: 1_577,
            detectedLanguage: "en"
        )
        let primary = [
            PhaseSegment(
                phase: .induction,
                startTime: 0,
                endTime: 1_577,
                characteristics: "Induction",
                tranceDepthEstimate: TrancePhase.induction.tranceDepthEstimate
            )
        ]

        let result = analyzer.adaptPredictedPhases(primary, transcription: transcription)
        let isolatedSuggestion = result.indices.contains { index in
            guard index > result.startIndex, index < result.index(before: result.endIndex) else {
                return false
            }
            let segment = result[index]
            return segment.phase.labelingPhase == .suggestions
                && result[result.index(before: index)].phase.labelingPhase
                    == result[result.index(after: index)].phase.labelingPhase
        }
        let resultDescription = result
            .map { "\($0.phase.rawValue) \($0.startTime)-\($0.endTime)" }
            .joined(separator: ", ")

        #expect(
            isolatedSuggestion == false,
            "A single 59-second suggestion phrase must not create a section in a stable 26-minute induction: \(resultDescription)"
        )
    }

    @Test func adaptationPreservesSustainedSuggestionReturnAfterConditioning() {
        let transcriptionSegments = [
            makeSegment(
                text: "Take a slow breath, close your eyes, and settle comfortably into trance.",
                start: 0,
                duration: 25
            ),
            makeSegment(
                text: "Whenever you hear the bell, this trigger will bring the response back automatically.",
                start: 25,
                duration: 30
            ),
            makeSegment(
                text: "You can feel calm, confident, and free to enjoy this pleasant change in everyday life.",
                start: 55,
                duration: 30
            ),
            makeSegment(
                text: "From now on, every time I say the word relax, the response activates instantly.",
                start: 85,
                duration: 30
            ),
            makeSegment(
                text: "I count up to five, becoming wide awake, alert, clear headed, and back in the room.",
                start: 115,
                duration: 25
            )
        ]
        let transcription = AudioTranscriptionResult(
            fullText: transcriptionSegments.map(\.text).joined(separator: " "),
            segments: transcriptionSegments,
            duration: 140,
            detectedLanguage: "en"
        )
        let primary = [
            PhaseSegment(
                phase: .induction,
                startTime: 0,
                endTime: 25,
                characteristics: "Induction",
                tranceDepthEstimate: TrancePhase.induction.tranceDepthEstimate
            ),
            PhaseSegment(
                phase: .conditioning,
                startTime: 25,
                endTime: 55,
                characteristics: "Conditioning",
                tranceDepthEstimate: TrancePhase.conditioning.tranceDepthEstimate
            ),
            PhaseSegment(
                phase: .suggestions,
                startTime: 55,
                endTime: 85,
                characteristics: "Suggestions",
                tranceDepthEstimate: TrancePhase.suggestions.tranceDepthEstimate
            ),
            PhaseSegment(
                phase: .conditioning,
                startTime: 85,
                endTime: 115,
                characteristics: "Conditioning",
                tranceDepthEstimate: TrancePhase.conditioning.tranceDepthEstimate
            ),
            PhaseSegment(
                phase: .emergence,
                startTime: 115,
                endTime: 140,
                characteristics: "Emergence",
                tranceDepthEstimate: TrancePhase.emergence.tranceDepthEstimate
            )
        ]

        let result = analyzer.adaptPredictedPhases(primary, transcription: transcription)
        let phases = result.map(\.phase)
        let conditioningIndex = phases.firstIndex(of: .conditioning)
        let laterSuggestionIndex = phases.indices.first { index in
            phases[index] == .suggestions && index > (conditioningIndex ?? phases.endIndex)
        }

        #expect(
            conditioningIndex != nil && laterSuggestionIndex != nil,
            "A sustained, transcript-supported return must survive adaptation; got \(phases.map(\.rawValue))"
        )
    }

}

// MARK: - consolidatePhaseSegments Tests

struct ConsolidatePhaseSegmentsTests {

    private let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)

    @Test func singlePhaseProducesOneSegment() {
        let timeline: [HypnosisMetadata.Phase?] = Array(repeating: .therapy, count: 60)
        let segments = analyzer.consolidatePhaseSegments(timeline: timeline, duration: 60)
        #expect(segments.count == 1)
        #expect(segments[0].phase == .therapy)
        #expect(segments[0].startTime == 0)
        #expect(segments[0].endTime == 60)
    }

    @Test func twoPhasesProduceTwoSegments() {
        var timeline: [HypnosisMetadata.Phase?] = Array(repeating: .preTalk, count: 30)
        timeline += Array(repeating: .therapy, count: 30)
        let segments = analyzer.consolidatePhaseSegments(timeline: timeline, duration: 60)
        #expect(segments.count == 2)
        #expect(segments[0].phase == .preTalk)
        #expect(segments[1].phase == .therapy)
    }

    @Test func segmentsAreChronologicallyOrdered() {
        var timeline: [HypnosisMetadata.Phase?] = Array(repeating: .preTalk, count: 20)
        timeline += Array(repeating: .induction, count: 20)
        timeline += Array(repeating: .deepening, count: 20)
        let segments = analyzer.consolidatePhaseSegments(timeline: timeline, duration: 60)
        for idx in 0..<(segments.count - 1) {
            #expect(segments[idx].endTime <= segments[idx + 1].startTime,
                "segments must be chronologically ordered")
        }
    }

    @Test func lastSegmentEndsAtDuration() {
        let timeline: [HypnosisMetadata.Phase?] = Array(repeating: .emergence, count: 10)
        let segments = analyzer.consolidatePhaseSegments(timeline: timeline, duration: 300)
        #expect(segments.last?.endTime == 300, "last segment must end at session duration")
    }

    @Test func emptyTimelineReturnsEmpty() {
        let segments = analyzer.consolidatePhaseSegments(timeline: [], duration: 60)
        #expect(segments.isEmpty)
    }
}

// MARK: - Position Weighting Tests

struct PositionAwareResolutionTests {

    private let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)

    @Test func earlyBrainwashingVocabularyDoesNotOverridePretalkAnchoring() {
        let words: [WordTimestamp] = [
            makeWord("welcome", at: 0),
            makeWord("comfortable", at: 4),
            makeWord("brainwashing", at: 8),
            makeWord("brainwashing", at: 9),
            makeWord("brainwashing", at: 10),
            makeWord("indoctrination", at: 11),
            makeWord("brainwash", at: 12),
            makeWord("relax", at: 38),
            makeWord("breathe", at: 42),
            makeWord("deeper", at: 72)
        ]

        let phases = analyzer.analyze(wordTimestamps: words, duration: 90)

        #expect(phases.first?.phase == .preTalk)
        #expect(phases.first?.startTime == 0)
    }
}

// MARK: - Transcript Confidence Tests

struct TranscriptConfidenceEnrichmentTests {

    private let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)

    @Test func repetitiveBrainwashingSectionIsPromotedToHighConfidence() {
        let segment = PhaseSegment(
            phase: .brainwashing,
            startTime: 0,
            endTime: 90,
            characteristics: "Brainwashing",
            tranceDepthEstimate: 0.82
        )
        let section = TranscriptSectionMetrics(
            id: segment.id,
            phase: .brainwashing,
            startTime: 0,
            endTime: 90,
            duration: 90,
            wordCount: 150,
            uniqueWordCount: 20,
            wordsPerMinute: 100,
            normalizedWordsPerMinute: 0.82,
            speechCoverage: 0.93,
            normalizedSpeechCoverage: 1.05,
            lexicalDiversity: 0.18,
            normalizedLexicalDiversity: 0.72,
            repetitionDensity: 2.4,
            normalizedRepetitionDensity: 1.85,
            topWords: [
                .init(word: "obey", count: 24, share: 0.16, normalizedShareLift: 2.3),
                .init(word: "programmed", count: 12, share: 0.08, normalizedShareLift: 2.0)
            ],
            topDistinctiveWords: [
                .init(word: "obey", count: 24, share: 0.16, normalizedShareLift: 2.3),
                .init(word: "programmed", count: 12, share: 0.08, normalizedShareLift: 2.0)
            ]
        )
        let transcriptAnalysis = TranscriptAnalysis(overall: section, sections: [section])

        let enriched = analyzer.enrichSegmentsWithTranscriptConfidence([segment], transcriptAnalysis: transcriptAnalysis)

        #expect(enriched.first?.confidenceLevel == .high)
        #expect(enriched.first?.confidenceRationale?.localizedLowercase.contains("repetition") == true)
        #expect(enriched.first?.confidenceRationale?.localizedLowercase.contains("vocabulary") == true)
    }

    @Test func contradictoryBrainwashingSectionFallsToLowConfidence() {
        let segment = PhaseSegment(
            phase: .brainwashing,
            startTime: 0,
            endTime: 18,
            characteristics: "Brainwashing",
            tranceDepthEstimate: 0.82
        )
        let overall = TranscriptSectionMetrics(
            id: UUID(),
            phase: nil,
            startTime: 0,
            endTime: 18,
            duration: 18,
            wordCount: 50,
            uniqueWordCount: 40,
            wordsPerMinute: 166,
            normalizedWordsPerMinute: 1.0,
            speechCoverage: 0.85,
            normalizedSpeechCoverage: 1.0,
            lexicalDiversity: 0.8,
            normalizedLexicalDiversity: 1.0,
            repetitionDensity: 0.2,
            normalizedRepetitionDensity: 1.0,
            topWords: [],
            topDistinctiveWords: []
        )
        let section = TranscriptSectionMetrics(
            id: segment.id,
            phase: .brainwashing,
            startTime: 0,
            endTime: 18,
            duration: 18,
            wordCount: 50,
            uniqueWordCount: 40,
            wordsPerMinute: 166,
            normalizedWordsPerMinute: 1.28,
            speechCoverage: 0.78,
            normalizedSpeechCoverage: 0.92,
            lexicalDiversity: 0.8,
            normalizedLexicalDiversity: 1.34,
            repetitionDensity: 0.2,
            normalizedRepetitionDensity: 0.42,
            topWords: [
                .init(word: "awake", count: 6, share: 0.12, normalizedShareLift: 1.7),
                .init(word: "alert", count: 4, share: 0.08, normalizedShareLift: 1.5)
            ],
            topDistinctiveWords: [
                .init(word: "awake", count: 6, share: 0.12, normalizedShareLift: 1.7),
                .init(word: "alert", count: 4, share: 0.08, normalizedShareLift: 1.5)
            ]
        )
        let transcriptAnalysis = TranscriptAnalysis(overall: overall, sections: [section])

        let enriched = analyzer.enrichSegmentsWithTranscriptConfidence([segment], transcriptAnalysis: transcriptAnalysis)

        #expect(enriched.first?.confidenceLevel == .low)
        #expect(enriched.first?.confidenceRationale?.localizedLowercase.contains("mixed") == true)
    }

    @Test func corpusLearnedWeightsFeedKeywordHitMap() {
        let analyzer = HypnosisPhaseAnalyzer(
            corpusKnowledge: CorpusPhaseKnowledge(
                keywordWeights: [.brainwashing: ["spiral": 3.6]],
                phaseTokens: [.brainwashing: ["spiral"]],
                fewShotExamples: []
            )
        )

        let hitMap = analyzer.buildHitMap(
            wordTimestamps: [makeWord("spiral", at: 0)],
            bucketCount: 1
        )

        #expect((hitMap[0][.brainwashing] ?? 0) > 0)
    }

    @Test func corpusLearnedPhraseWeightsFeedKeywordHitMap() {
        let analyzer = HypnosisPhaseAnalyzer(
            corpusKnowledge: CorpusPhaseKnowledge(
                phraseWeights: [.conditioning: ["snap right back": 4.2]]
            )
        )

        let hitMap = analyzer.buildHitMap(
            wordTimestamps: [
                makeWord("snap", at: 0),
                makeWord("right", at: 1),
                makeWord("back", at: 2)
            ],
            bucketCount: 4
        )

        #expect((hitMap[0][.conditioning] ?? 0) > 0)
    }

    @Test func fullTextOnlyTranscriptionStillProducesPhases() {
        let transcription = AudioTranscriptionResult(
            fullText: "Take a slow breath, close your eyes, and relax deeper and deeper.",
            segments: [],
            duration: 60,
            detectedLanguage: "en"
        )

        let phases = analyzer.analyzeTranscription(transcription)

        #expect(phases.isEmpty == false)
    }

    @Test func hybridSelectionPrefersKeywordWhenChunkedTranscriptFitIsWorse() {
        let transcription = AudioTranscriptionResult(
            fullText: "obey programmed obey obey repeat after me obey automatically",
            segments: [
                makeSegment(text: "obey programmed obey", start: 0, duration: 20),
                makeSegment(text: "obey repeat after me", start: 20, duration: 20),
                makeSegment(text: "obey automatically", start: 40, duration: 20)
            ],
            duration: 60,
            detectedLanguage: "en"
        )

        let keywordPhases = [
            PhaseSegment(
                phase: .brainwashing,
                startTime: 0,
                endTime: 60,
                characteristics: "Brainwashing",
                tranceDepthEstimate: 0.82
            )
        ]
        let chunkedPhases = [
            PhaseSegment(
                phase: .emergence,
                startTime: 0,
                endTime: 60,
                characteristics: "Emergence",
                tranceDepthEstimate: 0.25,
                confidenceLevel: .high
            )
        ]

        let selection = analyzer.selectPreferredPhases(
            keywordPhases: keywordPhases,
            chunkedPhases: chunkedPhases,
            transcription: transcription
        )

        #expect(selection.usedChunkedAnalyzer == false)
        #expect(selection.phases.first?.phase == .brainwashing)
    }

    @Test func hybridSelectionCanFuseBestSectionsFromKeywordAndChunkedOutputs() {
        let transcription = AudioTranscriptionResult(
            fullText: """
            take a deep breath and close your eyes
            deeper and deeper down the staircase step by step
            as i count to five you become wide awake and aware
            """,
            segments: [
                makeSegment(
                    text: "take a deep breath and close your eyes",
                    start: 0,
                    duration: 30
                ),
                makeSegment(
                    text: "deeper and deeper down the staircase step by step",
                    start: 30,
                    duration: 30
                ),
                makeSegment(
                    text: "as i count to five you become wide awake and aware",
                    start: 60,
                    duration: 30
                )
            ],
            duration: 90,
            detectedLanguage: "en"
        )

        let keywordPhases = [
            PhaseSegment(
                phase: .induction,
                startTime: 0,
                endTime: 30,
                characteristics: "Induction",
                tranceDepthEstimate: 0.22
            ),
            PhaseSegment(
                phase: .deepening,
                startTime: 30,
                endTime: 90,
                characteristics: "Deepening",
                tranceDepthEstimate: 0.62
            )
        ]
        let chunkedPhases = [
            PhaseSegment(
                phase: .induction,
                startTime: 0,
                endTime: 60,
                characteristics: "Induction",
                tranceDepthEstimate: 0.22,
                confidenceLevel: .high
            ),
            PhaseSegment(
                phase: .emergence,
                startTime: 60,
                endTime: 90,
                characteristics: "Emergence",
                tranceDepthEstimate: 0.24,
                confidenceLevel: .high
            )
        ]

        let selection = analyzer.selectPreferredPhases(
            keywordPhases: keywordPhases,
            chunkedPhases: chunkedPhases,
            transcription: transcription
        )

        #expect(selection.phases.count == 3)
        #expect(selection.phases.map(\.phase) == [.induction, .deepening, .emergence])
    }

    @Test func adaptPredictedPhasesCanMoveBoundaryTowardTranscriptTransition() {
        let transcription = AudioTranscriptionResult(
            fullText: """
            deeper and deeper down the staircase with every breath
            even deeper now step by step
            as i count to five you become wide awake and aware
            clear headed and back in the room
            """,
            segments: [
                makeSegment(
                    text: "deeper and deeper down the staircase with every breath",
                    start: 0,
                    duration: 30
                ),
                makeSegment(
                    text: "even deeper now step by step",
                    start: 30,
                    duration: 30
                ),
                makeSegment(
                    text: "as i count to five you become wide awake and aware",
                    start: 60,
                    duration: 20
                ),
                makeSegment(
                    text: "clear headed and back in the room",
                    start: 80,
                    duration: 20
                )
            ],
            duration: 100,
            detectedLanguage: "en"
        )

        let adapted = analyzer.adaptPredictedPhases(
            [
                PhaseSegment(
                    phase: .deepening,
                    startTime: 0,
                    endTime: 45,
                    characteristics: "Deepening",
                    tranceDepthEstimate: 0.62
                ),
                PhaseSegment(
                    phase: .emergence,
                    startTime: 45,
                    endTime: 100,
                    characteristics: "Emergence",
                    tranceDepthEstimate: 0.24
                )
            ],
            transcription: transcription
        )

        #expect(adapted.count == 2)
        #expect(adapted[0].phase == .deepening)
        #expect(adapted[1].phase == .emergence)
        #expect(adapted[0].endTime >= 55)
        #expect(adapted[1].startTime == adapted[0].endTime)
    }

    @Test func suggestPhaseTimelineBuildsOrderedPhraseDrivenProposal() {
        let transcription = AudioTranscriptionResult(
            fullText: """
            welcome and get comfortable as you settle in
            now begin to relax and close your eyes
            with every breath you can go deeper and deeper
            when i snap my fingers this response returns instantly
            and as i count to five you become wide awake
            """,
            segments: [
                makeSegment(text: "welcome and get comfortable as you settle in", start: 0, duration: 20),
                makeSegment(text: "now begin to relax and close your eyes", start: 20, duration: 20),
                makeSegment(text: "with every breath you can go deeper and deeper", start: 40, duration: 20),
                makeSegment(text: "when i snap my fingers this response returns instantly", start: 60, duration: 20),
                makeSegment(text: "and as i count to five you become wide awake", start: 80, duration: 20)
            ],
            duration: 100,
            detectedLanguage: "en"
        )

        let suggestion = analyzer.suggestPhaseTimeline(for: transcription)
        let phases = suggestion.segments.map(\.phase)

        #expect(!suggestion.windows.isEmpty)
        #expect(phases.contains(.induction))
        #expect(phases.contains(.deepening))
        #expect(phases.contains(.suggestions) || phases.contains(.conditioning))
        #expect(phases.last == .emergence)
        #expect(suggestion.averageConfidence > 0.40)
        #expect(
            Set(suggestion.segments.map(\.id)).count == suggestion.segments.count,
            "Every suggested timeline row must have a stable, unique identity."
        )
    }

    @Test func adaptPredictedPhasesCanAdoptPhraseDrivenProposalWhenSeedTimelineIsWeak() {
        let transcription = AudioTranscriptionResult(
            fullText: """
            welcome and get comfortable
            now begin to relax and close your eyes
            deeper and deeper with every breath
            from now on these suggestions settle in
            when i snap my fingers this trigger activates
            and now wide awake and back in the room
            """,
            segments: [
                makeSegment(text: "welcome and get comfortable", start: 0, duration: 20),
                makeSegment(text: "now begin to relax and close your eyes", start: 20, duration: 20),
                makeSegment(text: "deeper and deeper with every breath", start: 40, duration: 20),
                makeSegment(text: "from now on these suggestions settle in", start: 60, duration: 20),
                makeSegment(text: "when i snap my fingers this trigger activates", start: 80, duration: 20),
                makeSegment(text: "and now wide awake and back in the room", start: 100, duration: 20)
            ],
            duration: 120,
            detectedLanguage: "en"
        )

        let adapted = analyzer.adaptPredictedPhases(
            [
                PhaseSegment(
                    phase: .therapy,
                    startTime: 0,
                    endTime: 120,
                    characteristics: "Therapy",
                    tranceDepthEstimate: 0.84
                )
            ],
            transcription: transcription
        )

        let adaptedPhases = adapted.map(\.phase)
        #expect(Set(adaptedPhases).count >= 3)
        // Any of the suggestion-family targets. post_hypnotic_conditioning is
        // now a phase in its own right rather than folding into suggestions, so
        // naming one of them specifically over-specifies what this is checking:
        // that adaptation reaches the later part of a session at all.
        #expect(adaptedPhases.contains { [.suggestions, .conditioning, .brainwashing].contains($0) })
        #expect(adaptedPhases.last == .emergence)
    }

    @Test func techniqueMarkersDoNotInventPhaseTransitions() {
        let baseline = analyzer.analyze(
            wordTimestamps: [
                makeWord("welcome", at: 0),
                makeWord("comfortable", at: 3),
                makeWord("ready", at: 6),
                makeWord("begin", at: 9),
                makeWord("later", at: 36),
                makeWord("this", at: 40),
                makeWord("returns", at: 44),
                makeWord("easily", at: 48)
            ],
            duration: 60
        )

        let techniqueAware = analyzer.analyze(
            wordTimestamps: [
                makeWord("welcome", at: 0),
                makeWord("comfortable", at: 3),
                makeWord("ready", at: 6),
                makeWord("begin", at: 9),
                makeWord("later", at: 36),
                makeWord("this", at: 40),
                makeWord("returns", at: 44),
                makeWord("easily", at: 48)
            ],
            duration: 60,
            techniqueDetection: TechniqueDetectionResult(
                techniques: [],
                markers: [
                    LinguisticMarker(
                        type: .triggerInstallation,
                        timestamp: 40,
                        textSnippet: "trigger",
                        strength: 0.95
                    ),
                    LinguisticMarker(
                        type: .futurePacing,
                        timestamp: 46,
                        textSnippet: "later",
                        strength: 0.80
                    )
                ]
            )
        )

        #expect(
            techniqueAware.map { "\($0.phase.rawValue):\($0.startTime):\($0.endTime)" }
                == baseline.map { "\($0.phase.rawValue):\($0.startTime):\($0.endTime)" }
        )
    }
}

// MARK: - Chunked Prompt Calibration Tests

struct ChunkedPromptCalibrationTests {

    private let analyzer = ChunkedPhaseAnalyzer(
        config: AnalyzerConfig.ChunkedAnalyzer(
            chunkDurationSeconds: 15,
            chunkOverlapSeconds: 5,
            minChunks: 4,
            maxChunks: 12,
            systemInstructions: "Base chunk instructions.",
            fewShotExamples: []
        )
    )

    @Test func effectiveSystemInstructionsIncludeCorpusCueGuide() {
        let knowledge = CorpusPhaseKnowledge(
            keywordWeights: [
                .induction: ["breathe": 2.4, "eyelids": 2.0],
                .conditioning: ["trigger": 2.1]
            ],
            phaseTokens: [:],
            phraseWeights: [
                .suggestions: ["when i say relax": 4.1]
            ],
            transitionPriors: [:],
            fewShotExamples: []
        )

        let instructions = analyzer.effectiveSystemInstructions(knowledge: knowledge)

        #expect(instructions.contains("Base chunk instructions."))
        #expect(instructions.contains("Corpus calibration cues"))
        #expect(instructions.contains("induction"))
        #expect(instructions.contains("breathe"))
        #expect(instructions.contains("when i say relax"))
    }

    @Test func earlyContextTreatsRepeatedWakeAndDropAsFractionation() {
        let hint = ChunkedPhaseAnalyzer.buildPositionHint(pct: 12)
        let candidates = ChunkedPhaseAnalyzer.positionAnchoredPhases(for: 12)

        #expect(hint.contains("not a phase") == false)
        #expect(hint.contains("wake-and-drop"))
        #expect(candidates.contains(.fractionation))
    }

    @Test func therapeuticSourceProfileSuppressesBambiPromptCues() {
        let analyzer = ChunkedPhaseAnalyzer(
            config: AnalyzerConfig.ChunkedAnalyzer(
                chunkDurationSeconds: 15,
                chunkOverlapSeconds: 5,
                minChunks: 4,
                maxChunks: 12,
                systemInstructions: "Base chunk instructions.",
                fewShotExamples: []
            ),
            corpusLearning: AnalyzerConfig.CorpusLearning(sourceProfile: .therapeutic)
        )
        let knowledge = CorpusPhaseKnowledge(
            keywordWeights: [
                .brainwashing: ["mindlock": 4.0]
            ],
            phraseWeights: [
                .brainwashing: ["mind lock": 4.0]
            ],
            keywordSourcePacks: [
                .brainwashing: ["mindlock": ["bambi"]]
            ],
            phraseSourcePacks: [
                .brainwashing: ["mind lock": ["bambi"]]
            ]
        )

        let instructions = analyzer.effectiveSystemInstructions(knowledge: knowledge)

        #expect(instructions.contains("Base chunk instructions."))
        #expect(instructions.contains("Corpus calibration cues") == false)
        #expect(instructions.contains("mindlock") == false)
        #expect(instructions.contains("mind lock") == false)
    }

    @Test func contextualFewShotExamplesFavorNearbyTransitionLikelyPhases() {
        let knowledge = CorpusPhaseKnowledge(
            keywordWeights: [:],
            phaseTokens: [:],
            phraseWeights: [:],
            transitionPriors: [
                .brainwashing: [
                    .conditioning: 0.92,
                    .emergence: 0.08
                ]
            ],
            fewShotExamples: [
                .init(
                    text: "welcome and get comfortable as we begin",
                    position: 0.04,
                    correctPhase: HypnosisMetadata.Phase.preTalk.rawValue
                ),
                .init(
                    text: "obey the pattern and let the programming settle in deeper",
                    position: 0.72,
                    correctPhase: HypnosisMetadata.Phase.brainwashing.rawValue
                ),
                .init(
                    text: "whenever i say the trigger you return to this feeling instantly",
                    position: 0.84,
                    correctPhase: HypnosisMetadata.Phase.conditioning.rawValue
                ),
                .init(
                    text: "counting up now becoming alert and awake",
                    position: 0.94,
                    correctPhase: HypnosisMetadata.Phase.emergence.rawValue
                )
            ]
        )

        let examples = ChunkedPhaseAnalyzer.contextualFewShotExamples(
            positionPct: 82,
            previousPhase: .brainwashing,
            knowledge: knowledge,
            baseExamples: knowledge.fewShotExamples
        )

        #expect(!examples.isEmpty)
        #expect(examples.first?.correctPhase == HypnosisMetadata.Phase.conditioning.rawValue)
        #expect(examples.contains { $0.correctPhase == HypnosisMetadata.Phase.brainwashing.rawValue })
        #expect(!examples.prefix(2).contains { $0.correctPhase == HypnosisMetadata.Phase.preTalk.rawValue })
    }

    @Test func contextualFewShotPromptStaysInsideACompactBudget() {
        let examples = (0..<6).map { index in
            AnalyzerConfig.ChunkedAnalyzer.FewShotExample(
                text: String(repeating: "calibration-word-\(index) ", count: 80),
                position: Double(index) / 6.0,
                correctPhase: HypnosisMetadata.Phase.suggestions.rawValue
            )
        }
        let knowledge = CorpusPhaseKnowledge(fewShotExamples: examples)
        let selected = ChunkedPhaseAnalyzer.contextualFewShotExamples(
            positionPct: 50,
            previousPhase: .deepening,
            knowledge: knowledge,
            baseExamples: examples
        )
        let rendered = ChunkedPhaseAnalyzer.renderFewShotExamples(selected)

        #expect(selected.count <= 2)
        #expect(rendered.count <= 800)
    }
}

// MARK: - Chunked Structured Output Tests

struct ChunkedStructuredOutputTests {

    @Test func typedLabelsNormalizeToRuntimePhaseTaxonomy() {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        #expect(ChunkPhaseLabel.preTalk.normalizedPhase == .induction)
        #expect(ChunkPhaseLabel.induction.normalizedPhase == .induction)
        #expect(ChunkPhaseLabel.fractionation.normalizedPhase == .fractionation)
        #expect(ChunkPhaseLabel.deepening.normalizedPhase == .deepening)
        #expect(ChunkPhaseLabel.therapy.normalizedPhase == .suggestions)
        #expect(ChunkPhaseLabel.suggestions.normalizedPhase == .suggestions)
        #expect(ChunkPhaseLabel.eroticSuggestions.normalizedPhase == .suggestions)
        #expect(ChunkPhaseLabel.postHypnoticConditioning.normalizedPhase == .conditioning)
        #expect(ChunkPhaseLabel.brainwashing.normalizedPhase == .brainwashing)
        #expect(ChunkPhaseLabel.emergence.normalizedPhase == .emergence)
    }

    @Test func defaultPromptUsesSevenRecurrentLightPhases() {
        let instructions = AnalyzerConfigLoader.load().chunkedAnalyzer.systemInstructions

        #expect(instructions.contains("Phases ALWAYS occur in this strict order") == false)
        #expect(instructions.contains("fractionation"))
        #expect(instructions.contains("post_hypnotic_conditioning"))
        #expect(instructions.contains("induction, fractionation, deepening, suggestions, brainwashing, post_hypnotic_conditioning, emergence"))
    }

    @Test func structuredClassificationUsesNormalizedPhase() {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let classification = ChunkPhaseClassification(
            phase: .postHypnoticConditioning,
            confidence: .high,
            rationale: "trigger installation and future pacing"
        )

        #expect(classification.normalizedPhase == .conditioning)
    }
}

// MARK: - Human-gold corpus regressions

private nonisolated func phaseSuggestionCorpusRoot() -> URL? {
    let environment = ProcessInfo.processInfo.environment
    let path = environment["LUMESYNC_CORPUS"] ?? environment["TEST_RUNNER_LUMESYNC_CORPUS"]
    return path.map { URL(filePath: $0) }
}

struct PhaseSuggestionCorpusRegressionTests {
    @Test(
        "Shipping pipeline keeps reviewed granularity without private corpus access",
        .enabled(if: phaseSuggestionCorpusRoot() != nil)
    )
    func shippingPipelineKeepsReviewedGranularityWithoutPrivateCorpusAccess() async throws {
        let root = try #require(phaseSuggestionCorpusRoot())
        let dataset = try AnalyzerOptimizationDataset.load(from: root)
        let example = try #require(
            dataset.examples.first { $0.originalFilename == "Against Your Will 01.mp3" }
        )
        let transcription = try await AnalyzerTranscriptCache(
            cacheDirectory: dataset.transcriptCacheDirectory
        ).transcription(for: example)
        let shippingKnowledge = try #require(CorpusPhaseKnowledgeSnapshot.loadDefault())
        let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: shippingKnowledge)
        let phases = analyzer.analyzeTranscription(transcription)
        let suggestion = analyzer.suggestPhaseTimeline(for: transcription).segments
        let summary = phases.map {
            "\($0.phase.displayName) \(Int($0.startTime))–\(Int($0.endTime))"
        }.joined(separator: "\n")
        let suggestionSummary = suggestion.map {
            "\($0.phase.displayName) \(Int($0.startTime))–\(Int($0.endTime))"
        }.joined(separator: "\n")
        Attachment.record(
            "SHIPPING PIPELINE\n\(summary)\n\nPHRASE PROPOSAL\n\(suggestionSummary)",
            named: "shipping-against-your-will.txt"
        )

        #expect(phases.first?.phase == .induction)
        #expect(phases.last?.phase == .emergence)
        #expect(phases.contains { $0.phase == .fractionation } == false)
        #expect(
            phases.count >= example.phaseSegments.count - 2
                && phases.count <= example.phaseSegments.count + 2,
            "The in-app analyzer should preserve the reviewed section granularity without access to a developer corpus."
        )
        if let firstSuggestionIndex = phases.firstIndex(where: { $0.phase == .suggestions }) {
            #expect(
                phases.dropFirst(firstSuggestionIndex + 1).contains { $0.phase == .deepening },
                "The in-app analyzer should preserve sustained returns from suggestions to deepening."
            )
        }
    }

    @Test(
        "Whole-file awakener pass recovers human fractionation files",
        .enabled(if: phaseSuggestionCorpusRoot() != nil)
    )
    func wholeFileAwakenerPassRecoversFractionation() async throws {
        let root = try #require(phaseSuggestionCorpusRoot())
        let dataset = try AnalyzerOptimizationDataset.load(from: root)
        let examples = dataset.examples.filter { example in
            example.example.labelTrust.isTrustedForLearning
                && example.phaseSegments.contains { $0.phase == .fractionation }
        }
        try #require(!examples.isEmpty)
        let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)
        let cache = AnalyzerTranscriptCache(cacheDirectory: dataset.transcriptCacheDirectory)
        var misses: [String] = []

        for example in examples {
            let transcription = try await cache.transcription(for: example)
            let ordinaryTimeline = example.phaseSegments.map { segment in
                let phase: HypnosisMetadata.Phase = segment.phase == .fractionation
                    ? .deepening
                    : segment.phase
                return PhaseSegment(
                    id: segment.id,
                    phase: phase,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    characteristics: phase.displayName,
                    tranceDepthEstimate: phase.tranceDepthEstimate
                )
            }
            let recovered = analyzer.applyFractionationSecondPass(
                in: ordinaryTimeline,
                transcription: transcription
            )
            if recovered.contains(where: { $0.phase == .fractionation }) == false {
                misses.append(example.originalFilename)
            }
        }

        #expect(misses.isEmpty, "Missed fractionation in: \(misses.joined(separator: ", "))")
    }

    @Test(
        "Explanatory opening stays induction in Against Your Will",
        .enabled(if: phaseSuggestionCorpusRoot() != nil)
    )
    func explanatoryOpeningStaysInduction() async throws {
        let root = try #require(phaseSuggestionCorpusRoot())
        let dataset = try AnalyzerOptimizationDataset.load(from: root)
        let example = try #require(
            dataset.examples.first { $0.originalFilename == "Against Your Will 01.mp3" }
        )
        let transcription = try await AnalyzerTranscriptCache(
            cacheDirectory: dataset.transcriptCacheDirectory
        ).transcription(for: example)
        let knowledge = CorpusPhaseKnowledgeBuilder(
            dataset: dataset,
            scriptCorpus: ScriptPhaseCorpus.loadDefault()
        ).build()

        let suggestion = HypnosisPhaseAnalyzer(corpusKnowledge: knowledge)
            .suggestPhaseTimeline(for: transcription)
        let openingCutoff = transcription.duration * 0.12
        let openingSegments = suggestion.segments.filter { $0.startTime < openingCutoff - 0.001 }
        let segmentSummary = suggestion.segments.map {
            "\($0.phase.displayName) \(Int($0.startTime))–\(Int($0.endTime))"
        }.joined(separator: "\n")
        let windowSummary = suggestion.windows.map { window in
            let scores = window.evidence.prefix(3).map { evidence in
                let parts = [
                    "total=\(String(format: "%.2f", evidence.totalScore))",
                    "text=\(String(format: "%.2f", evidence.transcriptScore))",
                    "phrase=\(String(format: "%.2f", evidence.phraseLibraryScore))",
                    "marker=\(String(format: "%.2f", evidence.waymarkerScore))",
                    "position=\(String(format: "%.2f", evidence.positionScore))",
                    "transition=\(String(format: "%.2f", evidence.transitionScore))"
                ].joined(separator: ",")
                return "\(evidence.phase.displayName){\(parts)}"
            }.joined(separator: " | ")
            return "\(Int(window.startTime))–\(Int(window.endTime)) \(window.phase.displayName) \(String(format: "%.0f%%", window.confidence * 100)) :: \(scores)"
        }.joined(separator: "\n")
        Attachment.record(
            "SEGMENTS\n\(segmentSummary)\n\nWINDOWS\n\(windowSummary)",
            named: "against-your-will-suggestions.txt"
        )

        #expect(!openingSegments.isEmpty)
        #expect(
            openingSegments.allSatisfy { $0.phase == .induction },
            "The explanatory opening should not be classified as an active downstream phase."
        )
        #expect(
            suggestion.segments.count >= example.phaseSegments.count - 2
                && suggestion.segments.count <= example.phaseSegments.count + 2,
            "The proposal should stay near the human section granularity instead of over- or under-segmenting."
        )
        #expect(suggestion.segments.last?.phase == .emergence)
        #expect(
            suggestion.segments.contains { $0.phase == .fractionation } == false,
            "A single contrast such as 'aware, but unaware' is not repeated fractionation."
        )
        #expect(
            (suggestion.segments.last?.startTime ?? 0) >= transcription.duration * 0.92,
            "A terminal emergence should not begin on an earlier countdown into hypnosis."
        )
        if let firstSuggestionIndex = suggestion.segments.firstIndex(where: { $0.phase == .suggestions }) {
            #expect(
                suggestion.segments.dropFirst(firstSuggestionIndex + 1).contains { $0.phase == .deepening },
                "Sustained returns from suggestions to deepening must remain available."
            )
        }
    }
}
