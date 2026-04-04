//
//  AnalyzerEvaluationEngine.swift
//  Ilumionate
//
//  Runs deterministic analyzer evaluation for optimizer loops.
//

import Foundation

enum AnalyzerEvaluationMode: String, Codable, Sendable {
    case keywordOnly
    case chunkedOnly
    case hybridRuntime
}

struct AnalyzerEvaluationResult: Codable, Sendable {
    let exampleID: UUID
    let originalFilename: String
    let evaluationMode: AnalyzerEvaluationMode
    let predictedContentType: AudioContentType
    let usedChunkedAnalyzer: Bool
    let transcriptionWordCount: Int
    let predictedPhases: [PhaseSegment]
    let metrics: AnalyzerOptimizationMetrics
}

struct AnalyzerEvaluationEngine {
    let mode: AnalyzerEvaluationMode
    let boundaryToleranceSeconds: Double

    init(
        mode: AnalyzerEvaluationMode = .keywordOnly,
        boundaryToleranceSeconds: Double = 30.0
    ) {
        self.mode = mode
        self.boundaryToleranceSeconds = boundaryToleranceSeconds
    }

    func evaluate(
        config: AnalyzerConfig,
        example: AnalyzerOptimizationDataset.Example,
        transcription: AudioTranscriptionResult
    ) async -> AnalyzerEvaluationResult {
        let prediction = await predictPhases(
            config: config,
            transcription: transcription,
            duration: example.duration
        )
        let predictedContentType = heuristicContentType(for: transcription)
        let metrics = AnalyzerMetrics.score(
            example: example.example,
            predictedSegments: prediction.phases,
            predictedContentType: predictedContentType,
            boundaryToleranceSeconds: boundaryToleranceSeconds
        )

        return AnalyzerEvaluationResult(
            exampleID: example.id,
            originalFilename: example.originalFilename,
            evaluationMode: mode,
            predictedContentType: predictedContentType,
            usedChunkedAnalyzer: prediction.usedChunkedAnalyzer,
            transcriptionWordCount: transcription.wordCount,
            predictedPhases: prediction.phases,
            metrics: metrics
        )
    }

    private func predictPhases(
        config: AnalyzerConfig,
        transcription: AudioTranscriptionResult,
        duration: TimeInterval
    ) async -> (phases: [PhaseSegment], usedChunkedAnalyzer: Bool) {
        switch mode {
        case .keywordOnly:
            return (
                HypnosisPhaseAnalyzer(config: config.keywordPipeline)
                    .analyze(segments: transcription.segments, duration: duration),
                false
            )
        case .chunkedOnly:
            let wordTimestamps = HypnosisPhaseAnalyzer(config: config.keywordPipeline)
                .approximateWordTimestamps(from: transcription.segments)
            let chunked = await ChunkedPhaseAnalyzer(config: config.chunkedAnalyzer)
                .analyze(wordTimestamps: wordTimestamps, duration: duration) ?? []
            return (chunked, !chunked.isEmpty)
        case .hybridRuntime:
            let wordTimestamps = HypnosisPhaseAnalyzer(config: config.keywordPipeline)
                .approximateWordTimestamps(from: transcription.segments)
            let chunked = await ChunkedPhaseAnalyzer(config: config.chunkedAnalyzer)
                .analyze(wordTimestamps: wordTimestamps, duration: duration)
            if let chunked, !chunked.isEmpty {
                return (chunked, true)
            }
            return (
                HypnosisPhaseAnalyzer(config: config.keywordPipeline)
                    .analyze(segments: transcription.segments, duration: duration),
                false
            )
        }
    }

    private func heuristicContentType(for transcription: AudioTranscriptionResult) -> AudioContentType {
        let text = transcription.fullText.lowercased()
        let hypnosisSignals = [
            "relax", "deeper", "drift", "trance", "suggestion",
            "eyes", "breath", "sleep", "counting", "hypnosis"
        ]
        let meditationSignals = [
            "mindfulness", "present moment", "observe", "awareness",
            "meditation", "body scan"
        ]
        let affirmationsSignals = [
            "i am", "you are", "worthy", "abundant", "confident"
        ]

        func hits(for keywords: [String]) -> Int {
            keywords.filter { text.localizedStandardContains($0) }.count
        }

        if hits(for: hypnosisSignals) >= 2 { return .hypnosis }
        if hits(for: meditationSignals) >= 2 { return .meditation }
        if hits(for: affirmationsSignals) >= 2 { return .affirmations }
        return transcription.wordCount < 10 ? .music : .unknown
    }
}
