//
//  AnalyzerOptimizerTests.swift
//  IlumionateTests
//
//  Coverage for analyzer optimizer dataset, metrics, and artifact output.
//

import Testing
import Foundation
@testable import Ilumionate

private struct AnalyzerTranscriptCacheFixture: Encodable {
    let schemaVersion: Int
    let cachedAt: Date
    let exampleID: UUID
    let audioSHA256: String
    let transcription: AudioTranscriptionResult
}

struct AnalyzerOptimizerTests {
    private actor TranscriptionCallCounter {
        private var count = 0

        func increment() {
            count += 1
        }

        func value() -> Int {
            count
        }
    }

    @Test
    func datasetLoaderReadsAnalyzerDatasetAndKeepsValidExamples() throws {
        let corpusDirectory = try makeTempDirectory()
        let datasetDirectory = corpusDirectory.appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
        let audioDirectory = datasetDirectory.appending(path: "audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let labeled = makeLabeledFile(
            originalFilename: "demo.wav",
            storedAudioFilename: "demo.wav",
            phases: [
                .init(phase: .preTalk, startTime: 0, endTime: 10),
                .init(phase: .induction, startTime: 10, endTime: 20)
            ]
        )
        let example = labeled.analyzerTrainingExample(
            exportedAt: Date(timeIntervalSince1970: 1_000),
            datasetRelativeAudioPath: "AnalyzerDataset/audio/demo.wav",
            datasetRelativeExamplePath: "AnalyzerDataset/examples/\(labeled.id.uuidString).json"
        )
        try Data("audio".utf8).write(to: audioDirectory.appending(path: "demo.wav"), options: .atomic)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(example).write(
            to: datasetDirectory.appending(path: "dataset.jsonl"),
            options: .atomic
        )

        let dataset = try AnalyzerOptimizationDataset.load(from: corpusDirectory)
        #expect(dataset.examples.count == 1)
        #expect(dataset.issues.isEmpty)
        #expect(!dataset.datasetHash.isEmpty)
        #expect(dataset.examples[0].audioURL.lastPathComponent == "demo.wav")
    }

