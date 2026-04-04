//
//  TechniqueDetector.swift
//  Ilumionate
//
//  Detects specific hypnotic techniques and linguistic markers from transcript
//  word timestamps and prosodic data. Populates the existing (but previously
//  empty) `HypnoticTechnique` and `LinguisticMarker` types defined in
//  AudioFile.swift.
//
//  Detected techniques drive targeted light responses in SessionGenerator:
//  countdowns → stepwise frequency drops, embedded commands → bilateral bursts,
//  deliberate pauses → maintained deepening, etc.
//
//  All methods are pure — same input always produces the same output.
//

import Foundation

// MARK: - Technique Detection Result

/// Combined output of technique and marker detection for a single audio file.
struct TechniqueDetectionResult: Codable, Sendable {
    let techniques: [HypnoticTechnique]
    let markers: [LinguisticMarker]

    /// Techniques sorted by timestamp for sequential light event generation.
    var sortedTechniques: [HypnoticTechnique] {
        techniques.sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Detector

/// Detects hypnotic techniques and linguistic markers from word timestamps,
/// transcript segments, and prosodic data.
struct TechniqueDetector: Sendable {

    let config: AnalyzerConfig.TechniqueDetection

    nonisolated init(config: AnalyzerConfig.TechniqueDetection? = nil) {
        self.config = config ?? AnalyzerConfigLoader.load().techniqueDetection
    }

    /// Run full detection pipeline on a transcribed audio file.
    ///
    /// - Parameters:
    ///   - wordTimestamps: Approximate per-word timing from WhisperKit.
    ///   - segments: Original transcript segments (for context windows).
    ///   - prosodic: Prosodic profile from ProsodyAnalyzer (optional — enhances detection).
    ///   - duration: Total audio duration.
    /// - Returns: Combined techniques and markers with timestamps.
    func detect(
        wordTimestamps: [WordTimestamp],
        segments: [AudioTranscriptionSegment],
        prosodic: ProsodicProfile?,
        duration: TimeInterval
    ) -> TechniqueDetectionResult {
        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        let countdowns = detectCountdowns(wordTimestamps: wordTimestamps)
        techniques.append(contentsOf: countdowns.techniques)
        markers.append(contentsOf: countdowns.markers)

        let relaxation = detectProgressiveRelaxation(wordTimestamps: wordTimestamps)
        techniques.append(contentsOf: relaxation.techniques)
        markers.append(contentsOf: relaxation.markers)

        let commands = detectEmbeddedCommands(wordTimestamps: wordTimestamps)
        techniques.append(contentsOf: commands.techniques)
        markers.append(contentsOf: commands.markers)

        let deepening = detectDeepeningCommands(wordTimestamps: wordTimestamps, prosodic: prosodic)
        techniques.append(contentsOf: deepening.techniques)
        markers.append(contentsOf: deepening.markers)

        let anchoring = detectAnchoring(wordTimestamps: wordTimestamps)
        techniques.append(contentsOf: anchoring.techniques)
        markers.append(contentsOf: anchoring.markers)

        let repetition = detectRepetitionPatterns(wordTimestamps: wordTimestamps, duration: duration)
        techniques.append(contentsOf: repetition.techniques)
        markers.append(contentsOf: repetition.markers)

        let fractionation = detectFractionation(wordTimestamps: wordTimestamps)
        techniques.append(contentsOf: fractionation.techniques)
        markers.append(contentsOf: fractionation.markers)

        let confusion = detectConfusionTechnique(wordTimestamps: wordTimestamps)
        techniques.append(contentsOf: confusion.techniques)
        markers.append(contentsOf: confusion.markers)

        let amnesia = detectAmnesiaSuggestions(wordTimestamps: wordTimestamps)
        techniques.append(contentsOf: amnesia.techniques)
        markers.append(contentsOf: amnesia.markers)

        let dissociation = detectDissociation(wordTimestamps: wordTimestamps)
        techniques.append(contentsOf: dissociation.techniques)
        markers.append(contentsOf: dissociation.markers)

        let ageRegression = detectAgeRegression(wordTimestamps: wordTimestamps)
        techniques.append(contentsOf: ageRegression.techniques)
        markers.append(contentsOf: ageRegression.markers)

        let hallucinationSugg = detectHallucination(wordTimestamps: wordTimestamps)
        techniques.append(contentsOf: hallucinationSugg.techniques)
        markers.append(contentsOf: hallucinationSugg.markers)

        let doubleBinds = detectDoubleBinds(wordTimestamps: wordTimestamps)
        techniques.append(contentsOf: doubleBinds.techniques)
        markers.append(contentsOf: doubleBinds.markers)

        let brainwashing = detectBrainwashing(wordTimestamps: wordTimestamps, duration: duration)
        techniques.append(contentsOf: brainwashing.techniques)
        markers.append(contentsOf: brainwashing.markers)

        let emergence = detectEmergenceCues(wordTimestamps: wordTimestamps, duration: duration)
        techniques.append(contentsOf: emergence.techniques)
        markers.append(contentsOf: emergence.markers)

        if let prosodic {
            let pauseTechniques = detectPauseBasedTechniques(prosodic: prosodic)
            techniques.append(contentsOf: pauseTechniques.techniques)
            markers.append(contentsOf: pauseTechniques.markers)
        }

        return TechniqueDetectionResult(techniques: deduplicateTechniques(techniques), markers: markers)
    }

    /// Removes duplicate techniques of the same type within a 2-second window.
    private func deduplicateTechniques(_ techniques: [HypnoticTechnique]) -> [HypnoticTechnique] {
        let sorted = techniques.sorted { $0.timestamp < $1.timestamp }
        var result: [HypnoticTechnique] = []
        for technique in sorted {
            let isDuplicate = result.contains { existing in
                existing.technique == technique.technique
                    && abs(existing.timestamp - technique.timestamp) < 2.0
            }
            if !isDuplicate { result.append(technique) }
        }
        return result
    }
}

// MARK: - Detection Methods

private extension TechniqueDetector {

    // MARK: - Countdown Detection

    func detectCountdowns(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        let numberWords: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
            "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
            "nineteen": 19, "twenty": 20,
            "1": 1, "2": 2, "3": 3, "4": 4, "5": 5,
            "6": 6, "7": 7, "8": 8, "9": 9, "10": 10
        ]

        var currentSequence: [(time: Double, number: Int)] = []

        for word in wordTimestamps {
            let cleaned = word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            guard let number = numberWords[cleaned] else {
                if currentSequence.count >= 3 {
                    recordCountdown(&techniques, &markers, sequence: currentSequence)
                }
                currentSequence.removeAll()
                continue
            }

            if let last = currentSequence.last {
                let timeSinceLast = word.startTime - last.time
                if number < last.number && timeSinceLast < 15.0 {
                    currentSequence.append((word.startTime, number))
                } else {
                    if currentSequence.count >= 3 {
                        recordCountdown(&techniques, &markers, sequence: currentSequence)
                    }
                    currentSequence = [(word.startTime, number)]
                }
            } else {
                currentSequence = [(word.startTime, number)]
            }
        }

        if currentSequence.count >= 3 {
            recordCountdown(&techniques, &markers, sequence: currentSequence)
        }

        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }

    func recordCountdown(
        _ techniques: inout [HypnoticTechnique],
        _ markers: inout [LinguisticMarker],
        sequence: [(time: Double, number: Int)]
    ) {
        guard let first = sequence.first, let last = sequence.last else { return }

        techniques.append(HypnoticTechnique(
            technique: "countdown",
            timestamp: first.time,
            description: "Countdown from \(first.number) to \(last.number) — deepening sequence",
            suggestedLightSync: "stepwise_frequency_drop"
        ))
        markers.append(LinguisticMarker(
            type: .countingDown,
            timestamp: first.time,
            textSnippet: "\(first.number)...\(last.number)",
            strength: min(1.0, Double(sequence.count) / 5.0)
        ))
    }

    // MARK: - Progressive Relaxation Detection

    func detectProgressiveRelaxation(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        let singleWordRegions: [(keywords: Set<String>, region: String)] = [
            (["feet", "toes", "soles", "ankles"], "feet"),
            (["legs", "calves", "thighs", "knees", "shins"], "legs"),
            (["hips", "pelvis", "abdomen", "stomach", "belly"], "torso_lower"),
            (["chest", "back", "spine", "ribcage", "lungs"], "torso_upper"),
            (["hands", "fingers", "wrists", "palms"], "hands"),
            (["arms", "forearms", "elbows", "biceps"], "arms"),
            (["shoulders", "neck", "throat"], "shoulders"),
            (["face", "jaw", "cheeks", "forehead", "eyes", "scalp", "head"], "head")
        ]
        let multiWordRegions: [(words: [String], region: String)] = [
            (["lower", "back"], "torso_lower"),
            (["upper", "back"], "torso_upper")
        ]

        var detectedRegions: [(time: Double, region: String)] = []

        for (wordIdx, word) in wordTimestamps.enumerated() {
            let cleaned = word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)

            var matched = false
            for (phrase, region) in multiWordRegions {
                let end = wordIdx + phrase.count
                guard end <= wordTimestamps.count else { continue }
                let window = wordTimestamps[wordIdx..<end]
                let isMatch = zip(window, phrase).allSatisfy {
                    $0.word.lowercased().trimmingCharacters(in: .punctuationCharacters) == $1
                }
                if isMatch {
                    if detectedRegions.last?.region != region {
                        detectedRegions.append((word.startTime, region))
                    }
                    matched = true
                    break
                }
            }
            guard !matched else { continue }

            for (keywords, region) in singleWordRegions where keywords.contains(cleaned) {
                if detectedRegions.last?.region != region {
                    detectedRegions.append((word.startTime, region))
                }
                break
            }
        }

        guard detectedRegions.count >= 4 else {
            return TechniqueDetectionResult(techniques: techniques, markers: markers)
        }

        if let first = detectedRegions.first, let last = detectedRegions.last {
            let span = last.time - first.time
            guard span > 30 && span < 600 else {
                return TechniqueDetectionResult(techniques: techniques, markers: markers)
            }

            techniques.append(HypnoticTechnique(
                technique: "progressive_relaxation",
                timestamp: first.time,
                description: "Progressive relaxation scanning \(detectedRegions.count) body regions over \(Int(span))s",
                suggestedLightSync: "gradual_intensity_reduction"
            ))
            markers.append(LinguisticMarker(
                type: .progressiveRelaxation,
                timestamp: first.time,
                textSnippet: detectedRegions.map(\.region).joined(separator: " → "),
                strength: min(1.0, Double(detectedRegions.count) / 6.0)
            ))
        }

        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }

