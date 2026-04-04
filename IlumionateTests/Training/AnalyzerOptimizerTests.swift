//
//  AnalyzerOptimizerTests.swift
//  IlumionateTests
//
//  Coverage for analyzer optimizer dataset, metrics, and artifact output.
//

import Testing
import Foundation
@testable import Ilumionate

struct AnalyzerOptimizerTests {
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
        #expect(metrics.overallScore == 1.0)
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
            audioDuration: phases.last?.endTime ?? 30,
            audioSHA256: UUID().uuidString,
            expectedContentType: .hypnosis,
            expectedFrequencyBand: .init(lower: 0.5, upper: 8),
            phases: phases,
            techniques: [],
            labeledAt: Date(timeIntervalSince1970: 1_000),
            labelerNotes: "test"
        )
    }

    private func syntheticTranscription(
        for example: AnalyzerOptimizationDataset.Example
    ) -> AudioTranscriptionResult {
        let segments = example.phaseSegments.map { phase -> AudioTranscriptionSegment in
            let text: String
            switch phase.phase {
            case .preTalk:
                text = "welcome settle in relax comfortably"
            case .induction:
                text = "take a deep breath and close your eyes"
            case .deepening:
                text = "drift deeper and deeper now"
            case .therapy:
                text = "allow this healing suggestion to integrate"
            case .suggestions:
                text = "from now on you will feel calm and strong"
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
}
