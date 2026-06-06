//
//  TechniqueDetector+AdvancedTechniques.swift
//  Ilumionate
//
//  Advanced technique detectors: confusion, amnesia, dissociation,
//  age regression, hallucination, double binds, and brainwashing.
//  Split from TechniqueDetector.swift for file-length compliance.
//

import Foundation

// MARK: - Pattern-Based Detection Helpers

private extension TechniqueDetector {

    /// Scans word timestamps for multi-word pattern matches and emits
    /// technique + marker pairs for each hit.
    func detectPatterns(
        wordTimestamps: [WordTimestamp],
        patterns: [[String]],
        techniqueName: String,
        markerType: LinguisticMarker.MarkerType,
        descriptionPrefix: String,
        suggestedLightSync: String,
        strength: Double,
        caseSensitive: Bool = false
    ) -> TechniqueDetectionResult {
        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        for windowStart in 0..<wordTimestamps.count {
            for pattern in patterns {
                let windowEnd = windowStart + pattern.count
                guard windowEnd <= wordTimestamps.count else { continue }

                let windowWords = wordTimestamps[windowStart..<windowEnd]
                let matches = zip(windowWords, pattern).allSatisfy { word, target in
                    let cleaned = word.word.trimmingCharacters(in: .punctuationCharacters)
                    if caseSensitive { return cleaned == target }
                    return cleaned.lowercased() == target.lowercased()
                }
                guard matches else { continue }

                let timestamp = wordTimestamps[windowStart].startTime
                let phrase = pattern.joined(separator: " ")

                techniques.append(HypnoticTechnique(
                    technique: techniqueName,
                    timestamp: timestamp,
                    description: "\(descriptionPrefix): \"\(phrase)\"",
                    suggestedLightSync: suggestedLightSync
                ))
                markers.append(LinguisticMarker(
                    type: markerType,
                    timestamp: timestamp,
                    textSnippet: phrase,
                    strength: strength
                ))
            }
        }

        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }
}

// MARK: - Advanced Technique Detectors

extension TechniqueDetector {

    // MARK: Metaphorical Story

    func detectMetaphoricalStories(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        let patterns: [[String]] = [
            ["let", "me", "tell", "you", "a", "story"],
            ["i", "want", "to", "tell", "you", "a", "story"],
            ["there", "was", "once"],
            ["once", "upon", "a", "time"],
            ["a", "parable"],
            ["a", "metaphor", "for"],
            ["this", "story", "is", "about"]
        ]

        return detectPatterns(
            wordTimestamps: wordTimestamps,
            patterns: patterns,
            techniqueName: "metaphorical_story",
            markerType: .metaphoricalStory,
            descriptionPrefix: "Metaphorical story",
            suggestedLightSync: "narrative_color_drift",
            strength: 0.8
        )
    }

    // MARK: Utilization / Ericksonian Response Following

    func detectUtilizationLanguage(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        let patterns: [[String]] = [
            ["thats", "right"],
            ["that's", "right"],
            ["use", "that"],
            ["use", "that", "feeling"],
            ["whatever", "happens"],
            ["in", "your", "own", "way"],
            ["your", "unconscious", "mind"],
            ["inner", "resources"],
            ["you", "may", "notice"],
            ["you", "can", "notice"]
        ]

        return detectPatterns(
            wordTimestamps: wordTimestamps,
            patterns: patterns,
            techniqueName: "utilization",
            markerType: .utilizationOfResponse,
            descriptionPrefix: "Utilization / response-following",
            suggestedLightSync: "adaptive_follow_mode",
            strength: 0.72
        )
    }

    // MARK: Confusion Technique

    func detectConfusionTechnique(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        let patterns: [[String]] = [
            ["you", "know", "that", "you", "don't", "know"],
            ["the", "more", "you", "try", "the", "less"],
            ["don't", "try", "to", "understand"],
            ["you", "can't", "not"],
            ["try", "not", "to"],
            ["the", "harder", "you", "try"],
            ["you", "don't", "need", "to", "understand"],
            ["isn't", "it", "interesting"],
            ["isn't", "it", "curious"],
            ["can", "you", "not"],
            ["that's", "right", "isn't", "it"]
        ]

        return detectPatterns(
            wordTimestamps: wordTimestamps,
            patterns: patterns,
            techniqueName: "confusion_technique",
            markerType: .confusionTechnique,
            descriptionPrefix: "Confusion technique",
            suggestedLightSync: "erratic_pattern_then_resolve",
            strength: 0.75
        )
    }

    // MARK: Amnesia Suggestion

