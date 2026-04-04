//
//  ProsodyAnalyzer+PauseDetection.swift
//  Ilumionate
//
//  Pause detection and classification logic for the ProsodyAnalyzer.
//  Split from the main file for SwiftLint file_length compliance.
//

import Foundation

extension ProsodyAnalyzer {

    // MARK: - Pause Detection

    /// Context needed for pause detection, bundled to reduce parameter count.
    struct PauseDetectionContext: Sendable {
        let segments: [AudioTranscriptionSegment]
        let volumeCurve: [Double]
        let windowDuration: TimeInterval
        let totalDuration: TimeInterval
        let config: Config
    }

    /// Detects pauses by finding gaps between transcript segments and
    /// cross-referencing with audio volume to classify pause type.
    nonisolated func detectPauses(context: PauseDetectionContext) -> [DetectedPause] {
        var pauses: [DetectedPause] = []

        let sorted = context.segments.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return pauses }

        // Check gap before first segment
        if sorted[0].timestamp > context.config.minPauseDuration {
            let category = classifyPause(
                startTime: 0,
                duration: sorted[0].timestamp,
                context: context
            )
            pauses.append(DetectedPause(
                startTime: 0,
                duration: sorted[0].timestamp,
                precedingText: nil,
                followingText: extractContext(from: sorted, at: 0),
                category: category
            ))
        }

        // Check gaps between consecutive segments
        for segmentIndex in 1..<sorted.count {
            let prevEnd = sorted[segmentIndex - 1].timestamp + sorted[segmentIndex - 1].duration
            let gap = sorted[segmentIndex].timestamp - prevEnd

            // Skip negative/zero gaps from overlapping WhisperKit segments
            guard gap > 0, gap >= context.config.minPauseDuration else { continue }

            let category = classifyPause(startTime: prevEnd, duration: gap, context: context)

            pauses.append(DetectedPause(
                startTime: prevEnd,
                duration: gap,
                precedingText: extractTrailingContext(from: sorted, at: segmentIndex - 1),
                followingText: extractContext(from: sorted, at: segmentIndex),
                category: category
            ))
        }

        // Check gap after last segment
        if let last = sorted.last {
            let lastEnd = last.timestamp + last.duration
            let trailingGap = context.totalDuration - lastEnd
            if trailingGap > context.config.minPauseDuration {
                let category = classifyPause(startTime: lastEnd, duration: trailingGap, context: context)
                pauses.append(DetectedPause(
                    startTime: lastEnd,
                    duration: trailingGap,
                    precedingText: extractTrailingContext(from: sorted, at: sorted.count - 1),
                    followingText: nil,
                    category: category
                ))
            }
        }

        return pauses
    }

    /// Classify a pause based on its duration and the audio volume during the gap.
    nonisolated func classifyPause(
        startTime: TimeInterval,
        duration: TimeInterval,
        context: PauseDetectionContext
    ) -> PauseCategory {
        let curveCount = context.volumeCurve.count
        guard curveCount > 0 else {
            return duration >= context.config.extendedPauseMin ? .silence : .natural
        }
        let startWindow = min(Int(startTime / context.windowDuration), curveCount - 1)
        let endWindow = min(Int((startTime + duration) / context.windowDuration), curveCount - 1)
        let pauseWindows = context.volumeCurve[
            max(0, startWindow)...max(0, endWindow)
        ]

        let avgVolume = pauseWindows.reduce(0, +) / Double(pauseWindows.count)
        let isSilent = avgVolume < 0.05

        if duration >= context.config.extendedPauseMin {
            return isSilent ? .silence : .musicOnly
        }
        if duration >= context.config.deliberatePauseMin {
            return .deliberate
        }
        return .natural
    }

    // MARK: - Context Extraction

    /// Extracts the first few words of a segment for pause context.
    nonisolated func extractContext(
        from segments: [AudioTranscriptionSegment],
        at index: Int
    ) -> String? {
        guard index < segments.count else { return nil }
        let words = segments[index].text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.prefix(5).joined(separator: " ")
    }

    /// Extracts the last few words of a segment for pause context.
    nonisolated func extractTrailingContext(
        from segments: [AudioTranscriptionSegment],
        at index: Int
    ) -> String? {
        guard index < segments.count else { return nil }
        let words = segments[index].text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.suffix(5).joined(separator: " ")
    }

    // MARK: - Empty Profile

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
}
