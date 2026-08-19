//
//  ProsodicProfile.swift
//  Ilumionate
//
//  Audio-level prosodic features and the pause map derived from them.
//
//  Extracted from AudioFile.swift so the labelling and analyzer tools can use
//  prosody without taking the whole library model with it: AudioFile.swift also
//  defines AudioFile, AnalysisResult and the storage types, and pulling those
//  into a secondary target cascades into most of the app.
//

import Foundation

/// How a pause in the audio should be categorized for light response decisions.
nonisolated enum PauseCategory: String, Codable, Sendable {
    /// Normal speech breathing pause (1–3 s) — maintain current light state.
    case natural
    /// Intentional therapeutic pause (3–8 s) — gentle frequency dip.
    case deliberate
    /// Extended silence with music/tones only (>5 s) — switch to energy-following mode.
    case musicOnly
    /// Pure silence (>3 s, no audio at all) — maintain and slightly deepen.
    case silence
}

/// A detected pause in the audio timeline with surrounding context.
nonisolated struct DetectedPause: Codable, Sendable, Identifiable {
    let id: UUID
    let startTime: TimeInterval
    let duration: TimeInterval
    let precedingText: String?
    let followingText: String?
    let category: PauseCategory

    init(id: UUID = UUID(), startTime: TimeInterval, duration: TimeInterval,
         precedingText: String? = nil, followingText: String? = nil,
         category: PauseCategory = .natural) {
        self.id = id
        self.startTime = startTime
        self.duration = duration
        self.precedingText = precedingText
        self.followingText = followingText
        self.category = category
    }
}

/// Audio-level prosodic features extracted from the raw audio signal and
/// WhisperKit transcript timing. All curves are sampled at `windowDuration`
/// intervals aligned to the start of the audio.
nonisolated struct ProsodicProfile: Codable, Sendable {
    /// Duration of each analysis window in seconds (typically 3.0).
    let windowDuration: TimeInterval

    /// Words per minute in each window (0 when no speech detected).
    let speechRateCurve: [Double]

    /// Normalised RMS energy per window (0.0–1.0).
    let volumeCurve: [Double]

    /// Estimated fundamental frequency (F0) in Hz per window.
    /// 0 means no voiced speech was detected in that window.
    let pitchCurve: [Double]

    /// Fraction of each window containing speech vs silence (0.0–1.0).
    let speechSilenceRatio: [Double]

    /// All detected pauses with context and categorisation.
    let pauses: [DetectedPause]

    /// Total duration of the analysed audio.
    let totalDuration: TimeInterval

    // MARK: - Convenience

    /// Average speech rate across windows that contain speech.
    var averageSpeechRate: Double {
        let speaking = speechRateCurve.filter { $0 > 0 }
        guard !speaking.isEmpty else { return 0 }
        return speaking.reduce(0, +) / Double(speaking.count)
    }

    /// Standard deviation of speech rate across spoken windows.
    var speechRateVariance: Double {
        let speaking = speechRateCurve.filter { $0 > 0 }
        guard speaking.count > 1 else { return 0 }
        let mean = speaking.reduce(0, +) / Double(speaking.count)
        let sumSquaredDiff = speaking.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (sumSquaredDiff / Double(speaking.count)).squareRoot()
    }

    /// Average pitch across windows that contain voiced speech.
    var averagePitch: Double {
        let voiced = pitchCurve.filter { $0 > 0 }
        guard !voiced.isEmpty else { return 0 }
        return voiced.reduce(0, +) / Double(voiced.count)
    }

    /// Speech rate at a specific time, clamped to nearest window.
    func speechRate(at time: TimeInterval) -> Double {
        let idx = Int(time / windowDuration)
        guard idx >= 0, idx < speechRateCurve.count else { return averageSpeechRate }
        return speechRateCurve[idx]
    }

    /// Volume at a specific time, clamped to nearest window.
    func volume(at time: TimeInterval) -> Double {
        let idx = Int(time / windowDuration)
        guard idx >= 0, idx < volumeCurve.count else { return 0.5 }
        return volumeCurve[idx]
    }

    /// Pitch at a specific time, clamped to nearest window.
    func pitch(at time: TimeInterval) -> Double {
        let idx = Int(time / windowDuration)
        guard idx >= 0, idx < pitchCurve.count else { return 0 }
        return pitchCurve[idx]
    }

    /// Speech-to-silence ratio at a specific time.
    func speechRatio(at time: TimeInterval) -> Double {
        let idx = Int(time / windowDuration)
        guard idx >= 0, idx < speechSilenceRatio.count else { return 0.5 }
        return speechSilenceRatio[idx]
    }
}
