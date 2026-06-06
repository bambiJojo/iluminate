//
//  TranscriptFeatureAnalyzer.swift
//  Ilumionate
//
//  Extracted from HypnosisPhaseAnalyzer.swift (structural decomposition).
//

import Foundation

/// Derives transcript-level features normalized against the current file rather
/// than fixed thresholds, so fast and slow hypnotists can still be compared on
/// relative change.
struct TranscriptFeatureAnalyzer {

    private struct SectionSeed {
        let id: UUID
        let phase: HypnosisMetadata.Phase?
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    struct RawSectionMetrics {
        let id: UUID
        let phase: HypnosisMetadata.Phase?
        let startTime: TimeInterval
        let endTime: TimeInterval
        let duration: TimeInterval
        let wordCount: Int
        let uniqueWordCount: Int
        let wordsPerMinute: Double
        let speechCoverage: Double
        let lexicalDiversity: Double
        let repetitionDensity: Double
        let wordCounts: [String: Int]
        let phraseCounts: [String: Int]
        let waymarkerMatches: [HypnosisWaymarkerMatch]
    }

    struct WindowContext {
        let transcription: AudioTranscriptionResult
        let wordTimestamps: [WordTimestamp]
        let overall: RawSectionMetrics
    }

    private let phaseAnalyzer = HypnosisPhaseAnalyzer()

    func analyze(
        transcription: AudioTranscriptionResult,
        phases: [PhaseSegment]? = nil
    ) -> TranscriptAnalysis {
        let sections = makeSections(duration: transcription.duration, phases: phases)
        let context = makeWindowContext(transcription: transcription)
        let overallRaw = context.overall

        let sectionRaw = sections.map {
            buildRawMetrics(
                id: $0.id,
                phase: $0.phase,
                startTime: $0.startTime,
                endTime: $0.endTime,
                transcription: context.transcription,
                wordTimestamps: context.wordTimestamps
            )
        }
        let timelineWindowSeeds = makeTimelineWindowSeeds(duration: transcription.duration, using: context)
        let timelineWindowRaw = timelineWindowSeeds.map {
            buildRawMetrics(
                id: $0.id,
                phase: nil,
                startTime: $0.startTime,
                endTime: $0.endTime,
                transcription: context.transcription,
                wordTimestamps: context.wordTimestamps
            )
        }

        return TranscriptAnalysis(
            overall: finalize(raw: overallRaw, overall: overallRaw),
            sections: sectionRaw.map { finalize(raw: $0, overall: overallRaw) },
            timelineWindows: timelineWindowRaw.map { finalize(raw: $0, overall: overallRaw) }
        )
    }

    func makeWindowContext(
        transcription: AudioTranscriptionResult
    ) -> WindowContext {
        let wordTimestamps = phaseAnalyzer.approximateWordTimestamps(from: transcription.segments)
        let overallRaw = buildRawMetrics(
            id: UUID(),
            phase: nil,
            startTime: 0,
            endTime: transcription.duration,
            transcription: transcription,
            wordTimestamps: wordTimestamps
        )
        return WindowContext(
            transcription: transcription,
            wordTimestamps: wordTimestamps,
            overall: overallRaw
        )
    }

    func sectionMetrics(
        startTime: TimeInterval,
        endTime: TimeInterval,
        phase: HypnosisMetadata.Phase?,
        using context: WindowContext
    ) -> TranscriptSectionMetrics {
        let raw = buildRawMetrics(
            id: UUID(),
            phase: phase,
            startTime: startTime,
            endTime: endTime,
            transcription: context.transcription,
            wordTimestamps: context.wordTimestamps
        )
        return finalize(raw: raw, overall: context.overall)
    }

    private func makeSections(
        duration: TimeInterval,
        phases: [PhaseSegment]?
    ) -> [SectionSeed] {
        if let phases, !phases.isEmpty {
            return phases
                .filter { $0.endTime > $0.startTime }
                .map {
                    SectionSeed(
                        id: $0.id,
                        phase: $0.phase,
                        startTime: $0.startTime,
                        endTime: $0.endTime
                    )
                }
        }

        let sectionCount = max(3, min(8, Int(ceil(duration / 150.0))))
        let sectionDuration = max(duration / Double(sectionCount), 1.0)

        return (0..<sectionCount).map { index in
            let startTime = Double(index) * sectionDuration
            let endTime = min(duration, startTime + sectionDuration)
            return SectionSeed(
                id: UUID(),
                phase: nil,
                startTime: startTime,
                endTime: endTime
            )
        }
    }

