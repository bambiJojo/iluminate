//
//  HypnosisPhaseAnalyzer.swift
//  Ilumionate
//
//  Keyword-based hypnosis phase detector.
//  Acts as fallback when Apple Intelligence is unavailable, and as a
//  pre-processing stage that the ChunkedPhaseAnalyzer can calibrate against.
//
//  Pipeline:
//   1. Convert WhisperKit transcript segments to approximate word timestamps.
//   2. Build a per-second hit map by scanning words against the keyword taxonomy.
//   3. Resolve each second to its best-scoring phase using a ±5s context window.
//   4. Enforce forward-only phase ordering (pre_talk → emergence).
//   5. Majority-vote smooth the timeline to eliminate single-word spikes.
//   6. Collapse short runs (<45s) to remove boundary oscillation.
//   7. Consolidate into PhaseSegment spans.
//

import Foundation

// MARK: - Word Timestamp

/// A single word with its approximate position in the audio timeline.
/// Derived from WhisperKit segment output by distributing words evenly
/// across each segment's time span.
struct WordTimestamp: Identifiable, Sendable {
    let id: UUID
    let word: String
    let startTime: Double  // seconds from audio start
    let duration: Double

    var endTime: Double { startTime + duration }

    init(id: UUID = UUID(), word: String, startTime: Double, duration: Double) {
        self.id = id
        self.word = word
        self.startTime = startTime
        self.duration = duration
    }
}

// MARK: - Analyzer

/// Keyword-based hypnosis phase analyzer.
/// All methods are pure — the same input always produces the same output.
struct HypnosisPhaseAnalyzer {

    let config: AnalyzerConfig.KeywordPipeline

    init(config: AnalyzerConfig.KeywordPipeline? = nil) {
        self.config = config ?? AnalyzerConfigLoader.load().keywordPipeline
    }

    // MARK: - Public Entry Point

    /// Converts WhisperKit segments into approximate word timestamps, then
    /// runs the full keyword pipeline to produce `PhaseSegment` spans.
    func analyze(
        segments: [AudioTranscriptionSegment],
        duration: Double
    ) -> [PhaseSegment] {
        let wordTimestamps = approximateWordTimestamps(from: segments)
        guard !wordTimestamps.isEmpty else { return [] }

        let bucketCount = max(1, Int(ceil(duration)))
        let hitMap      = buildHitMap(wordTimestamps: wordTimestamps, bucketCount: bucketCount)
        var timeline    = resolveTimeline(hitMap: hitMap, bucketCount: bucketCount)

        timeline = enforcePhaseOrdering(timeline: timeline)
        timeline = majorityVoteSmooth(timeline: timeline, windowSize: config.smoothingWindowSize)
        timeline = collapseShortRuns(
            timeline,
            minRun: max(config.minimumPhaseDurationSeconds, Int(duration * config.collapseThresholdFraction))
        )

        return consolidatePhaseSegments(timeline: timeline, duration: duration)
    }

    /// Converts WhisperKit segments directly to a PhaseSegment array,
    /// using the full pipeline. Public entry point for callers that
    /// already have AudioTranscriptionResult.
    func analyzeTranscription(
        _ transcription: AudioTranscriptionResult
    ) -> [PhaseSegment] {
        analyze(segments: transcription.segments, duration: transcription.duration)
    }

    // MARK: - Word Timestamp Approximation

    /// Distributes words across each WhisperKit segment's time span.
    /// WhisperKit returns phrase-level segments; we approximate per-word
    /// timing by dividing the segment duration equally among its words.
    func approximateWordTimestamps(
        from segments: [AudioTranscriptionSegment]
    ) -> [WordTimestamp] {
        var wordTimestamps: [WordTimestamp] = []
        wordTimestamps.reserveCapacity(segments.count * 8)

        for segment in segments {
            let words = segment.text
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            guard !words.isEmpty else { continue }

            let wordDuration = segment.duration / Double(words.count)
            for (wordIndex, word) in words.enumerated() {
                let startTime = segment.timestamp + Double(wordIndex) * wordDuration
                wordTimestamps.append(WordTimestamp(
                    word: word,
                    startTime: startTime,
                    duration: wordDuration
                ))
            }
        }

        return wordTimestamps
    }

    // MARK: - Hit Map Construction