    // MARK: - Embedded Command Detection

    func detectEmbeddedCommands(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        let commandPatterns: [[String]] = [
            ["relax", "now"], ["sleep", "now"], ["let", "go"], ["go", "deeper"],
            ["feel", "calm"], ["feel", "relaxed"], ["feel", "peaceful"],
            ["release", "tension"], ["drift", "deeper"], ["sink", "down"],
            ["close", "your", "eyes"], ["breathe", "deeply"], ["feel", "safe"],
            ["trust", "yourself"], ["be", "still"], ["rest", "now"],
            ["calm", "down"], ["be", "calm"]
        ]

        for windowStart in 0..<wordTimestamps.count {
            for pattern in commandPatterns {
                let windowEnd = windowStart + pattern.count
                guard windowEnd <= wordTimestamps.count else { continue }

                let windowWords = wordTimestamps[windowStart..<windowEnd]
                let matches = zip(windowWords, pattern).allSatisfy { word, target in
                    word.word.lowercased().trimmingCharacters(in: .punctuationCharacters) == target
                }
                guard matches else { continue }

                let timestamp = wordTimestamps[windowStart].startTime
                let phrase = pattern.joined(separator: " ")

                techniques.append(HypnoticTechnique(
                    technique: "embedded_command",
                    timestamp: timestamp,
                    description: "Embedded command: \"\(phrase)\"",
                    suggestedLightSync: "brief_bilateral_burst"
                ))
                markers.append(LinguisticMarker(
                    type: .embeddedCommand,
                    timestamp: timestamp,
                    textSnippet: phrase,
                    strength: 0.7
                ))
            }
        }

        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }

