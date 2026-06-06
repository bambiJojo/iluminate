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

    var displayName: String {
        switch self {
        case .keywordOnly:
            return "Keyword Only"
        case .chunkedOnly:
            return "Chunked Only"
        case .hybridRuntime:
            return "Hybrid Runtime"
        }
    }
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

struct AnalyzerEvaluationEngine: Sendable {
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
        preparedTranscription: AnalyzerTranscriptCache.PreparedTranscription
    ) async -> AnalyzerEvaluationResult {
        let prediction = await predictPhases(
            config: config,
            transcription: preparedTranscription.transcription,
            wordTimestamps: preparedTranscription.wordTimestamps,
            duration: example.duration
        )
        let metrics = AnalyzerMetrics.score(
            example: example.example,
            predictedSegments: prediction.phases,
            predictedContentType: preparedTranscription.heuristicContentType,
            boundaryToleranceSeconds: boundaryToleranceSeconds
        )

        return AnalyzerEvaluationResult(
            exampleID: example.id,
            originalFilename: example.originalFilename,
            evaluationMode: mode,
            predictedContentType: preparedTranscription.heuristicContentType,
            usedChunkedAnalyzer: prediction.usedChunkedAnalyzer,
            transcriptionWordCount: preparedTranscription.wordCount,
            predictedPhases: prediction.phases,
            metrics: metrics
        )
    }

    private func predictPhases(
        config: AnalyzerConfig,
        transcription: AudioTranscriptionResult,
        wordTimestamps: [WordTimestamp],
        duration: TimeInterval
    ) async -> (phases: [PhaseSegment], usedChunkedAnalyzer: Bool) {
        let keywordAnalyzer = HypnosisPhaseAnalyzer(config: config)

        switch mode {
        case .keywordOnly:
            return (
                keywordAnalyzer.analyze(
                    wordTimestamps: wordTimestamps,
                    transcription: transcription
                ),
                false
            )
        case .chunkedOnly:
            let chunked = await ChunkedPhaseAnalyzer(config: config.chunkedAnalyzer)
                .analyze(wordTimestamps: wordTimestamps, duration: duration) ?? []
            let adaptedChunked = chunked.isEmpty
                ? []
                : keywordAnalyzer.adaptPredictedPhases(chunked, transcription: transcription)
            return (adaptedChunked, !adaptedChunked.isEmpty)
        case .hybridRuntime:
            let chunked = await ChunkedPhaseAnalyzer(config: config.chunkedAnalyzer)
                .analyze(wordTimestamps: wordTimestamps, duration: duration)
            let keywordPhases = keywordAnalyzer.analyze(
                wordTimestamps: wordTimestamps,
                transcription: transcription
            )
            return keywordAnalyzer.selectPreferredPhases(
                keywordPhases: keywordPhases,
                chunkedPhases: chunked,
                transcription: transcription
            )
        }
    }

    nonisolated static func heuristicContentType(for transcription: AudioTranscriptionResult) -> AudioContentType {
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
