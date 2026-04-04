//
//  LabeledFile.swift
//  Ilumionate
//
//  Ground-truth labeled audio file for analyzer training.
//

import Foundation
import CryptoKit

nonisolated struct LabeledFile: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var version: Int = 2
    var originalFilename: String
    var storedAudioFilename: String
    var audioDuration: TimeInterval
    var audioSHA256: String
    var expectedContentType: AudioContentType
    var expectedFrequencyBand: FrequencyBand
    var phases: [LabeledPhase]
    var techniques: [LabeledTechnique]
    var labeledAt: Date
    var labelerNotes: String

    nonisolated var audioFilename: String { originalFilename }

    var status: LabelStatus {
        if phases.isEmpty { return .unlabeled }
        let allHaveNotes = phases.allSatisfy { !($0.notes ?? "").isEmpty }
        return allHaveNotes ? .refined : .rough
    }

    enum LabelStatus: String, Codable, Sendable {
        case unlabeled, rough, refined
    }

    struct FrequencyBand: Codable, Sendable {
        var lower: Double
        var upper: Double

        nonisolated var closedRange: ClosedRange<Double> { lower...upper }

        func validated() throws -> Self {
            guard lower < upper else {
                throw ValidationError.invalidFrequencyBand(lower: lower, upper: upper)
            }
            return self
        }
    }

    struct LabeledPhase: Codable, Identifiable, Sendable {
        var id: UUID = UUID()
        var phase: TrancePhase
        var startTime: TimeInterval
        var endTime: TimeInterval
        var notes: String?
    }

    struct LabeledTechnique: Codable, Identifiable, Sendable {
        var id: UUID = UUID()
        var name: String
        var startTime: TimeInterval
        var endTime: TimeInterval
    }

    enum ValidationError: LocalizedError, Sendable, Equatable {
        case invalidFrequencyBand(lower: Double, upper: Double)
        case phaseOutOfBounds(index: Int, start: TimeInterval, end: TimeInterval, duration: TimeInterval)
        case phaseHasNonPositiveDuration(index: Int, start: TimeInterval, end: TimeInterval)
        case phaseOverlap(index: Int, previousEnd: TimeInterval, nextStart: TimeInterval)
        case phaseGap(index: Int, previousEnd: TimeInterval, nextStart: TimeInterval)

        var errorDescription: String? {
            switch self {
            case .invalidFrequencyBand(let lower, let upper):
                return "Frequency band is invalid (\(lower)–\(upper) Hz)."
            case .phaseOutOfBounds(_, let start, let end, let duration):
                return "A phase extends outside the audio duration (\(start)–\(end), duration \(duration))."
            case .phaseHasNonPositiveDuration(_, let start, let end):
                return "A phase has a non-positive duration (\(start)–\(end))."
            case .phaseOverlap(_, let previousEnd, let nextStart):
                return "Phases overlap near \(previousEnd)s and \(nextStart)s."
            case .phaseGap(_, let previousEnd, let nextStart):
                return "Phases contain a gap near \(previousEnd)s and \(nextStart)s."
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case version
        case originalFilename
        case storedAudioFilename
        case audioFilename
        case audioDuration
        case audioSHA256
        case expectedContentType
        case expectedFrequencyBand
        case phases
        case techniques
        case labeledAt
        case labelerNotes
    }

    init(
        id: UUID = UUID(),
        version: Int = 2,
        originalFilename: String,
        storedAudioFilename: String,
        audioDuration: TimeInterval,
        audioSHA256: String,
        expectedContentType: AudioContentType,
        expectedFrequencyBand: FrequencyBand,
        phases: [LabeledPhase],
        techniques: [LabeledTechnique],
        labeledAt: Date,
        labelerNotes: String
    ) {
        self.id = id
        self.version = version
        self.originalFilename = originalFilename
        self.storedAudioFilename = storedAudioFilename
        self.audioDuration = audioDuration
        self.audioSHA256 = audioSHA256
        self.expectedContentType = expectedContentType
        self.expectedFrequencyBand = expectedFrequencyBand
        self.phases = phases
        self.techniques = techniques
        self.labeledAt = labeledAt
        self.labelerNotes = labelerNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1

        let legacyFilename = try container.decodeIfPresent(String.self, forKey: .audioFilename)
        originalFilename = try container.decodeIfPresent(String.self, forKey: .originalFilename) ?? legacyFilename ?? "Unknown Audio"
        storedAudioFilename = try container.decodeIfPresent(String.self, forKey: .storedAudioFilename) ?? legacyFilename ?? originalFilename

        audioDuration = try container.decode(TimeInterval.self, forKey: .audioDuration)
        audioSHA256 = try container.decodeIfPresent(String.self, forKey: .audioSHA256) ?? ""
        expectedContentType = try container.decode(AudioContentType.self, forKey: .expectedContentType)
        expectedFrequencyBand = try container.decode(FrequencyBand.self, forKey: .expectedFrequencyBand)
        phases = try container.decodeIfPresent([LabeledPhase].self, forKey: .phases) ?? []
        techniques = try container.decodeIfPresent([LabeledTechnique].self, forKey: .techniques) ?? []
        labeledAt = try container.decode(Date.self, forKey: .labeledAt)
        labelerNotes = try container.decodeIfPresent(String.self, forKey: .labelerNotes) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(version, forKey: .version)
        try container.encode(originalFilename, forKey: .originalFilename)
        try container.encode(storedAudioFilename, forKey: .storedAudioFilename)
        try container.encode(originalFilename, forKey: .audioFilename)
        try container.encode(audioDuration, forKey: .audioDuration)
        try container.encode(audioSHA256, forKey: .audioSHA256)
        try container.encode(expectedContentType, forKey: .expectedContentType)
        try container.encode(expectedFrequencyBand, forKey: .expectedFrequencyBand)
        try container.encode(phases, forKey: .phases)
        try container.encode(techniques, forKey: .techniques)
        try container.encode(labeledAt, forKey: .labeledAt)
        try container.encode(labelerNotes, forKey: .labelerNotes)
    }

    func mergedForSave(over existing: LabeledFile?) -> LabeledFile {
        guard let existing else { return self }

        var merged = self
        merged.id = existing.id
        merged.originalFilename = existing.originalFilename
        merged.storedAudioFilename = existing.storedAudioFilename
        merged.audioSHA256 = existing.audioSHA256
        merged.audioDuration = existing.audioDuration
        merged.version = max(version, existing.version, 2)
        return merged
    }

    func validatedForPersistence(gapTolerance: TimeInterval = 0.05) throws -> LabeledFile {
        var validated = self
        validated.version = max(version, 2)
        validated.expectedFrequencyBand = try expectedFrequencyBand.validated()
        validated.phases.sort { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.startTime < rhs.startTime
        }

        for (index, phase) in validated.phases.enumerated() {
            guard phase.startTime >= 0, phase.endTime <= validated.audioDuration else {
                throw ValidationError.phaseOutOfBounds(
                    index: index,
                    start: phase.startTime,
                    end: phase.endTime,
                    duration: validated.audioDuration
                )
            }
            guard phase.startTime < phase.endTime else {
                throw ValidationError.phaseHasNonPositiveDuration(
                    index: index,
                    start: phase.startTime,
                    end: phase.endTime
                )
            }
            guard index > 0 else { continue }

            let previous = validated.phases[index - 1]
            if previous.endTime > phase.startTime + gapTolerance {
                throw ValidationError.phaseOverlap(
                    index: index,
                    previousEnd: previous.endTime,
                    nextStart: phase.startTime
                )
            }
            if phase.startTime > previous.endTime + gapTolerance {
                throw ValidationError.phaseGap(
                    index: index,
                    previousEnd: previous.endTime,
                    nextStart: phase.startTime
                )
            }
        }

        return validated
    }

    static func computeSHA256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension LabeledFile: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: LabeledFile, rhs: LabeledFile) -> Bool { lhs.id == rhs.id }
}

