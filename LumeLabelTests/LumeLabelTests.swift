//
//  LumeLabelTests.swift
//  LumeLabelTests
//

import Foundation
import Testing
@testable import LumeLabel

struct LumeLabelTests {
    @Test
    func legacyCorpusJSONDecodesIntoNewAudioFields() throws {
        let json = """
        {
          "id": "D7C0DB3C-4C62-45CE-B521-3122C994A2C1",
          "version": 1,
          "audioFilename": "legacy.wav",
          "audioDuration": 42.0,
          "audioSHA256": "abc123",
          "expectedContentType": "hypnosis",
          "expectedFrequencyBand": {
            "lower": 0.5,
            "upper": 8.0
          },
          "phases": [],
          "techniques": [],
          "labeledAt": "2026-04-01T00:00:00Z",
          "labelerNotes": ""
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(LabeledFile.self, from: Data(json.utf8))

        #expect(file.originalFilename == "legacy.wav")
        #expect(file.storedAudioFilename == "legacy.wav")
        #expect(file.audioFilename == "legacy.wav")
    }

    @Test
    func phaseValidationRejectsGapsAndOverlaps() throws {
        let base = makeFile(phases: [
            .init(phase: .preTalk, startTime: 0, endTime: 10),
            .init(phase: .induction, startTime: 12, endTime: 20)
        ])

        do {
            _ = try base.validatedForPersistence()
            Issue.record("Expected a phase gap validation failure.")
        } catch let error as LabeledFile.ValidationError {
            #expect(error == .phaseGap(index: 1, previousEnd: 10, nextStart: 12))
        }

        let overlapping = makeFile(phases: [
            .init(phase: .preTalk, startTime: 0, endTime: 10),
            .init(phase: .induction, startTime: 9, endTime: 20)
        ])

        do {
            _ = try overlapping.validatedForPersistence()
            Issue.record("Expected a phase overlap validation failure.")
        } catch let error as LabeledFile.ValidationError {
            #expect(error == .phaseOverlap(index: 1, previousEnd: 10, nextStart: 9))
        }
    }

    @Test
    @MainActor
    func importUsesUniqueStoredFilenamesAndDeleteOnlyRemovesUnreferencedAudio() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)

        let sourceA = try makeWAVFile(
            at: baseDirectory.appending(path: "A/clip.wav"),
            frequency: 220
        )
        let sourceB = try makeWAVFile(
            at: baseDirectory.appending(path: "B/clip.wav"),
            frequency: 440
        )

        let first = try await manager.importAudio(from: sourceA)
        let second = try await manager.importAudio(from: sourceB)

        #expect(first.originalFilename == "clip.wav")
        #expect(second.originalFilename == "clip.wav")
        #expect(first.storedAudioFilename != second.storedAudioFilename)

        let secondURL = manager.audioURL(for: second)
        #expect(FileManager.default.fileExists(atPath: secondURL.path()))

        try await manager.delete(first)

        #expect(!FileManager.default.fileExists(atPath: manager.audioURL(for: first).path()))
        #expect(FileManager.default.fileExists(atPath: secondURL.path()))
    }

    @Test
    @MainActor
    func saveMergesAgainstLatestStoredMetadata() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "merge/source.wav"),
            frequency: 330
        )

        let imported = try await manager.importAudio(from: source)
        var edited = imported
        edited.originalFilename = "mutated.wav"
        edited.storedAudioFilename = "different.wav"
        edited.audioSHA256 = "tampered"
        edited.audioDuration = 1
        edited.labelerNotes = "edited"

        let saved = try await manager.save(edited)

        #expect(saved.originalFilename == imported.originalFilename)
        #expect(saved.storedAudioFilename == imported.storedAudioFilename)
        #expect(saved.audioSHA256 == imported.audioSHA256)
        #expect(saved.audioDuration == imported.audioDuration)
        #expect(saved.labelerNotes == "edited")
    }

    @Test
    @MainActor
    func corpusNormalizationForcesHypnosisContentType() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "normalize/source.wav"),
            frequency: 330
        )

        let imported = try await manager.importAudio(from: source)
        var edited = imported
        edited.expectedContentType = .asmr
        edited.phases = [
            .init(phase: .preTalk, startTime: 0, endTime: imported.audioDuration)
        ]

        let saved = try await manager.save(edited)
        #expect(saved.expectedContentType == .hypnosis)

        await manager.reload()
        #expect(manager.labeledFiles.first?.expectedContentType == .hypnosis)

        let dataset = try AnalyzerOptimizationDataset.load(from: baseDirectory)
        #expect(dataset.examples.first?.example.labels.contentType == .hypnosis)
    }

    @Test
    @MainActor
    func importedUnlabeledAudioIsExcludedFromAnalyzerDataset() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "dataset/unlabeled.wav"),
            frequency: 330
        )

        _ = try await manager.importAudio(from: source)

        let datasetIndexURL = manager.analyzerDatasetIndexURL
        let datasetManifestURL = manager.analyzerDatasetManifestURL

        #expect(FileManager.default.fileExists(atPath: datasetIndexURL.path()))
        #expect(FileManager.default.fileExists(atPath: datasetManifestURL.path()))
        #expect((try String(contentsOf: datasetIndexURL)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            AnalyzerDatasetManifest.self,
            from: Data(contentsOf: datasetManifestURL)
        )
        let dataset = try AnalyzerOptimizationDataset.load(from: baseDirectory)

        #expect(manifest.exampleCount == 0)
        #expect(manifest.exampleFiles.isEmpty)
        #expect(dataset.examples.isEmpty)
        #expect(dataset.issues.isEmpty)
    }

    @Test
    @MainActor
    func batchFolderImportLabelsAudioFilesAsOnePhaseAndSkipsUnsupportedFiles() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let sourceDirectory = baseDirectory.appending(path: ".inductions", directoryHint: .isDirectory)
        let first = try makeWAVFile(at: sourceDirectory.appending(path: "deepener-a.wav"), frequency: 220)
        let second = try makeWAVFile(at: sourceDirectory.appending(path: "deepener-b.wav"), frequency: 440)
        let nested = try makeWAVFile(at: sourceDirectory.appending(path: "nested/deepener-c.wav"), frequency: 550)
        try Data("not audio".utf8).write(to: sourceDirectory.appending(path: "notes.txt"), options: .atomic)
        try Data("not audio".utf8).write(to: sourceDirectory.appending(path: "nested/readme.md"), options: .atomic)

        let result = try await manager.importAudioFolder(from: sourceDirectory, labeledAs: .deepening)

        #expect(result.importedFiles.map(\.originalFilename) == [
            first.lastPathComponent,
            second.lastPathComponent,
            nested.lastPathComponent
        ])
        #expect(result.skippedFilenames == ["nested/readme.md", "notes.txt"])
        #expect(manager.labeledFiles.count == 3)

        for file in result.importedFiles {
            let phase = try #require(file.phases.first)
            #expect(file.phases.count == 1)
            #expect(phase.phase == .deepening)
            #expect(phase.startTime == 0)
            #expect(abs(phase.endTime - file.audioDuration) < 0.001)
            #expect(file.labelerNotes.contains("Silver label"))
        }

        let dataset = try AnalyzerOptimizationDataset.load(from: baseDirectory)
        #expect(dataset.examples.count == 3)
        #expect(dataset.examples.allSatisfy { $0.example.labels.phaseOrder == [.deepening] })
    }

    @Test
    func trancePhaseExpansionHasStableOrderAndNames() {
        #expect(TrancePhase.orderedHypnosisPhases == [
            .induction,
            .deepening,
            .suggestions,
            .brainwashing,
            .emergence
        ])

        #expect(TrancePhase.fractionation.displayName == "Fractionation")
        #expect(TrancePhase.confusion.displayName == "Confusion")
        #expect(TrancePhase.suggestions.displayName == "Suggestions")
        #expect(TrancePhase.brainwashing.displayName == "Brainwashing")
        #expect(TrancePhase.preTalk.labelingPhase == .induction)
        #expect(TrancePhase.fractionation.labelingPhase == .deepening)
        #expect(TrancePhase.confusion.labelingPhase == .deepening)
        #expect(TrancePhase.therapy.labelingPhase == .suggestions)
        #expect(TrancePhase.eroticSuggestions.labelingPhase == .suggestions)
        #expect(TrancePhase.conditioning.labelingPhase == .suggestions)
    }

    @Test
    func legacyContentSpecificPhasesDecodeAsSuggestions() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        for rawValue in ["therapeutic_work", "erotic_suggestions", "post_hypnotic_conditioning"] {
            let decoded = try decoder.decode(TrancePhase.self, from: Data("\"\(rawValue)\"".utf8))
            #expect(decoded == .suggestions)

            let encoded = try String(data: encoder.encode(TrancePhase(rawValue: rawValue) ?? .suggestions), encoding: .utf8)
            #expect(encoded == "\"suggestions\"")
        }
    }

    @Test
    func legacyTechniquePhasesDecodeAsDeepening() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        for rawValue in ["fractionation", "confusion"] {
            let decoded = try decoder.decode(TrancePhase.self, from: Data("\"\(rawValue)\"".utf8))
            #expect(decoded == .deepening)

            let encoded = try String(data: encoder.encode(TrancePhase(rawValue: rawValue) ?? .deepening), encoding: .utf8)
            #expect(encoded == "\"deepening\"")
        }
    }

    @Test
    @MainActor
    func saveCanonicalizesLegacyContentPhasesInAnalyzerDataset() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "expanded/source.wav"),
            frequency: 220
        )

        let imported = try await manager.importAudio(from: source)
        let duration = imported.audioDuration
        let quarter = duration / 4
        var labeled = imported
        labeled.phases = [
            .init(phase: .induction, startTime: 0, endTime: quarter),
            .init(phase: .fractionation, startTime: quarter, endTime: quarter * 2),
            .init(phase: .eroticSuggestions, startTime: quarter * 2, endTime: quarter * 3),
            .init(phase: .brainwashing, startTime: quarter * 3, endTime: duration)
        ]

        _ = try await manager.save(labeled)
        let dataset = try AnalyzerOptimizationDataset.load(from: baseDirectory)
        let phases = dataset.examples.first?.example.labels.phaseSegments.map(\.phase) ?? []

        #expect(phases == [.induction, .deepening, .suggestions, .brainwashing])
    }

    @Test
    @MainActor
    func saveWritesAnalyzerDatasetWithAudioAndTimeline() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "dataset/source.wav"),
            frequency: 330
        )

        let imported = try await manager.importAudio(from: source)
        var labeled = imported
        let midpoint = imported.audioDuration / 2
        labeled.phases = [
            .init(phase: .preTalk, startTime: 0, endTime: midpoint),
            .init(phase: .suggestions, startTime: midpoint, endTime: imported.audioDuration)
        ]
        labeled.labelerNotes = "Ground truth export"

        let saved = try await manager.save(labeled)

        let datasetIndexURL = manager.analyzerDatasetIndexURL
        let datasetManifestURL = manager.analyzerDatasetManifestURL
        let datasetAudioURL = manager.analyzerDatasetDirectory
            .appending(path: "audio")
            .appending(path: saved.storedAudioFilename)

        #expect(FileManager.default.fileExists(atPath: datasetIndexURL.path()))
        #expect(FileManager.default.fileExists(atPath: datasetManifestURL.path()))
        #expect(FileManager.default.fileExists(atPath: datasetAudioURL.path()))

        let datasetLines = try String(contentsOf: datasetIndexURL)
            .split(separator: "\n")
            .map(String.init)
        #expect(datasetLines.count == 1)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let example = try decoder.decode(
            AnalyzerTrainingExample.self,
            from: Data(datasetLines[0].utf8)
        )
        let manifest = try decoder.decode(
            AnalyzerDatasetManifest.self,
            from: Data(contentsOf: datasetManifestURL)
        )

        #expect(example.exampleID == saved.id)
        #expect(example.audio.datasetRelativePath == "audio/\(saved.storedAudioFilename)")
        #expect(example.labels.phasePoints.count == 2)
        #expect(example.labels.phaseSegments.count == 2)
        #expect(example.labels.hasCompletePhaseCoverage)
        #expect(example.labels.labelerNotes == "Ground truth export")
        #expect(example.labels.denseTimeline.contains { $0.phase == .preTalk })
        #expect(example.labels.denseTimeline.contains { $0.phase == .suggestions })
        #expect(manifest.exampleCount == 1)
        #expect(manifest.exampleFiles == ["examples/\(saved.id.uuidString).json"])
    }

    @Test
    func transcriptInsightSummarizesSectionWordsAndRate() throws {
        let transcription = AudioTranscriptionResult(
            fullText: "relax deeper relax drift deeper relax calm calm focus",
            segments: [
                .init(text: "relax deeper relax", timestamp: 0, duration: 3, confidence: -0.2),
                .init(text: "drift deeper relax", timestamp: 3, duration: 3, confidence: -0.3),
                .init(text: "calm calm focus", timestamp: 6, duration: 3, confidence: -0.4)
            ],
            duration: 9,
            detectedLanguage: "en"
        )

        let insight = try #require(
            LabelingDetailEditor.makeTranscriptInsight(
                id: UUID(),
                phase: .deepening,
                startTime: 0,
                endTime: 9,
                transcription: transcription
            )
        )

        #expect(insight.wordCount == 9)
        #expect(insight.uniqueWordCount == 5)
        #expect(insight.wordsPerMinute == 60)
        #expect(insight.excerpts.count == 3)
        #expect(insight.topWords.prefix(3).map(\.word) == ["relax", "calm", "deeper"])
        #expect(insight.topWords.prefix(3).map(\.count) == [3, 2, 2])
    }

    @Test
    func transcriptInsightClipsToSelectedPhaseWindow() throws {
        let transcription = AudioTranscriptionResult(
            fullText: "begin settle deeper deeper awake again",
            segments: [
                .init(text: "begin settle", timestamp: 0, duration: 2, confidence: -0.2),
                .init(text: "deeper deeper", timestamp: 2, duration: 2, confidence: -0.2),
                .init(text: "awake again", timestamp: 4, duration: 2, confidence: -0.2)
            ],
            duration: 6,
            detectedLanguage: "en"
        )

        let insight = try #require(
            LabelingDetailEditor.makeTranscriptInsight(
                id: UUID(),
                phase: .deepening,
                startTime: 1.5,
                endTime: 4.5,
                transcription: transcription
            )
        )

        #expect(insight.excerpts.count == 3)
        #expect(insight.wordCount == 6)
        #expect(insight.topWords.first?.word == "deeper")
        #expect(insight.topWords.first?.count == 2)
        #expect(insight.longestPause == 0)
    }

    @Test
    @MainActor
    func corruptedJSONIsReportedInsteadOfSilentlyDropped() async throws {
        let baseDirectory = try makeTempDirectory()
        let invalidJSONURL = baseDirectory.appending(path: "broken.json")
        try Data("{ invalid json".utf8).write(to: invalidJSONURL, options: .atomic)

        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        await manager.reload()

        #expect(manager.labeledFiles.isEmpty)
        #expect(manager.lastLoadIssues.count == 1)
        #expect(manager.lastLoadIssues[0].filename == "broken.json")
    }

    private func makeFile(phases: [LabeledFile.LabeledPhase]) -> LabeledFile {
        LabeledFile(
            originalFilename: "sample.wav",
            storedAudioFilename: "stored.wav",
            audioDuration: 60,
            audioSHA256: "hash",
            expectedContentType: .hypnosis,
            expectedFrequencyBand: .init(lower: 0.5, upper: 8),
            phases: phases,
            techniques: [],
            labeledAt: Date(),
            labelerNotes: ""
        )
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeWAVFile(at url: URL, frequency: Double) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let sampleRate = 8_000
        let sampleCount = 16_000
        let bitsPerSample = 16
        let channels = 1
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = sampleCount * blockAlign

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(UInt32(36 + dataSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(channels))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(byteRate))
        data.appendLE(UInt16(blockAlign))
        data.appendLE(UInt16(bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.appendLE(UInt32(dataSize))

        for index in 0..<sampleCount {
            let theta = Double(index) / Double(sampleRate) * frequency * .pi * 2
            let sample = Int16((sin(theta) * 0.4 * Double(Int16.max)).rounded())
            data.appendLE(sample)
        }

        try data.write(to: url, options: .atomic)
        return url
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(UnsafeBufferPointer(start: &littleEndian, count: 1))
    }

    mutating func appendLE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(UnsafeBufferPointer(start: &littleEndian, count: 1))
    }

    mutating func appendLE(_ value: Int16) {
        var littleEndian = value.littleEndian
        append(UnsafeBufferPointer(start: &littleEndian, count: 1))
    }
}
