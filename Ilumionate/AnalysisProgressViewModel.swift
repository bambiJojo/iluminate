//
//  AnalysisProgressViewModel.swift
//  Ilumionate
//
//  Drives AnalysisProgressView state via the injected AnalysisPipeline.
//  All logic that was previously embedded in the view now lives here,
//  making it testable without a running UI.
//

import Foundation
import Observation

/// View model for AnalysisProgressView.
///
/// Inject an `AnalysisPipeline` for testing; call with default arguments
/// in production to use `AnalysisPipeline.live()`.
@MainActor @Observable
final class AnalysisProgressViewModel {

    // MARK: - Observable State

    var stage: AnalysisStage = .starting
    var overallProgress: Double = 0.0
    var currentStageProgress: Double = 0.0
    var statusMessage: String = ""
    var transcriptionResult: AudioTranscriptionResult?
    var analysisResult: AnalysisResult?
    var errorMessage: String?

    // MARK: - Services

    private let pipeline: AnalysisPipeline

    // MARK: - Init

    /// Production init — uses the live ML implementations.
    init() {
        pipeline = AnalysisPipeline.live()
    }

    /// Testable init — inject a pre-configured pipeline.
    init(pipeline: AnalysisPipeline) {
        self.pipeline = pipeline
    }

    // MARK: - Analysis

    /// Runs the full pipeline and updates state on each stage transition.
    func startAnalysis(for audioFile: AudioFile) async {
        stage = .starting
        overallProgress = 0.0
        currentStageProgress = 0.0
        errorMessage = nil
        transcriptionResult = nil
        analysisResult = nil

        do {
            let result = try await pipeline.run(audioFile: audioFile) { [weak self] progress in
                guard let self else { return }
                stage = progress.stage
                overallProgress = progress.fraction
                statusMessage = progress.message
                // Reset per-stage progress on stage change
                currentStageProgress = progress.fraction
            }

            transcriptionResult = result.transcription
            analysisResult = result.analysis
            stage = .complete
            overallProgress = 1.0
            currentStageProgress = 1.0
            statusMessage = "Complete"

        } catch {
            stage = .failed
            errorMessage = error.localizedDescription
        }
    }

    /// Cancels any in-flight analysis and resets progress.
    func cancel() async {
        await pipeline.cancel()
        stage = .starting
        overallProgress = 0.0
        currentStageProgress = 0.0
    }
}
