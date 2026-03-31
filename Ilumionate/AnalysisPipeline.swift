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
        let session = generator.generateSession(
            from: audioFile,
            analysis: enrichedAnalysis,
            config: .default
        )

        onProgress(.init(stage: .complete, fraction: 1.0, message: "Complete"))
        return AnalysisPipelineResult(
            transcription: transcription,
            analysis: enrichedAnalysis,
            session: session
        )
    }

    // MARK: - Cancel

    /// Cancels any in-flight transcription and prosody extraction.
    func cancel() async {
        prosodyTask?.cancel()
        prosodyTask = nil
        await transcriber.cancelTranscription()
    }

    // MARK: - Private

    /// Runs prosody extraction and AI analysis in parallel, then merges results.
    private func runParallelAnalysis(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile
    ) async throws -> AnalysisResult {
        let prosodySvc = prosodyAnalyzer
        let fileURL = audioFile.url
        let segments = transcription.segments

        // Run prosody on a background thread — errors are non-fatal
        // (the session still generates from text-only analysis).
        let prosodyConfig = ProsodyAnalyzer.Config(from: analyzerConfig.prosody)
        let prosodyHandle = Task.detached { [prosodySvc, prosodyConfig] () -> ProsodicProfile? in
            do {
                return try prosodySvc.analyze(
                    url: fileURL,
                    segments: segments,
                    config: prosodyConfig
                )
            } catch {
                print("⚠️ Prosody extraction failed: \(error.localizedDescription)")
                return nil
            }
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

        // Merge prosodic profile into the analysis result
        var enriched = analysis
        enriched.prosodicProfile = prosody

        if let prosody {
            enriched.voiceCharacteristics = buildVoiceCharacteristics(from: prosody)
        }

        // Compute word timestamps once, shared by technique detection
        let wordTimestamps = HypnosisPhaseAnalyzer()
            .approximateWordTimestamps(from: segments)

        let detector = TechniqueDetector(config: analyzerConfig.techniqueDetection)
        enriched.techniqueDetection = detector.detect(
            wordTimestamps: wordTimestamps,
            segments: segments,
            prosodic: prosody,
            duration: prosody?.totalDuration ?? audioFile.duration
        )

        return enriched
    }

    /// Derives `VoiceCharacteristics` from a `ProsodicProfile`.
    private func buildVoiceCharacteristics(
        from prosody: ProsodicProfile
    ) -> VoiceCharacteristics {
        let pauseDurations = prosody.pauses.map(\.duration)

        // Infer tonal qualities from pitch and volume curves
        var tonal: [String] = []
        let avgPitch = prosody.averagePitch
        if avgPitch > 0 && avgPitch < 160 { tonal.append("low-pitched") }
        if avgPitch >= 160 && avgPitch < 220 { tonal.append("mid-range") }
        if avgPitch >= 220 { tonal.append("high-pitched") }

        let voicedPitchSamples = prosody.pitchCurve.filter { $0 > 0 }
        let pitchVariance = voicedPitchSamples
            .map { ($0 - avgPitch) * ($0 - avgPitch) }
            .reduce(0, +) / max(1, Double(voicedPitchSamples.count))
        if pitchVariance < 200 { tonal.append("monotone") }
        if pitchVariance > 1000 { tonal.append("expressive") }

        if prosody.averageSpeechRate < 100 { tonal.append("slow-paced") }
        if prosody.averageSpeechRate > 150 { tonal.append("rapid") }

        // Infer volume pattern from the curve trend
        let volumePattern = inferVolumePattern(from: prosody.volumeCurve)

        return VoiceCharacteristics(
            averagePace: prosody.averageSpeechRate,
            paceVariation: prosody.speechRateVariance,
            pausePatterns: pauseDurations,
            tonalQualities: tonal,
            volumePattern: volumePattern
        )
    }

    /// Infers a human-readable volume pattern from the volume curve.
    private func inferVolumePattern(from curve: [Double]) -> String {
        guard curve.count >= 4 else { return "steady" }
        let quarterLen = curve.count / 4
        let firstQ = curve.prefix(quarterLen).reduce(0, +) / Double(quarterLen)
        let lastQ = curve.suffix(quarterLen).reduce(0, +) / Double(quarterLen)
        let diff = lastQ - firstQ
        if abs(diff) < 0.05 { return "steady" }
        if diff < -0.15 { return "gradually quieter" }
        if diff > 0.15 { return "gradually louder" }
        return "dynamic"
    }
}
