//
//  KeywordTaxonomyTests.swift
//  IlumionateTests
//
//  Tests for Step 1.3: Keyword collision fixes in HypnosisPhaseKeywords.
//  Verifies that the three targeted changes produce correct hit-map scores:
//    1. "deeply relaxed" (phrase) → .therapy wins, not .deepening
//    2. "deeper and deeper" (phrase) → .deepening wins
//    3. "whenever" → only scores .conditioning, not .suggestions
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Helpers

private func makeWord(_ text: String, at time: Double) -> WordTimestamp {
    WordTimestamp(word: text, startTime: time, duration: 1.0)
}

/// Builds a hit map from a sentence and returns the score map for second 0.
private func hitMapScores(for sentence: String) -> [HypnosisMetadata.Phase: Double] {
    let words = sentence.lowercased().components(separatedBy: .whitespaces)
    let timestamps = words.enumerated().map { idx, word in
        makeWord(word, at: Double(idx))
    }
    let analyzer = HypnosisPhaseAnalyzer()
    let bucketCount = max(1, words.count + 1)
    let hitMap = analyzer.buildHitMap(wordTimestamps: timestamps, bucketCount: bucketCount)

    // Sum all buckets so the whole sentence's signal is visible
    var totals: [HypnosisMetadata.Phase: Double] = [:]
    for bucket in hitMap {
        for (phase, score) in bucket {
            totals[phase, default: 0] += score
        }
    }
    return totals
}

// MARK: - Keyword Collision Tests

struct KeywordCollisionTests {

    // MARK: Fix 1: "deeply relaxed" → therapy must win over deepening

    @Test func deeplyRelaxedScoresTherapyHigherThanDeepening() {
        let scores = hitMapScores(for: "you are deeply relaxed")
        let therapy   = scores[.therapy]   ?? 0
        let deepening = scores[.deepening] ?? 0
        #expect(therapy > deepening,
            "therapy (\(therapy)) must beat deepening (\(deepening)) for 'deeply relaxed'")
    }

    @Test func deeplyRelaxedTherapyScoreAboveThreshold() {
        // The phrase "deeply relaxed" has weight 3.0; should clearly dominate
        let scores = hitMapScores(for: "you are deeply relaxed and comfortable")
        let therapy = scores[.therapy] ?? 0
        #expect(therapy >= 3.0,
            "therapy score should be ≥3.0 for 'deeply relaxed', got \(therapy)")
    }

    // MARK: Fix 2: "deeper and deeper" → deepening must clearly win

    @Test func deeperAndDeeperScoresDeepeningHighest() {
        let scores = hitMapScores(for: "going deeper and deeper now")
        let deepening = scores[.deepening] ?? 0
        let therapy   = scores[.therapy]   ?? 0
        #expect(deepening > therapy,
            "deepening (\(deepening)) must beat therapy (\(therapy)) for 'deeper and deeper'")
    }

    @Test func deeperAndDeeperScoreAboveThreshold() {
        // Multi-word phrase "deeper and deeper" weight 3.5 + "deeper" single 2.5
        let scores = hitMapScores(for: "deeper and deeper")
        let deepening = scores[.deepening] ?? 0
        #expect(deepening >= 3.5,
            "deepening score should be ≥3.5, got \(deepening)")
    }

    // MARK: Fix 3: "whenever" → only conditioning, not suggestions

    @Test func wheneverScoresConditioningNotSuggestions() {
        // Use an isolated sentence: only "whenever" appears — no other suggestion triggers
        let scores = hitMapScores(for: "whenever that happens")
        let conditioning = scores[.conditioning] ?? 0
        let suggestions  = scores[.suggestions]  ?? 0
        #expect(conditioning > 0,
            "conditioning must score >0 for 'whenever'")
        #expect(suggestions == 0,
            "suggestions must be 0 for 'whenever' alone — it was removed from that list, got \(suggestions)")
    }

    @Test func wheneverOnlyAppearsInConditioningTaxonomy() {
        // Exhaustive check: "whenever" keyword must not exist in suggestionsWords
        let suggestionsEntries = HypnosisPhaseKeywords.all.filter {
            $0.phrase == "whenever" && $0.phase == .suggestions
        }
        #expect(suggestionsEntries.isEmpty,
            "'whenever' must not appear in suggestions taxonomy, found \(suggestionsEntries.count) entry/entries")

        // And must still exist in conditioning
        let conditioningEntries = HypnosisPhaseKeywords.all.filter {
            $0.phrase == "whenever" && $0.phase == .conditioning
        }
        #expect(!conditioningEntries.isEmpty,
            "'whenever' must still appear in conditioning taxonomy")
    }

    // MARK: Regression: single "deep" no longer dominates therapy sections

    @Test func singleWordDeepDoesNotOutscoreTherapyPhrases() {
        // A therapy sentence that contains the word "deep" should still score therapy highest
        let scores = hitMapScores(for: "you are in a deep comfortable trance now deeply relaxed")
        let therapy   = scores[.therapy]   ?? 0
        let deepening = scores[.deepening] ?? 0
        #expect(therapy > deepening,
            "therapy (\(therapy)) must win over deepening (\(deepening)) in a therapy sentence")
    }

    @Test func singleWordDeepWeightIsLow() {
        // "deep" single-word entry must have weight ≤ 0.7 (was 1.8 before fix)
        let deepEntry = HypnosisPhaseKeywords.all.first {
            $0.phrase == "deep" && $0.phase == .deepening
        }
        #expect(deepEntry != nil, "'deep' entry must still exist in deepening")
        if let entry = deepEntry {
            #expect(entry.weight <= 0.7,
                "'deep' single-word weight must be ≤0.7 after fix, got \(entry.weight)")
        }
    }

    // MARK: Completeness: multi-word phrases still carry full weight

    @Test func deeplyRelaxedMultiWordWeightIsHigh() {
        let entry = HypnosisPhaseKeywords.all.first {
            $0.phrase == "deeply relaxed" && $0.phase == .therapy
        }
        #expect(entry != nil, "'deeply relaxed' must exist in therapy")
        if let entry {
            #expect(entry.weight >= 3.0,
                "'deeply relaxed' weight must be ≥3.0, got \(entry.weight)")
        }
    }
}
