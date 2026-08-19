//
//  StructuralFrames.swift
//  Ilumionate
//
//  Turns a transcript and its prosodic profile into a single time series that
//  later stages can compare frame-against-frame.
//
//  This exists because phase structure is a global property. The chunked
//  classifier asks the model to name a phase from fifteen seconds of text, and
//  fifteen seconds is not enough to tell induction from deepening — "your eyes
//  are getting heavier" belongs to both. Frames make no judgement about phase;
//  they only describe what each stretch of the file is *like*, so that the
//  boundaries can be found by contrast rather than by naming.
//

import Foundation

/// One fixed-width slice of the file, described independently of any phase.
nonisolated struct StructuralFrame: Sendable, Equatable {
    let startTime: TimeInterval
    let endTime: TimeInterval

    /// Z-normalised prosodic dimensions, in `StructuralFrames.prosodyDimensions`
    /// order. Empty when the file has no prosodic profile — lexical-only is a
    /// supported mode, since `AnalysisResult.prosodicProfile` is optional.
    let prosody: [Double]

    /// L2-normalised term frequencies, so cosine similarity is a dot product.
    let terms: [String: Double]
}

nonisolated enum StructuralFrames {

    /// Order of the values in `StructuralFrame.prosody`.
    static let prosodyDimensions = [
        "speechRate", "volume", "pitch", "speechSilenceRatio", "pauseDensity"
    ]

    /// Wide enough that a single slow sentence does not read as a section, and
    /// narrow enough to place a boundary within a few seconds. Prosody arrives
    /// in 3-second windows, so this is four of them.
    static let defaultFrameDuration: TimeInterval = 12

    static func build(
        words: [WordTimestamp],
        prosody: ProsodicProfile?,
        duration: TimeInterval,
        frameDuration: TimeInterval = defaultFrameDuration
    ) -> [StructuralFrame] {
        let span = max(duration, words.last?.endTime ?? 0)
        guard span > 0, frameDuration > 0 else { return [] }

        let count = max(1, Int(ceil(span / frameDuration)))
        let bounds = (0..<count).map { index in
            (
                start: Double(index) * frameDuration,
                end: min(Double(index + 1) * frameDuration, span)
            )
        }

        let terms = termFrequencies(words: words, bounds: bounds, frameDuration: frameDuration)
        let prosodyRows = prosody.map { normalised(rawProsody(from: $0, bounds: bounds)) }

        return bounds.enumerated().map { index, bound in
            StructuralFrame(
                startTime: bound.start,
                endTime: bound.end,
                prosody: prosodyRows?[index] ?? [],
                terms: terms[index]
            )
        }
    }

    // MARK: - Lexical

    /// Common words are deliberately kept. They occur in every frame, so they
    /// raise similarity uniformly rather than distinguishing sections — and the
    /// checkerboard kernel downstream measures *contrast*, which cancels a
    /// uniform offset. Dropping them would bake English stopword assumptions in
    /// for no gain.
    private static func termFrequencies(
        words: [WordTimestamp],
        bounds: [(start: Double, end: Double)],
        frameDuration: TimeInterval
    ) -> [[String: Double]] {
        var counts = Array(repeating: [String: Double](), count: bounds.count)
        for word in words {
            let index = min(bounds.count - 1, max(0, Int(word.startTime / frameDuration)))
            guard let token = normalise(word.word) else { continue }
            counts[index][token, default: 0] += 1
        }
        return counts.map(l2Normalised)
    }

    private static func normalise(_ word: String) -> String? {
        let token = word.lowercased().filter { $0.isLetter || $0.isNumber }
        return token.isEmpty ? nil : token
    }

    private static func l2Normalised(_ counts: [String: Double]) -> [String: Double] {
        let norm = counts.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return [:] }
        return counts.mapValues { $0 / norm }
    }

    // MARK: - Prosody

    private static func rawProsody(
        from profile: ProsodicProfile,
        bounds: [(start: Double, end: Double)]
    ) -> [[Double]] {
        bounds.map { bound in
            [
                mean(profile.speechRateCurve, from: bound, window: profile.windowDuration),
                mean(profile.volumeCurve, from: bound, window: profile.windowDuration),
                mean(profile.pitchCurve, from: bound, window: profile.windowDuration),
                mean(profile.speechSilenceRatio, from: bound, window: profile.windowDuration),
                pauseDensity(profile.pauses, in: bound)
            ]
        }
    }

    private static func mean(
        _ curve: [Double],
        from bound: (start: Double, end: Double),
        window: TimeInterval
    ) -> Double {
        guard window > 0, !curve.isEmpty else { return 0 }
        let first = max(0, Int(bound.start / window))
        let last = min(curve.count - 1, Int(ceil(bound.end / window)) - 1)
        guard first <= last else { return curve[min(first, curve.count - 1)] }
        let slice = curve[first...last]
        return slice.reduce(0, +) / Double(slice.count)
    }

    /// Seconds of deliberate silence per second of frame. Natural pauses are
    /// excluded: they track sentence rhythm, not structure.
    private static func pauseDensity(
        _ pauses: [DetectedPause],
        in bound: (start: Double, end: Double)
    ) -> Double {
        let span = bound.end - bound.start
        guard span > 0 else { return 0 }
        let total = pauses
            .filter { $0.category != .natural }
            .reduce(0.0) { running, pause in
                let overlap = min(bound.end, pause.startTime + pause.duration) - max(bound.start, pause.startTime)
                return running + max(0, overlap)
            }
        return total / span
    }

    /// Z-normalises each dimension across frames.
    ///
    /// A dimension that never varies carries no boundary information, and
    /// dividing by its zero standard deviation would put NaN into every later
    /// similarity score — one silent file would corrupt the whole matrix. Such
    /// a dimension flattens to zero instead, contributing nothing.
    private static func normalised(_ rows: [[Double]]) -> [[Double]] {
        guard let width = rows.first?.count, rows.count > 1 else {
            return rows.map { $0.map { _ in 0 } }
        }
        var result = rows
        for dimension in 0..<width {
            let column = rows.map { $0[dimension] }
            let mean = column.reduce(0, +) / Double(column.count)
            let variance = column.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(column.count)
            let deviation = variance.squareRoot()
            for index in rows.indices {
                result[index][dimension] = deviation > 0 ? (column[index] - mean) / deviation : 0
            }
        }
        return result
    }
}
