//  PhasePlan.swift
//  CorpusGenKit
//
//  A phase plan is an ordered list of (phase, duration) blocks. The assembler
//  places blocks back-to-back, so boundary truth is exact by construction.
//
import Foundation
import CorpusKit

/// Deterministic RNG so a seed reproduces a plan (spec §3d reproducibility).
public struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        // splitmix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public struct PhasePlanBlock: Sendable, Equatable {
    public let phase: TrancePhase
    public let duration: TimeInterval
    public init(phase: TrancePhase, duration: TimeInterval) {
        self.phase = phase; self.duration = duration
    }
}

public struct PhasePlan: Sendable {
    public let archetype: String
    public let blocks: [PhasePlanBlock]

    public init(archetype: String, blocks: [PhasePlanBlock]) {
        self.archetype = archetype; self.blocks = blocks
    }

    public var totalDuration: TimeInterval { blocks.reduce(0) { $0 + $1.duration } }

    public enum Archetype: String, CaseIterable, Sendable {
        case classic
        case fractionationLadder = "fractionation_ladder"
        case confusionTherapy = "confusion_therapy"
        case suggestionConditioning = "suggestion_conditioning"
        case directSuggestion = "direct_suggestion"

        public var phases: [TrancePhase] {
            switch self {
            case .classic:
                return [.induction, .deepening, .suggestions, .emergence]
            case .fractionationLadder:
                return [.induction, .fractionation, .deepening, .suggestions, .emergence]
            case .confusionTherapy:
                return [.induction, .deepening, .confusion, .suggestions, .emergence]
            case .suggestionConditioning:
                return [.induction, .deepening, .suggestions, .emergence]
            case .directSuggestion:
                return [.induction, .suggestions, .emergence]
            }
        }
    }

    /// Per-phase duration range (seconds) used to vary block lengths.
    public static func durationRange(for phase: TrancePhase) -> ClosedRange<TimeInterval> {
        switch phase {
        case .preTalk:   return 30...90
        case .induction: return 90...240
        case .fractionation: return 60...180
        case .deepening: return 120...300
        case .confusion: return 60...180
        case .suggestions, .therapy, .eroticSuggestions: return 90...300
        case .conditioning: return 60...180
        case .emergence: return 30...90
        default:         return 60...180
        }
    }

    /// Named archetype with varied per-phase block lengths.
    public static func make<R: RandomNumberGenerator>(
        archetype: Archetype,
        using rng: inout R
    ) -> PhasePlan {
        let blocks = archetype.phases.map { phase -> PhasePlanBlock in
            let range = durationRange(for: phase)
            let duration = TimeInterval.random(in: range, using: &rng).rounded()
            return PhasePlanBlock(phase: phase, duration: duration)
        }
        return PhasePlan(archetype: archetype.rawValue, blocks: blocks)
    }

    /// Classic induction→deepening→suggestions→emergence archetype with varied lengths.
    public static func classic<R: RandomNumberGenerator>(using rng: inout R) -> PhasePlan {
        make(archetype: .classic, using: &rng)
    }
}
