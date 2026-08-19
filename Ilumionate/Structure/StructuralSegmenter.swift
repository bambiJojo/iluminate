//
//  StructuralSegmenter.swift
//  Ilumionate
//
//  Turns the novelty curve and counting anchors into segment boundaries.
//
//  The ordering here is the whole argument. The existing pipeline classifies
//  ~2110 windows independently and tries to recover segments from the labels;
//  this finds the boundaries first and leaves naming to a later, much smaller
//  step. Boundaries are a global property of the file and cannot be recovered
//  from local guesses — which is why the current collapser, a 3.5%-of-duration
//  minimum-run filter, reduced six classified phases to one on a real file
//  rather than smoothing them.
//
//  Nothing in this file consults a language model.
//

import Foundation

nonisolated struct StructuralSegment: Sendable, Equatable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    /// Novelty at this segment's opening boundary. Zero for the first segment,
    /// which opens because the file does, not because anything changed.
    let confidence: Double

    var duration: TimeInterval { endTime - startTime }
}

/// The conclusion together with the evidence behind it, so the offline harness
/// can show what the detector saw and not only what it decided.
nonisolated struct StructuralSegmentation: Sendable {
    let segments: [StructuralSegment]
    let frames: [StructuralFrame]
    let novelty: [Double]
    let countingRuns: [CountingRun]
}

nonisolated enum StructuralSegmenter {

    /// No structural phase in this material is credibly shorter than this, and
    /// it keeps a noisy novelty curve from shredding a file into fragments.
    static let minimumSegmentDuration: TimeInterval = 45

    /// **Unvalidated.** Novelty is scaled absolutely — roughly 0 for a
    /// homogeneous stretch and roughly 0.5 for a clean seam — so a fixed floor
    /// is meaningful across files, but the right value for real audio is not
    /// known yet. It is a parameter, not a constant, precisely so the offline
    /// harness can sweep it against files whose structure the user recognises.
    ///
    /// Stated plainly because the number it replaces — the collapser's 3.5% —
    /// was chosen the same way and never revisited.
    static let defaultMinimumNovelty: Double = 0.08

    /// Peaks are ranked, so this only has to be high enough that a counted
    /// passage outranks any ordinary novelty peak competing for the same slot.
    private static let countingAnchorScore = Double.greatestFiniteMagnitude

    static func segment(
        words: [WordTimestamp],
        prosody: ProsodicProfile?,
        duration: TimeInterval,
        frameDuration: TimeInterval = StructuralFrames.defaultFrameDuration,
        minimumNovelty: Double = defaultMinimumNovelty
    ) -> StructuralSegmentation {
        let frames = StructuralFrames.build(
            words: words,
            prosody: prosody,
            duration: duration,
            frameDuration: frameDuration
        )
        guard frames.isEmpty == false else {
            return StructuralSegmentation(segments: [], frames: [], novelty: [], countingRuns: [])
        }

        let novelty = StructuralNovelty.curve(frames: frames)
        let runs = CountingRunDetector.runs(in: words)

        let boundaries = selectBoundaries(
            novelty: novelty,
            countingRuns: runs,
            frameCount: frames.count,
            frameDuration: frameDuration,
            minimumNovelty: minimumNovelty
        )

        return StructuralSegmentation(
            segments: assemble(boundaries: boundaries, frames: frames, novelty: novelty),
            frames: frames,
            novelty: novelty,
            countingRuns: runs
        )
    }

    // MARK: - Selection

    /// Frame indices at which a new segment begins, ascending. Empty means the
    /// file is one segment — a legitimate answer, not a failure.
    static func selectBoundaries(
        novelty: [Double],
        countingRuns: [CountingRun],
        frameCount: Int,
        frameDuration: TimeInterval,
        minimumNovelty: Double
    ) -> [Int] {
        let spacing = max(1, Int(ceil(minimumSegmentDuration / frameDuration)))
        // A boundary must leave a full segment on *both* sides, or the last
        // segment ends up shorter than the minimum it was meant to guarantee.
        let admissible = spacing..<max(spacing, frameCount - spacing + 1)
        guard admissible.isEmpty == false else { return [] }

        var candidates: [(index: Int, score: Double)] = []

        for run in countingRuns {
            let index = Int(run.startTime / frameDuration)
            guard admissible.contains(index) else { continue }
            candidates.append((index, countingAnchorScore))
        }

        let threshold = max(minimumNovelty, adaptiveThreshold(novelty))
        for index in admissible where isLocalMaximum(novelty, at: index) {
            guard novelty[index] >= threshold else { continue }
            candidates.append((index, novelty[index]))
        }

        var accepted: [Int] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard accepted.allSatisfy({ abs($0 - candidate.index) >= spacing }) else { continue }
            accepted.append(candidate.index)
        }
        return accepted.sorted()
    }

    /// Mean plus one standard deviation. On a file that genuinely has seams this
    /// keeps the shoulders of a peak from being admitted alongside it; on a flat
    /// file it collapses to nearly zero, which is why the absolute floor rather
    /// than this is what rejects a structureless file.
    private static func adaptiveThreshold(_ novelty: [Double]) -> Double {
        guard novelty.count > 1 else { return .greatestFiniteMagnitude }
        let mean = novelty.reduce(0, +) / Double(novelty.count)
        let variance = novelty.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(novelty.count)
        return mean + variance.squareRoot()
    }

    private static func isLocalMaximum(_ novelty: [Double], at index: Int) -> Bool {
        let previous = index > 0 ? novelty[index - 1] : -.infinity
        let next = index + 1 < novelty.count ? novelty[index + 1] : -.infinity
        return novelty[index] >= previous && novelty[index] >= next
    }

    // MARK: - Assembly

    private static func assemble(
        boundaries: [Int],
        frames: [StructuralFrame],
        novelty: [Double]
    ) -> [StructuralSegment] {
        let starts = [0] + boundaries
        return starts.enumerated().map { position, start in
            let end = position + 1 < starts.count ? starts[position + 1] : frames.count
            return StructuralSegment(
                startTime: frames[start].startTime,
                endTime: frames[end - 1].endTime,
                confidence: start == 0 ? 0 : novelty[start]
            )
        }
    }
}
