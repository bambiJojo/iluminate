//
//  DeferredAIAnalysisTests.swift
//  IlumionateTests
//
//  The pipeline logged "↺ Transient — analysing this file again later should
//  succeed" and then cleared the checkpoint, so nothing could. Device evidence
//  on 2026-08-17: foreground 0/16 used AI, and sixteen files were permanently
//  downgraded by a condition that was going to pass.
//

import Testing
import Foundation
@testable import Ilumionate

struct DeferredAIAnalysisTests {

    // MARK: Eligibility

    /// Only the kinds that will pass on their own. A guardrail refusal is the
    /// model having evaluated the content and declined — retrying it is an
    /// infinite loop against a deterministic answer.
    @Test(
        "Transient fallbacks are eligible for a later AI attempt",
        arguments: [AIGenerationDiagnosis.Kind.systemBusy, .rateLimited]
    )
    func transientFallbacksAreEligible(kind: AIGenerationDiagnosis.Kind) {
        #expect(DeferredAIAnalysisPolicy.isEligible(fallbackKind: kind, attempts: 0))
    }

    @Test(
        "A settled answer is never retried",
        arguments: [
            AIGenerationDiagnosis.Kind.guardrail,
            .assetsUnavailable,
            .contextWindow,
            .safetyHostUnavailable,
            .other
        ]
    )
    func nonTransientFallbacksAreNotEligible(kind: AIGenerationDiagnosis.Kind) {
        #expect(DeferredAIAnalysisPolicy.isEligible(fallbackKind: kind, attempts: 0) == false)
    }

    @Test("A result the model produced is not a retry candidate")
    func successfulAnalysisIsNotEligible() {
        #expect(DeferredAIAnalysisPolicy.isEligible(fallbackKind: nil, attempts: 0) == false)
    }

    /// A device with Game Mode permanently on must stop trying rather than
    /// retry every time it backgrounds, forever.
    @Test("Retries stop at the ceiling")
    func retriesAreBounded() {
        let ceiling = DeferredAIAnalysisPolicy.maximumRetryAttempts
        #expect(DeferredAIAnalysisPolicy.isEligible(fallbackKind: .systemBusy, attempts: ceiling - 1))
        #expect(DeferredAIAnalysisPolicy.isEligible(fallbackKind: .systemBusy, attempts: ceiling) == false)
        #expect(DeferredAIAnalysisPolicy.isEligible(fallbackKind: .systemBusy, attempts: ceiling + 1) == false)
    }

    @Test("A window takes a bounded slice, oldest attempt first")
    func windowIsBoundedAndOrdered() {
        let candidates = (0..<12).map { index in
            DeferredAIAnalysisCandidate(
                audioFileID: UUID(),
                attempts: 0,
                lastAttemptAt: Date(timeIntervalSince1970: TimeInterval(100 - index))
            )
        }

        let selected = DeferredAIAnalysisPolicy.selectForWindow(candidates)

        #expect(selected.count == DeferredAIAnalysisPolicy.maximumPerWindow)
        // Oldest first: the file waiting longest goes first.
        #expect(selected.first?.lastAttemptAt == Date(timeIntervalSince1970: 89))
    }

    @Test("A never-attempted candidate sorts ahead of one already tried")
    func neverAttemptedGoesFirst() {
        let tried = DeferredAIAnalysisCandidate(
            audioFileID: UUID(),
            attempts: 1,
            lastAttemptAt: Date(timeIntervalSince1970: 0)
        )
        let fresh = DeferredAIAnalysisCandidate(
            audioFileID: UUID(),
            attempts: 0,
            lastAttemptAt: nil
        )

        let selected = DeferredAIAnalysisPolicy.selectForWindow([tried, fresh])

        #expect(selected.first?.audioFileID == fresh.audioFileID)
    }

    // MARK: Checkpoint retention

    /// The behaviour the whole change exists for: a transient failure must
    /// leave something to resume from.
    @Test(
        "A transient failure keeps its checkpoint",
        arguments: [AIGenerationDiagnosis.Kind.systemBusy, .rateLimited]
    )
    func transientFailureRetainsCheckpoint(kind: AIGenerationDiagnosis.Kind) {
        #expect(DeferredAIAnalysisPolicy.retainsCheckpoint(after: kind))
    }

    @Test(
        "A settled failure clears its checkpoint",
        arguments: [AIGenerationDiagnosis.Kind.guardrail, .assetsUnavailable, .other]
    )
    func settledFailureClearsCheckpoint(kind: AIGenerationDiagnosis.Kind) {
        #expect(DeferredAIAnalysisPolicy.retainsCheckpoint(after: kind) == false)
    }
}

// MARK: - Provenance on the stored result

struct AnalysisResultProvenanceTests {

    private func result(fallbackKind: AIGenerationDiagnosis.Kind?) -> AnalysisResult {
        AnalysisResult(
            mood: .relaxing,
            energyLevel: 0.2,
            suggestedFrequencyRange: 8...12,
            suggestedIntensity: 0.5,
            keyMoments: [],
            aiSummary: "summary",
            recommendedPreset: "Alpha Relaxation",
            aiFallbackKind: fallbackKind
        )
    }

    @Test("The kind that caused a fallback survives a round trip")
    func fallbackKindRoundTrips() throws {
        let encoded = try JSONEncoder().encode(result(fallbackKind: .rateLimited))
        let decoded = try JSONDecoder().decode(AnalysisResult.self, from: encoded)

        #expect(decoded.aiFallbackKind == .rateLimited)
    }

    @Test("A model-produced result records no fallback kind")
    func successfulResultHasNoFallbackKind() throws {
        let encoded = try JSONEncoder().encode(result(fallbackKind: nil))
        let decoded = try JSONDecoder().decode(AnalysisResult.self, from: encoded)

        #expect(decoded.aiFallbackKind == nil)
    }

    /// 117 cached results predate this field. Decoding must not throw, or the
    /// library's whole analysis cache is lost on upgrade.
    @Test("A result stored before the field existed still decodes")
    func resultWithoutTheFieldStillDecodes() throws {
        let encoded = try JSONEncoder().encode(result(fallbackKind: .systemBusy))
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "aiFallbackKind")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AnalysisResult.self, from: legacy)

        #expect(decoded.aiFallbackKind == nil)
        #expect(decoded.mood == .relaxing)
    }
}

// MARK: - Rebuild hazard, resolved
//
// `AnalysisResult` is reconstructed field-by-field in five files, and every one
// of those sites drops any field it does not name. `aiFallbackKind` was lost
// that way twice in a day: once in `makeKeywordFallbackResult`, caught by
// reading the code, and once in `AudioAnalysisEnricher` — which runs on every
// analysis, so it reached the device and made every rate-limited file clear its
// checkpoint instead of deferring.
//
// `AnalysisResult.with(...)` now exists for this: it copies by default and
// overrides only what it is given. `AudioAnalysisEnricher` uses it, and
// `AnalysisResultCopyTests` covers both the helper and that path.
//
// `makeKeywordFallbackResult` still calls `init` and names the field by hand,
// as do KnownAudioCatalog, PlaylistWholeSessionAnalyzer, and
// ConcurrencyOptimizations. Those four carry the same hazard for the next field
// added, and converting them is the obvious follow-up.
