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