    // MARK: - Deepening Command Detection

    func detectDeepeningCommands(
        wordTimestamps: [WordTimestamp],
        prosodic: ProsodicProfile?
    ) -> TechniqueDetectionResult {
        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        let deepeningKeywords = Set([
            "deeper", "deep", "sleep", "down", "sinking",
            "dropping", "falling", "drifting", "floating",
            "heavier", "heavy", "relaxing"
        ])

        let avgVol: Double? = prosodic.map { profile in
            let voiced = profile.volumeCurve.filter { $0 > 0 }
            return voiced.isEmpty ? 0 : voiced.reduce(0, +) / Double(voiced.count)
        }

        for (wordIndex, word) in wordTimestamps.enumerated() {
            let cleaned = word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            guard deepeningKeywords.contains(cleaned) else { continue }

            var hasPrecedingPause = false
            if wordIndex > 0 {
                let prevEnd = wordTimestamps[wordIndex - 1].endTime
                hasPrecedingPause = word.startTime - prevEnd > 1.5
            }

            var hasProsodicEmphasis = false
            if let prosodic, let avg = avgVol, avg > 0 {
                let vol = prosodic.volume(at: word.startTime)
                hasProsodicEmphasis = vol < avg * 0.7 || vol > avg * 1.3
            }

            let strength: Double
            if hasPrecedingPause && hasProsodicEmphasis {
                strength = 1.0
            } else if hasPrecedingPause || hasProsodicEmphasis {
                strength = 0.75
            } else {
                strength = 0.4
            }

            guard strength >= config.sensitivityThreshold else { continue }

            let context = hasPrecedingPause ? "preceding pause" : "emphasis"
            techniques.append(HypnoticTechnique(
                technique: "deepening_command",
                timestamp: word.startTime,
                description: "Deepening command \"\(cleaned)\" with \(context)",
                suggestedLightSync: "momentary_frequency_dip"
            ))
            markers.append(LinguisticMarker(
                type: .descendingImagery,
                timestamp: word.startTime,
                textSnippet: cleaned,
                strength: strength
            ))
        }

        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }

