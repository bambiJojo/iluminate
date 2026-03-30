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

    private let transcriber: any AudioTranscribingService
    private let analyzer: any ContentAnalyzingService
    private let generator: any SessionGeneratingService

    // MARK: - Init

    /// Production init — uses the live ML implementations.
    init() {
        transcriber = AudioAnalyzer()
        analyzer    = AIContentAnalyzer()
        generator   = SessionGenerator()
    }

    /// Testable init — inject mock services.
    init(
        transcriber: any AudioTranscribingService,
        analyzer:    any ContentAnalyzingService,
        generator:   any SessionGeneratingService
    ) {
        self.transcriber = transcriber
        self.analyzer    = analyzer
        self.generator   = generator
    }

    // MARK: - Analysis

    /// Runs the full pipeline and updates state on each stage transition.
    func startAnalysis(for audioFile: AudioFile) async {
        stage         = .starting
        overallProgress      = 0.0
        currentStageProgress = 0.0
        errorMessage  = nil
        transcriptionResult  = nil
        analysisResult       = nil

        do {
            // Stage 1 — Transcription
            stage         = .transcribing
            statusMessage = "Transcribing audio…"
            transcriptionResult = try await transcriber.transcribe(audioFile: audioFile)
            overallProgress      = 0.4
            currentStageProgress = 1.0

            // Stage 2 — AI Analysis
            stage         = .analyzing
            statusMessage = "Analysing content…"
            let analysis = try await analyzer.analyzeContent(
                transcription: transcriptionResult!,
                audioFile: audioFile
            )
            analysisResult       = analysis
            overallProgress      = 0.8
            currentStageProgress = 1.0

            // Stage 3 — Session generation (synchronous)
            stage         = .generatingSession
            statusMessage = "Generating light session…"
            _ = generator.generateSession(from: audioFile, analysis: analysis, config: .default)

            stage         = .complete
            overallProgress      = 1.0
            currentStageProgress = 1.0
            statusMessage = "Complete"

        } catch {
            stage        = .failed
            errorMessage = error.localizedDescription
        }
    }

    /// Cancels any in-flight transcription and resets progress.
    func cancel() async {
        await transcriber.cancelTranscription()
        stage         = .starting
        overallProgress      = 0.0
        currentStageProgress = 0.0
    }
}