nonisolated struct AnalyzerTrainingExample: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let exampleID: UUID
    let source: SourceMetadata
    let audio: AudioPayload
    let labels: LabelPayload

    struct SourceMetadata: Codable, Sendable {
        let corpusFileID: UUID
        let corpusLabelFilename: String
        let datasetRelativeExamplePath: String
        let originalFilename: String
        let labeledAt: Date
    }

    struct AudioPayload: Codable, Sendable {
        let datasetRelativePath: String
        let storedAudioFilename: String
        let originalFilename: String
        let fileExtension: String?
        let sha256: String
        let durationSeconds: TimeInterval
    }

    struct LabelPayload: Codable, Sendable {
        let contentType: AudioContentType
        let expectedFrequencyBand: LabeledFile.FrequencyBand
        let status: LabeledFile.LabelStatus
        let labelerNotes: String
        let hasPhaseLabels: Bool
        let hasCompletePhaseCoverage: Bool
        let phaseOrder: [TrancePhase]
        let phasePoints: [PhasePoint]
        let phaseSegments: [PhaseSegment]
        let denseTimeline: [TimelineBucket]
        let techniques: [TechniqueSegment]
    }

    struct PhasePoint: Codable, Sendable {
        let id: UUID
        let timeSeconds: TimeInterval
        let phase: TrancePhase
        let notes: String?
    }

    struct PhaseSegment: Codable, Sendable {
        let id: UUID
        let phase: TrancePhase
        let startTime: TimeInterval
        let endTime: TimeInterval
        let durationSeconds: TimeInterval
        let notes: String?
    }

    struct TimelineBucket: Codable, Sendable {
        let secondIndex: Int
        let startTime: TimeInterval
        let endTime: TimeInterval
        let phase: TrancePhase?
    }

    struct TechniqueSegment: Codable, Sendable {
        let id: UUID
        let name: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let durationSeconds: TimeInterval
    }
}

