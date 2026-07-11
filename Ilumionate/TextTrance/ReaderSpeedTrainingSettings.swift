//  ReaderSpeedTrainingSettings.swift
//  Ilumionate
//
//  Speed-training controls used by setup, resume, and the pacing engine.

import Foundation

struct ReaderSpeedTrainingSettings: Codable, Equatable, Sendable {
    var mode: ReaderSpeedMode
    var targetWPM: Int
    var warmUpWPM: Int
    var rampStartWPM: Int
    var chunkSize: Int
    var punctuationPause: ReaderPunctuationPause

    init(mode: ReaderSpeedMode = .steady,
         targetWPM: Int = TextPacingEngine.defaultBaseWPMInt,
         warmUpWPM: Int = 110,
         rampStartWPM: Int = 100,
         chunkSize: Int = 1,
         punctuationPause: ReaderPunctuationPause = .normal) {
        self.mode = mode
        self.targetWPM = targetWPM
        self.warmUpWPM = warmUpWPM
        self.rampStartWPM = rampStartWPM
        self.chunkSize = chunkSize
        self.punctuationPause = punctuationPause
    }

    static let standard = ReaderSpeedTrainingSettings()
}

enum ReaderSpeedMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case steady
    case warmUp
    case ramp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .steady: return "Steady"
        case .warmUp: return "Warm-up"
        case .ramp: return "Ramp"
        }
    }
}

enum ReaderPunctuationPause: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case light
    case normal
    case deep

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .normal: return "Normal"
        case .deep: return "Deep"
        }
    }
}

extension ReaderSpeedTrainingSettings {
    static let targetWPMRange: ClosedRange<Int> = 75...600
    static let setupTargetWPMRange: ClosedRange<Double> = 75...600
    static let chunkSizeRange: ClosedRange<Int> = 1...3

    var clampedTargetWPM: Int {
        Self.clampWPM(targetWPM)
    }

    var clampedWarmUpWPM: Int {
        Self.clampWPM(min(warmUpWPM, clampedTargetWPM))
    }

    var clampedRampStartWPM: Int {
        Self.clampWPM(min(rampStartWPM, clampedTargetWPM))
    }

    var clampedChunkSize: Int {
        min(max(chunkSize, Self.chunkSizeRange.lowerBound), Self.chunkSizeRange.upperBound)
    }

    var targetSpeedMultiplier: Double {
        Double(clampedTargetWPM) / TextPacingEngine.defaultBaseWPM
    }

    func speedMultiplier(readableWordIndex: Int, readableWordCount: Int) -> Double {
        let target = Double(clampedTargetWPM)
        let wpm: Double

        switch mode {
        case .steady:
            wpm = target
        case .warmUp:
            let warmUp = Double(clampedWarmUpWPM)
            let holdWords = min(90, max(24, readableWordCount / 8))
            let blendWords = min(90, max(24, readableWordCount / 8))
            if readableWordIndex < holdWords {
                wpm = warmUp
            } else if readableWordIndex < holdWords + blendWords {
                let progress = Double(readableWordIndex - holdWords) / Double(max(blendWords, 1))
                wpm = warmUp + (target - warmUp) * min(max(progress, 0), 1)
            } else {
                wpm = target
            }
        case .ramp:
            let start = Double(clampedRampStartWPM)
            let rampWords = min(max(readableWordCount / 2, 90), 420)
            let progress = Double(readableWordIndex) / Double(max(rampWords, 1))
            wpm = start + (target - start) * min(max(progress, 0), 1)
        }

        return wpm / TextPacingEngine.defaultBaseWPM
    }

    private static func clampWPM(_ value: Int) -> Int {
        min(max(value, targetWPMRange.lowerBound), targetWPMRange.upperBound)
    }
}

extension ReaderPunctuationPause {
    func multiplier(for pause: PauseKind) -> Double {
        guard pause != .none else { return 1 }

        let base = TextPacingEngine.baseHoldMultiplier(pause)
        switch self {
        case .off:
            return 1
        case .light:
            return 1 + (base - 1) * 0.5
        case .normal:
            return base
        case .deep:
            return 1 + (base - 1) * 1.45
        }
    }
}

extension TextPacingEngine {
    static let defaultBaseWPMInt = Int(defaultBaseWPM)
}