    // MARK: - Anchoring / Trigger Installation

    func detectAnchoring(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        let anchorPatterns: [[String]] = [
            ["whenever", "you"], ["every", "time"], ["from", "now", "on"],
            ["each", "time", "you"], ["any", "time", "you"],
            ["you", "will", "find"], ["you", "will", "notice"],
            ["you", "will", "feel"], ["your", "subconscious"]
        ]

        for windowStart in 0..<wordTimestamps.count {
            for pattern in anchorPatterns {
                let windowEnd = windowStart + pattern.count
                guard windowEnd <= wordTimestamps.count else { continue }

                let windowWords = wordTimestamps[windowStart..<windowEnd]
                let matches = zip(windowWords, pattern).allSatisfy { word, target in
                    word.word.lowercased().trimmingCharacters(in: .punctuationCharacters) == target
                }
                guard matches else { continue }

                let timestamp = wordTimestamps[windowStart].startTime
                let phrase = pattern.joined(separator: " ")

                techniques.append(HypnoticTechnique(
                    technique: "anchoring",
                    timestamp: timestamp,
                    description: "Anchoring/conditioning: \"\(phrase)...\"",
                    suggestedLightSync: "bilateral_activation_warm_shift"
                ))
                markers.append(LinguisticMarker(
                    type: .anchoringResponse,
                    timestamp: timestamp,
                    textSnippet: phrase,
                    strength: 0.8
                ))
            }
        }

        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }

    // MARK: - Repetition Pattern Detection

