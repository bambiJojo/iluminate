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
                makeSegment(text: "welcome and get comfortable as you settle in", start: 0, duration: 18),
                makeSegment(text: "now begin to relax and close your eyes", start: 18, duration: 18),
                makeSegment(text: "with every breath you can go deeper and deeper", start: 36, duration: 20),
                makeSegment(text: "when i snap my fingers this response returns instantly", start: 56, duration: 20),
                makeSegment(text: "and as i count to five you become wide awake", start: 76, duration: 20)
            ],
            duration: 96,
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
                makeSegment(text: "welcome and get comfortable", start: 0, duration: 16),
                makeSegment(text: "now begin to relax and close your eyes", start: 16, duration: 16),
                makeSegment(text: "deeper and deeper with every breath", start: 32, duration: 16),
                makeSegment(text: "from now on these suggestions settle in", start: 48, duration: 16),
                makeSegment(text: "when i snap my fingers this trigger activates", start: 64, duration: 16),
                makeSegment(text: "and now wide awake and back in the room", start: 80, duration: 16)
            ],
            duration: 96,
            detectedLanguage: "en"
        )

        let adapted = analyzer.adaptPredictedPhases(
            [
                PhaseSegment(
                    phase: .therapy,
                    startTime: 0,
                    endTime: 96,
                    characteristics: "Therapy",
                    tranceDepthEstimate: 0.84
                )
            ],
            transcription: transcription
        )

        let adaptedPhases = adapted.map(\.phase)
        #expect(Set(adaptedPhases).count >= 3)
        #expect(adaptedPhases.contains(.suggestions))
        #expect(adaptedPhases.last == .emergence)
    }

    @Test func techniqueMarkersCanCreateLateConditioningPhaseEvidence() {
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

        #expect(baseline.count == 1)
        #expect(baseline.first?.phase == .induction)
        #expect(techniqueAware.count >= 2)
        #expect(techniqueAware.last?.phase == .suggestions)
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
}

// MARK: - Chunked Structured Output Tests

struct ChunkedStructuredOutputTests {

    @Test func typedLabelsNormalizeToRuntimePhaseTaxonomy() {
        #expect(ChunkPhaseLabel.preTalk.normalizedPhase == .induction)
        #expect(ChunkPhaseLabel.induction.normalizedPhase == .induction)
        #expect(ChunkPhaseLabel.deepening.normalizedPhase == .deepening)
        #expect(ChunkPhaseLabel.therapy.normalizedPhase == .suggestions)
        #expect(ChunkPhaseLabel.suggestions.normalizedPhase == .suggestions)
        #expect(ChunkPhaseLabel.eroticSuggestions.normalizedPhase == .suggestions)
        #expect(ChunkPhaseLabel.postHypnoticConditioning.normalizedPhase == .suggestions)
        #expect(ChunkPhaseLabel.brainwashing.normalizedPhase == .brainwashing)
        #expect(ChunkPhaseLabel.emergence.normalizedPhase == .emergence)
    }

    @Test func structuredClassificationUsesNormalizedPhase() {
        let classification = ChunkPhaseClassification(
            phase: .postHypnoticConditioning,
            confidence: .high,
            rationale: "trigger installation and future pacing"
        )

        #expect(classification.normalizedPhase == .suggestions)
    }
}
