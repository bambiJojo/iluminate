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
import UniformTypeIdentifiers

nonisolated enum TrainingCorpusLocation {
    static let visibleDirectoryName = "TrainingCorpus"
    static let hiddenDirectoryName = ".TrainingCorpus"

    static func defaultURL(
        documentsDirectory: URL = .documentsDirectory,
        fileManager: FileManager = .default
    ) -> URL {
        let hiddenURL = documentsDirectory.appending(path: hiddenDirectoryName, directoryHint: .isDirectory)
        let visibleURL = documentsDirectory.appending(path: visibleDirectoryName, directoryHint: .isDirectory)
        let hiddenHasData = hasCorpusData(at: hiddenURL, fileManager: fileManager)
        let visibleHasData = hasCorpusData(at: visibleURL, fileManager: fileManager)

        if hiddenHasData {
            return hiddenURL
        }
        if visibleHasData {
            return visibleURL
        }
        if fileManager.fileExists(atPath: hiddenURL.path()) {
            return hiddenURL
        }
        return visibleURL
    }

    private static func hasCorpusData(at url: URL, fileManager: FileManager) -> Bool {
        let datasetIndexURL = url
            .appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
            .appending(path: "dataset.jsonl")
        if fileManager.fileExists(atPath: datasetIndexURL.path()) {
            return true
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        return contents.contains { item in
            item.pathExtension == "json" || item.lastPathComponent == "Audio"
        }
    }
}

struct TrainingCorpusLoadIssue: Identifiable, Hashable, Sendable {
    let id = UUID()
    let filename: String
    let message: String
}

struct TrainingCorpusSnapshot: Sendable {
    var labeledFiles: [LabeledFile]
    var issues: [TrainingCorpusLoadIssue]
}

struct BatchPhaseImportResult: Sendable {
    let importedFiles: [LabeledFile]
    let skippedFilenames: [String]
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

    init(baseDirectory: URL = TrainingCorpusLocation.defaultURL()) {
        corpusDirectory = baseDirectory
        audioDirectory = baseDirectory.appending(path: "Audio")
        analyzerDatasetDirectory = baseDirectory.appending(path: "AnalyzerDataset")
        analyzerExamplesDirectory = analyzerDatasetDirectory.appending(path: "examples")
        analyzerAudioDirectory = analyzerDatasetDirectory.appending(path: "audio")
        analyzerDatasetIndexURL = analyzerDatasetDirectory.appending(path: "dataset.jsonl")
        analyzerDatasetManifestURL = analyzerDatasetDirectory.appending(path: "dataset_manifest.json")
    }

    /// Every file in this corpus is hypnosis, so the content type is forced.
    ///
    /// Phases are deliberately **not** projected here. This used to rewrite each
    /// one through `labelingPhase` on save, which meant labelling a `pre_talk`,
    /// a `fractionation` or an `erotic_suggestions` and pressing save silently
    /// stored something else — the ten phases the labeller can choose collapsed
    /// to five on the way to disk, taking every `pre_talk → induction` boundary
    /// with them.
    ///
    /// The five-bucket view is still what selects light, and `labelingPhase`
    /// supplies it at the point of use. Removing the codec's copy of this
    /// collapse (952fe80) was not enough on its own: this path runs on every
    /// save regardless of how the value encodes.
    private func normalizedForHypnosisCorpus(_ file: LabeledFile) -> LabeledFile {
        var normalized = file
        normalized.expectedContentType = .hypnosis
        return normalized
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
                let file = normalizedForHypnosisCorpus(try decoder.decode(LabeledFile.self, from: data))
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
            validated = try normalizedForHypnosisCorpus(file).validatedForPersistence()
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
        let sortedFiles = files
            .map(normalizedForHypnosisCorpus)
            .sorted { lhs, rhs in
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
        CorpusPhaseKnowledgeCache.shared.invalidate()
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
    private(set) var hasFinishedInitialLoad = false

    private let store: TrainingCorpusStore
    private let audioDirectory: URL
    let analyzerDatasetDirectory: URL
    let analyzerDatasetIndexURL: URL
    let analyzerDatasetManifestURL: URL

    init(
        baseDirectory: URL = TrainingCorpusLocation.defaultURL(),
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
        defer { hasFinishedInitialLoad = true }
        do {
            let snapshot = try await store.loadAll()
            labeledFiles = snapshot.labeledFiles
            lastLoadIssues = snapshot.issues
            do {
                try await store.rebuildAnalyzerDataset(for: snapshot.labeledFiles)
                try await refreshOfficialTranscriptCaches()
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

    /// Replaces legacy/generated transcript cache entries for recognized audio
    /// as soon as the corpus opens, so every LumeLabel consumer sees the
    /// official bundled text without requiring the user to open each file.
    private func refreshOfficialTranscriptCaches() async throws {
        let corpusDirectory = analyzerDatasetDirectory.deletingLastPathComponent()
        let dataset = try await Task.detached(priority: .utility) {
            try AnalyzerOptimizationDataset.load(from: corpusDirectory)
        }.value
        let cache = AnalyzerTranscriptCache(
            cacheDirectory: dataset.transcriptCacheDirectory
        )

        for example in dataset.examples {
            guard BundledAudioTranscriptCatalog.shared.transcription(
                filename: example.originalFilename,
                duration: example.duration
            ) != nil else {
                continue
            }
            _ = try await cache.transcription(for: example)
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

    func importAudioFolder(from folderURL: URL, labeledAs phase: TrancePhase) async throws -> BatchPhaseImportResult {
        let audioURLs = try audioFiles(in: folderURL)
        guard !audioURLs.isEmpty else {
            throw TrainingCorpusError.invalidLabel("No supported audio files were found in \(folderURL.lastPathComponent).")
        }

        var importedFiles: [LabeledFile] = []
        importedFiles.reserveCapacity(audioURLs.count)

        for url in audioURLs {
            let imported = try await importAudio(from: url)
            var labeled = imported
            labeled.phases = [
                LabeledFile.LabeledPhase(
                    phase: phase,
                    startTime: 0,
                    endTime: imported.audioDuration
                )
            ]
            labeled.labelerNotes = "Silver label: batch folder import as \(phase.rawValue)."
            importedFiles.append(try await save(labeled))
        }

        let importedPaths = Set(audioURLs.map { $0.standardizedFileURL.path })
        let skipped = try files(in: folderURL)
            .filter { !importedPaths.contains($0.standardizedFileURL.path) }
            .map { displayPath(for: $0, relativeTo: folderURL) }
            .sorted()

        return BatchPhaseImportResult(importedFiles: importedFiles, skippedFilenames: skipped)
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

    private func audioFiles(in folderURL: URL) throws -> [URL] {
        try files(in: folderURL)
            .filter(Self.isSupportedAudioFile)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func files(in folderURL: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .typeIdentifierKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            throw TrainingCorpusError.directoryEnumerationFailed(folderURL, underlying: "Could not open folder.")
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isDirectory == true {
                    continue
                }
                files.append(url)
            } catch {
                throw TrainingCorpusError.directoryEnumerationFailed(folderURL, underlying: error.localizedDescription)
            }
        }
        return files
    }

    private func displayPath(for url: URL, relativeTo folderURL: URL) -> String {
        let folderPath = folderURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        if filePath.hasPrefix(folderPath + "/") {
            return String(filePath.dropFirst(folderPath.count + 1))
        }
        return url.lastPathComponent
    }

    private nonisolated static func isSupportedAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if supportedAudioExtensions.contains(ext) {
            return true
        }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .audio) {
            return true
        }
        do {
            let values = try url.resourceValues(forKeys: [.typeIdentifierKey])
            if let identifier = values.typeIdentifier,
               let type = UTType(identifier),
               type.conforms(to: .audio) {
                return true
            }
        } catch {
            return false
        }
        return false
    }

    private nonisolated static let supportedAudioExtensions: Set<String> = [
        "aac", "aif", "aiff", "caf", "flac", "m4a", "mp3", "mp4", "wav"
    ]
}
