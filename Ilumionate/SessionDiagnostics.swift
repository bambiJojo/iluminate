//
//  SessionDiagnostics.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation

/// Diagnostic and validation utilities for session playback.
/// These tools help identify issues during development and testing.
@MainActor
struct SessionDiagnostics {

    // MARK: - Session Validation

    /// Validate a session for common issues
    static func validateSession(_ session: LightSession) -> ValidationResult {
        var warnings: [String] = []
        var errors: [String] = []

        // Check duration
        if session.duration_sec <= 0 {
            errors.append("Session duration must be positive")
        }

        if session.duration_sec < 10 {
            warnings.append("Very short session (<10s) may not provide effective entrainment")
        }

        if session.duration_sec > 3600 {
            warnings.append("Very long session (>1 hour) - ensure this is intentional")
        }

        // Check light score
        if session.light_score.isEmpty {
            warnings.append("Empty light score - no control points defined")
        }

        // Check moment timing
        for (index, moment) in session.light_score.enumerated() {
            if moment.time < 0 {
                errors.append("Moment \(index) has negative time: \(moment.time)")
            }

            if moment.time > session.duration_sec {
                warnings.append("Moment \(index) at \(moment.time)s is beyond session duration")
            }

            // Check frequency range
            if moment.frequency < 0.1 {
                warnings.append("Moment \(index) has very low frequency (<0.1 Hz)")
            }

            if moment.frequency > 100 {
                warnings.append("Moment \(index) has very high frequency (>100 Hz)")
            }

            // Optimal entrainment range is typically 1-40 Hz
            if moment.frequency > 40 {
                warnings.append("Moment \(index) frequency \(moment.frequency) Hz is above typical entrainment range (1-40 Hz)")
            }

            // Check intensity range
            if moment.intensity < 0.0 || moment.intensity > 1.0 {
                errors.append("Moment \(index) intensity \(moment.intensity) is out of range [0, 1]")
            }

            if moment.intensity < 0.1 {
                warnings.append("Moment \(index) has very low intensity (<0.1) - may be hard to perceive")
            }

            // Check color temperature if present
            if let temp = moment.color_temperature {
                if temp < 1000 || temp > 10000 {
                    warnings.append("Moment \(index) color temperature \(temp)K is unusual (typical range: 2000-6500K)")
                }
            }

            // Check ramp duration if present
            if let rampDur = moment.ramp_duration {
                if rampDur < 0 {
                    errors.append("Moment \(index) has negative ramp duration")
                }
                if rampDur > session.duration_sec {
                    warnings.append("Moment \(index) ramp duration (\(rampDur)s) exceeds session duration")
                }
            }

            // Check bilateral transition duration if present
            if let bilatDur = moment.bilateral_transition_duration {
                if bilatDur < 0 {
                    errors.append("Moment \(index) has negative bilateral transition duration")
                }
                if bilatDur > 30 {
                    warnings.append("Moment \(index) has very long bilateral transition (>30s)")
                }
            }
        }

        // Check for duplicate times
        let times = session.light_score.map { $0.time }
        let uniqueTimes = Set(times)
        if times.count != uniqueTimes.count {
            warnings.append("Multiple moments at the same time - only one will be used")
        }

        // Check for very rapid frequency changes (potential seizure risk)
        let sortedMoments = session.light_score.sorted { $0.time < $1.time }
        for i in 1..<sortedMoments.count {
            let prev = sortedMoments[i-1]
            let curr = sortedMoments[i]

            let timeDelta = curr.time - prev.time
            let freqDelta = abs(curr.frequency - prev.frequency)

            if timeDelta > 0 && timeDelta < 0.5 && freqDelta > 20 {
                warnings.append("Very rapid frequency change (\(freqDelta) Hz in \(timeDelta)s) between moments \(i-1) and \(i)")
            }
        }

        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    /// Analyze session characteristics for optimization suggestions
    static func analyzeSession(_ session: LightSession) -> SessionAnalysis {
        guard !session.light_score.isEmpty else {
            return SessionAnalysis(
                totalMoments: 0,
                frequencyRange: (0, 0),
                intensityRange: (0, 0),
                averageFrequency: 0,
                averageIntensity: 0,
                hasBilateral: false,
                hasColorTemperature: false,
                hasCustomRamps: false,
                estimatedEntrainmentEffectiveness: .unknown,
                suggestions: ["Session has no control points"]
            )
        }

        let moments = session.light_score

        // Frequency analysis
        let frequencies = moments.map { $0.frequency }
        let minFreq = frequencies.min() ?? 0
        let maxFreq = frequencies.max() ?? 0
        let avgFreq = frequencies.reduce(0, +) / Double(frequencies.count)

        // Intensity analysis
        let intensities = moments.map { $0.intensity }
        let minIntensity = intensities.min() ?? 0
        let maxIntensity = intensities.max() ?? 0
        let avgIntensity = intensities.reduce(0, +) / Double(intensities.count)

        // Feature detection
        let hasBilateral = moments.contains { $0.bilateral == true }
        let hasColorTemp = moments.contains { $0.color_temperature != nil }
        let hasCustomRamps = moments.contains { $0.ramp_duration != nil }

        // Effectiveness estimation
        let effectiveness = estimateEffectiveness(
            avgFrequency: avgFreq,
            avgIntensity: avgIntensity,
            duration: session.duration_sec,
            momentCount: moments.count
        )

        // Generate suggestions
        var suggestions: [String] = []

        if avgIntensity < 0.3 {
            suggestions.append("Consider increasing intensity for better visibility")
        }

        if avgIntensity > 0.9 {
            suggestions.append("High average intensity - may be uncomfortable for extended use")
        }

        if maxFreq - minFreq < 5 {
            suggestions.append("Limited frequency variation - consider wider range for more engaging experience")
        }

        if moments.count < 3 {
            suggestions.append("Few control points - consider adding more for smoother transitions")
        }

        if session.duration_sec < 60 && moments.count > 10 {
            suggestions.append("Many transitions in short duration - may feel rushed")
        }

        if !hasBilateral && session.duration_sec > 300 {
            suggestions.append("Long session without bilateral mode - consider adding for variety")
        }

        if avgFreq > 30 {
            suggestions.append("High average frequency - may be fatiguing for long sessions")
        }

        if avgFreq < 5 {
            suggestions.append("Low average frequency - entrainment may be less effective")
        }

        return SessionAnalysis(
            totalMoments: moments.count,
            frequencyRange: (minFreq, maxFreq),
            intensityRange: (minIntensity, maxIntensity),
            averageFrequency: avgFreq,
            averageIntensity: avgIntensity,
            hasBilateral: hasBilateral,
            hasColorTemperature: hasColorTemp,
            hasCustomRamps: hasCustomRamps,
            estimatedEntrainmentEffectiveness: effectiveness,
            suggestions: suggestions
        )
    }

    private static func estimateEffectiveness(
        avgFrequency: Double,
        avgIntensity: Double,
        duration: Double,
        momentCount: Int
    ) -> EntrainmentEffectiveness {
        var score = 0

        // Optimal frequency range (8-13 Hz for alpha, 1-40 Hz overall)
        if avgFrequency >= 8 && avgFrequency <= 13 {
            score += 2 // Alpha range
        } else if avgFrequency >= 1 && avgFrequency <= 40 {
            score += 1 // General entrainment range
        }

        // Good intensity (0.4-0.8 is ideal)
        if avgIntensity >= 0.4 && avgIntensity <= 0.8 {
            score += 1
        }

        // Duration (5-30 min optimal)
        if duration >= 300 && duration <= 1800 {
            score += 1
        }

        // Enough variation (at least 3 moments)
        if momentCount >= 3 {
            score += 1
        }

        // Classify
        switch score {
        case 5: return .excellent
        case 4: return .good
        case 3: return .moderate
        case 2: return .low
        default: return .minimal
        }
    }

    // MARK: - Engine State Snapshot

    /// Capture current engine state for debugging
    static func captureEngineState(_ engine: LightEngine) -> EngineSnapshot {
        return EngineSnapshot(
            isRunning: engine.isRunning,
            brightness: engine.brightness,
            brightnessLeft: engine.brightnessLeft,
            brightnessRight: engine.brightnessRight,
            currentFrequency: engine.currentFrequency,
            targetFrequency: engine.targetFrequency,
            waveform: engine.waveform,
            bilateralMode: engine.bilateralMode,
            bilateralPhaseOffset: engine.bilateralPhaseOffset,
            minimumBrightness: engine.minimumBrightness,
            maximumBrightness: engine.maximumBrightness,
            userBrightnessMultiplier: engine.userBrightnessMultiplier,
            colorTemperature: engine.colorTemperature,
            hasActiveSession: engine.hasActiveSession
        )
    }

    /// Capture current player state for debugging
    static func capturePlayerState(_ player: LightScorePlayer) -> PlayerSnapshot {
        let currentState = player.currentState()

        return PlayerSnapshot(
            currentTime: player.currentTime,
            isPlaying: player.isPlaying,
            isComplete: player.isComplete,
            progress: player.progress,
            sessionDuration: player.session.duration_sec,
            currentMomentIndex: player.currentMomentIndex(),
            currentState: currentState
        )
    }

    // MARK: - Logging Helpers

    /// Generate detailed debug log of session
    static func logSessionDetails(_ session: LightSession) -> String {
        var log = """

        ========================================
        SESSION: \(session.session_name)
        ========================================
        Duration: \(session.durationFormatted) (\(session.duration_sec)s)
        Moments: \(session.light_score.count)

        """

        for (index, moment) in session.light_score.enumerated() {
            log += """

            Moment \(index):
              Time: \(String(format: "%.1f", moment.time))s
              Frequency: \(String(format: "%.1f", moment.frequency)) Hz
              Intensity: \(String(format: "%.2f", moment.intensity))
              Waveform: \(moment.waveform.displayName)
              Bilateral: \(moment.bilateral ?? false)
            """

            if let ramp = moment.ramp_duration {
                log += "\n  Ramp Duration: \(ramp)s"
            }

            if let temp = moment.color_temperature {
                log += "\n  Color Temp: \(Int(temp))K"
            }

            log += "\n"
        }

        log += "========================================\n"

        return log
    }
}

// MARK: - Result Types

struct ValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]

    var hasIssues: Bool {
        !errors.isEmpty || !warnings.isEmpty
    }

    var summary: String {
        if isValid && warnings.isEmpty {
            return "✅ Session is valid with no issues"
        }

        var parts: [String] = []

        if !errors.isEmpty {
            parts.append("❌ \(errors.count) error(s)")
        } else {
            parts.append("✅ No errors")
        }

        if !warnings.isEmpty {
            parts.append("⚠️ \(warnings.count) warning(s)")
        }

        return parts.joined(separator: ", ")
    }
}