    /// Scans all word timestamps against the keyword taxonomy and produces a
    /// bucket array where each element maps phase → accumulated score.
    func buildHitMap(
        wordTimestamps: [WordTimestamp],
        bucketCount: Int
    ) -> [[HypnosisMetadata.Phase: Double]] {
        var hitMap = [[HypnosisMetadata.Phase: Double]](
            repeating: [:],
            count: bucketCount
        )
        let sortedKeywords = HypnosisPhaseKeywords.all
            .sorted { $0.phrase.count > $1.phrase.count }  // longest phrase first

        for wordIndex in 0..<wordTimestamps.count {
            let bucket = max(0, min(Int(wordTimestamps[wordIndex].startTime), bucketCount - 1))
            var matched = false

            // Try multi-word phrases (up to 4 words starting at this position)
            let maxPhrase = min(4, wordTimestamps.count - wordIndex)
            for phraseLen in stride(from: maxPhrase, through: 1, by: -1) {
                let phrase = wordTimestamps[wordIndex..<(wordIndex + phraseLen)]
                    .map { $0.word.lowercased() }
                    .joined(separator: " ")
                if let keyword = sortedKeywords.first(where: { $0.phrase == phrase }) {
                    hitMap[bucket][keyword.phase, default: 0.0] += keyword.weight * Double(phraseLen)
                    matched = true
                    break
                }
            }

            // Single-word fallback
            if !matched {
                let singleWord = wordTimestamps[wordIndex].word.lowercased()
                if let keyword = sortedKeywords.first(where: { $0.phrase == singleWord }) {
                    hitMap[bucket][keyword.phase, default: 0.0] += keyword.weight
                }
            }
        }

        return hitMap
    }

    // MARK: - Timeline Resolution

    /// Assigns the best-scoring phase to each second, using a recency-biased context window.
    func resolveTimeline(
        hitMap: [[HypnosisMetadata.Phase: Double]],
        bucketCount: Int
    ) -> [HypnosisMetadata.Phase?] {
        let contextRadius = config.contextWindowSeconds
        var timeline = [HypnosisMetadata.Phase?](repeating: nil, count: bucketCount)

        for secondIndex in 0..<bucketCount {
            var scores = [HypnosisMetadata.Phase: Double]()
            let lo = max(0, secondIndex - contextRadius)
            let hi = min(bucketCount - 1, secondIndex + contextRadius)

            for nearIndex in lo...hi {
                let recency = 1.0 - Double(abs(nearIndex - secondIndex)) / Double(contextRadius + 1)
                for (phase, score) in hitMap[nearIndex] {
                    scores[phase, default: 0.0] += score * recency
                }
            }

            if let best = scores.max(by: { $0.value < $1.value }), best.value > 0 {
                timeline[secondIndex] = best.key
            }
        }

        return timeline
    }

    // MARK: - Phase Ordering

    private static let orderedPhases: [HypnosisMetadata.Phase] = [
        .preTalk, .induction, .deepening, .therapy, .suggestions, .conditioning, .emergence
    ]

    /// Clamps any backward phase jump to the highest phase seen so far.
    func enforcePhaseOrdering(
        timeline: [HypnosisMetadata.Phase?]
    ) -> [HypnosisMetadata.Phase?] {
        var result = timeline
        var highestIndex = 0

        for secondIndex in 0..<result.count {
            guard let phase = result[secondIndex] else { continue }
            guard let phaseIndex = Self.orderedPhases.firstIndex(of: phase) else { continue }

            if phaseIndex >= highestIndex {
                highestIndex = phaseIndex
            } else {
                result[secondIndex] = Self.orderedPhases[highestIndex]
            }
        }

        return result
    }

    // MARK: - Smoothing

    /// Majority-vote sliding window — most frequent phase in the window wins.
    func majorityVoteSmooth(
        timeline: [HypnosisMetadata.Phase?],
        windowSize: Int
    ) -> [HypnosisMetadata.Phase?] {
        guard windowSize > 1 else { return timeline }
        var smoothed = timeline

        for secondIndex in 0..<timeline.count {
            let lo = max(0, secondIndex - windowSize / 2)
            let hi = min(timeline.count - 1, secondIndex + windowSize / 2)

            var counts = [HypnosisMetadata.Phase: Int]()
            for nearIndex in lo...hi {
                if let phase = timeline[nearIndex] {
                    counts[phase, default: 0] += 1
                }
            }

            if let winner = counts.max(by: { $0.value < $1.value }) {
                smoothed[secondIndex] = winner.key
            }
        }

        // Forward-fill any remaining nil gaps
        var lastKnown: HypnosisMetadata.Phase? = nil
        for secondIndex in 0..<smoothed.count {
            if let phase = smoothed[secondIndex] {
                lastKnown = phase
            } else if let known = lastKnown {
                smoothed[secondIndex] = known
            }
        }

        return smoothed
    }

