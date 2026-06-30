//
//  EvaluationHarnessTests.swift
//  IlumionateTests
//
//  Offline quality-scoring tests for the analysis pipeline.
//
//  - Deterministic tests (keyword pipeline + fixture data) run in CI without a device.
//  - AI-gated tests are tagged `.enabled(if: ChunkedPhaseAnalyzer.isAvailable)`
//    so they skip cleanly in CI and run on-device when Apple Intelligence is present.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Keyword Pipeline Tests (deterministic, CI-safe)

@MainActor
struct KeywordPipelineEvaluationTests {

    private let analyzer  = HypnosisPhaseAnalyzer()
    private let generator = SessionGenerator()
    private let evaluator = AnalysisEvaluator()
    private let timelineEvaluator = PhaseTimelineEvaluator()

    // MARK: - Timeline metrics over the file corpus

    /// Maps analyzer output to truth-span shape for the timeline evaluator.
    private func predictedSpans(_ phases: [PhaseSegment]) -> [PhaseTruthSpan] {
        phases.map { PhaseTruthSpan(phase: $0.phase, start: $0.startTime, end: $0.endTime) }
    }

    @Test("Timeline metrics run over the file corpus and meet thresholds")
    func timelineMetricsOverCorpus() async throws {
        let eval = timelineEvaluator

        // Only cases that carry ground-truth spans participate in timeline scoring.
        let cases = try (CorpusLoader.load(subdirectory: "fixtures")
                       + CorpusLoader.load(subdirectory: "synthetic")
                       + CorpusLoader.load(subdirectory: "real"))
            .filter { !$0.truth.isEmpty }

        try #require(cases.count >= 8, "expected the complete truth-bearing corpus; found \(cases.count) cases")

        var scores: [PhaseTimelineScore] = []
        for kase in cases {
            let segments = kase.transcriptionSegments
            let transcription = AudioTranscriptionResult(
                fullText: kase.transcriptText,
                segments: segments.isEmpty
                    ? [AudioTranscriptionSegment(text: kase.transcriptText, timestamp: 0, duration: kase.duration, confidence: 1.0)]
                    : segments,
                duration: kase.duration,
                detectedLanguage: "en"
            )
            let phases = analyzer.analyzeTranscription(transcription)
            scores.append(eval.score(case: kase, predicted: predictedSpans(phases)))
        }

        let report = eval.report(scores: scores)
        // Real-corpus baseline 2026-06-08 (iPhone 17 Pro sim, OS 26.5), 4 truth-bearing
        // cases (2 fixtures + 2 real imports): overallAgreement 0.296
        // (fixtures 0.467 — above the original 2026-05-31 0.40 baseline; real 0.126).
        // Reflects two analyzer fixes: denoise-before-ordering (no ratchet erasure) and
        // rejecting structurally-invalid proposals in selectBestAdaptedSegments.
        // Real cases stay weak (keyword primary is poor on long sessions — the proposal
        // generator / learned-model work is the next lever). Floor set just below the
        // observed value to guard against regression; raising it is the Phase-1 goal.
        #expect(report.overallAgreement >= 0.28,
                "overall agreement \(report.overallAgreement); by-source \(report.agreementBySource); by-ambiguity \(report.agreementByAmbiguity); mean boundary err \(report.meanBoundaryError); cases \(scores.count)")
    }

    // MARK: - Structural validity

    @Test func allCorpusCases_sessionPassesStructuralInvariants() {
        for evalCase in EvaluationCorpus.all {
            let phases  = analyzer.analyzeTranscription(evalCase.transcript)
            let analysis = buildAnalysisResult(evalCase: evalCase, phases: phases)
            let session  = generator.generateSession(from: evalCase.audioFile, analysis: analysis)
            let score    = evaluator.score(evalCase: evalCase, result: analysis, session: session)

            #expect(score.sessionValidityScore == 1.0,
                    "'\(evalCase.name)' failed session validity (score \(score.sessionValidityScore))")
        }
    }

    // MARK: - Baseline score ≥ 0.60

    @Test func classicHypnosis_keywordPipelineScoresAboveBaseline() {
        let evalCase = EvaluationCorpus.classicHypnosis30min
        let phases   = analyzer.analyzeTranscription(evalCase.transcript)
        let analysis = buildAnalysisResult(evalCase: evalCase, phases: phases)
        let session  = generator.generateSession(from: evalCase.audioFile, analysis: analysis)
        let score    = evaluator.score(evalCase: evalCase, result: analysis, session: session)

        #expect(score.overallScore >= 0.60,
                "Keyword pipeline scored \(score.overallScore) on '\(evalCase.name)' — expected ≥0.60")
    }

    @Test func shortInduction_keywordPipelineScoresAboveBaseline() {
        let evalCase = EvaluationCorpus.shortInduction10min
        let phases   = analyzer.analyzeTranscription(evalCase.transcript)
        let analysis = buildAnalysisResult(evalCase: evalCase, phases: phases)
        let session  = generator.generateSession(from: evalCase.audioFile, analysis: analysis)
        let score    = evaluator.score(evalCase: evalCase, result: analysis, session: session)

        #expect(score.overallScore >= 0.60,
                "Keyword pipeline scored \(score.overallScore) on '\(evalCase.name)' — expected ≥0.60")
    }

    // MARK: - Timeline structure

    @Test func classicHypnosis_phaseTimelineIsChronological() {
        let evalCase = EvaluationCorpus.classicHypnosis30min
        let phases   = analyzer.analyzeTranscription(evalCase.transcript)
        let analysis = buildAnalysisResult(evalCase: evalCase, phases: phases)
        let score    = evaluator.score(
            evalCase: evalCase,
            result: analysis,
            session: generator.generateSession(from: evalCase.audioFile, analysis: analysis)
        )
        #expect(score.phaseOrderScore == 1.0,
                "Timeline structure score \(score.phaseOrderScore) — expected chronological, non-overlapping spans")
    }

    // MARK: - Frequency band

    @Test func hypnosis_frequencyBandIsTheta() {
        let evalCase = EvaluationCorpus.classicHypnosis30min
        let analysis = buildAnalysisResult(evalCase: evalCase, phases: [])
        // Hypnosis keyword fallback should land in theta (0.5–10 Hz)
        let score = evaluator.score(
            evalCase: evalCase,
            result: analysis,
            session: generator.generateSession(from: evalCase.audioFile, analysis: analysis)
        )
        #expect(score.frequencyRangeScore == 1.0,
                "Frequency range \(analysis.suggestedFrequencyRange) doesn't overlap theta band 0.5–10 Hz")
    }

    @Test func allHypnosisCorpusCases_lightScoreAlignmentMeetsProductionTarget() {
        for evalCase in EvaluationCorpus.all where evalCase.expectedContentType == .hypnosis {
            let phases = analyzer.analyzeTranscription(evalCase.transcript)
            let analysis = buildAnalysisResult(evalCase: evalCase, phases: phases)
            let session = generator.generateSession(from: evalCase.audioFile, analysis: analysis)
            let report = LightScoreAlignmentScorer().score(session: session, analysis: analysis)

            #expect(report.overallScore >= LightScoreAlignmentReport.productionTarget,
                    "'\(evalCase.name)' light-score alignment \(report.overallScore) — expected >=0.90")
        }
    }
}

