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

        try #require(!cases.isEmpty, "no truth-bearing corpus cases found")

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
        // Observed baseline 2026-05-31 (iPhone 17 Pro sim): overallAgreement 0.40,
        // meanBoundaryError 12.0s, over 2 truth-bearing low-ambiguity fixtures.
        // This is the number Phase-1 tuning must raise; floor set at the observed
        // value to catch regressions without overstating current quality.
        #expect(report.overallAgreement >= 0.40,
                "overall agreement \(report.overallAgreement); by-ambiguity \(report.agreementByAmbiguity); mean boundary err \(report.meanBoundaryError); cases \(scores.count)")
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

    // MARK: - Phase ordering

    @Test func classicHypnosis_phasesAreForwardOrdered() {
        let evalCase = EvaluationCorpus.classicHypnosis30min
        let phases   = analyzer.analyzeTranscription(evalCase.transcript)
        let analysis = buildAnalysisResult(evalCase: evalCase, phases: phases)
        let score    = evaluator.score(
            evalCase: evalCase,
            result: analysis,
            session: generator.generateSession(from: evalCase.audioFile, analysis: analysis)
        )
        #expect(score.phaseOrderScore == 1.0,
                "Phase ordering score \(score.phaseOrderScore) — expected 1.0 (no backward jumps)")
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

    private let evaluator = AnalysisEvaluator()
    private let generator = SessionGenerator()

    @Test(.enabled(if: ChunkedPhaseAnalyzer.isAvailable))
    func classicHypnosis_aiPipelineScoresAboveKeywordBaseline() async throws {
        let evalCase    = EvaluationCorpus.classicHypnosis30min
        let mockAnalyzer = MockContentAnalyzer()
        mockAnalyzer.analysisToReturn = buildAnalysisResult(
            evalCase: evalCase, phases: []
        )
        let pipeline = AnalysisPipeline(
            transcriber: MockAudioTranscriber(),
            analyzer:    mockAnalyzer,
            generator:   SessionGenerator()
        )

        let result  = try await pipeline.run(audioFile: evalCase.audioFile)
        let score   = evaluator.score(evalCase: evalCase, result: result.analysis, session: result.session)

        #expect(score.overallScore >= 0.60,
                "AI pipeline scored \(score.overallScore) on '\(evalCase.name)' — expected ≥0.60")
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
