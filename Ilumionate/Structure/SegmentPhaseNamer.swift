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

    /// Five of the seven target phases, in session order.
    ///
    /// `conditioning` is named because it is both detectable and expensive to
    /// miss: it sits immediately before the emergence in every labelled file
    /// (66.7-91.9%, 88.2-99.1%, 90.4-96.0%, 95.0-98.0%) and is *shallower* than
    /// suggestions — 0.58 against 0.72 — so calling it suggestions lights the
    /// close of a session deeper than the hypnotist intended.
    ///
    /// `fractionation` is a target phase but is deliberately absent. All four
    /// corpus files containing it carry a single whole-file label, so nothing
    /// shows where within a file it occurs, and a positional prior for it could
    /// not be checked against anything. `brainwashing` is absent for a weaker
    /// version of the same reason: its one distinguishing signal so far is a
    /// pitch outlier (224 Hz against ~180) measured on three segments.
    ///
    /// Naming finer than the evidence supports is how the emergence prior came
    /// to claim the last five and a half minutes of a file whose real emergence
    /// is twenty-one seconds.
    static let namedPhases: [TrancePhase] = [
        .induction, .deepening, .suggestions, .conditioning, .emergence
    ]

    /// A count is near-deterministic evidence, so it outweighs every prior.
    private static let countingWeight = 4.0

    /// Where a labelled emergence can begin, as a share of the file.
    ///
    /// Measured, not guessed: across the labelled corpus emergences start at
    /// 91.9%, 96.0%, 98.0% and 99.1% and run for 0.9% to 8.1% of the duration.
    /// The first version of this namer began favouring emergence at 82% and
    /// consequently claimed the last 5.5 minutes of Mind Melt.mp3 — whose real
    /// emergence is 21 seconds — putting a rising light over five and a half
    /// minutes of post-hypnotic conditioning.
    private static let emergenceBegins = 0.88

    /// Counting up only argues for an emergence near the end. BF.mp3 counts up
    /// at 47% and DFTC at 34%, and neither is an emergence — counting up mid-file
    /// belongs to fractionation. Treating those as emergences inverts the light
    /// for everything after them.
    private static let emergenceCountWindow = 0.85

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
            let late = (run.startTime / span) >= emergenceCountWindow
            switch (run.direction, phase) {
            case (.descending, .deepening): score += countingWeight
            // A count down inside a segment argues against that segment being
            // the emergence — the pair the light engine treats most differently.
            case (.descending, .emergence): score -= countingWeight
            case (.ascending, .emergence): score += late ? countingWeight : 0
            // A mid-file count up is left neutral rather than penalised: it is
            // ambiguous, not evidence of the opposite.
            case (.ascending, .deepening): score -= late ? countingWeight : 0
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
        case .suggestions: return 1.0 - abs(position - 0.65) * 1.5
        // Spans 66.7% to 99.1% across the labelled files, always ending where the
        // emergence starts. Broad on purpose: the ordering constraint does most
        // of the work by keeping it between suggestions and emergence.
        case .conditioning: return 1.2 - abs(position - 0.86) * 3.0
        case .emergence:   return 3.0 * max(0, (position - emergenceBegins) / (1 - emergenceBegins))
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
        // Measured at 94.7 wpm against suggestions' 97.1 — too close to separate
        // on pace, so this contributes nothing and says so rather than guessing.
        case .conditioning: return 0
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
