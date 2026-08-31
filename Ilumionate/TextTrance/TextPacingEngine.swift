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
    let readableStartIndex: Int?
    let readableWordCount: Int

    init(text: String,
         pivotIndex: Int,
         phase: TrancePhase,
         startTime: TimeInterval,
         duration: TimeInterval,
         fade: FadeKind = .none,
         isSubliminal: Bool = false,
         readableStartIndex: Int? = nil,
         readableWordCount: Int = 1) {
        self.text = text
        self.pivotIndex = pivotIndex
        self.phase = phase
        self.startTime = startTime
        self.duration = duration
        self.fade = fade
        self.isSubliminal = isSubliminal
        self.readableStartIndex = readableStartIndex
        self.readableWordCount = readableWordCount
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
    enum SubliminalSpeed: String, Codable, CaseIterable, Sendable, Identifiable {
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
    let speedMultiplier: Double
    let subliminalEnabled: Bool
    let subliminalSpeed: SubliminalSpeed
    let speedTraining: ReaderSpeedTrainingSettings

    init(arc: ScriptArc,
         speedMultiplier: Double,
         subliminalEnabled: Bool = true,
         subliminalSpeed: SubliminalSpeed = .medium,
         speedTraining: ReaderSpeedTrainingSettings = .standard) {
        self.arc = arc
        self.speedMultiplier = speedMultiplier
        self.subliminalEnabled = subliminalEnabled
        self.subliminalSpeed = subliminalSpeed
        self.speedTraining = speedTraining
    }

    /// Convenience for the legacy three presets (setup anchors, tests).
    init(arc: ScriptArc,
         speed: Speed,
         subliminalEnabled: Bool = true,
         subliminalSpeed: SubliminalSpeed = .medium,
         speedTraining: ReaderSpeedTrainingSettings = .standard) {
        self.init(arc: arc, speedMultiplier: speed.multiplier,
                  subliminalEnabled: subliminalEnabled, subliminalSpeed: subliminalSpeed,
                  speedTraining: speedTraining)
    }
}

enum TextPacingEngine {
    /// WPM used when a segment omits an explicit pacing hint, before the
    /// depth-derived slowdown is applied.
    nonisolated static let defaultBaseWPM: Double = 150
    /// Slowest depth factor (applied at max trance depth) for depth-derived pace.
    static let deepeningFloor: Double = 0.55

    // Pause hold multipliers on the segment's base word duration.
    static let briefHoldMultiplier:  Double = 1.6
    static let mediumHoldMultiplier: Double = 2.2
    static let breathHoldMultiplier: Double = 3.0
    static let driftHoldMultiplier:  Double = 4.5

    /// Live speed slider bounds (multiplier on nominal WPM).
    static let minSpeedMultiplier: Double = 0.5
    static let maxSpeedMultiplier: Double = 4.0

    /// Representative WPM for the slider readout. Per-segment WPM varies; this
    /// is the nominal default-base rate scaled by the multiplier.
    static func nominalWPM(forMultiplier multiplier: Double) -> Int {
        Int((defaultBaseWPM * multiplier).rounded())
    }

    static func schedule(for script: TranceScript,
                         settings: TextPacingSettings) -> [PacedWord] {
        // Pass 1: flatten to pending words (text, pause, authored flag, base WPM).
        var pending: [Pending] = []
        for segment in script.segments {
            guard segmentPlays(segment, in: settings.arc) else { continue }
            let baseWPM = effectiveBaseWPM(for: segment)
            for token in WordTokenizer.tokenize(segment.text) {
                pending.append(Pending(text: token.text,
                                       pause: token.pause,
                                       authoredSubliminal: token.isSubliminal,
                                       phase: segment.phase,
                                       baseWPM: baseWPM))
            }
            if settings.arc == .handoff, segment.triggersHandoff == true { break }
        }

        let hasAuthored = pending.contains { $0.authoredSubliminal }
        let readableWordCount = pending.filter {
            !resolveSubliminal($0, hasAuthored: hasAuthored, settings: settings)
        }.count

        // Pass 2: resolve subliminal, apply speed training, group readable chunks.
        var result: [PacedWord] = []
        var cursor: TimeInterval = 0
        var index = 0
        var readableIndex = 0
        while index < pending.count {
            let item = pending[index]
            let subliminal = resolveSubliminal(item, hasAuthored: hasAuthored, settings: settings)

            if subliminal {
                result.append(PacedWord(
                    text: item.text,
                    pivotIndex: ORPCalculator.pivotIndex(for: item.text),
                    phase: item.phase,
                    startTime: cursor,
                    duration: settings.subliminalSpeed.flashDuration,
                    fade: .none,
                    isSubliminal: true,
                    readableStartIndex: nil,
                    readableWordCount: 0))
                cursor += settings.subliminalSpeed.flashDuration
                index += 1
                continue
            }

            let chunk = readableChunk(
                from: index,
                pending: pending,
                hasAuthored: hasAuthored,
                settings: settings
            )
            var duration: TimeInterval = 0
            var strongestPause: PauseKind = .none
            let chunkReadableStartIndex = readableIndex

            for word in chunk {
                let speedMultiplier = settings.speedTraining == .standard
                    ? settings.speedMultiplier
                    : settings.speedTraining.speedMultiplier(
                        readableWordIndex: readableIndex,
                        readableWordCount: readableWordCount
                    )
                let durationWPM = word.baseWPM * max(speedMultiplier, 0.0001)
                let baseDuration = 60.0 / durationWPM
                duration += baseDuration * settings.speedTraining.punctuationPause.multiplier(for: word.pause)
                strongestPause = WordTokenizer.strongest(strongestPause, word.pause)
                readableIndex += 1
            }

            let text = chunk.map(\.text).joined(separator: " ")
            let pivot = chunkPivotIndex(for: chunk)
            result.append(PacedWord(
                text: text,
                pivotIndex: pivot,
                phase: chunk[0].phase,
                startTime: cursor,
                duration: duration,
                fade: fadeKind(strongestPause),
                isSubliminal: false,
                readableStartIndex: chunkReadableStartIndex,
                readableWordCount: chunk.count))
            cursor += duration
            index += chunk.count
        }
        return result
    }

    private struct Pending {
        let text: String
        let pause: PauseKind
        let authoredSubliminal: Bool
        let phase: TrancePhase
        let baseWPM: Double
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

    private static func effectiveBaseWPM(for segment: TranceScriptSegment) -> Double {
        if let hint = segment.pacing?.baseWPM, hint > 0 {
            return hint
        }
        let depth = segment.phase.tranceDepthEstimate            // 0...1
        let depthFactor = 1.0 - depth * (1.0 - deepeningFloor)   // [floor, 1]
        return defaultBaseWPM * depthFactor
    }

    static func holdMultiplier(_ pause: PauseKind) -> Double {
        baseHoldMultiplier(pause)
    }

    static func baseHoldMultiplier(_ pause: PauseKind) -> Double {
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

    private static func readableChunk(from startIndex: Int,
                                      pending: [Pending],
                                      hasAuthored: Bool,
                                      settings: TextPacingSettings) -> [Pending] {
        var chunk: [Pending] = []
        var index = startIndex
        let maxCount = settings.speedTraining.clampedChunkSize

        while index < pending.count, chunk.count < maxCount {
            let item = pending[index]
            if resolveSubliminal(item, hasAuthored: hasAuthored, settings: settings) {
                break
            }
            chunk.append(item)
            index += 1

            if item.pause != .none { break }
        }

        return chunk.isEmpty ? [pending[startIndex]] : chunk
    }

    private static func chunkPivotIndex(for chunk: [Pending]) -> Int {
        guard let first = chunk.first else { return 0 }
        return ORPCalculator.pivotIndex(for: first.text)
    }
}
