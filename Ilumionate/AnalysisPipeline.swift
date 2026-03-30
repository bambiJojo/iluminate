//
//  AnalysisPipeline.swift
//  Ilumionate
//
//  Orchestrates the three-stage audio-analysis pipeline:
//    1. Transcription  (AudioTranscribingService)
//    2. AI Analysis    (ContentAnalyzingService)
//    3. Session Gen    (SessionGeneratingService)
//
//  Designed for dependency injection: call AnalysisPipeline.live() in
//  production, or inject mocks for unit testing.
//

import Foundation

/// Coordinates the audio-analysis pipeline end-to-end.
///
/// Services are injected via the initializer, which makes the pipeline
/// fully testable without real ML calls.
@MainActor
final class AnalysisPipeline {

    // MARK: - Services (internal so the view model can read progress)

    let transcriber: any AudioTranscribingService
    let analyzer: any ContentAnalyzingService
    let generator: any SessionGeneratingService

    // MARK: - Init

    init(
        transcriber: any AudioTranscribingService,
        analyzer: any ContentAnalyzingService,
        generator: any SessionGeneratingService
    ) {
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.generator = generator
    }

    /// Creates a pipeline wired to the live, ML-backed implementations.
    static func live() -> AnalysisPipeline {
        AnalysisPipeline(
            transcriber: AudioAnalyzer(),
            analyzer: AIContentAnalyzer(),
            generator: SessionGenerator()
        )
    }

    // MARK: - Run

    /// Executes all three stages and returns the combined result.
    ///
    /// - Parameters:
    ///   - audioFile: The audio file to analyse.
    ///   - onProgress: Optional closure called at each pipeline milestone.
    func run(
        audioFile: AudioFile,
        onProgress: (AnalysisPipelineProgress) -> Void = { _ in }
    ) async throws -> AnalysisPipelineResult {

        onProgress(.init(stage: .starting, fraction: 0.0, message: "Starting…"))

        // Stage 1 — Transcription
        onProgress(.init(stage: .transcribing, fraction: 0.0, message: "Transcribing audio…"))
        let transcription = try await transcriber.transcribe(audioFile: audioFile)

        // Stage 2 — AI Analysis
        onProgress(.init(stage: .analyzing, fraction: 0.4, message: "Analysing content…"))
        let analysis = try await analyzer.analyzeContent(
            transcription: transcription,
            audioFile: audioFile
        )

        // Stage 3 — Session generation
        onProgress(.init(stage: .generatingSession, fraction: 0.8, message: "Generating light session…"))
        let session = generator.generateSession(from: audioFile, analysis: analysis, config: .default)

        onProgress(.init(stage: .complete, fraction: 1.0, message: "Complete"))
        return AnalysisPipelineResult(
            transcription: transcription,
            analysis: analysis,
            session: session
        )
    }

    // MARK: - Cancel

    /// Cancels any in-flight transcription.
    func cancel() async {
        await transcriber.cancelTranscription()
    }
}
