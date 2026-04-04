//
//  AnalyzerOptimizationDataset.swift
//  Ilumionate
//
//  Loads and validates analyzer-training examples exported by LumeLabel.
//

import Foundation
import CryptoKit

struct AnalyzerOptimizationDatasetIssue: Codable, Identifiable, Hashable, Sendable {
    enum Severity: String, Codable, Sendable {
        case warning
        case error
    }

    let id: UUID
    let severity: Severity
    let exampleID: UUID?
    let filename: String
    let message: String

    init(
        id: UUID = UUID(),
        severity: Severity,
        exampleID: UUID? = nil,
        filename: String,
        message: String
    ) {
        self.id = id
        self.severity = severity
        self.exampleID = exampleID
        self.filename = filename
        self.message = message
    }
}

struct AnalyzerOptimizationDataset: Sendable {
    struct Example: Identifiable, Sendable {
        let example: AnalyzerTrainingExample
        let audioURL: URL

        var id: UUID { example.exampleID }
        var duration: TimeInterval { example.audio.durationSeconds }
        var originalFilename: String { example.audio.originalFilename }
        var phaseSegments: [AnalyzerTrainingExample.PhaseSegment] { example.labels.phaseSegments }
        var denseTimeline: [AnalyzerTrainingExample.TimelineBucket] { example.labels.denseTimeline }

        func makeAudioFileForDocumentsBackedCorpus() throws -> AudioFile {
            let documentsPath = URL.documentsDirectory.standardizedFileURL.path()
            let audioPath = audioURL.standardizedFileURL.path()
            guard audioPath.hasPrefix(documentsPath + "/") else {
                throw AnalyzerOptimizerError.documentsBackedAudioRequired(audioURL)
            }

            let relativePath = String(audioPath.dropFirst(documentsPath.count + 1))
            let resourceValues = try? audioURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let fileSize = Int64(resourceValues?.fileSize ?? 0)
            let createdDate = resourceValues?.creationDate ?? example.source.labeledAt

            return AudioFile(
                id: example.exampleID,
                filename: relativePath,
                duration: example.audio.durationSeconds,
                fileSize: fileSize,
                createdDate: createdDate
            )
        }
    }

    struct Summary: Codable, Sendable {
        let exampleCount: Int
        let warningCount: Int
        let errorCount: Int
        let totalDurationSeconds: Double
        let datasetHash: String
        let datasetIndexPath: String

        nonisolated init(
            exampleCount: Int,
            warningCount: Int,
            errorCount: Int,
            totalDurationSeconds: Double,
            datasetHash: String,
            datasetIndexPath: String
        ) {
            self.exampleCount = exampleCount
            self.warningCount = warningCount
            self.errorCount = errorCount
            self.totalDurationSeconds = totalDurationSeconds
            self.datasetHash = datasetHash
            self.datasetIndexPath = datasetIndexPath
        }
    }

    let corpusDirectory: URL
    let datasetDirectory: URL
    let datasetIndexURL: URL
    let audioDirectory: URL
    let transcriptCacheDirectory: URL
    let examples: [Example]
    let issues: [AnalyzerOptimizationDatasetIssue]
    let datasetHash: String

    var summary: Summary {
        Summary(
            exampleCount: examples.count,
            warningCount: issues.filter { $0.severity == .warning }.count,
            errorCount: issues.filter { $0.severity == .error }.count,
            totalDurationSeconds: examples.map(\.duration).reduce(0, +),
            datasetHash: datasetHash,
            datasetIndexPath: datasetIndexURL.path(),
        )
    }

    init(
        corpusDirectory: URL,
        datasetDirectory: URL,
        datasetIndexURL: URL,
        audioDirectory: URL,
        transcriptCacheDirectory: URL,
        examples: [Example],
        issues: [AnalyzerOptimizationDatasetIssue],
        datasetHash: String
    ) {
        self.corpusDirectory = corpusDirectory
        self.datasetDirectory = datasetDirectory
        self.datasetIndexURL = datasetIndexURL
        self.audioDirectory = audioDirectory
        self.transcriptCacheDirectory = transcriptCacheDirectory
        self.examples = examples
        self.issues = issues
        self.datasetHash = datasetHash
    }