    func detectAmnesiaSuggestions(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        let patterns: [[String]] = [
            ["won't", "remember"],
            ["won't", "need", "to", "remember"],
            ["don't", "need", "to", "remember"],
            ["let", "it", "fade"],
            ["slip", "away"],
            ["no", "need", "to", "recall"],
            ["forget", "everything"],
            ["forget", "what", "happened"],
            ["fade", "from", "memory"],
            ["drift", "from", "your", "mind"],
            ["leave", "it", "behind"],
            ["can't", "remember"],
            ["cannot", "remember"],
            ["hard", "to", "remember"],
            ["impossible", "to", "recall"],
            ["memories", "fading"],
            ["memories", "dissolving"],
            ["thoughts", "fading"],
            ["thoughts", "dissolving"],
            ["like", "a", "dream"],
            ["as", "if", "it", "never"],
            ["you", "will", "forget"],
            ["forget", "this"],
            ["mind", "going", "blank"],
            ["mind", "goes", "blank"],
            ["blank", "and", "empty"]
        ]

        return detectPatterns(
            wordTimestamps: wordTimestamps,
            patterns: patterns,
            techniqueName: "amnesia_suggestion",
            markerType: .amnesiaSuggestion,
            descriptionPrefix: "Amnesia suggestion",
            suggestedLightSync: "slow_fade_to_minimum",
            strength: 0.85
        )
    }

    // MARK: Dissociation

    func detectDissociation(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        let patterns: [[String]] = [
            ["watching", "yourself"],
            ["see", "yourself"],
            ["looking", "down", "at"],
            ["from", "a", "distance"],
            ["from", "above"],
            ["outside", "your", "body"],
            ["out", "of", "your", "body"],
            ["separate", "from"],
            ["detach", "from"],
            ["floating", "above"],
            ["observing", "yourself"],
            ["step", "outside"],
            ["step", "back"],
            ["third", "person"],
            ["as", "if", "watching"],
            ["like", "watching", "a", "movie"],
            ["on", "a", "screen"],
            ["another", "you"],
            ["part", "of", "you"],
            ["the", "other", "you"]
        ]

        return detectPatterns(
            wordTimestamps: wordTimestamps,
            patterns: patterns,
            techniqueName: "dissociation",
            markerType: .dissociation,
            descriptionPrefix: "Dissociation",
            suggestedLightSync: "bilateral_split_diverge",
            strength: 0.8
        )
    }

    // MARK: Age Regression

    func detectAgeRegression(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        let patterns: [[String]] = [
            ["go", "back", "to"],
            ["going", "back", "to"],
            ["take", "you", "back"],
            ["taking", "you", "back"],
            ["return", "to", "a", "time"],
            ["back", "to", "a", "time"],
            ["when", "you", "were", "young"],
            ["when", "you", "were", "little"],
            ["when", "you", "were", "a", "child"],
            ["as", "a", "child"],
            ["younger", "you"],
            ["younger", "self"],
            ["inner", "child"],
            ["remember", "being"],
            ["remember", "when", "you"],
            ["earlier", "time"],
            ["first", "time", "you"],
            ["childhood", "memory"],
            ["long", "ago"],
            ["years", "ago"]
        ]

        return detectPatterns(
            wordTimestamps: wordTimestamps,
            patterns: patterns,
            techniqueName: "age_regression",
            markerType: .ageRegression,
            descriptionPrefix: "Age regression",
            suggestedLightSync: "warm_slow_pulse",
            strength: 0.8
        )
    }

    // MARK: Hallucination Suggestion

    func detectHallucination(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        // Positive hallucination (seeing/hearing something not there) and
        // negative hallucination (not perceiving something present)
        let patterns: [[String]] = [
            ["you", "begin", "to", "see"],
            ["you", "begin", "to", "hear"],
            ["imagine", "you", "see"],
            ["imagine", "you", "hear"],
            ["picture", "in", "your", "mind"],
            ["see", "it", "clearly"],
            ["hear", "the", "sound"],
            ["as", "if", "you", "can", "see"],
            ["you", "no", "longer", "see"],
            ["you", "no", "longer", "hear"],
            ["you", "no", "longer", "feel"],
            ["disappears", "from", "view"],
            ["fades", "from", "view"],
            ["cannot", "see"],
            ["cannot", "hear"],
            ["cannot", "feel"],
            ["invisible", "to", "you"],
            ["a", "voice", "that", "isn't", "there"],
            ["see", "something", "that", "isn't", "there"]
        ]

        return detectPatterns(
            wordTimestamps: wordTimestamps,
            patterns: patterns,
            techniqueName: "hallucination_suggestion",
            markerType: .hallucination,
            descriptionPrefix: "Hallucination suggestion",
            suggestedLightSync: "color_shift_immersive",
            strength: 0.7
        )
    }