    @Test
    func datasetLoaderWarnsAboutSparseLongExamplesAndRarePhaseCoverage() throws {
        let corpusDirectory = try makeTempDirectory()
        let datasetDirectory = corpusDirectory.appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
        let audioDirectory = datasetDirectory.appending(path: "audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let files = (0..<12).map { index in
            let phase: TrancePhase = index == 0 ? .confusion : .induction
            let duration: TimeInterval = index == 0 ? 900 : 30
            return makeLabeledFile(
                originalFilename: "quality-\(index).wav",
                storedAudioFilename: "quality-\(index).wav",
                phases: [
                    .init(phase: phase, startTime: 0, endTime: duration)
                ]
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let lines = try files.map { file -> String in
            try Data("audio".utf8).write(to: audioDirectory.appending(path: file.storedAudioFilename), options: .atomic)
            let example = file.analyzerTrainingExample(
                exportedAt: Date(timeIntervalSince1970: 1_000),
                datasetRelativeAudioPath: "AnalyzerDataset/audio/\(file.storedAudioFilename)",
                datasetRelativeExamplePath: "AnalyzerDataset/examples/\(file.id.uuidString).json"
            )
            return String(decoding: try encoder.encode(example), as: UTF8.self)
        }
        try lines.joined(separator: "\n").write(
            to: datasetDirectory.appending(path: "dataset.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let dataset = try AnalyzerOptimizationDataset.load(from: corpusDirectory)

        #expect(dataset.examples.count == 12)
        #expect(dataset.issues.contains { $0.severity == .warning && $0.message.contains("Long example has only one labeled phase segment") })
        #expect(dataset.issues.contains { $0.severity == .warning && $0.message.contains("Rare phase coverage: deepening") })
    }

    @Test
    func datasetLoaderAlsoResolvesModernRelativeAudioPaths() throws {
        let corpusDirectory = try makeTempDirectory()
        let datasetDirectory = corpusDirectory.appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
        let audioDirectory = datasetDirectory.appending(path: "audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let labeled = makeLabeledFile(
            originalFilename: "modern.wav",
            storedAudioFilename: "modern.wav",
            phases: [
                .init(phase: .preTalk, startTime: 0, endTime: 5),
                .init(phase: .induction, startTime: 5, endTime: 10)
            ]
        )
        let example = labeled.analyzerTrainingExample(
            exportedAt: Date(timeIntervalSince1970: 1_000),
            datasetRelativeAudioPath: "audio/modern.wav",
            datasetRelativeExamplePath: "examples/\(labeled.id.uuidString).json"
        )
        try Data("audio".utf8).write(to: audioDirectory.appending(path: "modern.wav"), options: .atomic)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(example).write(
            to: datasetDirectory.appending(path: "dataset.jsonl"),
            options: .atomic
        )

        let dataset = try AnalyzerOptimizationDataset.load(from: corpusDirectory)
        #expect(dataset.examples.count == 1)
        #expect(dataset.issues.isEmpty)
        #expect(dataset.examples[0].audioURL == audioDirectory.appending(path: "modern.wav"))
    }

    @Test
    func metricsScorePerfectPredictionAsPerfect() {
        let labeled = makeLabeledFile(
            originalFilename: "perfect.wav",
            storedAudioFilename: "perfect.wav",
            phases: [
                .init(phase: .preTalk, startTime: 0, endTime: 10),
                .init(phase: .induction, startTime: 10, endTime: 20),
                .init(phase: .deepening, startTime: 20, endTime: 30)
            ]
        )
        let example = labeled.analyzerTrainingExample(
            exportedAt: Date(timeIntervalSince1970: 1_000),
            datasetRelativeAudioPath: "AnalyzerDataset/audio/perfect.wav",
            datasetRelativeExamplePath: "AnalyzerDataset/examples/\(labeled.id.uuidString).json"
        )
        let predicted = [
            PhaseSegment(phase: .preTalk, startTime: 0, endTime: 10, characteristics: "", tranceDepthEstimate: 0.1),
            PhaseSegment(phase: .induction, startTime: 10, endTime: 20, characteristics: "", tranceDepthEstimate: 0.4),
            PhaseSegment(phase: .deepening, startTime: 20, endTime: 30, characteristics: "", tranceDepthEstimate: 0.8)
        ]

        let metrics = AnalyzerMetrics.score(
            example: example,
            predictedSegments: predicted,
            predictedContentType: .hypnosis,
            boundaryToleranceSeconds: 5
        )

        #expect(metrics.timelineAccuracy == 1.0)
        #expect(metrics.macroPhaseF1 == 1.0)
        #expect(metrics.boundaryScore == 1.0)
        #expect(metrics.transitionRecall == 1.0)
        #expect(metrics.orderValidity == 1.0)
        #expect(abs(metrics.overallScore - 1.0) < 0.000_000_001)
    }

    @Test
    func metricsTreatChronologicalRecurrentPhasesAsStructurallyValid() {
        let labeled = makeLabeledFile(
            originalFilename: "recurrent.wav",
            storedAudioFilename: "recurrent.wav",
            phases: [
                .init(phase: .suggestions, startTime: 0, endTime: 20),
                .init(phase: .conditioning, startTime: 20, endTime: 40),
                .init(phase: .suggestions, startTime: 40, endTime: 60)
            ]
        )
        let example = labeled.analyzerTrainingExample(
            exportedAt: Date(timeIntervalSince1970: 1_000),
            datasetRelativeAudioPath: "AnalyzerDataset/audio/recurrent.wav",
            datasetRelativeExamplePath: "AnalyzerDataset/examples/\(labeled.id.uuidString).json"
        )
        let predicted = [
            PhaseSegment(phase: .suggestions, startTime: 0, endTime: 20, characteristics: "", tranceDepthEstimate: 0.72),
            PhaseSegment(phase: .conditioning, startTime: 20, endTime: 40, characteristics: "", tranceDepthEstimate: 0.58),
            PhaseSegment(phase: .suggestions, startTime: 40, endTime: 60, characteristics: "", tranceDepthEstimate: 0.72)
        ]

        let metrics = AnalyzerMetrics.score(
            example: example,
            predictedSegments: predicted,
            predictedContentType: .hypnosis,
            boundaryToleranceSeconds: 5
        )

        #expect(metrics.orderValidity == 1.0)
        #expect(abs(metrics.overallScore - 1.0) < 0.000_000_001)
    }

    @Test
    func boundaryScoreRetainsSignalForLargeMisses() {
        let labeled = makeLabeledFile(
            originalFilename: "boundary.wav",
            storedAudioFilename: "boundary.wav",
            phases: [
                .init(phase: .preTalk, startTime: 0, endTime: 10),
                .init(phase: .induction, startTime: 10, endTime: 20),
                .init(phase: .deepening, startTime: 20, endTime: 30)
            ]
        )
        let example = labeled.analyzerTrainingExample(
            exportedAt: Date(timeIntervalSince1970: 1_000),
            datasetRelativeAudioPath: "AnalyzerDataset/audio/boundary.wav",
            datasetRelativeExamplePath: "AnalyzerDataset/examples/\(labeled.id.uuidString).json"
        )
        let badlyShifted = [
            PhaseSegment(phase: .preTalk, startTime: 0, endTime: 2, characteristics: "", tranceDepthEstimate: 0.1),
            PhaseSegment(phase: .induction, startTime: 2, endTime: 4, characteristics: "", tranceDepthEstimate: 0.4),
            PhaseSegment(phase: .deepening, startTime: 4, endTime: 30, characteristics: "", tranceDepthEstimate: 0.8)
        ]

        let metrics = AnalyzerMetrics.score(
            example: example,
            predictedSegments: badlyShifted,
            predictedContentType: .hypnosis,
            boundaryToleranceSeconds: 5
        )

        #expect(metrics.boundaryScore > 0)
        #expect(metrics.boundaryScore < 1)
    }

    @Test
    func overallScoreStaysLowWhenPhaseLabelsAreWrongDespiteGoodStructure() {
        let labeled = makeLabeledFile(
            originalFilename: "wrong-phases.wav",
            storedAudioFilename: "wrong-phases.wav",
            phases: [
                .init(phase: .preTalk, startTime: 0, endTime: 10),
                .init(phase: .induction, startTime: 10, endTime: 20),
                .init(phase: .deepening, startTime: 20, endTime: 30)
            ]
        )
        let example = labeled.analyzerTrainingExample(
            exportedAt: Date(timeIntervalSince1970: 1_000),
            datasetRelativeAudioPath: "AnalyzerDataset/audio/wrong-phases.wav",
            datasetRelativeExamplePath: "AnalyzerDataset/examples/\(labeled.id.uuidString).json"
        )
        let wrongButWellTimed = [
            PhaseSegment(phase: .suggestions, startTime: 0, endTime: 10, characteristics: "", tranceDepthEstimate: 0.2),
            PhaseSegment(phase: .suggestions, startTime: 10, endTime: 20, characteristics: "", tranceDepthEstimate: 0.5),
            PhaseSegment(phase: .suggestions, startTime: 20, endTime: 30, characteristics: "", tranceDepthEstimate: 0.8)
        ]

        let metrics = AnalyzerMetrics.score(
            example: example,
            predictedSegments: wrongButWellTimed,
            predictedContentType: .hypnosis,
            boundaryToleranceSeconds: 5
        )

        #expect(metrics.boundaryScore == 1.0)
        #expect(metrics.transitionRecall == 1.0)
        #expect(metrics.orderValidity == 1.0)
        #expect(metrics.timelineAccuracy == 0.0)
        #expect(metrics.macroPhaseF1 == 0.0)
        #expect(metrics.overallScore < 0.10)
    }

    @Test
    func singlePredictedBoundaryCannotMatchMultipleTruthBoundaries() {
        let labeled = makeLabeledFile(
            originalFilename: "boundary-reuse.wav",
            storedAudioFilename: "boundary-reuse.wav",
            phases: [
                .init(phase: .preTalk, startTime: 0, endTime: 10),
                .init(phase: .induction, startTime: 10, endTime: 14),
                .init(phase: .deepening, startTime: 14, endTime: 30),
                .init(phase: .emergence, startTime: 30, endTime: 40)
            ]
        )
        let example = labeled.analyzerTrainingExample(
            exportedAt: Date(timeIntervalSince1970: 1_000),
            datasetRelativeAudioPath: "AnalyzerDataset/audio/boundary-reuse.wav",
            datasetRelativeExamplePath: "AnalyzerDataset/examples/\(labeled.id.uuidString).json"
        )
        let sparsePrediction = [
            PhaseSegment(phase: .preTalk, startTime: 0, endTime: 12, characteristics: "", tranceDepthEstimate: 0.2),
            PhaseSegment(phase: .induction, startTime: 12, endTime: 40, characteristics: "", tranceDepthEstimate: 0.6)
        ]

        let metrics = AnalyzerMetrics.score(
            example: example,
            predictedSegments: sparsePrediction,
            predictedContentType: .hypnosis,
            boundaryToleranceSeconds: 5
        )

        #expect(metrics.matchedTruthBoundaryCount == 1)
        #expect(abs(metrics.transitionRecall - (1.0 / 3.0)) < 0.000_000_001)
    }

    @Test
    func splitUsesBroaderValidationAndTestCoverageForSmallDatasets() throws {
        let optimizer = AnalyzerOptimizer(
            corpusDirectory: try makeTempDirectory(),
            outputDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )

        let examples = (0..<9).map { index in
            let file = makeLabeledFile(
                originalFilename: "example-\(index).wav",
                storedAudioFilename: "example-\(index).wav",
                phases: [
                    .init(phase: .preTalk, startTime: 0, endTime: 5),
                    .init(phase: .induction, startTime: 5, endTime: 10 + Double(index))
                ]
            )
            return AnalyzerOptimizationDataset.Example(
                example: file.analyzerTrainingExample(
                    exportedAt: Date(timeIntervalSince1970: 1_000),
                    datasetRelativeAudioPath: "AnalyzerDataset/audio/\(file.storedAudioFilename)",
                    datasetRelativeExamplePath: "AnalyzerDataset/examples/\(file.id.uuidString).json"
                ),
                audioURL: URL(filePath: "/tmp/\(file.storedAudioFilename)")
            )
        }

        let split = optimizer.split(examples, trainFraction: 0.7, validationFraction: 0.15)

        #expect(split.train.count == 5)
        #expect(split.validation.count == 2)
        #expect(split.test.count == 2)
    }

    @Test
    func splitDistributesRarePhasesAcrossAvailableBuckets() throws {
        let optimizer = AnalyzerOptimizer(
            corpusDirectory: try makeTempDirectory(),
            outputDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )

        let examples = (0..<12).map { index in
            let targetPhase: TrancePhase = index < 3 ? .confusion : .induction
            let file = makeLabeledFile(
                originalFilename: "stratified-\(index).wav",
                storedAudioFilename: "stratified-\(index).wav",
                phases: [
                    .init(phase: .preTalk, startTime: 0, endTime: 5),
                    .init(phase: targetPhase, startTime: 5, endTime: 20)
                ]
            )
            return AnalyzerOptimizationDataset.Example(
                example: file.analyzerTrainingExample(
                    exportedAt: Date(timeIntervalSince1970: 1_000),
                    datasetRelativeAudioPath: "AnalyzerDataset/audio/\(file.storedAudioFilename)",
                    datasetRelativeExamplePath: "AnalyzerDataset/examples/\(file.id.uuidString).json"
                ),
                audioURL: URL(filePath: "/tmp/\(file.storedAudioFilename)")
            )
        }

        let split = optimizer.split(examples, trainFraction: 0.7, validationFraction: 0.15)

        #expect(split.train.count == 8)
        #expect(split.validation.count == 2)
        #expect(split.test.count == 2)
        #expect(split.train.contains { $0.phaseSegments.contains { $0.phase == .deepening } })
        #expect(split.validation.contains { $0.phaseSegments.contains { $0.phase == .deepening } })
        #expect(split.test.contains { $0.phaseSegments.contains { $0.phase == .deepening } })
    }

    @Test
    func optimizerWritesArtifactsFromDatasetAndSyntheticTranscripts() async throws {
        let corpusDirectory = try makeTempDirectory()
        let outputDirectory = corpusDirectory.appending(path: "Output", directoryHint: .isDirectory)
        let datasetDirectory = corpusDirectory.appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
        let audioDirectory = datasetDirectory.appending(path: "audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let files = [
            makeLabeledFile(
                originalFilename: "one.wav",
                storedAudioFilename: "one.wav",
                phases: [
                    .init(phase: .preTalk, startTime: 0, endTime: 8),
                    .init(phase: .induction, startTime: 8, endTime: 18),
                    .init(phase: .deepening, startTime: 18, endTime: 30)
                ]
            ),
            makeLabeledFile(
                originalFilename: "two.wav",
                storedAudioFilename: "two.wav",
                phases: [
                    .init(phase: .preTalk, startTime: 0, endTime: 6),
                    .init(phase: .induction, startTime: 6, endTime: 16),
                    .init(phase: .suggestions, startTime: 16, endTime: 28)
                ]
            ),
            makeLabeledFile(
                originalFilename: "three.wav",
                storedAudioFilename: "three.wav",
                phases: [
                    .init(phase: .preTalk, startTime: 0, endTime: 7),
                    .init(phase: .induction, startTime: 7, endTime: 17),
                    .init(phase: .emergence, startTime: 17, endTime: 25)
                ]
            )
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var lines: [String] = []
        for file in files {
            try Data("audio".utf8).write(
                to: audioDirectory.appending(path: file.storedAudioFilename),
                options: .atomic
            )
            let example = file.analyzerTrainingExample(
                exportedAt: Date(timeIntervalSince1970: 1_000),
                datasetRelativeAudioPath: "AnalyzerDataset/audio/\(file.storedAudioFilename)",
                datasetRelativeExamplePath: "AnalyzerDataset/examples/\(file.id.uuidString).json"
            )
            let line = try String(decoding: encoder.encode(example), as: UTF8.self)
            lines.append(line)
        }
        try Data(lines.joined(separator: "\n").utf8).write(
            to: datasetDirectory.appending(path: "dataset.jsonl"),
            options: .atomic
        )

        let optimizer = AnalyzerOptimizer(
            corpusDirectory: corpusDirectory,
            outputDirectory: outputDirectory
        )
        let seedConfig = AnalyzerConfigLoader.load()
        let result = try await optimizer.run(
            seedConfig: seedConfig,
            params: .init(
                populationSize: 3,
                maxGenerations: 2,
                elitismCount: 1,
                mutationRate: 0.8,
                earlyStopPatience: 2,
                trainFraction: 0.67,
                validationFraction: 0.33,
                evaluationMode: .keywordOnly,
                publishBestConfigToDocuments: false
            ),
            transcribe: { example in
                syntheticTranscription(for: example)
            }
        )

        #expect(FileManager.default.fileExists(atPath: result.outputFiles.configURL.path()))
        #expect(FileManager.default.fileExists(atPath: result.outputFiles.reportURL.path()))
        #expect(FileManager.default.fileExists(atPath: result.outputFiles.diagnosticsURL.path()))
        #expect(FileManager.default.fileExists(atPath: result.outputFiles.historyURL.path()))
        #expect(FileManager.default.fileExists(atPath: result.outputFiles.scorecardURL.path()))
        #expect(result.report.dataset.exampleCount == 3)
        #expect(result.report.trainCount >= 1)
        #expect(result.scorecard.evaluatedExampleCount == 3)
        #expect(result.scorecard.matchPercentage >= 0)
    }

    @Test
    func measureWritesStandaloneTrainingMatchScorecard() async throws {
        let corpusDirectory = try makeTempDirectory()
        let outputDirectory = corpusDirectory.appending(path: "Output", directoryHint: .isDirectory)
        let datasetDirectory = corpusDirectory.appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
        let audioDirectory = datasetDirectory.appending(path: "audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let file = makeLabeledFile(
            originalFilename: "measure.wav",
            storedAudioFilename: "measure.wav",
            phases: [
                .init(phase: .preTalk, startTime: 0, endTime: 5),
                .init(phase: .induction, startTime: 5, endTime: 12),
                .init(phase: .deepening, startTime: 12, endTime: 20)
            ]
        )
        try Data("audio".utf8).write(
            to: audioDirectory.appending(path: file.storedAudioFilename),
            options: .atomic
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let example = file.analyzerTrainingExample(
            exportedAt: Date(timeIntervalSince1970: 1_000),
            datasetRelativeAudioPath: "AnalyzerDataset/audio/\(file.storedAudioFilename)",
            datasetRelativeExamplePath: "AnalyzerDataset/examples/\(file.id.uuidString).json"
        )
        try encoder.encode(example).write(
            to: datasetDirectory.appending(path: "dataset.jsonl"),
            options: .atomic
        )

        let optimizer = AnalyzerOptimizer(
            corpusDirectory: corpusDirectory,
            outputDirectory: outputDirectory
        )
        let measurement = try await optimizer.measure(
            config: AnalyzerConfigLoader.load(),
            evaluationMode: .keywordOnly,
            transcribe: { example in
                syntheticTranscription(for: example)
            }
        )

        #expect(FileManager.default.fileExists(atPath: measurement.outputURL.path()))
        #expect(FileManager.default.fileExists(atPath: measurement.historyURL.path()))
        #expect(measurement.scorecard.evaluatedExampleCount == 1)
        #expect(measurement.scorecard.splitSummaries.contains(where: { $0.name == "all" }))
    }

    @Test
    func measureUsesOnlyHumanGoldExamples() async throws {
        let corpusDirectory = try makeTempDirectory()
        let outputDirectory = corpusDirectory.appending(path: "Output", directoryHint: .isDirectory)
        let datasetDirectory = corpusDirectory.appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
        let audioDirectory = datasetDirectory.appending(path: "audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let gold = makeLabeledFile(
            originalFilename: "human-gold.wav",
            storedAudioFilename: "human-gold.wav",
            phases: [.init(phase: .induction, startTime: 0, endTime: 30)]
        )
        let silver = makeLabeledFile(
            originalFilename: "derived-silver.wav",
            storedAudioFilename: "derived-silver.wav",
            phases: [.init(phase: .suggestions, startTime: 0, endTime: 30)],
            labelerNotes: "Silver label: transcript-only Bambi derivation; not human reviewed."
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let lines = try [gold, silver].map { file -> String in
            try Data("audio".utf8).write(
                to: audioDirectory.appending(path: file.storedAudioFilename),
                options: .atomic
            )
            let example = file.analyzerTrainingExample(
                exportedAt: Date(timeIntervalSince1970: 1_000),
                datasetRelativeAudioPath: "AnalyzerDataset/audio/\(file.storedAudioFilename)",
                datasetRelativeExamplePath: "AnalyzerDataset/examples/\(file.id.uuidString).json"
            )
            return String(decoding: try encoder.encode(example), as: UTF8.self)
        }
        try Data(lines.joined(separator: "\n").utf8).write(
            to: datasetDirectory.appending(path: "dataset.jsonl"),
            options: .atomic
        )

        let optimizer = AnalyzerOptimizer(
            corpusDirectory: corpusDirectory,
            outputDirectory: outputDirectory
        )
        let measurement = try await optimizer.measure(
            config: AnalyzerConfigLoader.load(),
            evaluationMode: .keywordOnly,
            transcribe: { example in
                syntheticTranscription(for: example)
            }
        )

        #expect(measurement.scorecard.evaluatedExampleCount == 1)
        #expect(measurement.scorecard.dataset.exampleCount == 1)
        #expect(measurement.scorecard.worstMatches.map(\.filename) == ["human-gold.wav"])

        let run = try await optimizer.run(
            seedConfig: AnalyzerConfigLoader.load(),
            params: .init(
                populationSize: 1,
                maxGenerations: 0,
                elitismCount: 1,
                mutationRate: 0,
                earlyStopPatience: 1,
                evaluationMode: .keywordOnly,
                publishBestConfigToDocuments: false
            ),
            transcribe: { example in
                syntheticTranscription(for: example)
            }
        )

        #expect(run.report.dataset.exampleCount == 1)
        #expect(run.scorecard.evaluatedExampleCount == 1)
        #expect(run.scorecard.worstMatches.map(\.filename) == ["human-gold.wav"])
    }

    @Test
    func preparedTranscriptCachePersistsPreparedFieldsAcrossRuns() async throws {
        let cacheDirectory = try makeTempDirectory()
        let file = makeLabeledFile(
            originalFilename: "cached.wav",
            storedAudioFilename: "cached.wav",
            phases: [
                .init(phase: .preTalk, startTime: 0, endTime: 5),
                .init(phase: .induction, startTime: 5, endTime: 12)
            ]
        )
        let example = AnalyzerOptimizationDataset.Example(
            example: file.analyzerTrainingExample(
                exportedAt: Date(timeIntervalSince1970: 1_000),
                datasetRelativeAudioPath: "AnalyzerDataset/audio/\(file.storedAudioFilename)",
                datasetRelativeExamplePath: "AnalyzerDataset/examples/\(file.id.uuidString).json"
            ),
            audioURL: URL(filePath: "/tmp/\(file.storedAudioFilename)")
        )

        let firstCache = AnalyzerTranscriptCache(cacheDirectory: cacheDirectory)
        let firstPrepared = try await firstCache.preparedTranscription(for: example) { sample in
            syntheticTranscription(for: sample)
        }

        let secondCache = AnalyzerTranscriptCache(cacheDirectory: cacheDirectory)
        let secondPrepared = try await secondCache.preparedTranscription(for: example)

        #expect(firstPrepared.transcription.fullText == secondPrepared.transcription.fullText)
        #expect(firstPrepared.wordCount == secondPrepared.wordCount)
        #expect(firstPrepared.heuristicContentType == secondPrepared.heuristicContentType)
        #expect(firstPrepared.wordTimestamps.count == secondPrepared.wordTimestamps.count)
        #expect(
            FileManager.default.fileExists(
                atPath: cacheDirectory.appending(path: "\(example.example.audio.sha256).json").path()
            )
        )
    }

    @Test
    func preparedTranscriptCacheReplacesStaleGeneratedTextForRecognizedAudio() async throws {
        let cacheDirectory = try makeTempDirectory()
        let file = makeLabeledFile(
            originalFilename: KnownAudioCatalogFixtures.recognizedFilename,
            storedAudioFilename: "example-reviewed-session.mp3",
            phases: [
                .init(phase: .emergence, startTime: 0, endTime: 600)
            ]
        )
        let example = AnalyzerOptimizationDataset.Example(
            example: file.analyzerTrainingExample(
                exportedAt: Date(timeIntervalSince1970: 1_000),
                datasetRelativeAudioPath: "AnalyzerDataset/audio/\(file.storedAudioFilename)",
                datasetRelativeExamplePath: "AnalyzerDataset/examples/\(file.id.uuidString).json"
            ),
            audioURL: URL(filePath: "/tmp/\(file.storedAudioFilename)")
        )
        let stale = AudioTranscriptionResult(
            fullText: "Old Whisper transcript with recognition mistakes.",
            segments: [],
            duration: example.duration,
            detectedLanguage: "en"
        )
        let fixture = AnalyzerTranscriptCacheFixture(
            schemaVersion: 1,
            cachedAt: .now,
            exampleID: example.id,
            audioSHA256: example.example.audio.sha256,
            transcription: stale
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(fixture).write(
            to: cacheDirectory.appending(path: "\(example.example.audio.sha256).json"),
            options: .atomic
        )

        let cache = AnalyzerTranscriptCache(
            cacheDirectory: cacheDirectory,
            bundledTranscriptCatalog: KnownAudioCatalogFixtures.bundledTranscriptCatalog
        )
        let result = try await cache.transcription(for: example)

        #expect(result.fullText != stale.fullText)
        #expect(result.fullText == KnownAudioCatalogFixtures.expectedTranscript)
    }

    @Test
    func preparedTranscriptCacheCoalescesConcurrentRequestsForSameFile() async throws {
        let cacheDirectory = try makeTempDirectory()
        let file = makeLabeledFile(
            originalFilename: "parallel.wav",
            storedAudioFilename: "parallel.wav",
            phases: [
                .init(phase: .preTalk, startTime: 0, endTime: 4),
                .init(phase: .induction, startTime: 4, endTime: 10)
            ]
        )
        let example = AnalyzerOptimizationDataset.Example(
            example: file.analyzerTrainingExample(
                exportedAt: Date(timeIntervalSince1970: 1_000),
                datasetRelativeAudioPath: "AnalyzerDataset/audio/\(file.storedAudioFilename)",
                datasetRelativeExamplePath: "AnalyzerDataset/examples/\(file.id.uuidString).json"
            ),
            audioURL: URL(filePath: "/tmp/\(file.storedAudioFilename)")
        )
        let cache = AnalyzerTranscriptCache(cacheDirectory: cacheDirectory)
        let callCounter = TranscriptionCallCounter()

        let preparedResults = try await withThrowingTaskGroup(
            of: AnalyzerTranscriptCache.PreparedTranscription.self,
            returning: [AnalyzerTranscriptCache.PreparedTranscription].self
        ) { group in
            for _ in 0..<4 {
                group.addTask {
                    try await cache.preparedTranscription(for: example) { sample in
                        await callCounter.increment()
                        try await Task.sleep(for: .milliseconds(50))
                        return syntheticTranscription(for: sample)
                    }
                }
            }

            var results: [AnalyzerTranscriptCache.PreparedTranscription] = []
            for try await prepared in group {
                results.append(prepared)
            }
            return results
        }

        #expect(await callCounter.value() == 1)
        #expect(preparedResults.count == 4)
        #expect(preparedResults.allSatisfy { $0.wordCount == preparedResults[0].wordCount })
        #expect(preparedResults.allSatisfy { $0.transcription.fullText == preparedResults[0].transcription.fullText })
    }

    @Test
    func transcriptAnalysisBuildsTimelineWaymarkersFromHypnosisPhrases() {
        let transcription = makeTranscription(
            duration: 120,
            segments: [
                ("welcome settle in and get comfortable", 0, 20),
                ("now begin to relax and close your eyes", 28, 20),
                ("with every breath you go deeper and deeper now", 58, 22),
                ("and when i snap my fingers you follow instantly", 88, 22)
            ]
        )

        let analysis = TranscriptFeatureAnalyzer().analyze(transcription: transcription)

        let inductionWindow = analysis.timelineWindow(at: 35)
        #expect(inductionWindow != nil)
        #expect(inductionWindow?.waymarkerMatches.contains(where: {
            $0.phase == .induction && $0.phrase == "begin to relax"
        }) == true)

        let deepeningWindow = analysis.timelineWindow(at: 68)
        #expect(deepeningWindow?.waymarkerMatches.contains(where: {
            $0.phase == .deepening && $0.phrase == "go deeper"
        }) == true)

        let conditioningWindow = analysis.timelineWindow(at: 98)
        #expect(conditioningWindow?.waymarkerMatches.contains(where: {
            $0.phase == .conditioning && $0.phrase == "when i snap my fingers"
        }) == true)
    }

    @Test
    func transcriptAnalysisRetainsDistinctivePhrasesInSectionMetrics() {
        let transcription = makeTranscription(
            duration: 70,
            segments: [
                ("now begin to relax and begin to relax completely", 0, 22),
                ("you can drift deeper and deeper and go deeper now", 25, 24),
                ("every time you breathe you return to calm", 52, 16)
            ]
        )

        let phases = [
            PhaseSegment(phase: .induction, startTime: 0, endTime: 24, characteristics: "", tranceDepthEstimate: 0.3),
            PhaseSegment(phase: .deepening, startTime: 24, endTime: 50, characteristics: "", tranceDepthEstimate: 0.6),
            PhaseSegment(phase: .conditioning, startTime: 50, endTime: 70, characteristics: "", tranceDepthEstimate: 0.7)
        ]

        let analysis = TranscriptFeatureAnalyzer().analyze(transcription: transcription, phases: phases)

        #expect(analysis.sections[0].topPhrases.contains(where: { $0.phrase == "begin to relax" }))
        #expect(analysis.sections[1].waymarkerMatches.contains(where: {
            $0.phase == .deepening && $0.phrase == "deeper and deeper"
        }))
        #expect(analysis.sections[2].waymarkerMatches.contains(where: {
            $0.phase == .conditioning && $0.phrase == "every time you"
        }))
    }

    @Test
    func measurementHistoryAppendsAcrossRuns() async throws {
        let corpusDirectory = try makeTempDirectory()
        let outputDirectory = corpusDirectory.appending(path: "Output", directoryHint: .isDirectory)
        let datasetDirectory = corpusDirectory.appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
        let audioDirectory = datasetDirectory.appending(path: "audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let file = makeLabeledFile(
            originalFilename: "history.wav",
            storedAudioFilename: "history.wav",
            phases: [
                .init(phase: .preTalk, startTime: 0, endTime: 4),
                .init(phase: .induction, startTime: 4, endTime: 10),
                .init(phase: .deepening, startTime: 10, endTime: 16)
            ]
        )
        try Data("audio".utf8).write(
            to: audioDirectory.appending(path: file.storedAudioFilename),
            options: .atomic
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let example = file.analyzerTrainingExample(
            exportedAt: Date(timeIntervalSince1970: 1_000),
            datasetRelativeAudioPath: "AnalyzerDataset/audio/\(file.storedAudioFilename)",
            datasetRelativeExamplePath: "AnalyzerDataset/examples/\(file.id.uuidString).json"
        )
        try encoder.encode(example).write(
            to: datasetDirectory.appending(path: "dataset.jsonl"),
            options: .atomic
        )

        let optimizer = AnalyzerOptimizer(
            corpusDirectory: corpusDirectory,
            outputDirectory: outputDirectory
        )
        let first = try await optimizer.measure(
            config: AnalyzerConfigLoader.load(),
            evaluationMode: .keywordOnly,
            transcribe: { example in
                syntheticTranscription(for: example)
            }
        )
        let second = try await optimizer.measure(
            config: AnalyzerConfigLoader.load(),
            evaluationMode: .keywordOnly,
            transcribe: { example in
                syntheticTranscription(for: example)
            }
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let history = try decoder.decode(
            AnalyzerTrainingMatchHistory.self,
            from: Data(contentsOf: second.historyURL)
        )

        #expect(first.historyURL == second.historyURL)
        #expect(history.entries.count == 2)
        #expect(history.entries[0].generatedAt <= history.entries[1].generatedAt)
    }

    @Test
    func analyzerConfigDecodesLegacyPayloadWithExpandedRuntimeDefaults() throws {
        let legacyJSON = """
        {
          "version": 1,
          "generation": 0,
          "fitness": 0,
          "keywordPipeline": {
            "weights": { "pre_talk": { "welcome": 1.0 } },
            "contextWindowSeconds": 5,
            "smoothingWindowSize": 5,
            "minimumPhaseDurationSeconds": 20,
            "collapseThresholdFraction": 0.035
          },
          "chunkedAnalyzer": {
            "chunkDurationSeconds": 15.0,
            "chunkOverlapSeconds": 5.0,
            "minChunks": 6,
            "maxChunks": 60,
            "systemInstructions": "demo",
            "fewShotExamples": []
          },
          "prosody": {
            "speechRateWindowSeconds": 3.0,
            "pauseThresholdSeconds": 1.0,
            "deliberatePauseMinSeconds": 3.0,
            "musicOnlyPauseMinSeconds": 5.0
          },
          "techniqueDetection": {
            "sensitivityThreshold": 0.6,
            "minConfidence": 0.3
          },
          "sessionGeneration": {
            "frequencyBands": {
              "hypnosis": { "lower": 0.5, "upper": 10.0 }
            },
            "phaseFrequencyBands": {},
            "transitionSmoothingSeconds": 2.0,
            "intensityCurve": "gentle"
          }
        }
        """

        let config = try JSONDecoder().decode(AnalyzerConfig.self, from: Data(legacyJSON.utf8))

        #expect(config.hybridSelection.chunkedClearWinMargin == 0.05)
        #expect(config.hybridSelection.transcriptSupportWeight == 0.55)
        #expect(config.corpusLearning.learnedPhraseWeightMultiplier == 1.0)
        #expect(config.boundaryRefinement.distancePenaltyWeight == 0.015)
    }

    @Test
    func analyzerConfigLoaderRejectsLowFitnessPublishedConfigs() {
        func makeConfig(fitness: Double) -> AnalyzerConfig {
            AnalyzerConfig(
                fitness: fitness,
                keywordPipeline: .init(
                    weights: ["pre_talk": ["welcome": 1.0]],
                    contextWindowSeconds: 5,
                    smoothingWindowSize: 5,
                    minimumPhaseDurationSeconds: 20,
                    collapseThresholdFraction: 0.035
                ),
                chunkedAnalyzer: .init(
                    chunkDurationSeconds: 15.0,
                    chunkOverlapSeconds: 5.0,
                    minChunks: 6,
                    maxChunks: 60,
                    systemInstructions: "demo",
                    fewShotExamples: []
                ),
                prosody: .init(
                    speechRateWindowSeconds: 3.0,
                    pauseThresholdSeconds: 1.0,
                    deliberatePauseMinSeconds: 3.0,
                    musicOnlyPauseMinSeconds: 5.0
                ),
                techniqueDetection: .init(
                    sensitivityThreshold: 0.6,
                    minConfidence: 0.3
                ),
                sessionGeneration: .init(
                    frequencyBands: ["hypnosis": .init(lower: 0.5, upper: 10.0)],
                    phaseFrequencyBands: [:],
                    transitionSmoothingSeconds: 2.0,
                    intensityCurve: "gentle"
                )
            )
        }

        #expect(!AnalyzerConfigLoader.isUsablePublishedConfig(makeConfig(fitness: 0.09039203848599565)))
        #expect(AnalyzerConfigLoader.isUsablePublishedConfig(makeConfig(fitness: 0.30)))
        #expect(AnalyzerConfigLoader.isUsablePublishedConfig(makeConfig(fitness: 0.72)))
    }

    @Test
    func mutationEngineExploresExpandedRuntimeSearchSpaceWithinSafeBounds() {
        let base = AnalyzerConfig(
            keywordPipeline: .init(
                weights: ["pre_talk": ["welcome": 1.0]],
                contextWindowSeconds: 5,
                smoothingWindowSize: 5,
                minimumPhaseDurationSeconds: 20,
                collapseThresholdFraction: 0.035
            ),
            chunkedAnalyzer: .init(
                chunkDurationSeconds: 15.0,
                chunkOverlapSeconds: 5.0,
                minChunks: 6,
                maxChunks: 60,
                systemInstructions: "demo",
                fewShotExamples: []
            ),
            prosody: .init(
                speechRateWindowSeconds: 3.0,
                pauseThresholdSeconds: 1.0,
                deliberatePauseMinSeconds: 3.0,
                musicOnlyPauseMinSeconds: 5.0
            ),
            techniqueDetection: .init(
                sensitivityThreshold: 0.6,
                minConfidence: 0.3
            ),
            hybridSelection: .init(),
            corpusLearning: .init(),
            boundaryRefinement: .init(),
            sessionGeneration: .init(
                frequencyBands: ["hypnosis": .init(lower: 0.5, upper: 10.0)],
                phaseFrequencyBands: [:],
                transitionSmoothingSeconds: 2.0,
                intensityCurve: "gentle"
            )
        )

        let engine = AnalyzerMutationEngine()

        for _ in 0..<25 {
            let mutated = engine.mutate(base)
            #expect((8.0...45.0).contains(mutated.chunkedAnalyzer.chunkDurationSeconds))
            #expect((1.0...min(mutated.chunkedAnalyzer.chunkDurationSeconds * 0.75, 18.0)).contains(mutated.chunkedAnalyzer.chunkOverlapSeconds))
            #expect(mutated.chunkedAnalyzer.maxChunks >= mutated.chunkedAnalyzer.minChunks)
            #expect((0.0...0.20).contains(mutated.hybridSelection.chunkedClearWinMargin))
            #expect((0.10...1.20).contains(mutated.hybridSelection.transcriptSupportWeight))
            #expect((0.20...3.0).contains(mutated.corpusLearning.learnedKeywordWeightMultiplier))
            #expect((0.0...0.10).contains(mutated.boundaryRefinement.distancePenaltyWeight))
        }
    }

    @Test
    func mutationEngineOnlyMutatesRelevantAxesForKeywordOnlyRuns() {
        let base = AnalyzerConfig(
            keywordPipeline: .init(
                weights: ["pre_talk": ["welcome": 1.0]],
                contextWindowSeconds: 5,
                smoothingWindowSize: 5,
                minimumPhaseDurationSeconds: 20,
                collapseThresholdFraction: 0.035
            ),
            chunkedAnalyzer: .init(
                chunkDurationSeconds: 15.0,
                chunkOverlapSeconds: 5.0,
                minChunks: 6,
                maxChunks: 60,
                systemInstructions: "demo",
                fewShotExamples: []
            ),
            prosody: .init(
                speechRateWindowSeconds: 3.0,
                pauseThresholdSeconds: 1.0,
                deliberatePauseMinSeconds: 3.0,
                musicOnlyPauseMinSeconds: 5.0
            ),
            techniqueDetection: .init(
                sensitivityThreshold: 0.6,
                minConfidence: 0.3
            ),
            hybridSelection: .init(),
            corpusLearning: .init(),
            boundaryRefinement: .init(),
            sessionGeneration: .init(
                frequencyBands: ["hypnosis": .init(lower: 0.5, upper: 10.0)],
                phaseFrequencyBands: [:],
                transitionSmoothingSeconds: 2.0,
                intensityCurve: "gentle"
            )
        )

        let engine = AnalyzerMutationEngine(
            parameters: .init(
                keywordWeightSigma: 0.50,
                contextWindowDelta: 4,
                smoothingWindowDelta: 3,
                minimumPhaseDurationDelta: 8,
                collapseThresholdSigma: 0.40,
                chunkDurationSigma: 0.40,
                chunkOverlapSigma: 0.40,
                chunkCountDelta: 6,
                selectionSigma: 0.40,
                corpusLearningSigma: 0.40,
                boundarySigma: 0.40
            )
        )

        let mutated = engine.mutate(base, for: .keywordOnly)

        #expect(mutated.chunkedAnalyzer.chunkDurationSeconds == base.chunkedAnalyzer.chunkDurationSeconds)
        #expect(mutated.chunkedAnalyzer.chunkOverlapSeconds == base.chunkedAnalyzer.chunkOverlapSeconds)
        #expect(mutated.chunkedAnalyzer.minChunks == base.chunkedAnalyzer.minChunks)
        #expect(mutated.chunkedAnalyzer.maxChunks == base.chunkedAnalyzer.maxChunks)
        #expect(mutated.hybridSelection.chunkedClearWinMargin == base.hybridSelection.chunkedClearWinMargin)
        #expect(mutated.hybridSelection.transcriptSupportWeight == base.hybridSelection.transcriptSupportWeight)
        #expect(
            mutated.corpusLearning.learnedKeywordWeightMultiplier != base.corpusLearning.learnedKeywordWeightMultiplier
                || mutated.boundaryRefinement.distancePenaltyWeight != base.boundaryRefinement.distancePenaltyWeight
                || mutated.keywordPipeline.minimumPhaseDurationSeconds != base.keywordPipeline.minimumPhaseDurationSeconds
                || mutated.keywordPipeline.smoothingWindowSize != base.keywordPipeline.smoothingWindowSize
        )
    }

    @Test
    func mutationEngineRepeatsExactlyWithSeededRandomGenerator() throws {
        let base = makeMutationTestConfig()
        let engine = AnalyzerMutationEngine()
        var firstGenerator = SeededRandomNumberGenerator(seed: 42)
        var secondGenerator = SeededRandomNumberGenerator(seed: 42)

        let first = engine.mutate(base, for: .hybridRuntime, using: &firstGenerator)
        let second = engine.mutate(base, for: .hybridRuntime, using: &secondGenerator)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let firstData = try encoder.encode(first)
        let secondData = try encoder.encode(second)
        #expect(firstData == secondData)
        #expect(firstGenerator.state == secondGenerator.state)
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
        phases: [LabeledFile.LabeledPhase],
        labelerNotes: String = "test"
    ) -> LabeledFile {
        LabeledFile(
            originalFilename: originalFilename,
            storedAudioFilename: storedAudioFilename,
            audioDuration: phases.last?.endTime ?? 30,
            audioSHA256: UUID().uuidString,
            expectedContentType: .hypnosis,
            expectedFrequencyBand: .init(lower: 0.5, upper: 8),
            phases: phases,
            techniques: [],
            labeledAt: Date(timeIntervalSince1970: 1_000),
            labelerNotes: labelerNotes
        )
    }

    private func makeMutationTestConfig() -> AnalyzerConfig {
        AnalyzerConfig(
            keywordPipeline: .init(
                weights: ["pre_talk": ["welcome": 1.0]],
                contextWindowSeconds: 5,
                smoothingWindowSize: 5,
                minimumPhaseDurationSeconds: 20,
                collapseThresholdFraction: 0.035
            ),
            chunkedAnalyzer: .init(
                chunkDurationSeconds: 15.0,
                chunkOverlapSeconds: 5.0,
                minChunks: 6,
                maxChunks: 60,
                systemInstructions: "demo",
                fewShotExamples: []
            ),
            prosody: .init(
                speechRateWindowSeconds: 3.0,
                pauseThresholdSeconds: 1.0,
                deliberatePauseMinSeconds: 3.0,
                musicOnlyPauseMinSeconds: 5.0
            ),
            techniqueDetection: .init(
                sensitivityThreshold: 0.6,
                minConfidence: 0.3
            ),
            hybridSelection: .init(),
            corpusLearning: .init(),
            boundaryRefinement: .init(),
            sessionGeneration: .init(
                frequencyBands: ["hypnosis": .init(lower: 0.5, upper: 10.0)],
                phaseFrequencyBands: [:],
                transitionSmoothingSeconds: 2.0,
                intensityCurve: "gentle"
            )
        )
    }

    nonisolated private func syntheticTranscription(
        for example: AnalyzerOptimizationDataset.Example
    ) -> AudioTranscriptionResult {
        let segments = example.phaseSegments.map { phase -> AudioTranscriptionSegment in
            let text: String
            switch phase.phase {
            case .preTalk:
                text = "welcome settle in relax comfortably"
            case .induction:
                text = "take a deep breath and close your eyes"
            case .fractionation:
                text = "open your eyes and drop back down deeper"
            case .deepening:
                text = "drift deeper and deeper now"
            case .confusion:
                text = "the more you try to follow the more you let go"
            case .therapy:
                text = "allow this healing suggestion to integrate"
            case .suggestions:
                text = "from now on you will feel calm and strong"
            case .eroticSuggestions:
                text = "every warm wave of pleasure carries you deeper"
            case .brainwashing:
                text = "obey now repeat after me obey now"
            case .conditioning:
                text = "every time you breathe you return to calm"
            case .emergence:
                text = "return now bringing awareness back"
            case .transitional:
                text = "continue drifting between phases"
            }
            return AudioTranscriptionSegment(
                text: text,
                timestamp: phase.startTime,
                duration: max(1, phase.endTime - phase.startTime),
                confidence: 0.9
            )
        }

        return AudioTranscriptionResult(
            fullText: segments.map(\.text).joined(separator: " "),
            segments: segments,
            duration: example.duration,
            detectedLanguage: "en"
        )
    }

    private func makeTranscription(
        duration: TimeInterval,
        segments: [(text: String, timestamp: TimeInterval, duration: TimeInterval)]
    ) -> AudioTranscriptionResult {
        AudioTranscriptionResult(
            fullText: segments.map(\.text).joined(separator: " "),
            segments: segments.map { segment in
                AudioTranscriptionSegment(
                    text: segment.text,
                    timestamp: segment.timestamp,
                    duration: segment.duration,
                    confidence: 0.9
                )
            },
            duration: duration,
            detectedLanguage: "en"
        )
    }
}