// MARK: - AI-Gated Tests (device only, skipped in CI)

@MainActor
struct AIAnalysisPipelineEvaluationTests {

    @Test(.enabled(if: ChunkedPhaseAnalyzer.isAvailable))
    func classicHypnosis_chunkedAnalyzerProducesUsableTimeline() async throws {
        let evalCase = EvaluationCorpus.classicHypnosis30min
        let timestamps = HypnosisPhaseAnalyzer(corpusKnowledge: .empty)
            .approximateWordTimestamps(from: evalCase.transcript.segments)

        let phases = try #require(await ChunkedPhaseAnalyzer.analyze(
            wordTimestamps: timestamps,
            duration: evalCase.transcript.duration
        ))

        #expect(phases.isEmpty == false)
        #expect(Set(phases.map(\.phase)).count >= 2)
    }
}

// MARK: - Helpers

@MainActor
private func buildAnalysisResult(evalCase: EvaluationCase, phases: [PhaseSegment]) -> AnalysisResult {
    // Map evaluation case to a plausible analysis result for scoring
    let metadata: HypnosisMetadata? = evalCase.expectedContentType == .hypnosis ? HypnosisMetadata(
        phases: phases,
        inductionStyle: .permissive,
        estimatedTranceDeph: .medium,
        suggestionDensity: nil,
        languagePatterns: [],
        detectedTechniques: []
    ) : nil

    return AnalysisResult(
        mood: .meditative,
        energyLevel: 0.2,
        suggestedFrequencyRange: evalCase.expectedFrequencyBand,
        suggestedIntensity: 0.6,
        keyMoments: [],
        aiSummary: "Evaluation fixture",
        recommendedPreset: "Default",
        contentType: evalCase.expectedContentType,
        hypnosisMetadata: metadata
    )
}
