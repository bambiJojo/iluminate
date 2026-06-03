//  BlockResponder.swift
//  CorpusGenKit
//
//  Abstraction over "produce the transcript text for one phase block".
//  StubResponder is offline & deterministic (dry-run + tests); ClaudeResponder
//  (in ClaudeClient.swift) hits the Anthropic API.
//
import Foundation
import CorpusKit

/// A real per-phase excerpt sliced from a labeled transcript (few-shot seed).
public struct PhaseSeed: Sendable, Equatable {
    public let phase: TrancePhase
    public let excerpt: String
    public init(phase: TrancePhase, excerpt: String) {
        self.phase = phase; self.excerpt = excerpt
    }
}

public struct BlockRequest: Sendable {
    public let phase: TrancePhase
    public let durationSec: TimeInterval
    public let ambiguity: CorpusAmbiguityLevel
    public let seeds: [PhaseSeed]
    public let priorPhases: [TrancePhase]
    public init(phase: TrancePhase, durationSec: TimeInterval, ambiguity: CorpusAmbiguityLevel,
                seeds: [PhaseSeed], priorPhases: [TrancePhase]) {
        self.phase = phase; self.durationSec = durationSec; self.ambiguity = ambiguity
        self.seeds = seeds; self.priorPhases = priorPhases
    }
}

public protocol BlockResponder: Sendable {
    func text(for request: BlockRequest) async throws -> String
}

/// Deterministic, offline responder. Emits keyword-rich, phase-appropriate text
/// so dry-run output is realistic enough for the analyzer to classify and the
/// harness to score — without any network call.
public struct StubResponder: BlockResponder {
    public init() {}

    public func text(for request: BlockRequest) async throws -> String {
        Self.template(for: request.phase)
    }

    static func template(for phase: TrancePhase) -> String {
        switch phase {
        case .preTalk:
            return "Welcome, and make yourself comfortable. Today we will explore hypnosis together, and I want you to know you are safe. Just relax and listen to the sound of my voice as we begin."
        case .induction:
            return "Now close your eyes and take a slow, deep breath. Let your eyelids grow heavy, so heavy you can barely keep them open, and let them close all the way down. Just relax and let go completely now."
        case .fractionation:
            return "Open your eyes for a moment... and now close them again, twice as deep as before. Up, and back down, deeper each time, sinking further with every cycle."
        case .deepening:
            return "Going deeper now, deeper and deeper with every breath you take. Down, down, ten times more relaxed with each number I count. Drifting further down into this calm, heavy relaxation."
        case .confusion:
            return "And the more you try to follow, the less you need to, because as you wonder you drift, and as you drift you wonder, and none of it matters as you simply let go."
        case .therapy:
            return "In this deep, calm state, imagine your goal clearly in front of you. See yourself confident and capable, achieving exactly what you came here for, feeling stronger with every breath."
        case .suggestions:
            return "From now on, each day you feel calmer, more focused, and more in control. These feelings grow stronger every time you relax like this, and they stay with you long after you wake."
        case .eroticSuggestions:
            return "Each wave of relaxation feels warm and pleasant, a gentle pleasure spreading through you as you sink deeper and surrender more completely to the calm."
        case .brainwashing:
            return "You believe it because it is true, and it is true because you believe it. The words become your thoughts, and your thoughts become the words, again and again."
        case .conditioning:
            return "Whenever you hear my voice, you return to this calm state instantly, every single time. The moment I say relax, you drop down twice as deep, automatically."
        case .emergence:
            return "In a moment I will count up to five, and you will wake feeling refreshed and alert. One, two, three, four, five — eyes open, wide awake, feeling wonderful and fully present."
        case .transitional:
            return "And as one feeling gently gives way to the next, you simply continue to relax, letting the change happen all on its own."
        }
    }
}
