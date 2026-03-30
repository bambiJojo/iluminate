//
//  MockContentAnalyzer.swift
//  IlumionateTests
//
//  Deterministic ContentAnalyzingService for unit tests.
//  Set isModelAvailable = false to simulate unavailable AI.
//

import Foundation
@testable import Ilumionate

@MainActor
final class MockContentAnalyzer: ContentAnalyzingService {
    var progress: Double = 0.0
    var statusMessage: String = ""
    var isModelAvailable: Bool = true

    var analysisToReturn: AnalysisResult = AnalysisFixtures.hypnosisAnalysis
    private(set) var callCount = 0

    func analyzeContent(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile
    ) async throws -> AnalysisResult {
        guard isModelAvailable else { throw AIAnalyzerError.modelUnavailable }
        callCount += 1
        progress = 1.0
        return analysisToReturn
    }

    func analyzeWithoutTranscription(
        audioFile: AudioFile,
        audioFeatures: AudioFeatures
    ) async throws -> AnalysisResult {
        guard isModelAvailable else { throw AIAnalyzerError.modelUnavailable }
        callCount += 1
        progress = 1.0
        return analysisToReturn
    }
}
