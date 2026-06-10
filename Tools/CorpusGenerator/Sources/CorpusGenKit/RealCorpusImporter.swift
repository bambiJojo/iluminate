//  RealCorpusImporter.swift
//  CorpusGenKit
//
//  Imports LumeLabel's on-disk label output into the evaluation corpus. LumeLabel
//  writes a `LabeledFile` JSON per session (contiguous phase spans) plus a cached
//  WhisperKit transcript keyed by audio SHA-256. This importer decodes both and
//  emits a real `CorpusCase` for `Corpus/real/`, so the evaluation harness runs
//  against real ground truth instead of a handful of fixtures.
//
//  Depends only on the on-disk JSON contract, not on app internals — the source
//  types live in the iOS app target and need not be linked here.
//
import Foundation
import CorpusKit

/// Decodable mirror of the LabeledFile JSON LumeLabel writes (only the fields the
/// importer consumes). Phase rawValues are validated when building the case.
public struct LabeledFileDTO: Decodable, Sendable {
    public let id: String
    public let originalFilename: String
    public let audioDuration: TimeInterval
    public let audioSHA256: String
    public let expectedContentType: String
    public let phases: [PhaseDTO]

    public struct PhaseDTO: Decodable, Sendable {
        public let phase: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval
    }

    private enum CodingKeys: String, CodingKey {
        case id, originalFilename, audioFilename, audioDuration, audioSHA256
        case expectedContentType, phases
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        // `originalFilename` is canonical; older files only carry `audioFilename`.
        originalFilename = try c.decodeIfPresent(String.self, forKey: .originalFilename)
            ?? c.decode(String.self, forKey: .audioFilename)
        audioDuration = try c.decode(TimeInterval.self, forKey: .audioDuration)
        audioSHA256 = try c.decodeIfPresent(String.self, forKey: .audioSHA256) ?? ""
        expectedContentType = try c.decode(String.self, forKey: .expectedContentType)
        phases = try c.decode([PhaseDTO].self, forKey: .phases)
    }
}

/// Decodable mirror of the cached-transcript JSON (only what we need).
public struct TranscriptCacheDTO: Decodable, Sendable {
    public let transcription: Transcription

    public struct Transcription: Decodable, Sendable {
        public let duration: TimeInterval
        public let segments: [SegmentDTO]
    }
    public struct SegmentDTO: Decodable, Sendable {
        public let text: String
        public let timestamp: TimeInterval
        public let duration: TimeInterval
        public let confidence: Double
    }
}

public struct RealCorpusImporter: Sendable {
    public init() {}

    public enum ImportError: Error, CustomStringConvertible, Equatable {
        case unknownPhase(String)

        public var description: String {
            switch self {
            case let .unknownPhase(raw):
                return "Labeled file contains unknown phase rawValue '\(raw)'"
            }
        }
    }

    // MARK: - Pure mapping

    /// Builds a real `CorpusCase` from a decoded labeled file and its optional
    /// transcript. Boundary mode is `.exact`: LumeLabel labels are contiguous full
    /// segmentations, so every second is gradable (no gray zones).
    public func makeCase(labeled: LabeledFileDTO, transcript: TranscriptCacheDTO?) throws -> CorpusCase {
        let truth = try labeled.phases
            .sorted { $0.startTime < $1.startTime }
            .map { dto -> PhaseTruthSpan in
                guard let phase = TrancePhase(rawValue: dto.phase) else {
                    throw ImportError.unknownPhase(dto.phase)
                }
                return PhaseTruthSpan(phase: phase, start: dto.startTime, end: dto.endTime)
            }

        let segments = (transcript?.transcription.segments ?? []).map {
            CorpusSegment(text: $0.text, timestamp: $0.timestamp, duration: $0.duration, confidence: $0.confidence)
        }

        return CorpusCase(
            id: Self.caseID(forFilename: labeled.originalFilename),
            source: .real,
            boundaryMode: .exact,
            ambiguityLevel: .unspecified,
            duration: labeled.audioDuration,
            segments: segments,
            truth: truth,
            expectedContentTypeRaw: labeled.expectedContentType
        )
    }

    /// `real-` prefixed, filesystem-safe slug of the source filename stem.
    static func caseID(forFilename filename: String) -> String {
        let stem = URL(filePath: filename).deletingPathExtension().lastPathComponent
        var slug = ""
        var lastWasDash = false
        for character in stem.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
        }
        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "real-\(trimmed.isEmpty ? "unnamed" : trimmed)"
    }

    // MARK: - Disk

    /// Top-level `*.json` files under the training-corpus directory that decode as
    /// labeled files. Non-label JSON (manifests, etc.) is skipped.
    public func loadLabeledFiles(trainingCorpusDir: URL) throws -> [LabeledFileDTO] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: trainingCorpusDir.path) else { return [] }
        let urls = try fm.contentsOfDirectory(at: trainingCorpusDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        return urls.compactMap { try? decoder.decode(LabeledFileDTO.self, from: Data(contentsOf: $0)) }
    }

    /// Loads the cached transcript for a SHA, if present.
    public func loadTranscript(sha256: String, trainingCorpusDir: URL) -> TranscriptCacheDTO? {
        guard !sha256.isEmpty else { return nil }
        let url = trainingCorpusDir
            .appending(path: "AnalyzerDataset/cache/transcripts", directoryHint: .isDirectory)
            .appending(path: "\(sha256).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TranscriptCacheDTO.self, from: data)
    }

    /// Imports every labeled file under `trainingCorpusDir`, pairing each with its
    /// cached transcript, and writes the resulting cases into `outDir`. Returns the
    /// written file URLs.
    @discardableResult
    public func importAll(trainingCorpusDir: URL, into outDir: URL) throws -> [URL] {
        let labeled = try loadLabeledFiles(trainingCorpusDir: trainingCorpusDir)
        return try labeled.map { file in
            let transcript = loadTranscript(sha256: file.audioSHA256, trainingCorpusDir: trainingCorpusDir)
            let kase = try makeCase(labeled: file, transcript: transcript)
            return try CorpusWriter.write(kase, to: outDir)
        }
    }
}
