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

    /// Captured verbatim from a device log, 2026-08-11. Note what is *absent*:
    /// no `guardrailViolation`, because Foundation Models surfaced this one as a
    /// bridged `NSError` chain rather than the Swift enum case. The old
    /// classifier only looked for a safety-host failure nested inside a
    /// guardrail violation, so this fell through to `.other` — which is
    /// retryable, and bought a second full round-trip that failed identically.
    private static let gameModeFailure = StubError(description: """
    Error Domain=FoundationModels.LanguageModelSession.GenerationError Code=-1 \
    "(null)" UserInfo={NSMultipleUnderlyingErrorsKey=("Error Domain=\
    com.apple.SensitiveContentAnalysisML Code=15 "Failed model manager query for \
    model com.apple.fm.language.instruct_300m.safety: Not executed due to current \
    system state [\\"StandardGameMode\\"], try again later" UserInfo={\
    NSUnderlyingError=Error Domain=ModelManagerServices.ModelManagerError \
    Code=1013 "Not executed due to current system state [\\"StandardGameMode\\"], \
    try again later"})}
    """)

    @Test("A device too busy to run the model is not an unknown error")
    func systemBusyIsIdentified() {
        let kind = AIGenerationDiagnosis.classify(Self.gameModeFailure)

        #expect(kind == .systemBusy)
        // A shorter prompt cannot change the system's state.
        #expect(kind.isRetryable == false)
        // Unlike the other failures, this one is worth trying again later.
        #expect(kind.isTransient)
    }

    @Test("A safety-host failure is caught even without a guardrail wrapper")
    func safetyHostFailureOutsideAGuardrailIsIdentified() {
        let error = StubError(description: """
        Error Domain=com.apple.SensitiveContentAnalysisML Code=15 "Failed model \
        manager query for model com.apple.fm.language.instruct_300m.safety: \
        InferenceError::hostFailed"
        """)

        let kind = AIGenerationDiagnosis.classify(error)

        #expect(kind == .safetyHostUnavailable)
        #expect(kind.isRetryable == false)
    }

    @Test("Only a passing system condition is worth another attempt later")
    func transiencePolicyIsExplicit() {
        let transient = AIGenerationDiagnosis.Kind.allCases.filter(\.isTransient)

        // Both are the system declining for now rather than failing at the
        // work, so the same recording succeeds later untouched.
        #expect(Set(transient) == [.systemBusy, .rateLimited])
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

    // MARK: - Carrying the reason onto the result

    private func makeResult(aiSummary: String) -> AnalysisResult {
        AnalysisResult(
            mood: .relaxing,
            energyLevel: 0.2,
            suggestedFrequencyRange: 4...8,
            suggestedIntensity: 0.5,
            keyMoments: [],
            aiSummary: aiSummary,
            recommendedPreset: "Test"
        )
    }

    @Test("A fallback result is still recognised once it carries a reason")
    func fallbackIsRecognisedWithAReasonAppended() {
        let result = makeResult(
            aiSummary: AIGenerationDiagnosis.fallbackSummary(for: .systemBusy)
        )

        #expect(result.usedKeywordFallback)
    }

    @Test("The reason is recoverable from the stored result")
    func reasonSurvivesOnTheResult() throws {
        let result = makeResult(
            aiSummary: AIGenerationDiagnosis.fallbackSummary(for: .systemBusy)
        )

        let reason = try #require(result.keywordFallbackReason)
        #expect(reason == AIGenerationDiagnosis.Kind.systemBusy.userFacingReason)
    }

    @Test("An AI-produced result reports no fallback and no reason")
    func aiResultHasNoFallbackReason() {
        let result = makeResult(aiSummary: "A genuine model summary of the recording.")

        #expect(result.usedKeywordFallback == false)
        #expect(result.keywordFallbackReason == nil)
    }

    // Results written before the reason was recorded carry the bare marker.
    @Test("A result stored before reasons existed is still a fallback")
    func legacyFallbackMarkerStillCounts() {
        let result = makeResult(aiSummary: AIGenerationDiagnosis.keywordFallbackSummary)

        #expect(result.usedKeywordFallback)
        #expect(result.keywordFallbackReason == nil)
    }
}

// MARK: - Rate limiting

/// Device text captured verbatim on 2026-08-17 while the analysis queue worked
/// through twelve resumed files in the background.
extension AIGenerationDiagnosisTests {

    private struct RateLimitStub: Error, CustomStringConvertible {
        let description: String
    }

    /// The bare form, as thrown by `LanguageModelSession.respond`.
    private static let rateLimitFailure = RateLimitStub(description: """
    rateLimited(FoundationModels.LanguageModelSession.GenerationError.Context(\
    debugDescription: "Request has been rate limited. Please try again later.\\n\\n\
    If you are using streaming responses in a background request, consider using \
    non-streaming requests in background activities to reduce the likelihood of \
    rate limiting.", underlyingErrors: [], errorDescriptionOverride: nil))
    """)

    /// The wrapped form, where the rate limit surfaces through the safety
    /// classifier's model-manager query.
    private static let rateLimitedSafetyQuery = RateLimitStub(description: """
    Error Domain=com.apple.SensitiveContentAnalysisML Code=15 "Failed model manager \
    query for model com.apple.fm.language.instruct_300m.safety: Rate limited. Wait a \
    little bit and then try again." UserInfo={NSUnderlyingError=0x11d244f00 \
    {Error Domain=com.apple.GenerativeFunctionsFoundation.GenerativeError \
    Code=1010000 "Rate limited. Wait a little bit and then try again."}}
    """)

    @Test("Rate limiting is identified rather than filed as unknown")
    func rateLimitIsIdentified() {
        let kind = AIGenerationDiagnosis.classify(Self.rateLimitFailure)

        #expect(kind == .rateLimited)
        // Retrying immediately sends a second request into an active rate
        // limit: it cannot succeed and makes the limit worse.
        #expect(kind.isRetryable == false)
        // But the same file will analyse fine once the limit clears.
        #expect(kind.isTransient)
    }

    /// The wrapped form also matches `Failed model manager query` and
    /// `SensitiveContentAnalysisML`, so without an earlier rate-limit check it
    /// reads as a broken safety host — not retryable *and* not transient, which
    /// strands the file.
    @Test("A rate-limited safety query is not mistaken for a broken safety host")
    func rateLimitedSafetyQueryIsNotASafetyHostFailure() {
        let kind = AIGenerationDiagnosis.classify(Self.rateLimitedSafetyQuery)

        #expect(kind == .rateLimited)
        #expect(kind != .safetyHostUnavailable)
        #expect(kind.isTransient)
    }

    /// Regression guard: adding the rate-limit check ahead of the others must
    /// not steal the Game Mode case.
    @Test("Game Mode still classifies as a busy system after the rate-limit check")
    func gameModeStillClassifiesAsSystemBusy() {
        #expect(AIGenerationDiagnosis.classify(Self.gameModeFailure) == .systemBusy)
    }

    @Test("A safety-host failure with no rate limit still reads as a host failure")
    func plainSafetyHostFailureIsUnaffected() {
        let error = RateLimitStub(description: """
        Error Domain=com.apple.SensitiveContentAnalysisML Code=15 "Failed model \
        manager query for model com.apple.fm.language.instruct_300m.safety: \
        hostFailed"
        """)

        #expect(AIGenerationDiagnosis.classify(error) == .safetyHostUnavailable)
    }
}