    // MARK: Double Bind

    func detectDoubleBinds(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        let patterns: [[String]] = [
            ["you", "can", "either"],
            ["you", "may", "choose", "to"],
            ["sooner", "or", "later"],
            ["now", "or", "in", "a", "moment"],
            ["before", "or", "after"],
            ["one", "way", "or", "another"],
            ["either", "way"],
            ["the", "choice", "is", "yours"],
            ["it", "doesn't", "matter", "whether"],
            ["it", "doesn't", "matter", "if"],
            ["perhaps", "now", "or", "perhaps"]
        ]

        return detectPatterns(
            wordTimestamps: wordTimestamps,
            patterns: patterns,
            techniqueName: "double_bind",
            markerType: .doubleBinding,
            descriptionPrefix: "Double bind",
            suggestedLightSync: "gentle_bilateral_alternation",
            strength: 0.7
        )
    }

    // MARK: Brainwashing

    /// Detects brainwashing patterns: heavy repetitive conditioning, identity
    /// overwrite language, obedience reinforcement, and thought-stopping phrases.
    func detectBrainwashing(
        wordTimestamps: [WordTimestamp],
        duration: TimeInterval
    ) -> TechniqueDetectionResult {
        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        // Pattern-based detection for identity overwrite and obedience phrases
        let brainwashPatterns: [[String]] = [
            ["you", "must", "obey"],
            ["you", "will", "obey"],
            ["you", "have", "no", "choice"],
            ["you", "cannot", "resist"],
            ["you", "can't", "resist"],
            ["resistance", "is", "futile"],
            ["stop", "thinking"],
            ["don't", "think"],
            ["do", "not", "think"],
            ["empty", "your", "mind"],
            ["blank", "mind"],
            ["mindless"],
            ["you", "are", "nothing"],
            ["belong", "to", "me"],
            ["you", "exist", "to"],
            ["say", "it", "again"],
            ["repeat", "after", "me"],
            ["say", "yes"],
            ["you", "love", "to", "obey"],
            ["obedience", "is", "pleasure"],
            ["surrender", "your", "will"],
            ["give", "up", "control"],
            ["I", "control", "you"],
            ["you", "are", "programmed"],
            ["programming", "complete"],
            ["deeper", "into", "obedience"],
            ["sink", "into", "obedience"]
        ]

        let patternResult = detectPatterns(
            wordTimestamps: wordTimestamps,
            patterns: brainwashPatterns,
            techniqueName: "brainwashing",
            markerType: .brainwashing,
            descriptionPrefix: "Brainwashing",
            suggestedLightSync: "deep_rhythmic_pulse",
            strength: 0.9
        )
        techniques.append(contentsOf: patternResult.techniques)
        markers.append(contentsOf: patternResult.markers)

        // Density-based detection: high repetition of obedience keywords
        // within a short window signals conditioning loops
        let conditioningKeywords = Set([
            "obey", "submit", "surrender", "comply", "serve",
            "programmed", "brainwashed", "mindless", "empty",
            "drone", "slave", "puppet"
        ])

        let windowSize: TimeInterval = 45.0
        let minimumKeywordHits = 6
        let minimumUniqueKeywords = 3
        var windowStart: TimeInterval = 0

        while windowStart < duration {
            let windowEnd = min(windowStart + windowSize, duration)
            let windowWords = wordTimestamps.filter {
                $0.startTime >= windowStart && $0.startTime < windowEnd
            }

            let hits = windowWords.filter { word in
                conditioningKeywords.contains(
                    word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                )
            }

            let uniqueHits = Set(hits.map {
                $0.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            })

            // Require both repetition and variety to avoid flagging ordinary emphasis.
            if hits.count >= minimumKeywordHits,
               uniqueHits.count >= minimumUniqueKeywords,
               let firstHit = hits.first {
                techniques.append(HypnoticTechnique(
                    technique: "brainwashing_conditioning_loop",
                    timestamp: firstHit.startTime,
                    description: "High-density conditioning: \(hits.count) obedience keywords in \(Int(windowSize))s",
                    suggestedLightSync: "deep_rhythmic_pulse"
                ))
                markers.append(LinguisticMarker(
                    type: .brainwashing,
                    timestamp: firstHit.startTime,
                    textSnippet: "conditioning loop (\(hits.count) keywords)",
                    strength: min(1.0, Double(hits.count) / 6.0)
                ))
            }

            windowStart += windowSize * 0.5 // 50% overlap for sensitivity
        }

        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }
}
