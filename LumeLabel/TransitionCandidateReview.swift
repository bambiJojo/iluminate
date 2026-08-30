//
//  TransitionCandidateReview.swift
//  LumeLabel
//
//  Stable, source-aware transition suggestions and the labeler's decisions.
//

import Foundation

nonisolated enum TransitionCandidateReview {
    struct BlindBaseline: Codable, Sendable {
        let lockedAt: Date
        let sourceLabeledAt: Date
        let phases: [LabeledFile.LabeledPhase]
    }

    enum Source: String, Codable, Hashable, Sendable {
        case backgroundTone
        case semantic

        var displayName: String {
            switch self {
            case .backgroundTone: "Background tone"
            case .semantic: "Transcript meaning"
            }
        }
    }

    struct ID: Codable, Hashable, Sendable {
        let source: Source
        let timeMilliseconds: Int

        init(
            source: Source,
            time: TimeInterval
        ) {
            self.source = source
            self.timeMilliseconds = Int((time * 1_000).rounded())
        }
    }

    enum Decision: String, Codable, Equatable, Sendable {
        case accepted
        case dismissed
    }

    struct Candidate: Identifiable, Equatable, Sendable {
        let id: ID
        let source: Source
        let time: TimeInterval
        let confidence: Double
        let suggestedPhase: TrancePhase?
        let evidence: String?

        init(
            source: Source,
            time: TimeInterval,
            confidence: Double,
            suggestedPhase: TrancePhase? = nil,
            evidence: String? = nil
        ) {
            self.id = ID(
                source: source,
                time: time
            )
            self.source = source
            self.time = time
            self.confidence = min(max(confidence, 0), 1)
            self.suggestedPhase = suggestedPhase
            self.evidence = evidence
        }
    }

    struct Record: Codable, Equatable, Sendable {
        let candidateID: ID
        let decision: Decision
        let decidedAt: Date
        let boundaryTime: TimeInterval?
    }
}
