//
//  AIGenerationDiagnosis.swift
//  Ilumionate
//
//  Tells apart the reasons Foundation Models declines to generate.
//
//  Every failure arrives as `LanguageModelSession.GenerationError`, so the type
//  alone is useless for deciding what to do. Worse, the framework fails *closed*:
//  when its own safety classifier cannot be queried, it reports the result as a
//  guardrail violation with "May contain sensitive or unsafe content" — wording
//  that blames the audio for what is actually broken plumbing. Observed
//  2026-08-09 in the simulator:
//
//      guardrailViolation(… underlyingErrors: [
//        com.apple.SensitiveContentAnalysisML Code=15
//        "Failed model manager query for model …instruct_300m.safety:
//         InferenceError::hostFailed::invalidClientData::DecodingError.keyNotFound"
//      ])
//
//  The distinction is load-bearing: a context overflow is worth retrying with a
//  shorter prompt, while a refused prompt or an unavailable safety host will fail
//  identically every time. Retrying those costs a second full model round-trip
//  and changes nothing.
//
//  MATCHING IS ON MESSAGE TEXT, deliberately. These are framework internals with
//  no public API to inspect, and the classification only drives logging,
//  telemetry, and whether to spend a retry — never correctness. An unrecognised
//  error degrades to `.other`, which stays retryable.
//

import Foundation

nonisolated enum AIGenerationDiagnosis {

    nonisolated enum Kind: String, Codable, Equatable, Sendable, CaseIterable {
        /// The safety classifier itself could not run; the framework failed
        /// closed and reported it as a guardrail violation.
        case safetyHostUnavailable
        /// The content was evaluated and refused.
        case guardrail
        /// Prompt and transcript exceeded the context window.
        case contextWindow
        /// The on-device model is not installed or not ready.
        case assetsUnavailable
        /// The system declined to run the model for now — Game Mode, thermal
        /// pressure, or another passing condition. Nothing to do with this
        /// recording, and it will work later untouched.
        case systemBusy
        case other

        /// Only a context overflow is plausibly fixed by the shorter prompt.
        /// The rest are deterministic, so a retry just doubles the wait.
        var isRetryable: Bool {
            switch self {
            case .contextWindow, .other: return true
            case .safetyHostUnavailable, .guardrail, .assetsUnavailable, .systemBusy: return false
            }
        }

        /// Whether analysing the same recording again later could succeed
        /// without anything changing about the recording or the app.
        ///
        /// Distinct from `isRetryable`, which asks whether a *second immediate*
        /// attempt with a shorter prompt is worth the wait. A busy system fails
        /// both attempts now and succeeds unprompted in ten minutes.
        var isTransient: Bool {
            switch self {
            case .systemBusy: return true
            case .safetyHostUnavailable, .guardrail, .contextWindow, .assetsUnavailable, .other:
                return false
            }
        }

        /// What to tell the user when AI analysis did not run.
        var userFacingReason: String {
            switch self {
            case .safetyHostUnavailable:
                return "On-device AI was unavailable, so keyword analysis was used."
            case .guardrail:
                return "On-device AI declined this content, so keyword analysis was used."
            case .contextWindow:
                return "This recording was too long for on-device AI, so keyword analysis was used."
            case .assetsUnavailable:
                return "The on-device AI model isn't ready yet, so keyword analysis was used."
            case .systemBusy:
                return "The device was busy, so keyword analysis was used. Analysing again later should give a fuller result."
            case .other:
                return "On-device AI didn't complete, so keyword analysis was used."
            }
        }
    }

    static func classify(_ error: any Error) -> Kind {
        let text = String(describing: error)

        // Checked before the guardrail branch, and independently of it. The
        // framework reports this failure two different ways: as a
        // `guardrailViolation` carrying underlying errors, and — observed on
        // device — as a bare bridged `NSError` chain with no case name at all.
        // Gating the check on `guardrailViolation` missed the second form
        // entirely, classifying it `.other`, which is retryable, and spending a
        // second full round-trip on a failure that could not resolve.
        if mentionsBusySystem(text) { return .systemBusy }
        if mentionsSafetyHostFailure(text) { return .safetyHostUnavailable }

        if text.contains("guardrailViolation") {
            // Reached a real content judgement: no host failure above, so the
            // model evaluated the audio and refused it.
            return .guardrail
        }
        if text.contains("exceededContextWindowSize") { return .contextWindow }
        if text.contains("assetsUnavailable") { return .assetsUnavailable }
        return .other
    }

    /// Written into `AnalysisResult.aiSummary` when keyword classification stood
    /// in for on-device AI. The result model has no provenance field, so this
    /// marker is the only record of which path produced the analysis — keep it
    /// and `AnalysisResult.usedKeywordFallback` in step.
    static let keywordFallbackSummary =
        "Analysis via keyword classification (AI generation failed)."

    /// The marker followed by why the model did not run, so the detail screen
    /// can explain the badge instead of only displaying it.
    static func fallbackSummary(for kind: Kind) -> String {
        "\(keywordFallbackSummary) \(kind.userFacingReason)"
    }

    private static func mentionsSafetyHostFailure(_ text: String) -> Bool {
        text.contains("Failed model manager query")
            || text.contains("hostFailed")
            || text.contains("invalidClientData")
            || text.contains("SensitiveContentAnalysisML")
    }

    /// The system declining to run the model for now rather than failing at it.
    ///
    /// `ModelManagerError` 1013 is the durable signal; the phrasing and the
    /// bracketed state name ("StandardGameMode" on the device that surfaced
    /// this) are matched too, since the numeric code is not documented and may
    /// not be the only one used.
    private static func mentionsBusySystem(_ text: String) -> Bool {
        text.contains("ModelManagerError Code=1013")
            || text.contains("Not executed due to current system state")
    }
}

extension AnalysisResult {
    /// Whether keyword classification produced this result instead of the
    /// on-device model. Drives the badge, which otherwise credits AI for work
    /// it did not do.
    /// Prefix, not equality: results written before the reason was recorded
    /// carry the bare marker and must keep reading as fallbacks.
    var usedKeywordFallback: Bool {
        aiSummary.hasPrefix(AIGenerationDiagnosis.keywordFallbackSummary)
    }

    /// Why the on-device model did not produce this result, when that was
    /// recorded. `nil` for an AI result, and for a fallback stored before
    /// reasons were kept.
    var keywordFallbackReason: String? {
        guard usedKeywordFallback else { return nil }
        let reason = aiSummary
            .dropFirst(AIGenerationDiagnosis.keywordFallbackSummary.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? nil : reason
    }
}
