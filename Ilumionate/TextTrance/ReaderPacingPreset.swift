import Foundation

enum ReaderPacingPreset: String, CaseIterable, Identifiable, Sendable {
    case gentle, balanced, focused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .balanced: "Balanced"
        case .focused: "Focused"
        }
    }

    var detail: String {
        switch self {
        case .gentle: "120 wpm · deeper pauses"
        case .balanced: "180 wpm · natural pauses"
        case .focused: "260 wpm · short warm-up"
        }
    }

    var settings: ReaderSpeedTrainingSettings {
        switch self {
        case .gentle:
            ReaderSpeedTrainingSettings(
                mode: .steady,
                targetWPM: 120,
                warmUpWPM: 100,
                rampStartWPM: 100,
                chunkSize: 1,
                punctuationPause: .deep
            )
        case .balanced:
            ReaderSpeedTrainingSettings(
                mode: .steady,
                targetWPM: 180,
                warmUpWPM: 120,
                rampStartWPM: 110,
                chunkSize: 1,
                punctuationPause: .normal
            )
        case .focused:
            ReaderSpeedTrainingSettings(
                mode: .warmUp,
                targetWPM: 260,
                warmUpWPM: 160,
                rampStartWPM: 140,
                chunkSize: 1,
                punctuationPause: .light
            )
        }
    }

    static func closest(to settings: ReaderSpeedTrainingSettings) -> ReaderPacingPreset {
        allCases.min {
            abs($0.settings.targetWPM - settings.targetWPM)
                < abs($1.settings.targetWPM - settings.targetWPM)
        } ?? .balanced
    }
}