    private func makeTimelineWindowSeeds(
        duration: TimeInterval,
        using context: WindowContext
    ) -> [SectionSeed] {
        // Window sizing scales with duration. Long sessions use coarse 45–60s
        // windows; short sessions (a few minutes) need finer windows or the few
        // heavily-overlapping coarse windows trivially share waymarker phases and
        // cascade-merge into a single window — collapsing the phrase-driven
        // proposal to one phase. Cap the window at ~1/4 of the duration so a
        // short transcript still yields several distinct, low-overlap windows.
        let durationCap = max(20.0, duration / 4.0)
        let windowDuration = min(max(45.0, duration / 8.0), 60.0, durationCap)
        let step = min(max(20.0, windowDuration * 0.66), 45.0)

        guard duration > windowDuration else {
            return [
                SectionSeed(
                    id: UUID(),
                    phase: nil,
                    startTime: 0,
                    endTime: duration
                )
            ]
        }

        var starts = Array(stride(from: 0.0, through: max(0.0, duration - windowDuration), by: step))
        let finalStart = max(0.0, duration - windowDuration)
        if abs((starts.last ?? 0) - finalStart) > 0.5 {
            starts.append(finalStart)
        }

        var initialSeeds = starts.map { startTime in
            SectionSeed(
                id: UUID(),
                phase: nil,
                startTime: startTime,
                endTime: min(duration, startTime + windowDuration)
            )
        }
        guard !initialSeeds.isEmpty else { return [] }

        var mergedSeeds: [SectionSeed] = []
        var currentSeed = initialSeeds.removeFirst()
        var currentRaw = buildRawMetrics(
            id: currentSeed.id,
            phase: nil,
            startTime: currentSeed.startTime,
            endTime: currentSeed.endTime,
            transcription: context.transcription,
            wordTimestamps: context.wordTimestamps
        )

        for nextSeed in initialSeeds {
            let nextRaw = buildRawMetrics(
                id: nextSeed.id,
                phase: nil,
                startTime: nextSeed.startTime,
                endTime: nextSeed.endTime,
                transcription: context.transcription,
                wordTimestamps: context.wordTimestamps
            )

            if shouldMergeTimelineWindows(lhs: currentRaw, rhs: nextRaw) {
                currentSeed = SectionSeed(
                    id: UUID(),
                    phase: nil,
                    startTime: currentSeed.startTime,
                    endTime: nextSeed.endTime
                )
                currentRaw = buildRawMetrics(
                    id: currentSeed.id,
                    phase: nil,
                    startTime: currentSeed.startTime,
                    endTime: currentSeed.endTime,
                    transcription: context.transcription,
                    wordTimestamps: context.wordTimestamps
                )
            } else {
                mergedSeeds.append(currentSeed)
                currentSeed = nextSeed
                currentRaw = nextRaw
            }
        }

        mergedSeeds.append(currentSeed)
        return mergedSeeds
    }

    private func buildRawMetrics(
        id: UUID,
        phase: HypnosisMetadata.Phase?,
        startTime: TimeInterval,
        endTime: TimeInterval,
        transcription: AudioTranscriptionResult,
        wordTimestamps: [WordTimestamp]
    ) -> RawSectionMetrics {
        let clippedStart = max(0, min(startTime, transcription.duration))
        let clippedEnd = max(clippedStart, min(endTime, transcription.duration))
        let duration = max(clippedEnd - clippedStart, 0.001)

        let overlappingSegments = transcription.segments.compactMap { segment -> ClosedRange<TimeInterval>? in
            let segmentStart = segment.timestamp
            let segmentEnd = segment.timestamp + max(segment.duration, 0)
            let overlapStart = max(clippedStart, segmentStart)
            let overlapEnd = min(clippedEnd, segmentEnd)
            guard overlapEnd > overlapStart else { return nil }
            return overlapStart...overlapEnd
        }

        let spokenDuration = mergeIntervals(overlappingSegments).reduce(0.0) { partial, interval in
            partial + (interval.upperBound - interval.lowerBound)
        }

        let sectionWords = wordTimestamps
            .filter { $0.startTime >= clippedStart && $0.startTime < clippedEnd }
            .map { $0.word }

        let tokens = tokenizeWords(in: sectionWords.joined(separator: " "))
        let wordCounts = tokenFrequency(in: tokens)
        let phraseCounts = phraseFrequency(in: tokens)
        let repeatedPhraseCount = repeatedPhraseOccurrences(in: tokens)

        return RawSectionMetrics(
            id: id,
            phase: phase,
            startTime: clippedStart,
            endTime: clippedEnd,
            duration: duration,
            wordCount: tokens.count,
            uniqueWordCount: Set(tokens).count,
            wordsPerMinute: (Double(tokens.count) / duration) * 60.0,
            speechCoverage: min(spokenDuration / duration, 1.0),
            lexicalDiversity: tokens.isEmpty ? 0.0 : Double(Set(tokens).count) / Double(tokens.count),
            repetitionDensity: (Double(repeatedPhraseCount) / duration) * 60.0,
            wordCounts: wordCounts,
            phraseCounts: phraseCounts,
            waymarkerMatches: detectWaymarkers(in: phraseCounts)
        )
    }

