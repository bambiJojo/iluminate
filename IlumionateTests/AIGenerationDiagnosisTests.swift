//
//  AIGenerationDiagnosisTests.swift
//  IlumionateTests
//
//  Foundation Models reports a broken safety classifier as a guardrail violation
//  against the user's audio. Telling those apart decides whether a retry is worth
//  spending and what the user is told, so the distinction is pinned here against
//  the real error text captured from a device log.
//

import Foundation
import Testing

@testable import Ilumionate

@Suite("AI generation diagnosis")
struct AIGenerationDiagnosisTests {

    /// Captured verbatim from the simulator, 2026-08-09.
    private struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    private static let safetyHostFailure = StubError(description: """
    guardrailViolation(FoundationModels.LanguageModelSession.GenerationError.Context(\
    debugDescription: "May contain sensitive or unsafe content", underlyingErrors: \
    [Error Domain=com.apple.SensitiveContentAnalysisML Code=15 "Failed model manager \
    query for model com.apple.fm.language.instruct_300m.safety: \
    InferenceError::hostFailed::InferenceError::invalidClientData::\
    DecodingError.keyNotFound: Key '_promptRequest' not found in keyed decoding \
    container. Path: countTokens._0"]))
    """)

    @Test("A guardrail caused by a broken safety host is not a content refusal")
    func safetyHostFailureIsNotAContentRefusal() {
        let kind = AIGenerationDiagnosis.classify(Self.safetyHostFailure)

        #expect(kind == .safetyHostUnavailable)
        #expect(kind.isRetryable == false)
    }

    @Test("A genuine guardrail violation is reported as one")
    func genuineGuardrailIsIdentified() {
        let error = StubError(description: """
        guardrailViolation(Context(debugDescription: "May contain sensitive or \
        unsafe content", underlyingErrors: []))
        """)

        #expect(AIGenerationDiagnosis.classify(error) == .guardrail)
    }

    @Test("Context overflow is the one worth retrying")
    func contextOverflowIsRetryable() {
        let error = StubError(description: "exceededContextWindowSize(Context(...))")
        let kind = AIGenerationDiagnosis.classify(error)

        #expect(kind == .contextWindow)
        #expect(kind.isRetryable)
    }

    @Test("Missing model assets are identified and not retried")
    func assetsUnavailableIsNotRetried() {
        let error = StubError(description: "assetsUnavailable(Context(...))")
        let kind = AIGenerationDiagnosis.classify(error)

        #expect(kind == .assetsUnavailable)
        #expect(kind.isRetryable == false)
    }

    @Test("An unrecognised error stays retryable rather than being written off")
    func unknownErrorsStayRetryable() {
        let kind = AIGenerationDiagnosis.classify(
            StubError(description: "some future framework error")
        )

        #expect(kind == .other)
        #expect(kind.isRetryable)
    }

    @Test("Every kind explains itself to the user", arguments: AIGenerationDiagnosis.Kind.allCases)
    func everyKindHasUserFacingCopy(kind: AIGenerationDiagnosis.Kind) {
        #expect(kind.userFacingReason.isEmpty == false)
        // The user is told keyword analysis ran, never left guessing.
        #expect(kind.userFacingReason.localizedStandardContains("keyword"))
    }

    @Test("Only deterministic failures skip the retry")
    func retryPolicyIsExplicit() {
        let retryable = AIGenerationDiagnosis.Kind.allCases.filter(\.isRetryable)

        #expect(Set(retryable) == [.contextWindow, .other])
    }
}
