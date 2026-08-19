//
//  SegmentPhaseNamer.swift
//  Ilumionate
//
//  Assigns a phase to each structural segment, without a language model.
//
//  Naming is where the cost is. Holding boundaries fixed and swapping correct
//  labels for the shipping analyser's own took BF.mp3 from 9% to 28% frequency
//  deviation and Tick Tock from 11% to 32% — roughly three times what boundary
//  error costs — because a wrong label selects a different light behaviour
//  outright while a misplaced boundary only shifts when the right one starts.
//
//  Two things make this tractable where per-chunk classification was not. There
//  are about eight segments in a file rather than 2110 windows, so each decision
//  has minutes of evidence behind it. And the sequence can be decoded as a
//  whole, so a single odd segment cannot send the rest of the file backwards —
//  which is exactly the failure the old greedy chain produced.
//

import Foundation

nonisolated enum SegmentPhaseNamer {

    /// Deliberately four names, not the full twelve.
    ///
    /// `SessionGenerator.intensityContour` has four behaviours, and these select
    /// three of them: decay for induction and deepening, gentle oscillation for
    /// suggestions, a rise for emergence. Naming finer than the light engine can
    /// act on would add error without adding fidelity — `pre_talk` and
    /// `induction` produce identical light, so distinguishing them here could
    /// only ever be wrong, never useful. Fractionation's faster oscillation is
    /// omitted because nothing measured so far separates it reliably.
    static let namedPhases: [TrancePhase] = [.induction, .deepening, .suggestions, .emergence]

    /// A count is near-deterministic evidence, so it outweighs every prior.
    private static let countingWeight = 4.0

    /// Going backwards is not impossible, only very unlikely — a hard block
    /// would make one bad segment unrecoverable for the rest of the file.
    private static let backwardsPenalty = -6.0

    static func name(
        segments: [StructuralSegment],
        countingRuns: [CountingRun],
        prosody: ProsodicProfile?,
        duration: TimeInterval
    ) -> [TrancePhase] {
        guard segments.isEmpty == false else { return [] }
        let span = max(duration, segments.last?.endTime ?? 0)
        guard span > 0 else { return segments.map { _ in .deepening } }

        let scores = segments.map { segment in
            namedPhases.map { phase in
                emission(for: phase, segment: segment, countingRuns: countingRuns, prosody: prosody, span: span)
            }
        }
        return decode(scores).map { namedPhases[$0] }
    }

    // MARK: - Evidence

    private static func emission(
        for phase: TrancePhase,
        segment: StructuralSegment,
        countingRuns: [CountingRun],
        prosody: ProsodicProfile?,
        span: TimeInterval
    ) -> Double {
        let midpoint = segment.startTime + (segment.endTime - segment.startTime) / 2
        var score = positionPrior(for: phase, at: midpoint / span)

        for run in countingRuns where run.startTime >= segment.startTime && run.startTime < segment.endTime {
            switch (run.direction, phase) {
            case (.descending, .deepening): score += countingWeight
            case (.ascending, .emergence): score += countingWeight
            // A count down inside a segment argues against that segment being
            // the emergence, and vice versa — the pair the light engine treats
            // most differently.
            case (.descending, .emergence): score -= countingWeight
            case (.ascending, .deepening): score -= countingWeight
            default: break
            }
        }

        if let prosody {
            score += prosodyPrior(for: phase, segment: segment, prosody: prosody)
        }
        return score
    }

    /// Shapes rather than thresholds: an induction is early, an emergence is
    /// late, and the middle is deepening shading into suggestions.
    private static func positionPrior(for phase: TrancePhase, at position: Double) -> Double {
        switch phase {
        case .induction:   return 2.0 * max(0, 1 - position * 3.5)
        case .deepening:   return 1.0 - abs(position - 0.35) * 1.5
        case .suggestions: return 1.0 - abs(position - 0.70) * 1.5
        case .emergence:   return 2.5 * max(0, (position - 0.82) / 0.18)
        default:           return 0
        }
    }

    /// Measured against the file's own averages, not absolute thresholds. The
    /// labelled corpus puts almost every phase between 82 and 97 wpm, so only
    /// the deviation within a file carries information.
    private static func prosodyPrior(
        for phase: TrancePhase,
        segment: StructuralSegment,
        prosody: ProsodicProfile
    ) -> Double {
        let window = prosody.windowDuration
        guard window > 0 else { return 0 }
        let first = max(0, Int(segment.startTime / window))
        let last = min(prosody.speechRateCurve.count - 1, Int(segment.endTime / window) - 1)
        guard first <= last, prosody.speechRateCurve.isEmpty == false else { return 0 }

        let spoken = prosody.speechRateCurve[first...last].filter { $0 > 0 }
        guard spoken.isEmpty == false else { return 0 }
        let rate = spoken.reduce(0, +) / Double(spoken.count)
        let average = prosody.averageSpeechRate
        guard average > 0 else { return 0 }

        // Normalised so a 20% deviation is worth about half a point — enough to
        // break a tie, never enough to overrule a count.
        let relative = (rate - average) / average
        switch phase {
        case .deepening:   return -relative * 2.5
        case .emergence:   return relative * 2.5
        case .induction:   return -relative * 1.0
        case .suggestions: return relative * 1.0
        default:           return 0
        }
    }

    // MARK: - Sequence

    /// Viterbi over the ordered phases.
    ///
    /// Decoding the sequence as a whole is the point. The chunk classifier chose
    /// each label greedily from the one before, so a single flip propagated
    /// forward with no way to revise it; here a strong later segment can pull an
    /// earlier ambiguous one into line.
    private static func decode(_ scores: [[Double]]) -> [Int] {
        guard let first = scores.first else { return [] }
        var best = first
        var backpointers: [[Int]] = []

        for step in scores.dropFirst() {
            var next = [Double](repeating: -.infinity, count: namedPhases.count)
            var pointers = [Int](repeating: 0, count: namedPhases.count)
            for current in namedPhases.indices {
                for previous in namedPhases.indices {
                    let transition = current >= previous
                        ? 0.0
                        : backwardsPenalty * Double(previous - current)
                    let total = best[previous] + transition + step[current]
                    if total > next[current] {
                        next[current] = total
                        pointers[current] = previous
                    }
                }
            }
            best = next
            backpointers.append(pointers)
        }

        var index = best.enumerated().max { $0.element < $1.element }?.offset ?? 0
        var path = [index]
        for pointers in backpointers.reversed() {
            index = pointers[index]
            path.append(index)
        }
        return path.reversed()
    }
}