struct SessionAnalysis {
    let totalMoments: Int
    let frequencyRange: (min: Double, max: Double)
    let intensityRange: (min: Double, max: Double)
    let averageFrequency: Double
    let averageIntensity: Double
    let hasBilateral: Bool
    let hasColorTemperature: Bool
    let hasCustomRamps: Bool
    let estimatedEntrainmentEffectiveness: EntrainmentEffectiveness
    let suggestions: [String]
}

enum EntrainmentEffectiveness: String {
    case unknown = "Unknown"
    case minimal = "Minimal"
    case low = "Low"
    case moderate = "Moderate"
    case good = "Good"
    case excellent = "Excellent"

    var emoji: String {
        switch self {
        case .unknown: return "❓"
        case .minimal: return "⭐️"
        case .low: return "⭐️⭐️"
        case .moderate: return "⭐️⭐️⭐️"
        case .good: return "⭐️⭐️⭐️⭐️"
        case .excellent: return "⭐️⭐️⭐️⭐️⭐️"
        }
    }
}

struct EngineSnapshot {
    let isRunning: Bool
    let brightness: Double
    let brightnessLeft: Double
    let brightnessRight: Double
    let currentFrequency: Double
    let targetFrequency: Double
    let waveform: Waveform
    let bilateralMode: Bool
    let bilateralPhaseOffset: Double
    let minimumBrightness: Double
    let maximumBrightness: Double
    let userBrightnessMultiplier: Double
    let colorTemperature: Double?
    let hasActiveSession: Bool

