//
//  PhaseTimelineNormalizer.swift
//  Ilumionate
//
//  Cleans analyzer phase timing before light-score generation.
//

import Foundation

struct PhaseTimelineNormalizer: Sendable {

    private let minimumSegmentDuration: TimeInterval = 0.75
    private let gapThreshold: TimeInterval = 4.0

    func normalize(
        _ phases: [PhaseSegment],
        duration: TimeInterval,
        contentType: AudioContentType
    ) -> [PhaseSegment] {
        guard duration > 0 else { return [] }

        let sorted = phases
            .compactMap { clamped($0, duration: duration) }
            .sorted {
                if abs($0.startTime - $1.startTime) > 0.001 {
                    return $0.startTime < $1.startTime
                }
                return $0.endTime < $1.endTime
            }

        guard !sorted.isEmpty else { return [] }

        var normalized: [PhaseSegment] = []
        var cursor: TimeInterval = 0

        for segment in sorted {
            let rawStart = max(segment.startTime, cursor)
            let shouldFillGap = rawStart - cursor > gapThreshold
            let start = shouldFillGap ? rawStart : cursor
            let end = min(max(segment.endTime, start), duration)
            guard end - start >= minimumSegmentDuration else { continue }

            if shouldFillGap {
                normalized.append(gapSegment(
                    start: cursor,
                    end: rawStart,
                    previous: normalized.last?.phase,
                    next: segment.phase
                ))
            }

            normalized.append(copy(segment, start: start, end: end))
            cursor = end
        }

        appendTrailingCoverage(
            to: &normalized,
            cursor: cursor,
            duration: duration,
            contentType: contentType
        )

        return normalized
    }

    // MARK: - Segment Construction

    private func appendTrailingCoverage(
        to phases: inout [PhaseSegment],
        cursor: TimeInterval,
        duration: TimeInterval,
        contentType: AudioContentType
    ) {
        let trailingGap = duration - cursor
        guard trailingGap > gapThreshold else {
            if let last = phases.last, duration - last.endTime > 0.001 {
                phases[phases.count - 1] = copy(last, start: last.startTime, end: duration)
            }
            return
        }

        guard contentType != .sleepHypnosis else {
            phases.append(gapSegment(
                start: cursor,
                end: duration,
                previous: phases.last?.phase,
                next: .deepening
            ))
            return
        }

        if phases.last?.phase == .emergence {
            phases.append(gapSegment(
                start: cursor,
                end: duration,
                previous: .emergence,
                next: .emergence
            ))
            return
        }

        let emergenceDuration = min(max(duration * 0.08, 30.0), min(90.0, trailingGap))
        let emergenceStart = max(cursor, duration - emergenceDuration)

        if emergenceStart - cursor > gapThreshold {
            phases.append(gapSegment(
                start: cursor,
                end: emergenceStart,
                previous: phases.last?.phase,
                next: .emergence
            ))
        }

        phases.append(PhaseSegment(
            phase: .emergence,
            startTime: emergenceStart,
            endTime: duration,
            characteristics: "Synthetic emergence coverage added to complete the audio timeline.",
            tranceDepthEstimate: TrancePhase.emergence.tranceDepthEstimate,
            confidenceLevel: .low,
            confidenceRationale: "Added because hypnosis phase analysis ended before the audio file did.",
            transitionTarget: nil
        ))
    }

    private func clamped(_ segment: PhaseSegment, duration: TimeInterval) -> PhaseSegment? {
        let start = clamp(segment.startTime, lower: 0, upper: duration)
        let end = clamp(segment.endTime, lower: 0, upper: duration)
        guard end - start >= minimumSegmentDuration else { return nil }
        return copy(segment, start: start, end: end)
    }

    private func gapSegment(
        start: TimeInterval,
        end: TimeInterval,
        previous: TrancePhase?,
        next: TrancePhase
    ) -> PhaseSegment {
        let phase: TrancePhase
        if start <= gapThreshold, next == .induction {
            phase = .induction
        } else {
            phase = .transitional
        }

        let previousDepth = previous?.tranceDepthEstimate ?? phase.tranceDepthEstimate
        let nextDepth = next.tranceDepthEstimate
        let depth = clamp((previousDepth + nextDepth) / 2, lower: 0, upper: 1)

        return PhaseSegment(
            phase: phase,
            startTime: start,
            endTime: end,
            characteristics: "Timeline gap filled between detected hypnosis phases.",
            tranceDepthEstimate: depth,
            confidenceLevel: .low,
            confidenceRationale: "Added to preserve continuous audio-to-light synchronization.",
            transitionTarget: next
        )
    }

    private func copy(
        _ segment: PhaseSegment,
        start: TimeInterval,
        end: TimeInterval
    ) -> PhaseSegment {
        PhaseSegment(
            id: segment.id,
            phase: segment.phase,
            startTime: start,
            endTime: end,
            characteristics: segment.characteristics,
            tranceDepthEstimate: clamp(segment.tranceDepthEstimate, lower: 0, upper: 1),
            linguisticMarkers: segment.linguisticMarkers,
            confidenceLevel: segment.confidenceLevel,
            confidenceRationale: segment.confidenceRationale,
            transitionTarget: segment.transitionTarget
        )
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
