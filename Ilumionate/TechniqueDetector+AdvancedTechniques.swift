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

    // MARK: Confusion Technique

    func detectConfusionTechnique(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        let patterns: [[String]] = [
            ["you", "know", "that", "you", "don't", "know"],
            ["the", "more", "you", "try", "the", "less"],
            ["don't", "try", "to", "understand"],
            ["don't", "think", "about"],
            ["you", "can't", "not"],
            ["try", "not", "to"],
            ["the", "harder", "you", "try"],
            ["you", "don't", "need", "to", "understand"],
            ["isn't", "it", "interesting"],
            ["isn't", "it", "curious"],
            ["can", "you", "not"],
            ["you", "may", "wonder"],
            ["you", "might", "wonder"],
            ["I", "wonder", "if", "you"],
            ["which", "means", "that"],
            ["or", "does", "it"],
            ["or", "is", "it"],
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
            ["you", "can", "see"],
            ["you", "can", "hear"],
            ["you", "can", "feel"],
            ["you", "can", "smell"],
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
            ["a", "beautiful", "light"],
            ["a", "warm", "light"],
            ["a", "golden", "light"],
            ["you", "notice", "a"]
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
            ["whether", "you"],
            ["you", "may", "choose", "to"],
            ["sooner", "or", "later"],
            ["now", "or", "in", "a", "moment"],
            ["before", "or", "after"],
            ["one", "way", "or", "another"],
            ["either", "way"],
            ["the", "choice", "is", "yours"],
            ["you", "can", "choose"],
            ["it", "doesn't", "matter", "whether"],
            ["it", "doesn't", "matter", "if"],
            ["perhaps", "now", "or", "perhaps"],
            ["you", "might", "already"],
            ["I", "don't", "know", "if"],
            ["I", "don't", "know", "whether"]
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
            ["you", "are", "mine"],
            ["belong", "to", "me"],
            ["I", "own", "you"],
            ["you", "exist", "to"],
            ["your", "only", "purpose"],
            ["good", "girl"],
            ["good", "boy"],
            ["good", "pet"],
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
            ["accept", "this", "truth"],
            ["this", "is", "your", "truth"],
            ["you", "know", "this", "is", "true"],
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
            "drone", "slave", "puppet", "toy", "object"
        ])

        let windowSize: TimeInterval = 60.0
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

            // 4+ conditioning keywords in 60 seconds = high-density conditioning
            if hits.count >= 4, let firstHit = hits.first {
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
