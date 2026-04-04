//
//  AnalysisPipelineProtocols.swift
//  Ilumionate
//
//  Typed contracts for each stage of the audio-analysis pipeline.
//  All conforming types are MainActor-isolated, matching the existing
//  Observable class architecture.  Mock implementations live in the
//  test target and conform to these protocols for dependency injection.
//

import Foundation

// MARK: - Pipeline Result

/// The combined output of a completed analysis run.
struct AnalysisPipelineResult: Sendable {
    let transcription: AudioTranscriptionResult
    let analysis: AnalysisResult
    let session: LightSession
}

// MARK: - Progress

/// A single progress event emitted while the pipeline is running.
struct AnalysisPipelineProgress: Sendable {
    let stage: AnalysisStage
    let fraction: Double   // 0.0 – 1.0 across the whole pipeline
    let message: String
}

// MARK: - Service Protocols

/// Transcribes an audio file to text.
/// All conforming types must be MainActor-isolated.
@MainActor
protocol AudioTranscribingService: AnyObject {
    var progress: Double { get }
    var statusMessage: String { get }
    func transcribe(audioFile: AudioFile) async throws -> AudioTranscriptionResult
    func cancelTranscription() async
}

/// Analyses transcribed audio content with AI.
/// All conforming types must be MainActor-isolated.
@MainActor
protocol ContentAnalyzingService: AnyObject {
    var progress: Double { get }
    var statusMessage: String { get }
    var isModelAvailable: Bool { get }
    func analyzeContent(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile
    ) async throws -> AnalysisResult
    func analyzeWithoutTranscription(
        audioFile: AudioFile,
        audioFeatures: AudioFeatures
    ) async throws -> AnalysisResult
}

/// Extracts prosodic features (speech rate, volume, pitch, pauses)
/// directly from the raw audio signal combined with transcript timing.
/// Not MainActor-isolated — runs on a background thread for performance.
protocol ProsodyAnalyzingService: Sendable {
    func analyze(
        url: URL,
        segments: [AudioTranscriptionSegment],
        config: ProsodyAnalyzer.Config
    ) throws -> ProsodicProfile
}

/// Generates a synchronized light session from an analysis result.
/// All conforming types must be MainActor-isolated.
@MainActor
protocol SessionGeneratingService: AnyObject {
    func generateSession(
        from audioFile: AudioFile,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig
    ) -> LightSession
}
