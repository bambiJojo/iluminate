//
//  StructuralReport.swift
//  Ilumionate
//
//  Renders a segmentation as something a person can check against a file they
//  know.
//
//  The detector's thresholds are unvalidated, and the honest way to validate
//  them is to put boundaries in front of someone who has listened to the audio.
//  That is cheaper than labelling a corpus and it catches the failure that
//  matters — boundaries in obviously wrong places — immediately.
//

import Foundation

nonisolated enum StructuralReport {

    static func text(for segmentation: StructuralSegmentation, filename: String) -> String {
        guard segmentation.segments.isEmpty == false else {
            return "\(filename) — no segments (empty transcript)"
        }

        let span = segmentation.segments.last?.endTime ?? 0
        var lines = ["\(filename) — \(clock(span)), \(segmentation.segments.count) segment(s)"]

        for (index, segment) in segmentation.segments.enumerated() {
            let reason = index == 0
                ? "opening"
                : "novelty \(rounded(segment.confidence))"
            let anchor = countingAnchor(near: segment.startTime, in: segmentation.countingRuns)
            lines.append(
                "  \(index + 1). \(clock(segment.startTime))–\(clock(segment.endTime))"
                    + "  (\(clock(segment.duration)))  ·  \(reason)\(anchor)"
            )
        }

        if segmentation.countingRuns.isEmpty == false {
            let runs = segmentation.countingRuns.map { run in
                "\(run.direction == .descending ? "↓" : "↑") \(clock(run.startTime))×\(run.length)"
            }
            lines.append("  counting: " + runs.joined(separator: "  "))
        }

        return lines.joined(separator: "\n")
    }

    /// Names the count that justified a boundary, so a surprising split can be
    /// traced to its evidence without re-running anything.
    private static func countingAnchor(
        near time: TimeInterval,
        in runs: [CountingRun]
    ) -> String {
        guard let run = runs.first(where: { abs($0.startTime - time) <= StructuralFrames.defaultFrameDuration })
        else { return "" }
        return run.direction == .descending ? "  ⟵ count down" : "  ⟵ count up"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        return "\(minutes):\(remainder < 10 ? "0" : "")\(remainder)"
    }

    private static func rounded(_ value: Double) -> String {
        (value * 100).rounded() / 100 == 0
            ? "0"
            : ((value * 100).rounded() / 100).formatted(.number.precision(.fractionLength(2)))
    }
}
