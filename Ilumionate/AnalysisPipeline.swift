//
//  AnalysisPipeline.swift
//  Ilumionate
//
//  Orchestrates the audio-analysis pipeline:
//    1. Transcription     (AudioTranscribingService)
//    2. Prosody + AI      (ProsodyAnalyzingService + ContentAnalyzingService) — parallel
//    3. Technique Detection (TechniqueDetector)
//    4. Session Generation (SessionGeneratingService)
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
    let prosodyAnalyzer: any ProsodyAnalyzingService
    let generator: any SessionGeneratingService
    private let analyzerConfig: AnalyzerConfig
    private var prosodyTask: Task<ProsodicProfile?, Never>?

    // MARK: - Init

    init(
        transcriber: any AudioTranscribingService,
        analyzer: any ContentAnalyzingService,
        prosodyAnalyzer: any ProsodyAnalyzingService = ProsodyAnalyzer(),
        generator: any SessionGeneratingService,
        analyzerConfig: AnalyzerConfig? = nil
    ) {
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.prosodyAnalyzer = prosodyAnalyzer
        self.generator = generator
        self.analyzerConfig = analyzerConfig ?? AnalyzerConfigLoader.load()
    }

    /// Creates a pipeline wired to the live, ML-backed implementations.
    static func live() -> AnalysisPipeline {
        let config = AnalyzerConfigLoader.load()
        return AnalysisPipeline(
            transcriber: AudioAnalyzer(),
            analyzer: AIContentAnalyzer(),
            prosodyAnalyzer: ProsodyAnalyzer(),
            generator: SessionGenerator(config: config.sessionGeneration),
            analyzerConfig: config
        )
    }

    // MARK: - Run

    /// Executes all pipeline stages and returns the combined result.
    ///
    /// After transcription, prosody extraction and AI analysis run in
    /// parallel. Prosody is fast (no ML) so it typically finishes first.
    /// The prosodic profile is merged into the analysis result before
    /// session generation.
    func run(
        audioFile: AudioFile,
        onProgress: (AnalysisPipelineProgress) -> Void = { _ in }
    ) async throws -> AnalysisPipelineResult {

        onProgress(.init(stage: .starting, fraction: 0.0, message: "Starting…"))

        // Stage 1 — Transcription
        onProgress(.init(stage: .transcribing, fraction: 0.0, message: "Transcribing audio…"))
        let transcription = try await transcriber.transcribe(audioFile: audioFile)

        // Stage 2 — Prosody extraction + AI analysis (parallel)
        onProgress(.init(stage: .analyzing, fraction: 0.4, message: "Analysing content…"))
        let enrichedAnalysis = try await runParallelAnalysis(
            transcription: transcription,
            audioFile: audioFile
        )

        // Stage 3 — Session generation
        onProgress(.init(stage: .generatingSession, fraction: 0.8, message: "Generating light session…"))
        let generationConfig = AnalysisPreferences.shared.generationConfig
        let session = generator.generateSession(
            from: audioFile,
            analysis: enrichedAnalysis,
            config: generationConfig
        )

        onProgress(.init(stage: .complete, fraction: 1.0, message: "Complete"))
        return AnalysisPipelineResult(
            transcription: transcription,
            analysis: enrichedAnalysis,
            session: session
        )
    }

    // MARK: - Cancel

    /// Cancels every in-flight pipeline stage.
    func cancel() async {
        prosodyTask?.cancel()
        prosodyTask = nil
        await transcriber.cancelTranscription()
        await analyzer.cancelAnalysis()
    }

    // MARK: - Private

    /// Runs prosody extraction and AI analysis in parallel, then merges results.
    private func runParallelAnalysis(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile
    ) async throws -> AnalysisResult {
        let enricher = AudioAnalysisEnricher(
            prosodyAnalyzer: prosodyAnalyzer,
            analyzerConfig: analyzerConfig
        )

        // Run prosody on a background thread — errors are non-fatal
        // (the session still generates from text-only analysis).
        let prosodyHandle = Task {
            await enricher.extractProsody(audioFile: audioFile, transcription: transcription)
        }

        // Store handle immediately so cancel() can reach it
        prosodyTask = prosodyHandle

        // AI analysis stays on MainActor
        let analysis = try await analyzer.analyzeContent(
            transcription: transcription,
            audioFile: audioFile
        )

        let prosody = await prosodyHandle.value
        prosodyTask = nil

        return enricher.enrich(
            analysis,
            transcription: transcription,
            audioFile: audioFile,
            prosody: prosody
        )
    }
}
