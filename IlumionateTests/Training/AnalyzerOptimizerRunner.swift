//
//  AnalyzerOptimizerRunner.swift
//  IlumionateTests
//
//  Developer-facing entry point for optimizer runs.
//

import Foundation
@testable import Ilumionate

@MainActor
struct AnalyzerOptimizerRunner {
    let corpusDirectory: URL
    let outputDirectory: URL

    init(
        corpusDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus"),
        outputDirectory: URL = URL.documentsDirectory.appending(path: "TrainingOutput")
    ) {
        self.corpusDirectory = corpusDirectory
        self.outputDirectory = outputDirectory
    }

    func run(
        seedConfig: AnalyzerConfig? = nil,
        params: AnalyzerOptimizer.Parameters = .init()
    ) async throws -> AnalyzerOptimizer.RunResult {
        let transcriber = AudioAnalyzer()
        let optimizer = AnalyzerOptimizer(
            corpusDirectory: corpusDirectory,
            outputDirectory: outputDirectory
        )

        return try await optimizer.run(
            seedConfig: seedConfig,
            params: params,
            transcribe: { example in
                let audioFile = try example.makeAudioFileForDocumentsBackedCorpus()
                return try await transcriber.transcribe(audioFile: audioFile)
            }
        )
    }

    func measure(
        config: AnalyzerConfig? = nil,
        evaluationMode: AnalyzerEvaluationMode = .keywordOnly
    ) async throws -> AnalyzerOptimizer.MeasurementResult {
        let transcriber = AudioAnalyzer()
        let optimizer = AnalyzerOptimizer(
            corpusDirectory: corpusDirectory,
            outputDirectory: outputDirectory
        )

        return try await optimizer.measure(
            config: config,
            evaluationMode: evaluationMode,
            transcribe: { example in
                let audioFile = try example.makeAudioFileForDocumentsBackedCorpus()
                return try await transcriber.transcribe(audioFile: audioFile)
            }
        )
    }
}
