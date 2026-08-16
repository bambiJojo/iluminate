//
//  AnalysisPipelineProtocols.swift
//  Ilumionate
//
//  Typed contracts for the variable stages of the audio-analysis run.
//  All conforming types are MainActor-isolated, matching the existing
//  Observable class architecture.  Mock implementations live in the
//  test target and conform to these protocols for dependency injection.
//

import Foundation

// MARK: - Analysis Stage Protocols

/// Transcribes an audio file to text.
/// All conforming types must be MainActor-isolated.
@MainActor
protocol AudioTranscribingService: AnyObject {
    var progress: Double { get }
    var statusMessage: String { get }
    func transcribe(audioFile: AudioFile) async throws -> AudioTranscriptionResult
    func cancelTranscription() async
    func releaseResources() async
}

extension AudioTranscribingService {
    func releaseResources() async {}
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
    func cancelAnalysis() async
}

extension ContentAnalyzingService {
    func cancelAnalysis() async {}
}

/// Extracts prosodic features (speech rate, volume, pitch, pauses)
/// directly from the raw audio signal combined with transcript timing.
/// Not MainActor-isolated — runs on a background thread for performance.
nonisolated protocol ProsodyAnalyzingService: Sendable {
    func analyze(
        url: URL,
        segments: [AudioTranscriptionSegment],
        config: ProsodyAnalyzer.Config
    ) throws -> ProsodicProfile
}
