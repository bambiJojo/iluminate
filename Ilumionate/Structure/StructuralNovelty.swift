//
//  StructuralNovelty.swift
//  Ilumionate
//
//  Foote's method, borrowed from music structure analysis.
//
//  Segmenting a song into intro/verse/chorus/outro is the same shape of problem
//  as segmenting a hypnosis file into induction/deepening/suggestion/awakening:
//  material repeats *within* a section and contrasts *between* sections, and no
//  two files share a template. The standard tool builds a self-similarity
//  matrix, slides a checkerboard kernel down its diagonal, and reads the
//  boundaries off the resulting novelty curve.
//
//  Nothing here consults a language model. That is the point — a speech-rate
//  curve cannot be refused by a safety model, rate limited, or blocked by Game
//  Mode, all three of which currently cost the pipeline whole analyses.
//

import Foundation

nonisolated enum StructuralNovelty {

    /// Frames per kernel side. At the default 12-second frame this looks one
    /// minute back and one minute forward, which is long enough to ignore a
    /// single slow sentence and short enough to localise a real transition.
    static let defaultKernelSize = 10

    /// Novelty per frame: high where the file stops resembling what came before
    /// and starts resembling what follows.
    static func curve(
        frames: [StructuralFrame],
        kernelSize: Int = defaultKernelSize
    ) -> [Double] {
        guard frames.isEmpty == false else { return [] }
        let half = max(1, kernelSize / 2)
        guard frames.count > 2 else { return Array(repeating: 0, count: frames.count) }

        let similarity = similarityMatrix(frames)
        let kernel = checkerboard(half: half)

        var novelty = [Double](repeating: 0, count: frames.count)
        for centre in frames.indices {
            var total = 0.0
            for a in -half..<half {
                for b in -half..<half {
                    let row = clamp(centre + a, to: frames.count)
                    let column = clamp(centre + b, to: frames.count)
                    total += kernel[a + half][b + half] * similarity[row][column]
                }
            }
            // A boundary is a *positive* checkerboard response. Negative values
            // mean the opposite pattern — homogeneity — which is not a weaker
            // boundary but a different thing, and must not survive as one.
            novelty[centre] = max(0, total)
        }
        return novelty.map { $0 / kernelWeight(kernel) }
    }

    // MARK: - Similarity

    /// Prosodic and lexical similarity are averaged over whichever modalities
    /// the file actually has. A file with no prosodic profile is scored on text
    /// alone rather than being scored as maximally dissimilar to itself.
    static func similarityMatrix(_ frames: [StructuralFrame]) -> [[Double]] {
        var matrix = [[Double]](
            repeating: [Double](repeating: 0, count: frames.count),
            count: frames.count
        )
        for i in frames.indices {
            for j in i..<frames.count {
                let value = similarity(frames[i], frames[j])
                matrix[i][j] = value
                matrix[j][i] = value
            }
        }
        return matrix
    }

    private static func similarity(_ lhs: StructuralFrame, _ rhs: StructuralFrame) -> Double {
        var parts: [Double] = []
        if lhs.prosody.isEmpty == false, lhs.prosody.count == rhs.prosody.count {
            parts.append(cosine(lhs.prosody, rhs.prosody))
        }
        if lhs.terms.isEmpty == false || rhs.terms.isEmpty == false {
            parts.append(cosine(lhs.terms, rhs.terms))
        }
        guard parts.isEmpty == false else { return 0 }
        return parts.reduce(0, +) / Double(parts.count)
    }

    private static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        let dot = zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
        let left = lhs.reduce(0) { $0 + $1 * $1 }.squareRoot()
        let right = rhs.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard left > 0, right > 0 else { return 0 }
        return dot / (left * right)
    }

    /// Term vectors arrive L2-normalised from `StructuralFrames`, so the dot
    /// product is already the cosine.
    private static func cosine(_ lhs: [String: Double], _ rhs: [String: Double]) -> Double {
        let (smaller, larger) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        return smaller.reduce(0.0) { running, entry in
            running + entry.value * (larger[entry.key] ?? 0)
        }
    }

    // MARK: - Kernel

    /// A Gaussian-tapered checkerboard: positive where both offsets fall on the
    /// same side of the seam, negative where they straddle it. Convolved along
    /// the diagonal it measures "these two stretches each resemble themselves
    /// but not each other", which is exactly a boundary.
    ///
    /// The seam sits at offset **-0.5**, between the last frame before and the
    /// first frame after, and the taper is measured from there. Two earlier
    /// attempts got this wrong in instructive ways:
    ///
    /// - Tapering from offset 0 over `-half..<half` puts the centre frame on the
    ///   positive side, so the halves carry unequal weight. A perfectly
    ///   homogeneous file then scores `(N - P)²` instead of zero, and every flat
    ///   file reports a boundary — fatal for single-phase files.
    /// - Excluding the centre offset entirely restores symmetry but makes the
    ///   frames either side of a seam score identically, so the peak is a tie
    ///   and which frame "starts" the new segment is arbitrary.
    ///
    /// Tapering about -0.5 is symmetric *and* unambiguous: `novelty[i]` scores a
    /// boundary immediately before frame `i`, so a peak at `i` means frame `i`
    /// is the first frame of the new segment.
    static func checkerboard(half: Int) -> [[Double]] {
        let sigma = max(1.0, Double(half) / 2)
        return (-half..<half).map { a in
            (-half..<half).map { b in
                let sign: Double = (a < 0) == (b < 0) ? 1 : -1
                let da = Double(a) + 0.5
                let db = Double(b) + 0.5
                return sign * exp(-(da * da + db * db) / (2 * sigma * sigma))
            }
        }
    }

    // MARK: - Helpers

    /// Clamping rather than zero-padding at the edges. Zero padding reads as
    /// "maximally different", which would plant a false boundary in the first
    /// and last frames of every file.
    private static func clamp(_ index: Int, to count: Int) -> Int {
        min(max(index, 0), count - 1)
    }

    /// Divides by the kernel's total absolute weight, **not** by the curve's own
    /// peak.
    ///
    /// Normalising to a peak of 1.0 was the first attempt and it is wrong: it
    /// makes every file peak at 1.0, including a file with no internal contrast
    /// at all, so "strong seam" and "noise, amplified" become indistinguishable.
    /// That would have made a single-phase file — a pure deepener with no
    /// boundaries to find — look exactly like a file with a clean transition.
    ///
    /// Against a fixed kernel the raw response is already comparable across
    /// files, so scaling by the kernel's weight yields roughly 0 for a
    /// homogeneous stretch and roughly 0.5 for a clean seam, on every file.
    private static func kernelWeight(_ kernel: [[Double]]) -> Double {
        let total = kernel.reduce(0.0) { running, row in
            running + row.reduce(0.0) { $0 + abs($1) }
        }
        return total > 0 ? total : 1
    }
}
