//
//  TrainingCorpusManager.swift
//  Ilumionate
//
//  Async coordinator for ground-truth labeled audio files stored in Documents/TrainingCorpus/.
//

import Foundation
import Observation
import AVFoundation
import CoreMedia

struct TrainingCorpusLoadIssue: Identifiable, Hashable, Sendable {
    let id = UUID()
    let filename: String
    let message: String
}

struct TrainingCorpusSnapshot: Sendable {
    var labeledFiles: [LabeledFile]
    var issues: [TrainingCorpusLoadIssue]
}

nonisolated struct AnalyzerDatasetManifest: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let exampleCount: Int
    let datasetIndexFilename: String
    let examplesDirectoryName: String
    let audioDirectoryName: String
    let exampleFiles: [String]
}

enum TrainingCorpusError: LocalizedError, Sendable {
    case directoryCreationFailed(URL, underlying: String)
    case directoryEnumerationFailed(URL, underlying: String)
    case audioCopyFailed(String)
    case audioDurationUnavailable(String)
    case jsonWriteFailed(String)
    case jsonDeleteFailed(String)
    case audioDeleteFailed(String)
    case datasetWriteFailed(String)
    case datasetAudioSyncFailed(String)
    case fileNotFound(UUID)
    case invalidLabel(String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let url, let underlying):
            return "Could not create corpus directory at \(url.path()): \(underlying)"
        case .directoryEnumerationFailed(let url, let underlying):
            return "Could not read corpus directory at \(url.path()): \(underlying)"
        case .audioCopyFailed(let filename):
            return "Could not import audio file \(filename)."
        case .audioDurationUnavailable(let filename):
            return "Could not determine the duration of \(filename)."
        case .jsonWriteFailed(let filename):
            return "Could not save labels for \(filename)."
        case .jsonDeleteFailed(let filename):
            return "Could not delete label file \(filename)."
        case .audioDeleteFailed(let filename):
            return "Could not delete stored audio \(filename)."
        case .datasetWriteFailed(let filename):
            return "Could not write analyzer dataset file \(filename)."
        case .datasetAudioSyncFailed(let filename):
            return "Could not sync analyzer dataset audio for \(filename)."
        case .fileNotFound:
            return "The selected labeled file no longer exists."
        case .invalidLabel(let message):
            return message
        }
    }
}

