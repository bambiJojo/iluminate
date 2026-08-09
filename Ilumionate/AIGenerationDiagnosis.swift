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

enum AIGenerationDiagnosis {

    enum Kind: String, Equatable, Sendable, CaseIterable {
        /// The safety classifier itself could not run; the framework failed
        /// closed and reported it as a guardrail violation.
        case safetyHostUnavailable
        /// The content was evaluated and refused.
        case guardrail
        /// Prompt and transcript exceeded the context window.
        case contextWindow
        /// The on-device model is not installed or not ready.
        case assetsUnavailable
        case other

        /// Only a context overflow is plausibly fixed by the shorter prompt.
        /// The rest are deterministic, so a retry just doubles the wait.
        var isRetryable: Bool {
            switch self {
            case .contextWindow, .other: return true
            case .safetyHostUnavailable, .guardrail, .assetsUnavailable: return false
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
            case .other:
                return "On-device AI didn't complete, so keyword analysis was used."
            }
        }
    }

    static func classify(_ error: any Error) -> Kind {
        let text = String(describing: error)

        if text.contains("guardrailViolation") {
            // A guardrail violation whose underlying error is a host or decoding
            // failure never reached a content judgement.
            return mentionsSafetyHostFailure(text) ? .safetyHostUnavailable : .guardrail
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

    private static func mentionsSafetyHostFailure(_ text: String) -> Bool {
        text.contains("Failed model manager query")
            || text.contains("hostFailed")
            || text.contains("invalidClientData")
            || text.contains("SensitiveContentAnalysisML")
    }
}

extension AnalysisResult {
    /// Whether keyword classification produced this result instead of the
    /// on-device model. Drives the badge, which otherwise credits AI for work
    /// it did not do.
    var usedKeywordFallback: Bool {
        aiSummary == AIGenerationDiagnosis.keywordFallbackSummary
    }
}
