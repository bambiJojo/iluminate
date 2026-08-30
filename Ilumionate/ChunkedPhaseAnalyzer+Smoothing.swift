//
//  ChunkedPhaseAnalyzer+Smoothing.swift
//  Ilumionate
//
//  Phase-ordering enforcement, run collapsing, and segment consolidation for
//  ChunkedPhaseAnalyzer. Kept in a separate file to stay within SwiftLint
//  file_length and type_body_length limits.
//

import Foundation

// MARK: - Phase Run Helper

/// Contiguous run of a single phase in the second-resolution timeline.
nonisolated struct PhaseRun {
    var phase: HypnosisMetadata.Phase?
    var start: Int
    var end: Int
}

/// A transcript-supported cluster of repeated wake-and-drop cycles.
nonisolated struct FractionationCycleSpan: Sendable, Equatable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let cycleCount: Int
}

// MARK: - Smoothing Extension

nonisolated extension ChunkedPhaseAnalyzer {

    // MARK: - Ordered Phases

    /// Canonical hypnosis phase order used for scoring and prompt context.
    static let orderedPhases: [HypnosisMetadata.Phase] = HypnosisMetadata.Phase.orderedHypnosisPhases

    // MARK: - Phase Ordering Enforcement

    static func enforcePhaseOrdering(
        timeline: [HypnosisMetadata.Phase?]
    ) -> [HypnosisMetadata.Phase?] {
        timeline.map { $0?.labelingPhase }
    }

    // MARK: - Fractionation Cycle Recognition

    /// Finds repeated explicit wake/open → sleep/close cycles directly from the
    /// timestamped transcript. This evidence does not depend on the phase model
    /// first deciding to emit an interior emergence label.
    static func detectFractionationSpans(
        in wordTimestamps: [WordTimestamp],
        duration: TimeInterval
    ) -> [FractionationCycleSpan] {
        struct Cycle {
            let wake: (startTime: TimeInterval, endTime: TimeInterval)
            let drop: (startTime: TimeInterval, endTime: TimeInterval)
        }

        guard duration > 0, wordTimestamps.isEmpty == false else { return [] }

        let words = wordTimestamps.sorted { $0.startTime < $1.startTime }
        let normalizedWords = words.map { normalizedCycleWord($0.word) }
        let wakePatterns = [
            ["open", "those", "eyes"],
            ["open", "your", "eyes"],
            ["open", "the", "eyes"],
            ["eyes", "open"],
            ["wake", "up"],
            ["wide", "awake"],
        ]
        let dropPatterns = [
            ["close", "those", "eyes"],
            ["close", "your", "eyes"],
            ["close", "the", "eyes"],
            ["eyes", "close"],
            ["sleep"],
            ["drop", "down"],
            ["dropping", "down"],
        ]
        let wakes = phraseEvents(
            patterns: wakePatterns,
            words: words,
            normalizedWords: normalizedWords
        )
        let drops = phraseEvents(
            patterns: dropPatterns,
            words: words,
            normalizedWords: normalizedWords
        )
        let sustainedWakeExits = phraseEvents(
            patterns: [
                ["keep", "them", "open"],
                ["keep", "your", "eyes", "open"],
                ["hold", "them", "open"],
                ["wait", "for", "my", "cue"],
                ["wait", "for", "the", "cue"],
            ],
            words: words,
            normalizedWords: normalizedWords
        )

        let maxDropDelay: TimeInterval = 45
        var cycles: [Cycle] = []
        for wake in wakes {
            guard cycles.last.map({ wake.startTime - $0.wake.startTime >= 5 }) ?? true else {
                continue
            }
            guard let drop = drops.first(where: {
                $0.startTime >= wake.endTime
                    && $0.startTime - wake.startTime <= maxDropDelay
            }) else {
                continue
            }
            guard sustainedWakeExits.contains(where: {
                $0.startTime >= wake.endTime && $0.startTime <= drop.startTime
            }) == false else {
                continue
            }
            cycles.append(Cycle(wake: wake, drop: drop))
        }
        guard cycles.count >= 2 else { return [] }

        let maxCycleGap: TimeInterval = 180
        var clusters: [[Cycle]] = []
        for cycle in cycles {
            if let lastCycle = clusters.last?.last,
               cycle.wake.startTime - lastCycle.wake.startTime <= maxCycleGap,
               sustainedWakeExits.contains(where: {
                   $0.startTime >= lastCycle.drop.endTime
                       && $0.startTime <= cycle.wake.startTime
               }) == false {
                clusters[clusters.count - 1].append(cycle)
            } else {
                clusters.append([cycle])
            }
        }

        // Whisper frequently preserves the repeated "eyes open" half of a
        // fractionation sequence while omitting the numbered drop that follows.
        // A dense chain of those wake cues can bridge verified cycle clusters;
        // one isolated wake cannot join two otherwise separate episodes.
        var bridgedClusters: [[Cycle]] = []
        for cluster in clusters {
            guard let previous = bridgedClusters.last,
                  let previousCycle = previous.last,
                  let nextCycle = cluster.first else {
                bridgedClusters.append(cluster)
                continue
            }
            let bridgeWakes = wakes.filter {
                $0.startTime > previousCycle.wake.startTime
                    && $0.startTime < nextCycle.wake.startTime
            }
            let bridgeTimes = [previousCycle.wake.startTime]
                + bridgeWakes.map(\.startTime)
                + [nextCycle.wake.startTime]
            let bridgeIsContinuous = zip(bridgeTimes, bridgeTimes.dropFirst()).allSatisfy {
                $1 - $0 <= maxCycleGap
            }
            let crossesExit = sustainedWakeExits.contains {
                $0.startTime >= previousCycle.drop.endTime
                    && $0.startTime <= nextCycle.wake.startTime
            }
            if bridgeWakes.count >= 3, bridgeIsContinuous, crossesExit == false {
                bridgedClusters[bridgedClusters.count - 1].append(contentsOf: cluster)
            } else {
                bridgedClusters.append(cluster)
            }
        }

        let declarations = words.enumerated().compactMap { index, word -> TimeInterval? in
            normalizedWords[index].hasPrefix("fractionat") ? word.startTime : nil
        }
        let maxDeclarationLead: TimeInterval = 360
        let maxDeclarationLag: TimeInterval = 120
        return bridgedClusters.enumerated().compactMap { clusterIndex, cluster in
            guard cluster.count >= 2,
                  let firstCycle = cluster.first,
                  let lastCycle = cluster.last else {
                return nil
            }

            let previousClusterEnd = clusterIndex > 0
                ? bridgedClusters[clusterIndex - 1].last?.drop.endTime ?? 0
                : 0
            var activityStart = firstCycle.wake.startTime
            for wake in wakes.reversed()
            where wake.startTime < firstCycle.wake.startTime
                && wake.startTime >= previousClusterEnd {
                guard activityStart - wake.startTime <= maxCycleGap else { break }
                activityStart = wake.startTime
            }

            let precedingDeclaration = declarations.first(where: {
                $0 <= activityStart && activityStart - $0 <= maxDeclarationLead
            })
            let inlineDeclaration = declarations.first(where: {
                $0 > firstCycle.wake.startTime
                    && $0 - firstCycle.wake.startTime <= maxDeclarationLag
                    && $0 <= lastCycle.drop.endTime
            })
            let declaredCycle = inlineDeclaration.flatMap { declaration in
                cluster.last(where: { $0.wake.startTime <= declaration })
            }
            let spanStart: TimeInterval
            let includedCycleCount: Int
            if let declaredCycle {
                spanStart = declaredCycle.drop.startTime
                includedCycleCount = cluster.filter {
                    $0.wake.startTime >= declaredCycle.wake.startTime
                }.count
            } else {
                spanStart = precedingDeclaration.map { $0 <= 60 ? 0 : $0 } ?? activityStart
                includedCycleCount = cluster.count
            }
            return FractionationCycleSpan(
                startTime: max(0, spanStart),
                endTime: min(duration, lastCycle.drop.endTime),
                cycleCount: includedCycleCount
            )
        }
    }

    static func applyFractionationSpans(
        to timeline: [HypnosisMetadata.Phase?],
        wordTimestamps: [WordTimestamp],
        duration: TimeInterval
    ) -> [HypnosisMetadata.Phase?] {
        var repaired = timeline
        for span in detectFractionationSpans(in: wordTimestamps, duration: duration) {
            let start = max(repaired.startIndex, Int(floor(span.startTime)))
            let end = min(repaired.endIndex, Int(ceil(span.endTime)))
            guard start < end else { continue }
            for index in start..<end {
                repaired[index] = .fractionation
            }
        }
        return repaired
    }

    private static func normalizedCycleWord(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func phraseEvents(
        patterns: [[String]],
        words: [WordTimestamp],
        normalizedWords: [String]
    ) -> [(startTime: TimeInterval, endTime: TimeInterval)] {
        var events: [(startTime: TimeInterval, endTime: TimeInterval)] = []
        for index in normalizedWords.indices {
            for pattern in patterns {
                let endIndex = index + pattern.count
                guard endIndex <= normalizedWords.count,
                      Array(normalizedWords[index..<endIndex]) == pattern else {
                    continue
                }
                let event = (
                    startTime: words[index].startTime,
                    endTime: words[endIndex - 1].endTime
                )
                if events.last.map({ event.startTime - $0.startTime >= 3 }) ?? true {
                    events.append(event)
                }
                break
            }
        }
        return events
    }

    /// Converts a repeated interior wake-and-drop sequence into the structural
    /// fractionation phase before short-run smoothing can erase its brief
    /// emergence and induction evidence.
    static func flagFractionationCycles(
        in timeline: [HypnosisMetadata.Phase?]
    ) -> [HypnosisMetadata.Phase?] {
        struct DetectedRun {
            let phase: HypnosisMetadata.Phase
            let start: Int
            var end: Int
        }

        var runs: [DetectedRun] = []
        for index in timeline.indices {
            guard let phase = timeline[index]?.labelingPhase else { continue }
            if runs.last?.phase == phase {
                runs[runs.count - 1].end = index + 1
            } else {
                runs.append(DetectedRun(phase: phase, start: index, end: index + 1))
            }
        }

        // The chunk sampler intentionally leaves gaps on long files. The rest
        // of this analyzer forward-fills those gaps, so each observed phase run
        // semantically lasts until the next different observation.
        if runs.count > 1 {
            for index in 0..<(runs.count - 1) {
                runs[index].end = runs[index + 1].start
            }
        }
        if runs.isEmpty == false {
            runs[runs.count - 1].end = timeline.endIndex
        }

        guard runs.count >= 5 else { return timeline }

        let returnIndices = runs.indices.filter { index in
            guard index > 0, index < runs.count - 1 else { return false }
            return runs[index].phase == .emergence
                && runs[index + 1].phase == .induction
        }
        guard returnIndices.count >= 2,
              let firstReturnIndex = returnIndices.first,
              let lastReturnIndex = returnIndices.last else {
            return timeline
        }

        let precedingRun = runs[firstReturnIndex - 1]
        let start = precedingRun.phase == .induction
            ? precedingRun.start
            : runs[firstReturnIndex].start
        let end = runs[lastReturnIndex + 1].end
        var repaired = timeline
        for index in start..<end {
            repaired[index] = .fractionation
        }
        return repaired
    }

    // MARK: - Short Run Collapsing

    /// Absorbs runs shorter than `minRun` seconds into their forward neighbour
    /// to eliminate boundary oscillation at phase transitions.
    static func collapseShortRuns(
        _ timeline: [HypnosisMetadata.Phase?],
        minRun: Int
    ) -> [HypnosisMetadata.Phase?] {
        guard !timeline.isEmpty else { return timeline }

        var runs = buildPhaseRuns(from: timeline)

        var changed = true
        while changed {
            changed = false
            guard let shortIdx = runs.indices.first(where: { runs[$0].end - runs[$0].start < minRun }) else { break }

            if shortIdx + 1 < runs.count {
                runs[shortIdx].phase = runs[shortIdx + 1].phase
            } else if shortIdx > 0 {
                runs[shortIdx].phase = runs[shortIdx - 1].phase
            } else {
                break
            }
            runs = mergeAdjacentIdentical(runs)
            changed = true
        }

        return applyRuns(runs, to: timeline)
    }

    // MARK: - Run Helpers

    private static func buildPhaseRuns(from timeline: [HypnosisMetadata.Phase?]) -> [PhaseRun] {
        var runs: [PhaseRun] = []
        var current = timeline[0]
        var runStart = 0

        for idx in 1..<timeline.count where timeline[idx] != current {
            runs.append(PhaseRun(phase: current, start: runStart, end: idx))
            current = timeline[idx]
            runStart = idx
        }
        runs.append(PhaseRun(phase: current, start: runStart, end: timeline.count))
        return runs
    }

    private static func mergeAdjacentIdentical(_ runs: [PhaseRun]) -> [PhaseRun] {
        var merged: [PhaseRun] = []
        for run in runs {
            if let last = merged.last, last.phase == run.phase {
                merged[merged.count - 1].end = run.end
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    private static func applyRuns(_ runs: [PhaseRun], to timeline: [HypnosisMetadata.Phase?]) -> [HypnosisMetadata.Phase?] {
        var output = timeline
        for run in runs {
            for idx in run.start..<run.end {
                output[idx] = run.phase
            }
        }
        return output
    }

    // MARK: - Segment Consolidation

    static func consolidatePhaseSegments(
        timeline: [HypnosisMetadata.Phase?],
        duration: Double
    ) -> [PhaseSegment] {
        guard !timeline.isEmpty else { return [] }

        var segments: [PhaseSegment] = []
        var currentPhase = timeline[0] ?? .preTalk
        var spanStart = 0

        for idx in 1..<timeline.count {
            let phase = timeline[idx] ?? currentPhase
            if phase != currentPhase {
                segments.append(makeSegment(
                    phase: currentPhase,
                    start: Double(spanStart),
                    end: Double(idx)
                ))
                currentPhase = phase
                spanStart = idx
            }
        }
        segments.append(makeSegment(
            phase: currentPhase,
            start: Double(spanStart),
            end: duration
        ))
        return segments
    }

    static func makeSegment(
        phase: HypnosisMetadata.Phase,
        start: Double,
        end: Double
    ) -> PhaseSegment {
        PhaseSegment(
            phase: phase,
            startTime: start,
            endTime: end,
            characteristics: phase.displayName,
            tranceDepthEstimate: phase.tranceDepthEstimate,
            confidenceLevel: .high   // AI-sourced segments get high confidence
        )
    }

    static func tranceDepthForPhase(_ phase: HypnosisMetadata.Phase) -> Double {
        phase.tranceDepthEstimate
    }
}