actor TrainingCorpusStore {
    private let corpusDirectory: URL
    private let audioDirectory: URL
    private let analyzerDatasetDirectory: URL
    private let analyzerExamplesDirectory: URL
    private let analyzerAudioDirectory: URL
    private let analyzerDatasetIndexURL: URL
    private let analyzerDatasetManifestURL: URL

    init(baseDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus")) {
        corpusDirectory = baseDirectory
        audioDirectory = baseDirectory.appending(path: "Audio")
        analyzerDatasetDirectory = baseDirectory.appending(path: "AnalyzerDataset")
        analyzerExamplesDirectory = analyzerDatasetDirectory.appending(path: "examples")
        analyzerAudioDirectory = analyzerDatasetDirectory.appending(path: "audio")
        analyzerDatasetIndexURL = analyzerDatasetDirectory.appending(path: "dataset.jsonl")
        analyzerDatasetManifestURL = analyzerDatasetDirectory.appending(path: "dataset_manifest.json")
    }

    func loadAll() throws -> TrainingCorpusSnapshot {
        try ensureDirectories()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: corpusDirectory,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw TrainingCorpusError.directoryEnumerationFailed(corpusDirectory, underlying: error.localizedDescription)
        }

        var labeledFiles: [LabeledFile] = []
        var issues: [TrainingCorpusLoadIssue] = []

        for url in files where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                let file = try decoder.decode(LabeledFile.self, from: data)
                labeledFiles.append(file)
            } catch {
                issues.append(
                    TrainingCorpusLoadIssue(
                        filename: url.lastPathComponent,
                        message: error.localizedDescription
                    )
                )
            }
        }

        labeledFiles.sort { $0.labeledAt > $1.labeledAt }
        return TrainingCorpusSnapshot(labeledFiles: labeledFiles, issues: issues)
    }

    func save(_ file: LabeledFile) throws -> LabeledFile {
        try ensureDirectories()

        let validated: LabeledFile
        do {
            validated = try file.validatedForPersistence()
        } catch {
            throw TrainingCorpusError.invalidLabel(error.localizedDescription)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let url = jsonURL(for: validated)
        do {
            let data = try encoder.encode(validated)
            try data.write(to: url, options: .atomic)
        } catch {
            throw TrainingCorpusError.jsonWriteFailed(validated.audioFilename)
        }

        let snapshot = try loadAll()
        try rebuildAnalyzerDataset(for: snapshot.labeledFiles)
        return validated
    }

    func importAudio(from sourceURL: URL) async throws -> LabeledFile {
        try ensureDirectories()

        let fileID = UUID()
        let storedFilename = makeStoredAudioFilename(for: fileID, sourceURL: sourceURL)
        let destinationURL = audioDirectory.appending(path: storedFilename)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw TrainingCorpusError.audioCopyFailed(sourceURL.lastPathComponent)
        }

        let duration = try await loadDuration(for: destinationURL, originalFilename: sourceURL.lastPathComponent)
        let sha256 = try LabeledFile.computeSHA256(url: destinationURL)

        let file = LabeledFile(
            id: fileID,
            version: 2,
            originalFilename: sourceURL.lastPathComponent,
            storedAudioFilename: storedFilename,
            audioDuration: duration,
            audioSHA256: sha256,
            expectedContentType: .hypnosis,
            expectedFrequencyBand: .init(lower: 0.5, upper: 10.0),
            phases: [],
            techniques: [],
            labeledAt: Date(),
            labelerNotes: ""
        )

        return try save(file)
    }

    func delete(_ file: LabeledFile, remainingFiles: [LabeledFile]) throws {
        let jsonURL = jsonURL(for: file)
        do {
            if FileManager.default.fileExists(atPath: jsonURL.path()) {
                try FileManager.default.removeItem(at: jsonURL)
            }
        } catch {
            throw TrainingCorpusError.jsonDeleteFailed(file.audioFilename)
        }

        let isStillReferenced = remainingFiles.contains { $0.storedAudioFilename == file.storedAudioFilename }
        if isStillReferenced {
            try rebuildAnalyzerDataset(for: remainingFiles)
            return
        }

        let storedAudioURL = audioDirectory.appending(path: file.storedAudioFilename)
        do {
            if FileManager.default.fileExists(atPath: storedAudioURL.path()) {
                try FileManager.default.removeItem(at: storedAudioURL)
            }
        } catch {
            throw TrainingCorpusError.audioDeleteFailed(file.storedAudioFilename)
        }

        try rebuildAnalyzerDataset(for: remainingFiles)
    }

    func rebuildAnalyzerDataset(for files: [LabeledFile]) throws {
        try ensureDirectories()

        let exportedAt = Date()
        let sortedFiles = files.sorted { lhs, rhs in
            if lhs.labeledAt == rhs.labeledAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.labeledAt > rhs.labeledAt
        }
        let exportableFiles = sortedFiles.filter { !$0.phases.isEmpty }

        let expectedAudioFilenames = Set(exportableFiles.map(\.storedAudioFilename))
        let expectedExampleFilenames = Set(exportableFiles.map { "\($0.id.uuidString).json" })

        for storedAudioFilename in expectedAudioFilenames {
            try syncAnalyzerDatasetAudio(named: storedAudioFilename)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let compactEncoder = JSONEncoder()
        compactEncoder.dateEncodingStrategy = .iso8601

        var datasetLines: [String] = []
        datasetLines.reserveCapacity(exportableFiles.count)

        // Only export files with at least one labeled phase into the analyzer dataset.
        // Newly imported audio stays in the corpus, but should not produce dataset issues
        // until the labeler actually creates training labels.
        for file in exportableFiles {
            let exampleFilename = "\(file.id.uuidString).json"
            let example = file.analyzerTrainingExample(
                exportedAt: exportedAt,
                datasetRelativeAudioPath: "audio/\(file.storedAudioFilename)",
                datasetRelativeExamplePath: "examples/\(exampleFilename)"
            )

            do {
                let exampleData = try encoder.encode(example)
                try exampleData.write(
                    to: analyzerExamplesDirectory.appending(path: exampleFilename),
                    options: .atomic
                )

                let lineData = try compactEncoder.encode(example)
                guard let line = String(data: lineData, encoding: .utf8) else {
                    throw TrainingCorpusError.datasetWriteFailed(exampleFilename)
                }
                datasetLines.append(line)
            } catch let error as TrainingCorpusError {
                throw error
            } catch {
                throw TrainingCorpusError.datasetWriteFailed(exampleFilename)
            }
        }

        do {
            let datasetData = Data(datasetLines.joined(separator: "\n").utf8)
            try datasetData.write(to: analyzerDatasetIndexURL, options: .atomic)

            let manifest = AnalyzerDatasetManifest(
                schemaVersion: AnalyzerDatasetManifest.currentSchemaVersion,
                generatedAt: exportedAt,
                exampleCount: exportableFiles.count,
                datasetIndexFilename: analyzerDatasetIndexURL.lastPathComponent,
                examplesDirectoryName: analyzerExamplesDirectory.lastPathComponent,
                audioDirectoryName: analyzerAudioDirectory.lastPathComponent,
                exampleFiles: exportableFiles.map { "examples/\($0.id.uuidString).json" }
            )
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: analyzerDatasetManifestURL, options: .atomic)
        } catch {
            throw TrainingCorpusError.datasetWriteFailed(analyzerDatasetIndexURL.lastPathComponent)
        }

        try removeStaleExports(
            in: analyzerExamplesDirectory,
            keeping: expectedExampleFilenames
        )
        try removeStaleExports(
            in: analyzerAudioDirectory,
            keeping: expectedAudioFilenames
        )
    }

    private func ensureDirectories() throws {
        let fm = FileManager.default
        for directory in [
            corpusDirectory,
            audioDirectory,
            analyzerDatasetDirectory,
            analyzerExamplesDirectory,
            analyzerAudioDirectory
        ] {
            guard !fm.fileExists(atPath: directory.path()) else { continue }
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw TrainingCorpusError.directoryCreationFailed(directory, underlying: error.localizedDescription)
            }
        }
    }

    private func jsonURL(for file: LabeledFile) -> URL {
        corpusDirectory.appending(path: "\(file.id.uuidString).json")
    }

    private func makeStoredAudioFilename(for id: UUID, sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension
        if ext.isEmpty {
            return id.uuidString
        }
        return "\(id.uuidString).\(ext)"
    }

    private func loadDuration(for url: URL, originalFilename: String) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else {
                throw TrainingCorpusError.audioDurationUnavailable(originalFilename)
            }
            return seconds
        } catch let error as TrainingCorpusError {
            throw error
        } catch {
            throw TrainingCorpusError.audioDurationUnavailable(originalFilename)
        }
    }

    private func syncAnalyzerDatasetAudio(named storedAudioFilename: String) throws {
        let sourceURL = audioDirectory.appending(path: storedAudioFilename)
        let destinationURL = analyzerAudioDirectory.appending(path: storedAudioFilename)
        let fm = FileManager.default

        guard fm.fileExists(atPath: sourceURL.path()) else {
            throw TrainingCorpusError.datasetAudioSyncFailed(storedAudioFilename)
        }

        if fm.fileExists(atPath: destinationURL.path()) {
            do {
                try fm.removeItem(at: destinationURL)
            } catch {
                throw TrainingCorpusError.datasetAudioSyncFailed(storedAudioFilename)
            }
        }

        do {
            try fm.linkItem(at: sourceURL, to: destinationURL)
        } catch {
            do {
                try fm.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                throw TrainingCorpusError.datasetAudioSyncFailed(storedAudioFilename)
            }
        }
    }

    private func removeStaleExports(in directory: URL, keeping filenames: Set<String>) throws {
        let fm = FileManager.default

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            throw TrainingCorpusError.directoryEnumerationFailed(directory, underlying: error.localizedDescription)
        }

        for url in contents where !filenames.contains(url.lastPathComponent) {
            do {
                try fm.removeItem(at: url)
            } catch {
                throw TrainingCorpusError.datasetWriteFailed(url.lastPathComponent)
            }
        }
    }
}

