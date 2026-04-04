//
//  PipelineRunner.swift
//  IlumionateTests
//
//  Orchestrates generations, caching, and report output.
//

import Foundation
@testable import Ilumionate

// MARK: - Evaluation Report

struct EvaluationReport: Codable {
    let generatedAt: Date
    let corpusSource: String
    let corpusFileCount: Int
    let totalGenerations: Int
    let bestFitness: Double
    let fitnessHistory: [GenerationSnapshot]
    let perFileScores: [FileScore]

    struct GenerationSnapshot: Codable {
        let generation: Int
        let bestFitness: Double
        let averageFitness: Double
    }

    struct FileScore: Codable {
        let filename: String
        let fitness: Double
        let contentTypeCorrect: Bool
        let phaseBoundaryScore: Double
        let phasePresenceScore: Double
    }
}

// MARK: - Pipeline Runner

struct PipelineRunner {

    let corpusDirectory: URL
    let outputDirectory: URL

    init(
        corpusDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus"),
        outputDirectory: URL = URL.documentsDirectory.appending(path: "TrainingOutput")
    ) {
        self.corpusDirectory = corpusDirectory
        self.outputDirectory = outputDirectory
    }

    /// Loads the labeled corpus from disk, preferring the analyzer dataset export.
    func loadCorpusResult() -> AnalyzerTrainingCorpusLoadResult {
        AnalyzerTrainingCorpusLoader(corpusDirectory: corpusDirectory).load()
    }

    func loadCorpus() -> [LabeledFile] {
        loadCorpusResult().labeledFiles
    }

    /// Runs the full improvement pipeline.
    @MainActor
    func run(
        params: EvolutionaryOptimizer.Parameters = .init()
    ) -> (config: AnalyzerConfig, report: EvaluationReport) {
        let corpusResult = loadCorpusResult()
        let corpus = corpusResult.labeledFiles
        print("📂 Loaded \(corpus.count) labeled file(s) from \(corpusResult.sourceDescription)")

        let seedConfig = AnalyzerConfigLoader.load()
        let optimizer = EvolutionaryOptimizer(params: params, labeledCorpus: corpus)

        let (bestConfig, history) = optimizer.run(seed: seedConfig) { gen in
            print("  Gen \(gen.generation): fitness \(gen.bestFitness)")
        }

        let perFileScores = buildPerFileScores(corpus: corpus, bestConfig: bestConfig)

        let report = EvaluationReport(
            generatedAt: Date(),
            corpusSource: corpusResult.sourceDescription,
            corpusFileCount: corpus.count,
            totalGenerations: history.count,
            bestFitness: bestConfig.fitness,
            fitnessHistory: history.map {
                .init(generation: $0.generation, bestFitness: $0.bestFitness, averageFitness: $0.averageFitness)
            },
            perFileScores: perFileScores
        )

        writeOutputs(config: bestConfig, report: report)

        return (bestConfig, report)
    }

    @MainActor
    private func buildPerFileScores(
        corpus: [LabeledFile],
        bestConfig: AnalyzerConfig
    ) -> [EvaluationReport.FileScore] {
        let fitnessEvaluator = FitnessEvaluator()
        let keywordAnalyzer = HypnosisPhaseAnalyzer(config: bestConfig.keywordPipeline)
        let sessionGenerator = SessionGenerator(config: bestConfig.sessionGeneration)

        return corpus.map { labeledFile in
            let audioFile = AudioFile(
                filename: labeledFile.audioFilename,
                duration: labeledFile.audioDuration,
                fileSize: 0
            )
            let phases = keywordAnalyzer.analyze(segments: [], duration: labeledFile.audioDuration)
            let metadata = HypnosisMetadata(
                phases: phases, inductionStyle: .permissive,
                estimatedTranceDeph: .medium, suggestionDensity: nil,
                languagePatterns: [], detectedTechniques: []
            )
            let result = AnalysisResult(
                mood: .meditative, energyLevel: 0.3,
                suggestedFrequencyRange: bestConfig.sessionGeneration
                    .band(for: labeledFile.expectedContentType).closedRange,
                suggestedIntensity: 0.5, keyMoments: [], aiSummary: "",
                recommendedPreset: "", contentType: labeledFile.expectedContentType,
                hypnosisMetadata: metadata
            )
            let session = sessionGenerator.generateSession(from: audioFile, analysis: result)
            let fitness = fitnessEvaluator.fitness(labeledFile: labeledFile, result: result, session: session)
            return EvaluationReport.FileScore(
                filename: labeledFile.audioFilename,
                fitness: fitness,
                contentTypeCorrect: result.contentType == labeledFile.expectedContentType,
                phaseBoundaryScore: fitnessEvaluator.scorePhaseBoundaries(
                    labeledFile: labeledFile, result: result),
                phasePresenceScore: fitnessEvaluator.scorePhasePresence(
                    labeledFile: labeledFile, result: result)
            )
        }
    }

    private func writeOutputs(config: AnalyzerConfig, report: EvaluationReport) {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: outputDirectory.path()) {
            try? fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(config) {
            let url = outputDirectory.appending(path: "AnalyzerConfig_gen\(config.generation).json")
            try? data.write(to: url, options: .atomic)
            print("💾 Wrote config: \(url.lastPathComponent)")
        }

        if let data = try? encoder.encode(report) {
            let url = outputDirectory.appending(path: "EvaluationReport_gen\(config.generation).json")
            try? data.write(to: url, options: .atomic)
            print("📊 Wrote report: \(url.lastPathComponent)")
        }

        try? AnalyzerConfigLoader.save(config)
        print("✅ Pipeline complete. Best fitness: \(config.fitness)")
    }
}
