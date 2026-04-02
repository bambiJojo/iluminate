//
//  ProsodyAnalyzer+PauseDetection.swift
//  Ilumionate
//
//  Empty-profile fallback and pause-detection logic for ProsodyAnalyzer.
//  Split out to keep each file under 400 lines (SwiftLint file_length).
//

import Foundation

extension ProsodyAnalyzer {

    // MARK: - Empty Profile Fallback

    /// Returns a zero-populated `ProsodicProfile` used when reading audio fails.
    nonisolated func emptyProfile(
        windowDuration: TimeInterval,
        totalDuration: TimeInterval
    ) -> ProsodicProfile {
        ProsodicProfile(
            windowDuration: windowDuration,
            speechRateCurve: [],
            volumeCurve: [],
            pitchCurve: [],
            speechSilenceRatio: [],
            pauses: [],
            totalDuration: totalDuration
        )
    }

    // MARK: - Pause Detection Context

    /// Parameters for gap-based pause detection bundled to reduce parameter count.
    struct PauseDetectionContext: Sendable {
        let segments: [AudioTranscriptionSegment]
        let volumeCurve: [Double]
        let windowDuration: TimeInterval
        let totalDuration: TimeInterval
        let config: Config
    }

    // MARK: - Pause Detection

    /// Detects and classifies pauses from transcript gaps and RMS silence.
    ///
    /// Gaps are found by comparing consecutive segment boundaries.
    /// Volume at the gap is sampled from the normalised curve (`rms / 0.15`),
    /// so "silence" is treated as < ~5% of max normalised volume.
    nonisolated func detectPauses(
        context: PauseDetectionContext
    ) -> [DetectedPause] {
        var pauses: [DetectedPause] = []
        let segs = context.segments
        let cfg  = context.config
        // Normalised silence threshold (~0.008 raw RMS / 0.15 peak ≈ 0.053)
        let silenceVolume = Double(cfg.silenceThreshold / 0.15)

        // Leading silence before first segment
        if let first = segs.first, first.timestamp >= cfg.minPauseDuration {
            let cat: PauseCategory = first.timestamp >= cfg.extendedPauseMin ? .silence : .natural
            pauses.append(DetectedPause(
                startTime: 0,
                duration: first.timestamp,
                followingText: String(first.text.prefix(50)),
                category: cat
            ))
        }

        // Gaps between consecutive segments
        for idx in 0..<segs.count - 1 {
            let cur  = segs[idx]
            let next = segs[idx + 1]
            let gapStart    = cur.timestamp + cur.duration
            let gapDuration = next.timestamp - gapStart
            guard gapDuration >= cfg.minPauseDuration else { continue }

            let winIdx   = Int(gapStart / context.windowDuration)
            let volAtGap = winIdx < context.volumeCurve.count
                             ? context.volumeCurve[winIdx] : 0.0
            let isSilent = volAtGap < silenceVolume

            let category: PauseCategory
            switch gapDuration {
            case cfg.extendedPauseMin...:
                category = isSilent ? .silence : .musicOnly
            case cfg.deliberatePauseMin...:
                category = .deliberate
            default:
                category = .natural
            }

            pauses.append(DetectedPause(
                startTime: gapStart,
                duration: gapDuration,
                precedingText: String(cur.text.suffix(50)),
                followingText: String(next.text.prefix(50)),
                category: category
            ))
        }

        return pauses.sorted { $0.startTime < $1.startTime }
    }
}
