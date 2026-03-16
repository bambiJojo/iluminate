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
struct PhaseRun {
    var phase: HypnosisMetadata.Phase?
    var start: Int
    var end: Int
}

// MARK: - Smoothing Extension

extension ChunkedPhaseAnalyzer {

    // MARK: - Ordered Phases

    /// Canonical hypnosis phase order used to enforce monotonic progression.
    static let orderedPhases: [HypnosisMetadata.Phase] = [
        .preTalk, .induction, .deepening, .therapy,
        .suggestions, .conditioning, .emergence
    ]

    // MARK: - Phase Ordering Enforcement

    static func enforcePhaseOrdering(
        timeline: [HypnosisMetadata.Phase?]
    ) -> [HypnosisMetadata.Phase?] {
        var result = timeline
        var highestIndex = 0

        for idx in 0..<result.count {
            guard let phase = result[idx],
                  let phaseIndex = orderedPhases.firstIndex(of: phase) else { continue }

            if phaseIndex >= highestIndex {
                highestIndex = phaseIndex
            } else {
                result[idx] = orderedPhases[highestIndex]
            }
        }
        return result
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
            tranceDepthEstimate: tranceDepthForPhase(phase),
            confidenceLevel: .high   // AI-sourced segments get high confidence
        )
    }

    static func tranceDepthForPhase(_ phase: HypnosisMetadata.Phase) -> Double {
        switch phase {
        case .preTalk:      return 0.05
        case .induction:    return 0.25
        case .deepening:    return 0.55
        case .therapy:      return 0.90
        case .suggestions:  return 0.75
        case .conditioning: return 0.65
        case .emergence:    return 0.30
        case .transitional: return 0.40
        }
    }
}