    /// Merges runs shorter than `minRun` seconds into their neighbour.
    /// Eliminates sub-15s boundary oscillation common at phase transitions.
    func collapseShortRuns(
        _ timeline: [HypnosisMetadata.Phase?],
        minRun: Int
    ) -> [HypnosisMetadata.Phase?] {
        guard !timeline.isEmpty else { return timeline }

        struct Run { var phase: HypnosisMetadata.Phase?; var start: Int; var end: Int }

        var runs: [Run] = []
        var currentPhase = timeline[0]
        var runStart = 0

        for timeIndex in 1..<timeline.count {
            if timeline[timeIndex] != currentPhase {
                runs.append(Run(phase: currentPhase, start: runStart, end: timeIndex))
                currentPhase = timeline[timeIndex]
                runStart = timeIndex
            }
        }
        runs.append(Run(phase: currentPhase, start: runStart, end: timeline.count))

        // Absorb short runs into their forward neighbour iteratively
        var changed = true
        while changed {
            changed = false
            var runIndex = 0
            while runIndex < runs.count {
                let runLen = runs[runIndex].end - runs[runIndex].start
                guard runLen < minRun else { runIndex += 1; continue }

                let absorb: HypnosisMetadata.Phase?
                if runIndex + 1 < runs.count {
                    absorb = runs[runIndex + 1].phase
                } else if runIndex > 0 {
                    absorb = runs[runIndex - 1].phase
                } else {
                    runIndex += 1; continue
                }
                runs[runIndex].phase = absorb

                // Merge adjacent identical phases
                var mergeIndex = 0
                while mergeIndex < runs.count - 1 {
                    if runs[mergeIndex].phase == runs[mergeIndex + 1].phase {
                        runs[mergeIndex].end = runs[mergeIndex + 1].end
                        runs.remove(at: mergeIndex + 1)
                    } else {
                        mergeIndex += 1
                    }
                }
                changed = true
                break
            }
        }

        var output = timeline
        for run in runs {
            for timeIndex in run.start..<run.end {
                output[timeIndex] = run.phase
            }
        }
        return output
    }

    // MARK: - Event Consolidation

    /// Converts a flat per-second timeline into `PhaseSegment` spans.
    func consolidatePhaseSegments(
        timeline: [HypnosisMetadata.Phase?],
        duration: Double
    ) -> [PhaseSegment] {
        guard !timeline.isEmpty else { return [] }

        var segments: [PhaseSegment] = []
        var currentPhase = timeline[0] ?? .preTalk
        var spanStart = 0

        for timeIndex in 1..<timeline.count {
            let phase = timeline[timeIndex] ?? currentPhase
            if phase != currentPhase {
                segments.append(buildPhaseSegment(
                    phase: currentPhase,
                    startTime: Double(spanStart),
                    endTime: Double(timeIndex)
                ))
                currentPhase = phase
                spanStart = timeIndex
            }
        }

        segments.append(buildPhaseSegment(
            phase: currentPhase,
            startTime: Double(spanStart),
            endTime: duration
        ))

        return segments
    }

    private func buildPhaseSegment(
        phase: HypnosisMetadata.Phase,
        startTime: Double,
        endTime: Double
    ) -> PhaseSegment {
        PhaseSegment(
            phase: phase,
            startTime: startTime,
            endTime: endTime,
            characteristics: phase.displayName,
            tranceDepthEstimate: tranceDepthForPhase(phase),
            confidenceLevel: .medium
        )
    }

    private func tranceDepthForPhase(_ phase: HypnosisMetadata.Phase) -> Double {
        switch phase {
        case .preTalk:       return 0.05
        case .induction:     return 0.25
        case .deepening:     return 0.55
        case .therapy:       return 0.90
        case .suggestions:   return 0.75
        case .conditioning:  return 0.65
        case .emergence:     return 0.30
        case .transitional:  return 0.40
        }
    }
}
