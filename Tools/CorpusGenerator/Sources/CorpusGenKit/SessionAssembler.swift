//  SessionAssembler.swift
//  CorpusGenKit
//
//  Requests one text block per phase from a BlockResponder, places blocks
//  back-to-back, splits each block's text into evenly-timed segments, and emits
//  one CorpusCase. Because the assembler owns placement, truth spans are exact.
//
import Foundation
import CorpusKit

public struct SessionAssembler: Sendable {
    private let responder: BlockResponder
    public init(responder: BlockResponder) { self.responder = responder }

    public func assemble(
        plan: PhasePlan,
        ambiguity: CorpusAmbiguityLevel,
        idPrefix: String,
        model: String?,
        seedSetID: String?
    ) async throws -> CorpusCase {
        var truth: [PhaseTruthSpan] = []
        var segments: [CorpusSegment] = []
        var cursor: TimeInterval = 0
        var priorPhases: [TrancePhase] = []

        for block in plan.blocks {
            let start = cursor
            let end = cursor + block.duration
            let request = BlockRequest(
                phase: block.phase, durationSec: block.duration,
                ambiguity: ambiguity, seeds: [], priorPhases: priorPhases
            )
            let text = try await responder.text(for: request)
            segments.append(contentsOf: Self.segmentize(text: text, start: start, duration: block.duration))
            truth.append(PhaseTruthSpan(phase: block.phase, start: start, end: end))
            cursor = end
            priorPhases.append(block.phase)
        }

        let shortID = UUID().uuidString.prefix(8).lowercased()
        return CorpusCase(
            id: "\(idPrefix)-\(plan.archetype)-\(shortID)",
            source: .synthetic,
            boundaryMode: .exact,
            ambiguityLevel: ambiguity,
            duration: cursor,
            segments: segments,
            truth: truth,
            expectedContentTypeRaw: "hypnosis",
            expectedPhaseOrder: plan.blocks.map(\.phase),
            minimumPhaseCount: max(1, plan.blocks.count - 1),
            generation: GenerationParams(
                archetype: plan.archetype,
                ambiguity: ambiguity.rawValue,
                seedSetID: seedSetID,
                model: model,
                createdAt: Date()
            )
        )
    }

    /// Splits text into sentence-ish segments distributed evenly across the
    /// block window [start, start+duration]. Always yields at least one segment.
    static func segmentize(text: String, start: TimeInterval, duration: TimeInterval) -> [CorpusSegment] {
        let sentences = text
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let parts = sentences.isEmpty ? [text] : sentences
        let each = duration / Double(parts.count)
        return parts.enumerated().map { idx, sentence in
            CorpusSegment(
                text: sentence,
                timestamp: start + Double(idx) * each,
                duration: each,
                confidence: 1.0
            )
        }
    }
}