nonisolated struct AnalyzerTrainingCorpusLoadResult: Sendable {
    let labeledFiles: [LabeledFile]
    let sourceDescription: String
}

nonisolated struct AnalyzerTrainingCorpusLoader: Sendable {
    let corpusDirectory: URL

    init(corpusDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus")) {
        self.corpusDirectory = corpusDirectory
    }

    var datasetDirectory: URL {
        corpusDirectory.appending(path: "AnalyzerDataset")
    }

    var datasetIndexURL: URL {
        datasetDirectory.appending(path: "dataset.jsonl")
    }

    func load() -> AnalyzerTrainingCorpusLoadResult {
        if FileManager.default.fileExists(atPath: datasetIndexURL.path()) {
            do {
                let examples = try loadExamples()
                return AnalyzerTrainingCorpusLoadResult(
                    labeledFiles: examples.map(\.labeledFile),
                    sourceDescription: "AnalyzerDataset (\(datasetIndexURL.path()))"
                )
            } catch {
                print("⚠️ Failed to load analyzer dataset index at \(datasetIndexURL.path()): \(error.localizedDescription)")
            }
        }

        return AnalyzerTrainingCorpusLoadResult(
            labeledFiles: loadLegacyCorpusFiles(),
            sourceDescription: "Legacy corpus JSON (\(corpusDirectory.path()))"
        )
    }

    private func loadExamples() throws -> [AnalyzerTrainingExample] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let rawText = try String(contentsOf: datasetIndexURL, encoding: .utf8)
        let lines = rawText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return try lines.map { line in
            try decoder.decode(AnalyzerTrainingExample.self, from: Data(line.utf8))
        }
    }

    private func loadLegacyCorpusFiles() -> [LabeledFile] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: corpusDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(LabeledFile.self, from: data)
            }
    }
}

extension AnalyzerTrainingExample {
    nonisolated var labeledFile: LabeledFile {
        LabeledFile(
            id: exampleID,
            version: max(schemaVersion, 2),
            originalFilename: audio.originalFilename,
            storedAudioFilename: audio.storedAudioFilename,
            audioDuration: audio.durationSeconds,
            audioSHA256: audio.sha256,
            expectedContentType: labels.contentType,
            expectedFrequencyBand: labels.expectedFrequencyBand,
            phases: labels.phaseSegments.map {
                .init(
                    id: $0.id,
                    phase: $0.phase,
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                    notes: $0.notes
                )
            },
            techniques: labels.techniques.map {
                .init(
                    id: $0.id,
                    name: $0.name,
                    startTime: $0.startTime,
                    endTime: $0.endTime
                )
            },
            labeledAt: source.labeledAt,
            labelerNotes: labels.labelerNotes
        )
    }
}

