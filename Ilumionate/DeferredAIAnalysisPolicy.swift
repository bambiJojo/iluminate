//
//  DeferredAIAnalysisPolicy.swift
//  Ilumionate
//
//  Decides which keyword-fallback results deserve another attempt at the
//  on-device model, and when to stop.
//
//  The pipeline already knew: it logged "↺ Transient — analysing this file
//  again later should succeed" and then cleared the checkpoint, so nothing
//  could. On 2026-08-17 the device recorded `foreground 0/16 used AI` — sixteen
//  files permanently downgraded by a condition that was going to pass.
//
//  Deliberately keyed on the *transience of the failure* rather than on
//  foreground/background. A device without Game Mode analyses fine in the
//  foreground, and gating on app state would defer work that would have
//  succeeded.
//

import Foundation

nonisolated struct DeferredAIAnalysisCandidate: Equatable, Sendable {
    let audioFileID: UUID
    let attempts: Int
    /// `nil` when the file has never been retried, only originally analysed.
    let lastAttemptAt: Date?
}

nonisolated enum DeferredAIAnalysisPolicy {

    /// A device with Game Mode permanently on must stop trying rather than
    /// retry on every backgrounding, forever.
    static let maximumRetryAttempts = 3

    /// Policy, not measurement. A background window is finite and an AI stage
    /// can be followed by hundreds of chunk requests.
    static let maximumPerWindow = 5

    /// Policy, not measurement — see the spec's Risks. `ChunkedPhaseAnalyzer`
    /// issues one model request per 15-second chunk (589 on one observed file),
    /// so a successful AI stage is followed by that volume. The interval that
    /// actually avoids rate limiting is unknown; the attempt log will show
    /// whether this holds.
    static let spacingBetweenAttempts: Duration = .seconds(30)

    /// Whether a result produced by keyword fallback is worth another attempt.
    ///
    /// `nil` means the model produced the result, so there is nothing to
    /// improve. A guardrail refusal means the model evaluated the content and
    /// declined — deterministic, and retrying it loops forever.
    static func isEligible(fallbackKind: AIGenerationDiagnosis.Kind?, attempts: Int) -> Bool {
        guard let fallbackKind, fallbackKind.isTransient else { return false }
        return attempts < maximumRetryAttempts
    }

    /// Whether the durable checkpoint survives this failure, which is what
    /// makes a later retry cheap: the device log shows `⏭️ Reusing saved
    /// transcript`, so only the AI stage re-runs, not WhisperKit.
    static func retainsCheckpoint(after fallbackKind: AIGenerationDiagnosis.Kind) -> Bool {
        fallbackKind.isTransient
    }

    /// The eligible slice of a set of checkpoints, already ordered and bounded.
    ///
    /// A `.guardrail` should never have been deferred in the first place, but
    /// filtering here too means a checkpoint written by an earlier build cannot
    /// put the retry loop up against a deterministic refusal.
    static func candidates(from checkpoints: [AnalysisCheckpoint]) -> [DeferredAIAnalysisCandidate] {
        let eligible = checkpoints.compactMap { checkpoint -> DeferredAIAnalysisCandidate? in
            guard let deferred = checkpoint.deferredAIRetry,
                  isEligible(fallbackKind: deferred.kind, attempts: deferred.attempts) else {
                return nil
            }
            return DeferredAIAnalysisCandidate(
                audioFileID: checkpoint.audioFile.id,
                attempts: deferred.attempts,
                lastAttemptAt: deferred.lastAttemptAt
            )
        }
        return selectForWindow(eligible)
    }

    /// Oldest wait first, and anything never tried ahead of anything already
    /// tried, so a large backlog drains fairly rather than starving its tail.
    static func selectForWindow(
        _ candidates: [DeferredAIAnalysisCandidate]
    ) -> [DeferredAIAnalysisCandidate] {
        candidates
            .sorted { lhs, rhs in
                switch (lhs.lastAttemptAt, rhs.lastAttemptAt) {
                case (nil, nil):            return lhs.audioFileID.uuidString < rhs.audioFileID.uuidString
                case (nil, _):              return true
                case (_, nil):              return false
                case let (left?, right?):
                    if left != right { return left < right }
                    return lhs.audioFileID.uuidString < rhs.audioFileID.uuidString
                }
            }
            .prefix(maximumPerWindow)
            .map { $0 }
    }
}
