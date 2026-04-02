//
//  SessionGenerator+ProsodicModulation.swift
//  Ilumionate
//
//  Prosody-driven modulation of generated light sessions.
//
//  Two entry points:
//    • applyProsodicModulation  — adjusts frequency/intensity of existing moments
//                                 based on speech rate, pitch, and pauses.
//    • applyAdaptiveBreathOscillation — replaces the fixed-rate breath oscillation
//                                 when a ProsodicProfile is available, syncing the
//                                 oscillation period to the speaker's actual pause rhythm.
//

import Foundation

extension SessionGenerator {

    // MARK: - Prosodic Modulation

    /// Adjusts frequency and intensity of moments in-place based on prosodic features.
    ///
    /// Rules applied:
    /// - Fast speech (>140 WPM) → slight frequency lift (+0.5–1.0 Hz) to match cognitive load.
    /// - Slow speech (<80 WPM)  → slight frequency drop (−0.5–1.0 Hz) for deeper receptivity.
    /// - Deliberate or extended pauses → insert a dedicated deep-theta moment at the pause
    ///   to take advantage of the heightened receptivity window.
    /// - High-volume windows → keep/lift intensity slightly; low-volume → reduce.
    ///
    /// All changes are clamped to `config.minFrequency…config.maxFrequency` and 0.15…0.85
    /// for intensity.
    func applyProsodicModulation(
        moments: inout [LightMoment],
        analysis: AnalysisResult,
        config: GenerationConfig
    ) {
        guard let prosody = analysis.prosodicProfile else { return }

        // Modulate existing moments based on speech rate and volume at their timestamps.
        for idx in 0..<moments.count {
            let time = moments[idx].time
            let rate = prosody.speechRate(at: time)
            let vol  = prosody.volume(at: time)

            // Frequency nudge from speech rate.
            let rateNudge: Double
            if rate > 140 {
                rateNudge = +min(1.0, (rate - 140) / 100.0)
            } else if rate > 0, rate < 80 {
                rateNudge = -min(1.0, (80 - rate) / 80.0)
            } else {
                rateNudge = 0
            }

            // Intensity nudge from volume (centred at 0.5 normalised).
            let volNudge = (vol - 0.5) * 0.05  // ±2.5% at extremes

            let newFreq = clamp(
                moments[idx].frequency + rateNudge,
                lower: config.minFrequency,
                upper: config.maxFrequency
            )
            let newAmp = clamp(
                moments[idx].intensity + volNudge,
                lower: 0.15,
                upper: 0.85
            )

            let orig = moments[idx]
            if newFreq != orig.frequency || newAmp != orig.intensity {
                moments[idx] = LightMoment(
                    time: orig.time,
                    frequency: newFreq,
                    intensity: newAmp,
                    waveform: orig.waveform,
                    bilateral: orig.bilateral,
                    bilateral_transition_duration: orig.bilateral_transition_duration,
                    color_temperature: orig.color_temperature
                )
            }
        }

        // Insert pause-response moments for deliberate/extended pauses.
        let pauses = prosody.pauses.filter {
            $0.category == .deliberate || $0.category == .silence
        }

        for pause in pauses {
            // Only insert if no existing moment is within ±2 s of the pause start.
            let nearbyExists = moments.contains { abs($0.time - pause.startTime) < 2.0 }
            guard !nearbyExists else { continue }
            guard pause.startTime >= 5.0 else { continue }

            // Deep-theta dip during pause, calibrated to pause depth.
            let deepFreq = pause.category == .silence ? 5.5 : 6.5
            let deepAmp  = pause.category == .silence ? 0.28 : 0.32
            let deepTemp = pause.category == .silence ? 2400.0 : 2600.0

            moments.append(LightMoment(
                time: pause.startTime,
                frequency: clamp(deepFreq, lower: config.minFrequency, upper: config.maxFrequency),
                intensity: deepAmp * config.intensityMultiplier,
                waveform: .noiseModulatedSine,
                color_temperature: deepTemp
            ))
        }
    }

    // MARK: - Adaptive Breath Oscillation

    /// Applies breath-rate frequency modulation whose period is derived from the
    /// actual pause rhythm in the `ProsodicProfile`.
    ///
    /// When no pause data is present (pure music / no-speech), it falls back to the
    /// duration-based `breathRate(for:)` heuristic.
    ///
    /// Only moments below 14 Hz are modulated — entrainment range only.
    func applyAdaptiveBreathOscillation(
        _ moments: inout [LightMoment],
        prosody: ProsodicProfile
    ) {
        // Derive effective breath rate from inter-pause rhythm.
        // Average spacing between natural pauses approximates the breath cycle.
        let naturalPauses = prosody.pauses.filter { $0.category == .natural }
        let breathRate: Double
        if naturalPauses.count >= 2 {
            var spacings: [Double] = []
            for idx in 1..<naturalPauses.count {
                spacings.append(naturalPauses[idx].startTime - naturalPauses[idx - 1].startTime)
            }
            let avgSpacing = spacings.reduce(0, +) / Double(spacings.count)
            // Convert spacing (seconds) to Hz, clamped to physiological range.
            let derivedRate = 1.0 / max(avgSpacing, 1.0)
            breathRate = max(0.05, min(0.20, derivedRate))
        } else {
            // Fall back to duration-based heuristic.
            breathRate = SessionGenerator.breathRate(for: prosody.totalDuration)
        }

        let depth = 0.20  // Hz amplitude of modulation

        for idx in 0..<moments.count {
            guard moments[idx].frequency < 14.0 else { continue }
            let modulation = depth * sin(2.0 * .pi * breathRate * moments[idx].time)
            let newFreq    = max(0.5, moments[idx].frequency + modulation)
            let orig       = moments[idx]
            moments[idx] = LightMoment(
                time: orig.time,
                frequency: newFreq,
                intensity: orig.intensity,
                waveform: orig.waveform,
                bilateral: orig.bilateral,
                bilateral_transition_duration: orig.bilateral_transition_duration,
                color_temperature: orig.color_temperature
            )
        }
    }
}
