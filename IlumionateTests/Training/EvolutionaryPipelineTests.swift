//
//  EvolutionaryPipelineTests.swift
//  IlumionateTests
//
//  Entry point to run the evolutionary improvement pipeline.
//  Run with: xcodebuild test -only-testing:IlumionateTests/EvolutionaryPipelineTests
//

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct EvolutionaryPipelineTests {
    @Test
    func pipelineRunnerPrefersAnalyzerDatasetExportOverLegacyCorpusJSON() throws {
        let corpusDirectory = try makeTempDirectory()
        let datasetDirectory = corpusDirectory.appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: datasetDirectory, withIntermediateDirectories: true)

        let datasetFile = makeLabeledFile(
            originalFilename: "dataset.wav",
            storedAudioFilename: "dataset-audio.wav",
            phases: [
                .init(phase: .preTalk, startTime: 0, endTime: 30),
                .init(phase: .induction, startTime: 30, endTime: 60)
            ]
        )
        let legacyFile = makeLabeledFile(
            originalFilename: "legacy.wav",
            storedAudioFilename: "legacy-audio.wav",
            phases: [
                .init(phase: .therapy, startTime: 0, endTime: 60)
            ]
        )

        let example = datasetFile.analyzerTrainingExample(
            exportedAt: Date(timeIntervalSince1970: 1_000),
            datasetRelativeAudioPath: "audio/\(datasetFile.storedAudioFilename)",
            datasetRelativeExamplePath: "examples/\(datasetFile.id.uuidString).json"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(example).write(
            to: datasetDirectory.appending(path: "dataset.jsonl"),
            options: .atomic
        )

        let prettyEncoder = JSONEncoder()
        prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        prettyEncoder.dateEncodingStrategy = .iso8601
        try prettyEncoder.encode(legacyFile).write(
            to: corpusDirectory.appending(path: "\(legacyFile.id.uuidString).json"),
            options: .atomic
        )

        let runner = PipelineRunner(
            corpusDirectory: corpusDirectory,
            outputDirectory: corpusDirectory.appending(path: "Output")
        )
        let result = runner.loadCorpusResult()

        #expect(result.sourceDescription.contains("AnalyzerDataset"))
        #expect(result.labeledFiles.count == 1)
        #expect(result.labeledFiles[0].id == datasetFile.id)
        #expect(result.labeledFiles[0].originalFilename == "dataset.wav")
    }

    /// Smoke test: runs 2 generations with population 4 to verify the pipeline works.
    @Test func pipelineSmokeTest() {
        let runner = PipelineRunner()
        let (config, report) = runner.run(
            params: .init(populationSize: 4, maxGenerations: 2, elitismCount: 1, earlyStopPatience: 2)
        )

        #expect(config.generation >= 0, "Config should have a generation number")
        #expect(report.totalGenerations > 0, "Report should contain at least one generation")
        #expect(report.fitnessHistory.count > 0, "Fitness history should not be empty")
        print("Smoke test passed. Best fitness: \(config.fitness)")
    }

    /// Full pipeline run — use this to actually improve the analyzer.
    /// Tagged so it doesn't run in CI.
    @Test(.disabled("Run manually for actual training"))
    func fullPipelineRun() {
        let runner = PipelineRunner()
        let (config, report) = runner.run(
            params: .init(populationSize: 10, maxGenerations: 20, elitismCount: 3, earlyStopPatience: 5)
        )

        print("Full run complete:")
        print("  Best fitness: \(config.fitness)")
        print("  Generations: \(report.totalGenerations)")
        for fileScore in report.perFileScores {
            print("  \(fileScore.filename): \(fileScore.fitness)")
        }
    }

    /// Verify mutation produces different configs.
    @Test func mutationProducesDiversity() {
        let seed = AnalyzerConfigLoader.load()
        let mutated = MutationOperators.mutate(seed, labeledCorpus: [])

        let seedWeights = seed.keywordPipeline.weights
        let mutatedWeights = mutated.keywordPipeline.weights
        var hasDifference = false
        for (phase, keywords) in seedWeights {
            for (keyword, weight) in keywords {
                if mutatedWeights[phase]?[keyword] != weight {
                    hasDifference = true
                    break
                }
            }
            if hasDifference { break }
        }
        #expect(hasDifference, "Mutation should produce at least one different value")
    }

    /// Verify crossover mixes sections from two parents.
    @Test func crossoverMixesSections() {
        let parentA = AnalyzerConfigLoader.load()
        var parentB = parentA
        parentB.keywordPipeline.contextWindowSeconds = 99
        parentB.prosody.speechRateWindowSeconds = 99.0

        var sawMix = false
        for _ in 0..<20 {
            let child = MutationOperators.crossover(parentA, parentB)
            let hasAKeyword = child.keywordPipeline.contextWindowSeconds != 99
            let hasBProsody = child.prosody.speechRateWindowSeconds == 99.0
            if hasAKeyword && hasBProsody {
                sawMix = true
                break
            }
        }
        #expect(sawMix, "Crossover should eventually mix sections from different parents")
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeLabeledFile(
        originalFilename: String,
        storedAudioFilename: String,
        phases: [LabeledFile.LabeledPhase]
    ) -> LabeledFile {
        LabeledFile(
            originalFilename: originalFilename,
            storedAudioFilename: storedAudioFilename,
            audioDuration: 60,
            audioSHA256: UUID().uuidString,
            expectedContentType: .hypnosis,
            expectedFrequencyBand: .init(lower: 0.5, upper: 8),
            phases: phases,
            techniques: [],
            labeledAt: Date(timeIntervalSince1970: 1_000),
            labelerNotes: "test"
        )
    }
}
