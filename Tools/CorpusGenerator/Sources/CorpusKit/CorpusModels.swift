//  CorpusModels.swift
//  CorpusKit
//
//  On-disk corpus schema. Pure DTOs with no app-type dependencies: phases use
//  TrancePhase (also in CorpusKit); content type is a raw string bridged on the
//  test-target side. JSON shape is unchanged from the landed schema, plus an
//  optional `generation` provenance block written by the generator.
//
import Foundation

public enum CorpusSource: String, Codable, Sendable { case synthetic, real }
public enum CorpusBoundaryMode: String, Codable, Sendable { case exact, anchored }
public enum CorpusAmbiguityLevel: String, Codable, Sendable {
    case low, medium, high, unspecified
}

/// Segment DTO mirroring `AudioTranscriptionSegment(text:timestamp:duration:confidence:)`.
public struct CorpusSegment: Codable, Sendable {
    public let text: String
    public let timestamp: TimeInterval
    public let duration: TimeInterval
    public let confidence: Double

    public init(text: String, timestamp: TimeInterval, duration: TimeInterval, confidence: Double) {
        self.text = text; self.timestamp = timestamp
        self.duration = duration; self.confidence = confidence
    }
}

/// A ground-truth phase span. `exact` mode: precise. `anchored` mode: anchor
/// regions; gaps between them are unlabeled gray zones the evaluator skips.
public struct PhaseTruthSpan: Codable, Sendable {
    public let phase: TrancePhase
    public let start: TimeInterval
    public let end: TimeInterval

    private enum CodingKeys: String, CodingKey { case phase, start, end }

    public init(phase: TrancePhase, start: TimeInterval, end: TimeInterval) {
        self.phase = phase; self.start = start; self.end = end
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .phase)
        guard let phase = TrancePhase(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .phase, in: c,
                debugDescription: "Unknown phase rawValue '\(raw)'"
            )
        }
        self.phase = phase
        self.start = try c.decode(TimeInterval.self, forKey: .start)
        self.end = try c.decode(TimeInterval.self, forKey: .end)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(phase.rawValue, forKey: .phase)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
    }
}

/// Provenance for a generated case (spec §3d). Optional; ignored by the harness.
public struct GenerationParams: Codable, Sendable {
    public let archetype: String
    public let ambiguity: String
    public let seedSetID: String?
    public let model: String?
    public let createdAt: Date

    public init(archetype: String, ambiguity: String, seedSetID: String?, model: String?, createdAt: Date) {
        self.archetype = archetype; self.ambiguity = ambiguity
        self.seedSetID = seedSetID; self.model = model; self.createdAt = createdAt
    }
}

/// One corpus case on disk. `truth` drives the timeline metrics; the optional
/// `expected*` fields preserve the legacy presence/order scorers.
public struct CorpusCase: Codable, Sendable {
    public let id: String
    public let source: CorpusSource
    public let boundaryMode: CorpusBoundaryMode
    public let ambiguityLevel: CorpusAmbiguityLevel
    public let duration: TimeInterval
    public let segments: [CorpusSegment]
    public let truth: [PhaseTruthSpan]

    /// Raw content-type string (e.g. "hypnosis"). Bridged to the app's
    /// `AnalysisResult.ContentType` on the test-target side.
    public let expectedContentTypeRaw: String?
    public let expectedPhaseOrder: [TrancePhase]?
    public let minimumPhaseCount: Int?
    public let generation: GenerationParams?

    private enum CodingKeys: String, CodingKey {
        case id, source, boundaryMode, ambiguityLevel, duration, segments, truth
        case expectedContentType, expectedPhaseOrder, minimumPhaseCount, generation
    }

    public init(
        id: String,
        source: CorpusSource,
        boundaryMode: CorpusBoundaryMode,
        ambiguityLevel: CorpusAmbiguityLevel,
        duration: TimeInterval,
        segments: [CorpusSegment],
        truth: [PhaseTruthSpan],
        expectedContentTypeRaw: String? = nil,
        expectedPhaseOrder: [TrancePhase]? = nil,
        minimumPhaseCount: Int? = nil,
        generation: GenerationParams? = nil
    ) {
        self.id = id; self.source = source; self.boundaryMode = boundaryMode
        self.ambiguityLevel = ambiguityLevel; self.duration = duration
        self.segments = segments; self.truth = truth
        self.expectedContentTypeRaw = expectedContentTypeRaw
        self.expectedPhaseOrder = expectedPhaseOrder
        self.minimumPhaseCount = minimumPhaseCount
        self.generation = generation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decode(CorpusSource.self, forKey: .source)
        boundaryMode = try c.decode(CorpusBoundaryMode.self, forKey: .boundaryMode)
        ambiguityLevel = try c.decodeIfPresent(CorpusAmbiguityLevel.self, forKey: .ambiguityLevel) ?? .unspecified
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        segments = try c.decodeIfPresent([CorpusSegment].self, forKey: .segments) ?? []
        truth = try c.decodeIfPresent([PhaseTruthSpan].self, forKey: .truth) ?? []
        expectedContentTypeRaw = try c.decodeIfPresent(String.self, forKey: .expectedContentType)
        if let rawOrder = try c.decodeIfPresent([String].self, forKey: .expectedPhaseOrder) {
            expectedPhaseOrder = rawOrder.compactMap { TrancePhase(rawValue: $0) }
        } else {
            expectedPhaseOrder = nil
        }
        minimumPhaseCount = try c.decodeIfPresent(Int.self, forKey: .minimumPhaseCount)
        generation = try c.decodeIfPresent(GenerationParams.self, forKey: .generation)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(source, forKey: .source)
        try c.encode(boundaryMode, forKey: .boundaryMode)
        try c.encode(ambiguityLevel, forKey: .ambiguityLevel)
        try c.encode(duration, forKey: .duration)
        try c.encode(segments, forKey: .segments)
        try c.encode(truth, forKey: .truth)
        try c.encodeIfPresent(expectedContentTypeRaw, forKey: .expectedContentType)
        try c.encodeIfPresent(expectedPhaseOrder?.map(\.rawValue), forKey: .expectedPhaseOrder)
        try c.encodeIfPresent(minimumPhaseCount, forKey: .minimumPhaseCount)
        try c.encodeIfPresent(generation, forKey: .generation)
    }

    /// Concatenated transcript text (pure; no app types).
    public var transcriptText: String {
        segments.map(\.text).joined(separator: " ")
    }
}