extension LabeledFile {
    nonisolated func analyzerTrainingExample(
        exportedAt: Date = Date(),
        datasetRelativeAudioPath: String,
        datasetRelativeExamplePath: String
    ) -> AnalyzerTrainingExample {
        let sortedPhases = phases.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.startTime < rhs.startTime
        }

        return AnalyzerTrainingExample(
            schemaVersion: AnalyzerTrainingExample.currentSchemaVersion,
            exportedAt: exportedAt,
            exampleID: id,
            source: .init(
                corpusFileID: id,
                corpusLabelFilename: "\(id.uuidString).json",
                datasetRelativeExamplePath: datasetRelativeExamplePath,
                originalFilename: originalFilename,
                labeledAt: labeledAt
            ),
            audio: .init(
                datasetRelativePath: datasetRelativeAudioPath,
                storedAudioFilename: storedAudioFilename,
                originalFilename: originalFilename,
                fileExtension: URL(filePath: storedAudioFilename).pathExtension.nilIfEmpty,
                sha256: audioSHA256,
                durationSeconds: audioDuration
            ),
            labels: .init(
                contentType: expectedContentType,
                expectedFrequencyBand: expectedFrequencyBand,
                status: status,
                labelerNotes: labelerNotes,
                hasPhaseLabels: !sortedPhases.isEmpty,
                hasCompletePhaseCoverage: hasCompletePhaseCoverage(sortedPhases),
                phaseOrder: sortedPhases.map(\.phase),
                phasePoints: sortedPhases.map {
                    .init(
                        id: $0.id,
                        timeSeconds: $0.startTime,
                        phase: $0.phase,
                        notes: $0.notes
                    )
                },
                phaseSegments: sortedPhases.map {
                    .init(
                        id: $0.id,
                        phase: $0.phase,
                        startTime: $0.startTime,
                        endTime: $0.endTime,
                        durationSeconds: max(0, $0.endTime - $0.startTime),
                        notes: $0.notes
                    )
                },
                denseTimeline: denseTimeline(from: sortedPhases),
                techniques: techniques.map {
                    .init(
                        id: $0.id,
                        name: $0.name,
                        startTime: $0.startTime,
                        endTime: $0.endTime,
                        durationSeconds: max(0, $0.endTime - $0.startTime)
                    )
                }
            )
        )
    }

    nonisolated private func denseTimeline(
        from sortedPhases: [LabeledPhase],
        resolutionSeconds: TimeInterval = 1
    ) -> [AnalyzerTrainingExample.TimelineBucket] {
        guard audioDuration > 0, resolutionSeconds > 0 else { return [] }

        let bucketCount = max(1, Int(ceil(audioDuration / resolutionSeconds)))
        return (0..<bucketCount).map { index in
            let startTime = Double(index) * resolutionSeconds
            let endTime = min(audioDuration, startTime + resolutionSeconds)
            let sampleTime = min(audioDuration, startTime + ((endTime - startTime) / 2))

            return AnalyzerTrainingExample.TimelineBucket(
                secondIndex: index,
                startTime: startTime,
                endTime: endTime,
                phase: phase(at: sampleTime, from: sortedPhases)
            )
        }
    }

    nonisolated private func phase(
        at time: TimeInterval,
        from sortedPhases: [LabeledPhase]
    ) -> TrancePhase? {
        sortedPhases.first {
            $0.startTime <= time && time < $0.endTime
        }?.phase ?? sortedPhases.last(where: { abs($0.endTime - time) < 0.001 })?.phase
    }

    nonisolated private func hasCompletePhaseCoverage(
        _ sortedPhases: [LabeledPhase],
        tolerance: TimeInterval = 0.05
    ) -> Bool {
        guard let first = sortedPhases.first, let last = sortedPhases.last else { return false }
        guard first.startTime <= tolerance else { return false }
        guard abs(last.endTime - audioDuration) <= tolerance else { return false }

        for index in sortedPhases.indices.dropFirst() {
            let previous = sortedPhases[index - 1]
            let current = sortedPhases[index]
            guard abs(current.startTime - previous.endTime) <= tolerance else {
                return false
            }
        }

        return true
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