    static func load(
        from corpusDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus")
    ) throws -> AnalyzerOptimizationDataset {
        let datasetDirectory = corpusDirectory.appending(path: "AnalyzerDataset", directoryHint: .isDirectory)
        let datasetIndexURL = datasetDirectory.appending(path: "dataset.jsonl")
        let audioDirectory = datasetDirectory.appending(path: "audio", directoryHint: .isDirectory)
        let transcriptCacheDirectory = datasetDirectory
            .appending(path: "cache", directoryHint: .isDirectory)
            .appending(path: "transcripts", directoryHint: .isDirectory)

        guard FileManager.default.fileExists(atPath: datasetIndexURL.path()) else {
            throw AnalyzerOptimizerError.datasetIndexMissing(datasetIndexURL)
        }

        let data = try Data(contentsOf: datasetIndexURL)
        let datasetHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var examples: [Example] = []
        var issues: [AnalyzerOptimizationDatasetIssue] = []
        var seenIDs = Set<UUID>()

        for line in lines {
            let rawData = Data(line.utf8)

            let decoded: AnalyzerTrainingExample
            do {
                decoded = try decoder.decode(AnalyzerTrainingExample.self, from: rawData)
            } catch {
                issues.append(
                    AnalyzerOptimizationDatasetIssue(
                        severity: .error,
                        filename: datasetIndexURL.lastPathComponent,
                        message: "Could not decode dataset line: \(error.localizedDescription)"
                    )
                )
                continue
            }

            if !seenIDs.insert(decoded.exampleID).inserted {
                issues.append(
                    AnalyzerOptimizationDatasetIssue(
                        severity: .error,
                        exampleID: decoded.exampleID,
                        filename: decoded.audio.originalFilename,
                        message: "Duplicate example ID in dataset export."
                    )
                )
                continue
            }

            let audioURL = resolveAudioURL(
                for: decoded.audio.datasetRelativePath,
                corpusDirectory: corpusDirectory,
                datasetDirectory: datasetDirectory
            )
            guard FileManager.default.fileExists(atPath: audioURL.path()) else {
                issues.append(
                    AnalyzerOptimizationDatasetIssue(
                        severity: .error,
                        exampleID: decoded.exampleID,
                        filename: decoded.audio.originalFilename,
                        message: "Referenced audio file is missing at \(audioURL.path())."
                    )
                )
                continue
            }

            if decoded.labels.phaseSegments.isEmpty {
                issues.append(
                    AnalyzerOptimizationDatasetIssue(
                        severity: .error,
                        exampleID: decoded.exampleID,
                        filename: decoded.audio.originalFilename,
                        message: "Example has no labeled phase segments."
                    )
                )
                continue
            }

            if decoded.labels.denseTimeline.isEmpty {
                issues.append(
                    AnalyzerOptimizationDatasetIssue(
                        severity: .warning,
                        exampleID: decoded.exampleID,
                        filename: decoded.audio.originalFilename,
                        message: "Example has no dense timeline buckets; metrics will rebuild from phase segments."
                    )
                )
            }

            if !isSorted(decoded.labels.phaseSegments) {
                issues.append(
                    AnalyzerOptimizationDatasetIssue(
                        severity: .error,
                        exampleID: decoded.exampleID,
                        filename: decoded.audio.originalFilename,
                        message: "Phase segments are out of order or overlapping."
                    )
                )
                continue
            }

            examples.append(
                Example(
                    example: decoded,
                    audioURL: audioURL
                )
            )
        }

        examples.sort { $0.id.uuidString < $1.id.uuidString }

        return AnalyzerOptimizationDataset(
            corpusDirectory: corpusDirectory,
            datasetDirectory: datasetDirectory,
            datasetIndexURL: datasetIndexURL,
            audioDirectory: audioDirectory,
            transcriptCacheDirectory: transcriptCacheDirectory,
            examples: examples,
            issues: issues,
            datasetHash: datasetHash
        )
    }

    private static func isSorted(_ segments: [AnalyzerTrainingExample.PhaseSegment]) -> Bool {
        guard !segments.isEmpty else { return false }

        let sorted = segments.sorted {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }
        guard sorted.count == segments.count else { return false }

        for (index, segment) in sorted.enumerated() {
            guard segment.startTime < segment.endTime else { return false }
            guard index > 0 else { continue }
            let previous = sorted[index - 1]
            if previous.endTime > segment.startTime + 0.05 {
                return false
            }
        }

        return true
    }

    private static func resolveAudioURL(
        for datasetRelativePath: String,
        corpusDirectory: URL,
        datasetDirectory: URL
    ) -> URL {
        let normalizedPath = datasetRelativePath.hasPrefix("AnalyzerDataset/")
            ? String(datasetRelativePath.dropFirst("AnalyzerDataset/".count))
            : datasetRelativePath

        let candidates = [
            corpusDirectory.appending(path: datasetRelativePath),
            datasetDirectory.appending(path: normalizedPath)
        ]

        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path()) })
            ?? candidates[0]
    }
}
