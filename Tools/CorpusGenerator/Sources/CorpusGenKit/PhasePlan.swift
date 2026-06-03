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

    /// Per-phase duration range (seconds) used to vary block lengths.
    public static func durationRange(for phase: TrancePhase) -> ClosedRange<TimeInterval> {
        switch phase {
        case .preTalk:   return 30...90
        case .induction: return 90...240
        case .deepening: return 120...300
        case .therapy:   return 120...360
        case .emergence: return 30...90
        default:         return 60...180
        }
    }

    /// Classic induction→deepening→therapy→emergence archetype with varied lengths.
    public static func classic<R: RandomNumberGenerator>(using rng: inout R) -> PhasePlan {
        let order: [TrancePhase] = [.preTalk, .induction, .deepening, .therapy, .emergence]
        let blocks = order.map { phase -> PhasePlanBlock in
            let r = durationRange(for: phase)
            let d = TimeInterval.random(in: r, using: &rng).rounded()
            return PhasePlanBlock(phase: phase, duration: d)
        }
        return PhasePlan(archetype: "classic", blocks: blocks)
    }
}