@MainActor
@Observable
final class TrainingCorpusManager {
    static let shared = TrainingCorpusManager()

    var labeledFiles: [LabeledFile] = []
    var lastLoadIssues: [TrainingCorpusLoadIssue] = []

    private let store: TrainingCorpusStore
    private let audioDirectory: URL
    let analyzerDatasetDirectory: URL
    let analyzerDatasetIndexURL: URL
    let analyzerDatasetManifestURL: URL

    init(
        baseDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus"),
        store: TrainingCorpusStore? = nil,
        autoLoad: Bool = true
    ) {
        self.store = store ?? TrainingCorpusStore(baseDirectory: baseDirectory)
        self.audioDirectory = baseDirectory.appending(path: "Audio")
        self.analyzerDatasetDirectory = baseDirectory.appending(path: "AnalyzerDataset")
        self.analyzerDatasetIndexURL = analyzerDatasetDirectory.appending(path: "dataset.jsonl")
        self.analyzerDatasetManifestURL = analyzerDatasetDirectory.appending(path: "dataset_manifest.json")
        if autoLoad {
            Task { await reload() }
        }
    }

    func reload() async {
        do {
            let snapshot = try await store.loadAll()
            labeledFiles = snapshot.labeledFiles
            lastLoadIssues = snapshot.issues
            do {
                try await store.rebuildAnalyzerDataset(for: snapshot.labeledFiles)
            } catch {
                lastLoadIssues.append(
                    TrainingCorpusLoadIssue(
                        filename: analyzerDatasetIndexURL.lastPathComponent,
                        message: error.localizedDescription
                    )
                )
            }
        } catch {
            labeledFiles = []
            lastLoadIssues = [
                TrainingCorpusLoadIssue(filename: "TrainingCorpus", message: error.localizedDescription)
            ]
        }
    }

    func file(withID id: LabeledFile.ID) -> LabeledFile? {
        labeledFiles.first { $0.id == id }
    }

    func save(_ file: LabeledFile) async throws -> LabeledFile {
        let merged = file.mergedForSave(over: self.file(withID: file.id))
        let saved = try await store.save(merged)
        upsert(saved)
        return saved
    }

    func importAudio(from sourceURL: URL) async throws -> LabeledFile {
        let file = try await store.importAudio(from: sourceURL)
        upsert(file)
        return file
    }

    func delete(_ file: LabeledFile) async throws {
        let remainingFiles = labeledFiles.filter { $0.id != file.id }
        try await store.delete(file, remainingFiles: remainingFiles)
        labeledFiles = remainingFiles.sorted { $0.labeledAt > $1.labeledAt }
    }

    func audioURL(for file: LabeledFile) -> URL {
        audioDirectory.appending(path: file.storedAudioFilename)
    }

    private func upsert(_ file: LabeledFile) {
        if let index = labeledFiles.firstIndex(where: { $0.id == file.id }) {
            labeledFiles[index] = file
        } else {
            labeledFiles.append(file)
        }
        labeledFiles.sort { $0.labeledAt > $1.labeledAt }
    }
}