    var description: String {
        """
        Engine State:
          Running: \(isRunning)
          Frequency: \(String(format: "%.2f", currentFrequency)) Hz (target: \(String(format: "%.2f", targetFrequency)))
          Brightness: \(String(format: "%.3f", brightness))
          Bilateral: \(bilateralMode) (L: \(String(format: "%.3f", brightnessLeft)), R: \(String(format: "%.3f", brightnessRight)))
          Waveform: \(waveform.displayName)
          User Multiplier: \(Int(userBrightnessMultiplier * 100))%
          Color Temp: \(colorTemperature.map { "\(Int($0))K" } ?? "none")
          Active Session: \(hasActiveSession)
        """
    }
}

struct PlayerSnapshot {
    let currentTime: Double
    let isPlaying: Bool
    let isComplete: Bool
    let progress: Double
    let sessionDuration: Double
    let currentMomentIndex: Int?
    let currentState: SessionState

    var description: String {
        """
        Player State:
          Time: \(String(format: "%.1f", currentTime))s / \(String(format: "%.1f", sessionDuration))s
          Progress: \(Int(progress * 100))%
          Playing: \(isPlaying)
          Complete: \(isComplete)
          Moment Index: \(currentMomentIndex.map { "\($0)" } ?? "none")
          Frequency: \(String(format: "%.1f", currentState.frequency)) Hz
          Intensity: \(String(format: "%.2f", currentState.intensity))
          Bilateral: \(currentState.bilateral)
        """
    }
}
