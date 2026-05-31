//  CorpusCase.swift
//  IlumionateTests
//
//  On-disk corpus schema. Decoupled DTOs so the JSON format does not depend
//  on app types' Codable conformance. Phases are stored by rawValue string.
//
import Foundation
@testable import Ilumionate

enum CorpusSource: String, Codable, Sendable { case synthetic, real }
enum CorpusBoundaryMode: String, Codable, Sendable { case exact, anchored }
enum CorpusAmbiguityLevel: String, Codable, Sendable {
    case low, medium, high, unspecified
}

/// Segment DTO mirroring `AudioTranscriptionSegment(text:timestamp:duration:confidence:)`.
struct CorpusSegment: Codable, Sendable {
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Double
}

/// A ground-truth phase span. In `exact` mode `start`/`end` are precise.
/// In `anchored` mode spans are anchor regions; gaps between them are
/// unlabeled gray zones the evaluator does not grade.
struct PhaseTruthSpan: Codable, Sendable {
    let phase: HypnosisMetadata.Phase
    let start: TimeInterval
    let end: TimeInterval

    private enum CodingKeys: String, CodingKey { case phase, start, end }

    init(phase: HypnosisMetadata.Phase, start: TimeInterval, end: TimeInterval) {
        self.phase = phase; self.start = start; self.end = end
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .phase)
        guard let phase = HypnosisMetadata.Phase(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .phase, in: c,
                debugDescription: "Unknown phase rawValue '\(raw)'"
            )
        }
        self.phase = phase
        self.start = try c.decode(TimeInterval.self, forKey: .start)
        self.end = try c.decode(TimeInterval.self, forKey: .end)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(phase.rawValue, forKey: .phase)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
    }
}

/// One corpus case on disk. `truth` drives the timeline metrics; the optional
/// `expected*` fields preserve the legacy presence/order scorers.
struct CorpusCase: Codable, Sendable {
    let id: String
    let source: CorpusSource
    let boundaryMode: CorpusBoundaryMode
    let ambiguityLevel: CorpusAmbiguityLevel
    let duration: TimeInterval
    let segments: [CorpusSegment]
    let truth: [PhaseTruthSpan]

    // Optional legacy expectations (used by AnalysisEvaluator path).
    // `AnalysisResult.ContentType` is the real enum (AnalysisEvaluationMetrics.swift:46).
    let expectedContentType: AnalysisResult.ContentType?
    let expectedPhaseOrder: [HypnosisMetadata.Phase]?
    let minimumPhaseCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, source, boundaryMode, ambiguityLevel, duration, segments, truth
        case expectedContentType, expectedPhaseOrder, minimumPhaseCount
    }

    init(
        id: String,
        source: CorpusSource,
        boundaryMode: CorpusBoundaryMode,
        ambiguityLevel: CorpusAmbiguityLevel,
        duration: TimeInterval,
        segments: [CorpusSegment],
        truth: [PhaseTruthSpan],
        expectedContentType: AnalysisResult.ContentType? = nil,
        expectedPhaseOrder: [HypnosisMetadata.Phase]? = nil,
        minimumPhaseCount: Int? = nil
    ) {
        self.id = id
        self.source = source
        self.boundaryMode = boundaryMode
        self.ambiguityLevel = ambiguityLevel
        self.duration = duration
        self.segments = segments
        self.truth = truth
        self.expectedContentType = expectedContentType
        self.expectedPhaseOrder = expectedPhaseOrder
        self.minimumPhaseCount = minimumPhaseCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decode(CorpusSource.self, forKey: .source)
        boundaryMode = try c.decode(CorpusBoundaryMode.self, forKey: .boundaryMode)
        ambiguityLevel = try c.decodeIfPresent(CorpusAmbiguityLevel.self, forKey: .ambiguityLevel) ?? .unspecified
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        segments = try c.decodeIfPresent([CorpusSegment].self, forKey: .segments) ?? []
        truth = try c.decodeIfPresent([PhaseTruthSpan].self, forKey: .truth) ?? []
        if let rawType = try c.decodeIfPresent(String.self, forKey: .expectedContentType) {
            expectedContentType = AnalysisResult.ContentType(rawValue: rawType)
        } else {
            expectedContentType = nil
        }
        if let rawOrder = try c.decodeIfPresent([String].self, forKey: .expectedPhaseOrder) {
            expectedPhaseOrder = rawOrder.compactMap { HypnosisMetadata.Phase(rawValue: $0) }
        } else {
            expectedPhaseOrder = nil
        }
        minimumPhaseCount = try c.decodeIfPresent(Int.self, forKey: .minimumPhaseCount)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(source, forKey: .source)
        try c.encode(boundaryMode, forKey: .boundaryMode)
        try c.encode(ambiguityLevel, forKey: .ambiguityLevel)
        try c.encode(duration, forKey: .duration)
        try c.encode(segments, forKey: .segments)
        try c.encode(truth, forKey: .truth)
        try c.encodeIfPresent(expectedContentType?.rawValue, forKey: .expectedContentType)
        try c.encodeIfPresent(expectedPhaseOrder?.map(\.rawValue), forKey: .expectedPhaseOrder)
        try c.encodeIfPresent(minimumPhaseCount, forKey: .minimumPhaseCount)
    }

    /// App-typed transcription segments for feeding the analyzer.
    var transcriptionSegments: [AudioTranscriptionSegment] {
        segments.map {
            AudioTranscriptionSegment(
                text: $0.text, timestamp: $0.timestamp,
                duration: $0.duration, confidence: $0.confidence
            )
        }
    }

    /// Concatenated transcript text (fallback when segment text is the whole script).
    var transcriptText: String {
        segments.map(\.text).joined(separator: " ")
    }
}