    private func finalize(
        raw: RawSectionMetrics,
        overall: RawSectionMetrics
    ) -> TranscriptSectionMetrics {
        let totalWordCount = max(raw.wordCount, 1)
        let overallWordCount = max(overall.wordCount, 1)
        let overallShares = overall.wordCounts.mapValues { Double($0) / Double(overallWordCount) }
        let totalPhraseCount = max(raw.phraseCounts.values.reduce(0, +), 1)
        let overallPhraseCount = max(overall.phraseCounts.values.reduce(0, +), 1)
        let overallPhraseShares = overall.phraseCounts.mapValues { Double($0) / Double(overallPhraseCount) }

        let topWords = raw.wordCounts
            .map { word, count in
                TranscriptWordStatistic(
                    word: word,
                    count: count,
                    share: Double(count) / Double(totalWordCount),
                    normalizedShareLift: normalizedRatio(
                        Double(count) / Double(totalWordCount),
                        baseline: overallShares[word] ?? 0
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.word < rhs.word }
                return lhs.count > rhs.count
            }

        let topDistinctiveWords = topWords
            .filter { $0.count >= 2 || $0.normalizedShareLift >= 1.8 }
            .sorted { lhs, rhs in
                if abs(lhs.normalizedShareLift - rhs.normalizedShareLift) < 0.001 {
                    if lhs.count == rhs.count { return lhs.word < rhs.word }
                    return lhs.count > rhs.count
                }
                return lhs.normalizedShareLift > rhs.normalizedShareLift
            }

        let topPhrases = raw.phraseCounts
            .map { phrase, count in
                TranscriptPhraseStatistic(
                    phrase: phrase,
                    count: count,
                    share: Double(count) / Double(totalPhraseCount),
                    normalizedShareLift: normalizedRatio(
                        Double(count) / Double(totalPhraseCount),
                        baseline: overallPhraseShares[phrase] ?? 0
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.phrase < rhs.phrase }
                return lhs.count > rhs.count
            }

        let topDistinctivePhrases = topPhrases
            .filter { $0.count >= 2 || $0.normalizedShareLift >= 1.5 }
            .sorted { lhs, rhs in
                if abs(lhs.normalizedShareLift - rhs.normalizedShareLift) < 0.001 {
                    if lhs.count == rhs.count { return lhs.phrase < rhs.phrase }
                    return lhs.count > rhs.count
                }
                return lhs.normalizedShareLift > rhs.normalizedShareLift
            }

        return TranscriptSectionMetrics(
            id: raw.id,
            phase: raw.phase,
            startTime: raw.startTime,
            endTime: raw.endTime,
            duration: raw.duration,
            wordCount: raw.wordCount,
            uniqueWordCount: raw.uniqueWordCount,
            wordsPerMinute: raw.wordsPerMinute,
            normalizedWordsPerMinute: normalizedRatio(raw.wordsPerMinute, baseline: overall.wordsPerMinute),
            speechCoverage: raw.speechCoverage,
            normalizedSpeechCoverage: normalizedRatio(raw.speechCoverage, baseline: overall.speechCoverage),
            lexicalDiversity: raw.lexicalDiversity,
            normalizedLexicalDiversity: normalizedRatio(raw.lexicalDiversity, baseline: overall.lexicalDiversity),
            repetitionDensity: raw.repetitionDensity,
            normalizedRepetitionDensity: normalizedRatio(raw.repetitionDensity, baseline: overall.repetitionDensity),
            topWords: Array(topWords.prefix(20)),
            topDistinctiveWords: Array(topDistinctiveWords.prefix(10)),
            topPhrases: Array(topPhrases.prefix(12)),
            topDistinctivePhrases: Array(topDistinctivePhrases.prefix(8)),
            waymarkerMatches: raw.waymarkerMatches
        )
    }

    private func mergeIntervals(
        _ intervals: [ClosedRange<TimeInterval>]
    ) -> [ClosedRange<TimeInterval>] {
        let sorted = intervals.sorted { $0.lowerBound < $1.lowerBound }
        guard var current = sorted.first else { return [] }

        var merged: [ClosedRange<TimeInterval>] = []
        for interval in sorted.dropFirst() {
            if interval.lowerBound <= current.upperBound {
                current = current.lowerBound...max(current.upperBound, interval.upperBound)
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged
    }

    private func tokenizeWords(in text: String) -> [String] {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'"))
        let normalized = String(
            text
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .unicodeScalars
                .map { allowedCharacters.contains($0) ? Character($0) : " " }
        )

        return normalized
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                token.trimmingCharacters(in: CharacterSet(charactersIn: "'")).lowercased()
            }
            .filter { !$0.isEmpty }
    }

    private func tokenFrequency(in words: [String]) -> [String: Int] {
        words.reduce(into: [:]) { counts, word in
            guard !transcriptStopWords.contains(word) else { return }
            guard word.rangeOfCharacter(from: .letters) != nil else { return }
            counts[word, default: 0] += 1
        }
    }

    private func phraseFrequency(in words: [String]) -> [String: Int] {
        guard words.count >= 2 else { return [:] }

        var counts: [String: Int] = [:]
        let maxPhraseLength = min(5, words.count)
        for phraseLength in 2...maxPhraseLength {
            for startIndex in 0...(words.count - phraseLength) {
                let phraseWords = Array(words[startIndex..<(startIndex + phraseLength)])
                guard shouldTrackTimelinePhrase(phraseWords) else { continue }
                counts[phraseWords.joined(separator: " "), default: 0] += 1
            }
        }

        return counts
    }

    private func shouldTrackTimelinePhrase(_ words: [String]) -> Bool {
        guard !words.isEmpty else { return false }
        let meaningfulWords = words.filter { word in
            !transcriptStopWords.contains(word) && word.count >= 3
        }
        guard !meaningfulWords.isEmpty else { return false }
        return Set(words).count > 1
    }

    private func detectWaymarkers(in phraseCounts: [String: Int]) -> [HypnosisWaymarkerMatch] {
        HypnosisWaymarkerLexicon.allPatterns.compactMap { pattern in
            guard let count = phraseCounts[pattern.phrase], count > 0 else { return nil }
            return HypnosisWaymarkerMatch(
                phrase: pattern.phrase,
                phase: pattern.phase,
                count: count,
                score: Double(count) * pattern.weight
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) < 0.001 {
                return lhs.phrase < rhs.phrase
            }
            return lhs.score > rhs.score
        }
    }

    private func repeatedPhraseOccurrences(in words: [String]) -> Int {
        guard words.count >= 3 else { return 0 }

        var counts: [String: Int] = [:]
        let ignoredPhrases = Set([
            "and you can",
            "you can feel",
            "and as you",
            "as you can"
        ])

        for startIndex in 0...(words.count - 3) {
            let phrase = words[startIndex...(startIndex + 2)].joined(separator: " ")
            guard !ignoredPhrases.contains(phrase) else { continue }
            counts[phrase, default: 0] += 1
        }

        return counts.values.reduce(0) { partial, count in
            partial + max(0, count - 1)
        }
    }

    private func normalizedRatio(_ value: Double, baseline: Double) -> Double {
        if value <= 0 { return 0 }
        if baseline <= 0 { return value > 0 ? 2.5 : 1.0 }
        return value / baseline
    }

    private func shouldMergeTimelineWindows(
        lhs: RawSectionMetrics,
        rhs: RawSectionMetrics
    ) -> Bool {
        let wordSimilarity = jaccardSimilarity(
            salientTerms(from: lhs.wordCounts, limit: 8),
            salientTerms(from: rhs.wordCounts, limit: 8)
        )
        let phraseSimilarity = jaccardSimilarity(
            salientTerms(from: lhs.phraseCounts, limit: 6),
            salientTerms(from: rhs.phraseCounts, limit: 6)
        )
        let lhsWaymarkerPhases = Set(lhs.waymarkerMatches.map(\.phase))
        let rhsWaymarkerPhases = Set(rhs.waymarkerMatches.map(\.phase))
        let sharesWaymarkerPhase = !lhsWaymarkerPhases.isDisjoint(with: rhsWaymarkerPhases)
        let sharesWaymarkerPhrase = !Set(lhs.waymarkerMatches.map(\.phrase)).isDisjoint(with: Set(rhs.waymarkerMatches.map(\.phrase)))

        return phraseSimilarity >= 0.22
            || wordSimilarity >= 0.30
            || sharesWaymarkerPhase
            || sharesWaymarkerPhrase
    }

    private func salientTerms(
        from counts: [String: Int],
        limit: Int
    ) -> Set<String> {
        Set(
            counts
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }
                .prefix(limit)
                .map(\.key)
        )
    }

    private func jaccardSimilarity(
        _ lhs: Set<String>,
        _ rhs: Set<String>
    ) -> Double {
        let union = lhs.union(rhs)
        guard !union.isEmpty else { return 0.0 }
        return Double(lhs.intersection(rhs).count) / Double(union.count)
    }

    private let transcriptStopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "for",
        "from", "had", "has", "have", "he", "her", "hers", "him", "his", "i",
        "if", "in", "into", "is", "it", "its", "just", "let", "me", "my",
        "now", "of", "on", "or", "our", "ours", "she", "so", "that", "the",
        "their", "theirs", "them", "there", "these", "they", "this", "those",
        "to", "up", "was", "we", "were", "with", "you", "your", "yours"
    ]
}
