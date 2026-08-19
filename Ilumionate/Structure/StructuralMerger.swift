//
//  StructuralMerger.swift
//  Ilumionate
//
//  Merges over-proposed segments back together.
//
//  The detector deliberately errs towards too many boundaries. Against the
//  labelled corpus it finds half of them and proposes two to three times too
//  many — where the shipping keyword analyser finds 3 of 34. A boundary never
//  proposed cannot be recovered; a boundary proposed in error can be removed,
//  which is why the split lands here.
//
//  Merging can only lower recall, never raise it, so the only thing it can
//  usefully do is drop false positives while keeping true ones. That needs
//  evidence the novelty curve does not carry: novelty is measured in a fixed
//  window either side of a point, while a merge compares two segments in full.
//  Two stretches flanking a locally-novel seam can be globally identical, and
//  raising the novelty threshold cannot tell that case from a real transition —
//  which is why thresholds saturated at 26% precision.
//
//  MEASURED AND IT DOES NOT WORK. Against the labelled corpus, merging trades
//  recall for precision at a ruinous rate:
//
//      no merge   recall 50%   precision 26%   F1 35%
//      cliff 0.10 recall 29%   precision 24%   F1 26%
//      cliff 0.30 recall 17%   precision 30%   F1 22%
//      cliff 0.55 recall  8%   precision 37%   F1 14%
//
//  Even the mildest setting costs 21 points of recall and *lowers* precision, so
//  the criterion is removing true boundaries in preference to false ones. Whole-
//  segment similarity turns out to discriminate no better than the local novelty
//  it was meant to complement, which is consistent with everything else measured
//  here: adjacent phases sit between 82 and 97 wpm, and hypnosis vocabulary is
//  shared across induction, deepening and suggestion alike.
//
//  Kept, tested and deliberately not wired into anything — as the record of an
//  experiment worth not repeating, and because the mechanism is sound if a
//  better cost function ever arrives. `Tools/structure-eval` sweeps it with a
//  negative cliff meaning "off", so the comparison stays reproducible.
//
//  No language model is involved.
//

import Foundation

