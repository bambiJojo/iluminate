//
//  AnalysisProgressViewModelTests.swift
//  IlumionateTests
//
//  Tests for AnalysisProgressViewModel stage transitions and error handling.
//

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct AnalysisProgressViewModelTests {

    /// Helper to create a ViewModel backed by mock services.
    private func makeViewModel(
        transcriber: MockAudioTranscriber,
        analyzer: MockContentAnalyzer,
        generator: MockSessionGenerator
    ) -> AnalysisProgressViewModel {
        let pipeline = AnalysisPipeline(
            transcriber: transcriber,
            analyzer: analyzer,
            generator: generator
        )
        return AnalysisProgressViewModel(pipeline: pipeline)
    }

    // MARK: - Happy Path

    @Test func startAnalysis_completesSuccessfully() async {
        let viewModel = makeViewModel(
            transcriber: MockAudioTranscriber(),
            analyzer: MockContentAnalyzer(),
            generator: MockSessionGenerator()
        )

        await viewModel.startAnalysis(for: AnalysisFixtures.audioFile())

        #expect(viewModel.stage == .complete)
        #expect(viewModel.overallProgress == 1.0)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.analysisResult != nil)
        #expect(viewModel.transcriptionResult != nil)
    }

    // MARK: - Error Handling

    @Test func startAnalysis_transcriptionError_setsFailedStage() async {
        let transcriber = MockAudioTranscriber()
        transcriber.resultToReturn = .failure(AnalyzerError.noAudioData)
        let viewModel = makeViewModel(
            transcriber: transcriber,
            analyzer: MockContentAnalyzer(),
            generator: MockSessionGenerator()
        )

        await viewModel.startAnalysis(for: AnalysisFixtures.audioFile())

        #expect(viewModel.stage == .failed)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.analysisResult == nil)
    }

    @Test func startAnalysis_aiUnavailable_setsFailedStage() async {
        let analyzer = MockContentAnalyzer()
        analyzer.isModelAvailable = false
        let viewModel = makeViewModel(
            transcriber: MockAudioTranscriber(),
            analyzer: analyzer,
            generator: MockSessionGenerator()
        )

        await viewModel.startAnalysis(for: AnalysisFixtures.audioFile())

        #expect(viewModel.stage == .failed)
        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - State Resets

    @Test func startAnalysis_clearsStaleStateBeforeRun() async {
        let viewModel = makeViewModel(
            transcriber: MockAudioTranscriber(),
            analyzer: MockContentAnalyzer(),
            generator: MockSessionGenerator()
        )

        // Simulate stale state from a previous run
        await viewModel.startAnalysis(for: AnalysisFixtures.audioFile())
        #expect(viewModel.stage == .complete)

        // Second run should start fresh
        let failTranscriber = MockAudioTranscriber()
        failTranscriber.resultToReturn = .failure(AnalyzerError.noAudioData)
        let viewModel2 = makeViewModel(
            transcriber: failTranscriber,
            analyzer: MockContentAnalyzer(),
            generator: MockSessionGenerator()
        )
        await viewModel2.startAnalysis(for: AnalysisFixtures.audioFile())
        #expect(viewModel2.stage == .failed)
        #expect(viewModel2.analysisResult == nil)
    }

    // MARK: - Cancel

    @Test func cancel_resetsProgressToZero() async {
        let viewModel = makeViewModel(
            transcriber: MockAudioTranscriber(),
            analyzer: MockContentAnalyzer(),
            generator: MockSessionGenerator()
        )

        await viewModel.cancel()

        #expect(viewModel.stage == .starting)
        #expect(viewModel.overallProgress == 0.0)
    }
}
