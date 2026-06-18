//  TextPacingEngine.swift
//  Ilumionate
//
//  Pure transform: a TranceScript + user settings -> a fully-timed schedule of
//  words to display. No UI, no clock, no script content knowledge beyond text.
//  Same philosophy as the light engine: deterministic, unit-testable.

import Foundation

/// How a word leaves the screen — drives the breath/drift opacity fade.
enum FadeKind: Equatable, Sendable {
    case none
    case breath   // sentence-end: visible hold then fade
    case drift    // ellipsis: longest, slowest fade
}

/// One scheduled word ready to render.
struct PacedWord: Equatable, Sendable {
    let text: String
    let pivotIndex: Int
    let phase: TrancePhase
    let startTime: TimeInterval  // cumulative seconds from reading start
    let duration: TimeInterval   // how long this word is held
    let fade: FadeKind
    let isSubliminal: Bool

    init(text: String,
         pivotIndex: Int,
         phase: TrancePhase,
         startTime: TimeInterval,
         duration: TimeInterval,
         fade: FadeKind = .none,
         isSubliminal: Bool = false) {
        self.text = text
        self.pivotIndex = pivotIndex
        self.phase = phase
        self.startTime = startTime
        self.duration = duration
        self.fade = fade
        self.isSubliminal = isSubliminal
    }
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

    /// How fast subliminal words flash past. Lower = faster = less consciously legible.
    enum SubliminalSpeed: String, CaseIterable, Sendable, Identifiable {
        case gentle, medium, deep
        var id: String { rawValue }
        var flashDuration: TimeInterval {
            switch self {
            case .gentle: return 0.12
            case .medium: return 0.09
            case .deep:   return 0.065
            }
        }
        var displayName: String {
            switch self {
            case .gentle: return "Gentle"
            case .medium: return "Medium"
            case .deep:   return "Deep"
            }
        }
    }

    let arc: ScriptArc
    let speed: Speed
    let subliminalEnabled: Bool
    let subliminalSpeed: SubliminalSpeed

    init(arc: ScriptArc,
         speed: Speed,
         subliminalEnabled: Bool = true,
         subliminalSpeed: SubliminalSpeed = .medium) {
        self.arc = arc
        self.speed = speed
        self.subliminalEnabled = subliminalEnabled
        self.subliminalSpeed = subliminalSpeed
    }
}

enum TextPacingEngine {
    /// WPM used when a segment omits an explicit pacing hint, before the
    /// depth-derived slowdown is applied.
    static let defaultBaseWPM: Double = 150
    /// Slowest depth factor (applied at max trance depth) for depth-derived pace.
    static let deepeningFloor: Double = 0.55

    // Pause hold multipliers on the segment's base word duration.
    static let briefHoldMultiplier:  Double = 1.6
    static let mediumHoldMultiplier: Double = 2.2
    static let breathHoldMultiplier: Double = 3.0
    static let driftHoldMultiplier:  Double = 4.5

    static func schedule(for script: TranceScript,
                         settings: TextPacingSettings) -> [PacedWord] {
        // Pass 1: flatten to pending words (text, pause, authored flag, base duration).
        var pending: [Pending] = []
        for segment in script.segments {
            guard segmentPlays(segment, in: settings.arc) else { continue }
            let baseDuration = 60.0 / effectiveWPM(for: segment, speed: settings.speed)
            for token in WordTokenizer.tokenize(segment.text) {
                pending.append(Pending(text: token.text,
                                       pause: token.pause,
                                       authoredSubliminal: token.isSubliminal,
                                       phase: segment.phase,
                                       baseDuration: baseDuration))
            }
            if settings.arc == .handoff, segment.triggersHandoff == true { break }
        }

        let hasAuthored = pending.contains { $0.authoredSubliminal }

        // Pass 2: resolve subliminal + compute the timed schedule.
        var result: [PacedWord] = []
        var cursor: TimeInterval = 0
        for item in pending {
            let subliminal = resolveSubliminal(item, hasAuthored: hasAuthored, settings: settings)
            let duration = subliminal
                ? settings.subliminalSpeed.flashDuration
                : item.baseDuration * holdMultiplier(item.pause)
            let fade: FadeKind = subliminal ? .none : fadeKind(item.pause)
            result.append(PacedWord(
                text: item.text,
                pivotIndex: ORPCalculator.pivotIndex(for: item.text),
                phase: item.phase,
                startTime: cursor,
                duration: duration,
                fade: fade,
                isSubliminal: subliminal))
            cursor += duration
        }
        return result
    }

    private struct Pending {
        let text: String
        let pause: PauseKind
        let authoredSubliminal: Bool
        let phase: TrancePhase
        let baseDuration: TimeInterval
    }

    private static func resolveSubliminal(_ item: Pending,
                                          hasAuthored: Bool,
                                          settings: TextPacingSettings) -> Bool {
        guard settings.subliminalEnabled else { return false }
        if hasAuthored { return item.authoredSubliminal }
        return SubliminalLexicon.contains(item.text)
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

    static func holdMultiplier(_ pause: PauseKind) -> Double {
        switch pause {
        case .none:   return 1.0
        case .brief:  return briefHoldMultiplier
        case .medium: return mediumHoldMultiplier
        case .breath: return breathHoldMultiplier
        case .drift:  return driftHoldMultiplier
        }
    }

    static func fadeKind(_ pause: PauseKind) -> FadeKind {
        switch pause {
        case .breath: return .breath
        case .drift:  return .drift
        default:      return .none
        }
    }
}
