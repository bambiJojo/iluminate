//  TextPacingEngine.swift
//  Ilumionate
//
//  Pure transform: a TranceScript + user settings -> a fully-timed schedule of
//  words to display. No UI, no clock, no script content knowledge beyond text.
//  Same philosophy as the light engine: deterministic, unit-testable.

import Foundation

/// One scheduled word ready to render.
struct PacedWord: Equatable, Sendable {
    let text: String
    let pivotIndex: Int
    let phase: TrancePhase
    let startTime: TimeInterval  // cumulative seconds from reading start
    let duration: TimeInterval   // how long this word is held
}

/// User-tunable pacing inputs.
struct TextPacingSettings: Sendable {
    enum Speed: String, CaseIterable, Sendable, Identifiable {
        case slow, natural, brisk
        var id: String { rawValue }
        var multiplier: Double {
            switch self {
            case .slow:    return 0.75
            case .natural: return 1.0
            case .brisk:   return 1.35
            }
        }
        var displayName: String {
            switch self {
            case .slow: return "Slow"
            case .natural: return "Natural"
            case .brisk: return "Brisk"
            }
        }
    }
    let arc: ScriptArc
    let speed: Speed
}

enum TextPacingEngine {
    /// WPM used when a segment omits an explicit pacing hint, before the
    /// depth-derived slowdown is applied.
    static let defaultBaseWPM: Double = 150
    /// Sentence-ending words are held this many times longer.
    static let sentenceHoldMultiplier: Double = 2.5
    /// Slowest depth factor (applied at max trance depth) for depth-derived pace.
    static let deepeningFloor: Double = 0.55

    static func schedule(for script: TranceScript,
                         settings: TextPacingSettings) -> [PacedWord] {
        var result: [PacedWord] = []
        var cursor: TimeInterval = 0

        for segment in script.segments {
            guard segmentPlays(segment, in: settings.arc) else { continue }

            let wpm = effectiveWPM(for: segment, speed: settings.speed)
            let baseDuration = 60.0 / wpm

            for token in WordTokenizer.tokenize(segment.text) {
                let duration = token.endsSentence
                    ? baseDuration * sentenceHoldMultiplier
                    : baseDuration
                result.append(PacedWord(
                    text: token.text,
                    pivotIndex: ORPCalculator.pivotIndex(for: token.text),
                    phase: segment.phase,
                    startTime: cursor,
                    duration: duration
                ))
                cursor += duration
            }

            if settings.arc == .handoff, segment.triggersHandoff == true {
                break
            }
        }
        return result
    }

    private static func segmentPlays(_ segment: TranceScriptSegment,
                                     in arc: ScriptArc) -> Bool {
        guard let arcs = segment.arcs else { return true }
        return arcs.contains(arc)
    }

    private static func effectiveWPM(for segment: TranceScriptSegment,
                                     speed: TextPacingSettings.Speed) -> Double {
        if let hint = segment.pacing?.baseWPM, hint > 0 {
            return hint * speed.multiplier
        }
        let depth = segment.phase.tranceDepthEstimate            // 0...1
        let depthFactor = 1.0 - depth * (1.0 - deepeningFloor)   // [floor, 1]
        return defaultBaseWPM * depthFactor * speed.multiplier
    }
}
