//
//  AIAttemptRecord.swift
//  Ilumionate
//
//  Game Mode refuses Foundation Models requests with "Not executed due to
//  current system state [\"StandardGameMode\"]", which the pipeline classifies
//  as `.systemBusy` and degrades to keyword matching. Whether a request made
//  while LumeSync is *backgrounded* is refused too decides the fix:
//
//  - refused only in the foreground → schedule analysis for the background and
//    keep Game Mode's frame priority during playback
//  - refused in both → scheduling cannot help, and declining Game Mode is the
//    only remaining lever
//
//  Recording the app's activation state alongside each outcome turns that from
//  an impression into a count.
//

import Foundation

nonisolated enum AIRunActivationState: String, Codable, Sendable, CaseIterable {
    case foreground
    case background
    /// Mid-transition, or a platform that does not distinguish. Counted, but
    /// never used as evidence for the verdict.
    case inactive
}

nonisolated struct AIAttemptRecord: Equatable, Codable, Sendable {
    let filename: String
    let activationState: AIRunActivationState
    /// `nil` when the model answered. Otherwise why it did not.
    let diagnosis: AIGenerationDiagnosis.Kind?
    let at: Date

    var usedAI: Bool { diagnosis == nil }

    /// Only `.systemBusy` is the Game Mode refusal. A context overflow or a
    /// guardrail says nothing about it and must not be read as evidence.
    var wasBlockedBySystemState: Bool { diagnosis == .systemBusy }
}

nonisolated struct AIAttemptSummary: Sendable {

    enum Verdict: Equatable, Sendable {
        case noData
        /// Only one activation state has been sampled, so there is nothing to
        /// compare against.
        case needsBackgroundSamples
        case backgroundAvoidsTheBlock
        case blockedInBothStates
        case notBlocked
    }

    let records: [AIAttemptRecord]

    init(records: [AIAttemptRecord]) {
        self.records = records
    }

    func total(in state: AIRunActivationState) -> Int {
        records.count { $0.activationState == state }
    }

    func usedAI(in state: AIRunActivationState) -> Int {
        records.count { $0.activationState == state && $0.usedAI }
    }

    func blocked(in state: AIRunActivationState) -> Int {
        records.count { $0.activationState == state && $0.wasBlockedBySystemState }
    }

    var verdict: Verdict {
        guard records.isEmpty == false else { return .noData }

        let foregroundBlocked = blocked(in: .foreground) > 0
        let backgroundBlocked = blocked(in: .background) > 0
        let backgroundSucceeded = usedAI(in: .background) > 0
        let foregroundSucceeded = usedAI(in: .foreground) > 0

        if backgroundBlocked, foregroundBlocked { return .blockedInBothStates }
        if backgroundSucceeded, foregroundBlocked { return .backgroundAvoidsTheBlock }
        if backgroundSucceeded, foregroundSucceeded { return .notBlocked }
        // Everything else is one-sided: a state with no usable sample, or
        // failures that were not the system-state refusal.
        return .needsBackgroundSamples
    }

    var description: String {
        guard records.isEmpty == false else { return "AI attempts: none recorded yet" }
        return """
        AI attempts — foreground \(usedAI(in: .foreground))/\(total(in: .foreground)) used AI, \
        background \(usedAI(in: .background))/\(total(in: .background)) used AI → \(verdictText)
        """
    }

    private var verdictText: String {
        switch verdict {
        case .noData:
            "no attempts recorded yet"
        case .needsBackgroundSamples:
            "inconclusive — need attempts in both foreground and background"
        case .backgroundAvoidsTheBlock:
            "backgrounding avoids the block — schedule analysis in the background"
        case .blockedInBothStates:
            "blocked in both states — scheduling cannot help"
        case .notBlocked:
            "not blocked — the system state is not the constraint"
        }
    }
}