nonisolated enum StructuralMerger {

    /// Agglomerative: repeatedly join the most similar adjacent pair, then cut
    /// the sequence where merging suddenly becomes expensive.
    static func merge(
        _ segmentation: StructuralSegmentation,
        minimumCliff: Double = StructuralMerger.minimumCliff
    ) -> StructuralSegmentation {
        guard segmentation.segments.count > 1 else { return segmentation }

        let protectedStarts = protectedBoundaryTimes(in: segmentation)
        var groups = segmentation.segments.map { [$0] }
        var history: [(cost: Double, groups: [[StructuralSegment]])] = [(0, groups)]

        while groups.count > 1 {
            guard let step = cheapestMerge(
                groups: groups,
                segmentation: segmentation,
                protectedStarts: protectedStarts
            ) else { break }

            groups = groups.enumerated().reduce(into: [[StructuralSegment]]()) { result, entry in
                if entry.offset == step.index + 1 {
                    result[result.count - 1] += entry.element
                } else {
                    result.append(entry.element)
                }
            }
            history.append((step.cost, groups))
        }

        return StructuralSegmentation(
            segments: assemble(cut(history, minimumCliff: minimumCliff)),
            frames: segmentation.frames,
            novelty: segmentation.novelty,
            countingRuns: segmentation.countingRuns
        )
    }

    // MARK: - Cost

    /// Dissimilarity between the two groups as wholes, averaged over whichever
    /// modalities the frames carry.
    private static func cost(
        _ left: [StructuralSegment],
        _ right: [StructuralSegment],
        segmentation: StructuralSegmentation
    ) -> Double {
        let leftProfile = profile(for: left, in: segmentation)
        let rightProfile = profile(for: right, in: segmentation)
        return 1 - StructuralNovelty.similarity(leftProfile, rightProfile)
    }

    /// Collapses a run of segments into one frame-shaped summary, so groups of
    /// different lengths compare on equal terms.
    private static func profile(
        for group: [StructuralSegment],
        in segmentation: StructuralSegmentation
    ) -> StructuralFrame {
        guard let start = group.first?.startTime, let end = group.last?.endTime else {
            return StructuralFrame(startTime: 0, endTime: 0, prosody: [], terms: [:])
        }
        let covered = segmentation.frames.filter { $0.startTime >= start && $0.endTime <= end }
        guard covered.isEmpty == false else {
            return StructuralFrame(startTime: start, endTime: end, prosody: [], terms: [:])
        }

        let width = covered.first?.prosody.count ?? 0
        let prosody = (0..<width).map { dimension in
            covered.reduce(0.0) { $0 + $1.prosody[dimension] } / Double(covered.count)
        }

        var terms: [String: Double] = [:]
        for frame in covered {
            for (term, weight) in frame.terms { terms[term, default: 0] += weight }
        }
        let norm = terms.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if norm > 0 { terms = terms.mapValues { $0 / norm } }

        return StructuralFrame(startTime: start, endTime: end, prosody: prosody, terms: terms)
    }

    private static func cheapestMerge(
        groups: [[StructuralSegment]],
        segmentation: StructuralSegmentation,
        protectedStarts: Set<TimeInterval>
    ) -> (index: Int, cost: Double)? {
        var best: (index: Int, cost: Double)?
        for index in 0..<(groups.count - 1) {
            // A counted passage is deterministic evidence of a transition; a
            // similarity score must not be allowed to overrule it.
            if let start = groups[index + 1].first?.startTime, protectedStarts.contains(start) {
                continue
            }
            let candidate = cost(groups[index], groups[index + 1], segmentation: segmentation)
            if best == nil || candidate < best!.cost { best = (index, candidate) }
        }
        return best
    }

    private static func protectedBoundaryTimes(in segmentation: StructuralSegmentation) -> Set<TimeInterval> {
        let tolerance = StructuralFrames.defaultFrameDuration
        return Set(
            segmentation.segments.dropFirst().map(\.startTime).filter { start in
                segmentation.countingRuns.contains { abs($0.startTime - start) <= tolerance }
            }
        )
    }

    // MARK: - Where to stop

    /// Cuts the merge sequence where joining the next pair costs sharply more
    /// than everything joined so far.
    ///
    /// A uniform file merges cheaply the whole way down and never produces such a
    /// jump, so it collapses to one segment — the answer the pipeline previously
    /// could not express. A file with real structure merges its false boundaries
    /// cheaply and then hits a wall at the true ones, and the wall is the cut.
    private static func cut(
        _ history: [(cost: Double, groups: [[StructuralSegment]])],
        minimumCliff: Double
    ) -> [[StructuralSegment]] {
        // `> 1`, not `> 2`: with exactly two segments there is a single merge
        // step, and it still has to be judged. Skipping it merged every
        // two-segment file unconditionally, however different the halves.
        guard history.count > 1 else { return history.last?.groups ?? [] }

        var runningMaximum = 0.0
        var best: (jump: Double, index: Int)?
        for index in 1..<history.count {
            let cost = history[index].cost
            // Compared against the largest cost paid so far rather than the
            // previous one: merge costs are not monotonic, and a single cheap
            // step in the middle should not manufacture a cliff after it.
            let jump = cost - runningMaximum
            if jump > (best?.jump ?? 0) { best = (jump, index) }
            runningMaximum = max(runningMaximum, cost)
        }

        guard let best, best.jump >= minimumCliff else {
            return history.last?.groups ?? []
        }
        return history[best.index - 1].groups
    }

    /// **Unvalidated**, and a parameter of the shape the sweep can move. Below
    /// this the largest jump is treated as ordinary variation rather than the
    /// edge of the file's real structure, and everything merges.
    static let minimumCliff = 0.25

    private static func assemble(_ groups: [[StructuralSegment]]) -> [StructuralSegment] {
        groups.compactMap { group in
            guard let first = group.first, let last = group.last else { return nil }
            return StructuralSegment(
                startTime: first.startTime,
                endTime: last.endTime,
                confidence: first.confidence
            )
        }
    }
}
