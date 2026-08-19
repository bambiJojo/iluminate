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
    ///
    /// Raised from 45s after running the detector over 143 real analyses: at 45s
    /// files were routinely cut into 13–27 pieces, with segments as short as
    /// 48 seconds sitting inside what is obviously one passage.
    static let minimumSegmentDuration: TimeInterval = 120

    /// The same rule, relaxed, for boundaries a counted passage places.
    ///
    /// A count is deterministic evidence and a closing awakening is routinely
    /// shorter than a full phase — "Umm....m4a" counts down at 13:56 of 14:44.
    /// Holding that to the 120-second rule discarded the one boundary in the
    /// file the detector was most certain about.
    static let minimumAnchoredSegmentDuration: TimeInterval = 30

    /// **Unvalidated.** Novelty is scaled absolutely — roughly 0 for a
    /// homogeneous stretch and roughly 0.5 for a clean seam — so a fixed floor
    /// is meaningful across files, but the right value for real audio is not
    /// known yet. It is a parameter, not a constant, precisely so the offline
    /// harness can sweep it against files whose structure the user recognises.
    ///
    /// Raised from 0.08 to 0.25 after the sweep over 143 real analyses: below
    /// 0.25 the adaptive threshold dominates and the floor never binds, which
    /// left files cut into as many as 27 pieces.
    ///
    /// Stated plainly because the number it replaces — the collapser's 3.5% —
    /// was chosen the same way and never revisited. This one has now been
    /// checked against a whole library, but not yet against anybody's ears.
    static let defaultMinimumNovelty: Double = 0.25

    /// How far a peak must rise above the surrounding curve to count.
    ///
    /// Height alone is a poor test: `isLocalMaximum` admits any bump that merely
    /// equals its two neighbours, so a gently undulating plateau contributes a
    /// dozen "peaks" that are not boundaries. Prominence — height above the
    /// deeper of the two valleys flanking it — is what separates a real edge
    /// from ripple, and against the labelled corpus it is precision, not recall,
    /// that limits the detector.
    static let defaultMinimumProminence: Double = 0.04

    /// Peaks are ranked, so this only has to be high enough that a counted
    /// passage outranks any ordinary novelty peak competing for the same slot.
    private static let countingAnchorScore = Double.greatestFiniteMagnitude

    static func segment(
        words: [WordTimestamp],
        prosody: ProsodicProfile?,
        duration: TimeInterval,
        frameDuration: TimeInterval = StructuralFrames.defaultFrameDuration,
        minimumSegmentDuration: TimeInterval = StructuralSegmenter.minimumSegmentDuration,
        minimumNovelty: Double = defaultMinimumNovelty,
        minimumProminence: Double = defaultMinimumProminence,
        kernelSize: Int = StructuralNovelty.defaultKernelSize
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

        let novelty = StructuralNovelty.curve(frames: frames, kernelSize: kernelSize)
        let runs = CountingRunDetector.runs(in: words)

        let boundaries = selectBoundaries(
            novelty: novelty,
            countingRuns: runs,
            frameCount: frames.count,
            frameDuration: frameDuration,
            minimumSegmentDuration: minimumSegmentDuration,
            minimumNovelty: minimumNovelty,
            minimumProminence: minimumProminence
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
        minimumSegmentDuration: TimeInterval = StructuralSegmenter.minimumSegmentDuration,
        minimumNovelty: Double,
        minimumProminence: Double = defaultMinimumProminence
    ) -> [Int] {
        let spacing = max(1, Int(ceil(minimumSegmentDuration / frameDuration)))
        // A boundary must leave a full segment on *both* sides, or the last
        // segment ends up shorter than the minimum it was meant to guarantee.
        let admissible = spacing..<max(spacing, frameCount - spacing + 1)

        var candidates: [(index: Int, score: Double)] = []

        let anchorSpacing = max(1, Int(ceil(minimumAnchoredSegmentDuration / frameDuration)))
        let anchorAdmissible = anchorSpacing..<max(anchorSpacing, frameCount - anchorSpacing + 1)
        for run in countingRuns {
            let index = Int(run.startTime / frameDuration)
            guard anchorAdmissible.contains(index) else { continue }
            candidates.append((index, countingAnchorScore))
        }

        let threshold = max(minimumNovelty, adaptiveThreshold(novelty))
        for index in admissible where isLocalMaximum(novelty, at: index) {
            guard novelty[index] >= threshold else { continue }
            guard prominence(of: novelty, at: index, window: spacing) >= minimumProminence else { continue }
            // Ranked by prominence, not raw height: a modest peak standing clear
            // of flat surroundings is better evidence than a tall one sitting on
            // an already-high plateau.
            candidates.append((index, prominence(of: novelty, at: index, window: spacing)))
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

    /// Height above the deeper of the two valleys flanking the peak, measured
    /// within one minimum-segment either side — beyond that the comparison stops
    /// being local and every peak in a long file looks prominent.
    static func prominence(of novelty: [Double], at index: Int, window: Int) -> Double {
        let lower = max(0, index - window)
        let upper = min(novelty.count - 1, index + window)
        guard lower < index, index < upper else { return 0 }
        let leftValley = novelty[lower..<index].min() ?? 0
        let rightValley = novelty[(index + 1)...upper].min() ?? 0
        return novelty[index] - max(leftValley, rightValley)
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