    func detectRepetitionPatterns(
        wordTimestamps: [WordTimestamp],
        duration: TimeInterval
    ) -> TechniqueDetectionResult {
        guard wordTimestamps.count >= 3 else {
            return TechniqueDetectionResult(techniques: [], markers: [])
        }

        struct PhraseOccurrence { let time: Double; let phrase: String }
        var phraseMap: [String: [PhraseOccurrence]] = [:]
        let commonPhrases = Set(["and you can", "you can feel", "and as you", "as you can"])

        for phraseStart in 0..<(wordTimestamps.count - 2) {
            let phrase = wordTimestamps[phraseStart...(phraseStart + 2)]
                .map { $0.word.lowercased().trimmingCharacters(in: .punctuationCharacters) }
                .joined(separator: " ")
            guard !commonPhrases.contains(phrase), phrase.count > 8 else { continue }
            phraseMap[phrase, default: []].append(
                PhraseOccurrence(time: wordTimestamps[phraseStart].startTime, phrase: phrase)
            )
        }

        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        for (phrase, occurrences) in phraseMap {
            guard occurrences.count >= 3 else { continue }

            for startIdx in 0..<occurrences.count {
                let windowEnd = occurrences[startIdx].time + 90.0
                let cluster = occurrences.filter {
                    $0.time >= occurrences[startIdx].time && $0.time <= windowEnd
                }
                guard cluster.count >= 3 else { continue }

                let firstTime = cluster[0].time
                var intervals: [Double] = []
                for idx in 1..<cluster.count {
                    intervals.append(cluster[idx].time - cluster[idx - 1].time)
                }
                let avgInterval = intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count)

                techniques.append(HypnoticTechnique(
                    technique: "repetition_pattern",
                    timestamp: firstTime,
                    description: "\"\(phrase)\" repeated \(cluster.count)x (avg interval: \(Int(avgInterval))s)",
                    suggestedLightSync: "rhythmic_pulse_sync"
                ))
                markers.append(LinguisticMarker(
                    type: .pacingAndLeading,
                    timestamp: firstTime,
                    textSnippet: phrase,
                    strength: min(1.0, Double(cluster.count) / 5.0)
                ))
                break
            }
        }

        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }

    // MARK: - Fractionation Detection

    func detectFractionation(wordTimestamps: [WordTimestamp]) -> TechniqueDetectionResult {
        let upKeywords    = Set(["open", "wake", "alert", "up", "lighter", "surface", "rise"])
        let downKeywords  = Set(["close", "sleep", "deeper", "down", "heavier", "sink", "drift"])

        enum Direction { case ascending, descending, none }
        var transitions: [(time: Double, direction: Direction)] = []

        for word in wordTimestamps {
            let cleaned = word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if upKeywords.contains(cleaned) {
                if transitions.last?.direction != .ascending {
                    transitions.append((word.startTime, .ascending))
                }
            } else if downKeywords.contains(cleaned) {
                if transitions.last?.direction != .descending {
                    transitions.append((word.startTime, .descending))
                }
            }
        }

        guard transitions.count >= 4 else {
            return TechniqueDetectionResult(techniques: [], markers: [])
        }

        var cycleCount = 0
        var firstCycleTime: Double?

        for transitionIndex in 1..<transitions.count {
            let prev = transitions[transitionIndex - 1]
            let curr = transitions[transitionIndex]
            if curr.time - prev.time < 30.0 && prev.direction != curr.direction {
                cycleCount += 1
                if firstCycleTime == nil { firstCycleTime = prev.time }
            }
        }

        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        if cycleCount >= 3, let startTime = firstCycleTime {
            techniques.append(HypnoticTechnique(
                technique: "fractionation",
                timestamp: startTime,
                description: "Fractionation pattern: \(cycleCount) oscillation cycles detected",
                suggestedLightSync: "oscillating_frequency_deepening"
            ))
            markers.append(LinguisticMarker(
                type: .fractionation,
                timestamp: startTime,
                textSnippet: "up/down cycling",
                strength: min(1.0, Double(cycleCount) / 4.0)
            ))
        }

        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }

    // MARK: - Emergence Cue Detection

    func detectEmergenceCues(
        wordTimestamps: [WordTimestamp],
        duration: TimeInterval
    ) -> TechniqueDetectionResult {
        guard duration > 10.0 else {
            return TechniqueDetectionResult(techniques: [], markers: [])
        }

        let emergenceKeywords = Set([
            "awake", "alert", "refreshed", "energized", "open",
            "returning", "awareness", "present", "bright", "clear",
            "wonderful", "amazing", "ready", "fully"
        ])
        let scanStart = duration * 0.85
        let lateWords = wordTimestamps.filter { $0.startTime >= scanStart }

        var emergenceHits = 0
        var firstHitTime: Double?

        for word in lateWords {
            let cleaned = word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if emergenceKeywords.contains(cleaned) {
                emergenceHits += 1
                if firstHitTime == nil { firstHitTime = word.startTime }
            }
        }

        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        if emergenceHits >= 3, let startTime = firstHitTime {
            techniques.append(HypnoticTechnique(
                technique: "emergence_sequence",
                timestamp: startTime,
                description: "Emergence cues detected (\(emergenceHits) keywords in final segment)",
                suggestedLightSync: "frequency_rise_to_beta"
            ))
            markers.append(LinguisticMarker(
                type: .physicalReengagement,
                timestamp: startTime,
                textSnippet: "emergence/awakening language",
                strength: min(1.0, Double(emergenceHits) / 5.0)
            ))
        }

        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }

    // MARK: - Pause-Based Technique Detection

    func detectPauseBasedTechniques(prosodic: ProsodicProfile) -> TechniqueDetectionResult {
        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        for pause in prosodic.pauses {
            switch pause.category {
            case .deliberate:
                let preceding = pause.precedingText ?? "..."
                techniques.append(HypnoticTechnique(
                    technique: "deliberate_pause",
                    timestamp: pause.startTime,
                    description: "Deliberate therapeutic pause (\(Int(pause.duration))s) after: \"\(preceding)\"",
                    suggestedLightSync: "gentle_frequency_dip"
                ))
                markers.append(LinguisticMarker(
                    type: .timeDistortion,
                    timestamp: pause.startTime,
                    textSnippet: "pause: \(Int(pause.duration))s",
                    strength: min(1.0, pause.duration / 8.0)
                ))

            case .silence:
                techniques.append(HypnoticTechnique(
                    technique: "extended_silence",
                    timestamp: pause.startTime,
                    description: "Extended silence (\(Int(pause.duration))s) — deep processing time",
                    suggestedLightSync: "maintain_and_deepen"
                ))

            case .musicOnly:
                techniques.append(HypnoticTechnique(
                    technique: "music_interlude",
                    timestamp: pause.startTime,
                    description: "Music-only section (\(Int(pause.duration))s) — no speech",
                    suggestedLightSync: "energy_following_mode"
                ))

            case .natural:
                break
            }
        }

        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }

}
