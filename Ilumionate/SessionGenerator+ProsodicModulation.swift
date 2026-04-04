//
//  SessionGenerator+ProsodicModulation.swift
//  Ilumionate
//
//  Prosodic modulation layer for adaptive light session generation.
//  Adjusts base light parameters based on the hypnotist's actual vocal
//  delivery — speech rate, volume, pitch, and detected techniques.
//

import Foundation

extension SessionGenerator {

    // MARK: - Prosodic Modulation

    /// Modulates a set of base moments using prosodic and technique data.
    ///
    /// For each base moment, the prosodic curve at that timestamp adjusts
    /// frequency and intensity within the phase's range. Then technique-
    /// responsive moments are inserted at detected technique timestamps.
    func applyProsodicModulation(
        moments: inout [LightMoment],
        analysis: AnalysisResult,
        config: GenerationConfig
    ) {
        guard let prosody = analysis.prosodicProfile else { return }

        // 1. Modulate existing moments based on vocal delivery
        modulateMomentsWithProsody(
            &moments, prosody: prosody, config: config
        )

        // 2. Insert technique-responsive moments
        if let techniques = analysis.techniqueDetection {
            insertTechniqueMoments(
                &moments,
                techniques: techniques,
                prosody: prosody,
                config: config
            )
        }
    }

    // MARK: - Per-Moment Vocal Modulation

    /// Adjusts each moment's frequency and intensity based on the
    /// hypnotist's voice characteristics at that timestamp.
    ///
    /// Rules:
    /// - Slower speech → deeper frequency (within ±1.5 Hz of base)
    /// - Quieter voice → lower intensity (matching vocal energy)
    /// - Lower pitch → slight frequency reduction (unconscious rapport)
    private func modulateMomentsWithProsody(
        _ moments: inout [LightMoment],
        prosody: ProsodicProfile,
        config: GenerationConfig
    ) {
        let avgRate = prosody.averageSpeechRate
        let avgVolume = prosody.volumeCurve.isEmpty
            ? 0.5
            : prosody.volumeCurve.reduce(0, +) / Double(prosody.volumeCurve.count)

        for idx in 0..<moments.count {
            let time = moments[idx].time
            guard moments[idx].frequency < 14.0 else { continue }

            let localRate = prosody.speechRate(at: time)
            let localVolume = prosody.volume(at: time)

            // Speech rate modulation: slower → deeper
            // Normalized deviation from average (−1.0 to +1.0)
            let rateDeviation = avgRate > 0
                ? (localRate - avgRate) / max(avgRate, 1.0)
                : 0.0
            // Maps to ±1.5 Hz: slower speech = negative deviation = lower freq
            let freqShift = rateDeviation * 1.5

            // Volume modulation: quieter → lower intensity
            let volDeviation = avgVolume > 0
                ? (localVolume - avgVolume) / max(avgVolume, 0.01)
                : 0.0
            let intensityShift = volDeviation * 0.08

            let original = moments[idx]
            let newFreq = max(
                config.minFrequency,
                min(config.maxFrequency, original.frequency + freqShift)
            )
            let newIntensity = max(0.10, min(1.0, original.intensity + intensityShift))

            moments[idx] = LightMoment(
                time: original.time,
                frequency: newFreq,
                intensity: newIntensity,
                waveform: original.waveform,
                bilateral: original.bilateral,
                bilateral_transition_duration: original.bilateral_transition_duration,
                color_temperature: original.color_temperature
            )
        }
    }

    // MARK: - Technique-Responsive Moments

    /// Inserts additional light moments at detected technique timestamps.
    private func insertTechniqueMoments(
        _ moments: inout [LightMoment],
        techniques: TechniqueDetectionResult,
        prosody: ProsodicProfile,
        config: GenerationConfig
    ) {
        for technique in techniques.sortedTechniques {
            let newMoments = momentsForTechnique(
                technique, prosody: prosody,
                existingMoments: moments, config: config
            )
            moments.append(contentsOf: newMoments)
        }
    }

    /// Returns light moments for a single detected technique.
    private func momentsForTechnique(
        _ technique: HypnoticTechnique,
        prosody: ProsodicProfile,
        existingMoments: [LightMoment],
        config: GenerationConfig
    ) -> [LightMoment] {
        let time = technique.timestamp
        let mul = config.intensityMultiplier
        let localFreq = findNearestFrequency(at: time, in: existingMoments)

        switch technique.technique {
        case "countdown":
            let baseFreq = prosody.speechRate(at: time) < 100 ? 5.0 : 6.0
            return [moment(time: time, freq: baseFreq, amp: 0.36 * mul,
                           waveform: .softPulse, colorTemp: 2800)]

        case "deepening_command":
            return [
                moment(time: time, freq: max(config.minFrequency, localFreq - 1.5),
                       amp: 0.42 * mul, waveform: .softPulse, colorTemp: 2400, bilateral: true),
                moment(time: time + 2.0, freq: localFreq,
                       amp: 0.34 * mul, waveform: .softPulse, colorTemp: 2600)
            ]

        case "deliberate_pause", "extended_silence":
            return [moment(time: time, freq: max(config.minFrequency, localFreq - 0.5),
                           amp: 0.28 * mul, waveform: .noiseModulatedSine, colorTemp: 2200)]

        case "embedded_command":
            return [moment(time: time, freq: localFreq, amp: 0.40 * mul,
                           waveform: .softPulse, bilateral: true, bilateralTransition: 0.5)]

        case "progressive_relaxation":
            return [moment(time: time, freq: 7.0, amp: 0.35 * mul,
                           waveform: .softPulse, colorTemp: 3000)]

        case "anchoring":
            return [moment(time: time, freq: 6.0, amp: 0.36 * mul,
                           waveform: .softPulse, colorTemp: 2400,
                           bilateral: true, bilateralTransition: 3.0)]

        case "repetition_pattern":
            let rate = prosody.speechRate(at: time)
            let pulseFreq = max(4.0, min(8.0, rate / 20.0))
            return [moment(time: time, freq: pulseFreq, amp: 0.38 * mul,
                           waveform: .softPulse, colorTemp: 2800)]

        case "fractionation":
            return [
                moment(time: time, freq: localFreq + 2.0, amp: 0.40 * mul,
                       waveform: .sine, colorTemp: 3200),
                moment(time: time + 5.0, freq: max(config.minFrequency, localFreq - 1.0),
                       amp: 0.32 * mul, waveform: .softPulse, colorTemp: 2600)
            ]

        default:
            return []
        }
    }

    // MARK: - Adaptive Breath Oscillation

    /// Applies breath oscillation synced to the hypnotist's actual speech rate
    /// rather than a fixed duration-based rate. When the speaker slows, the
    /// light follows — creating unconscious rapport.
    func applyAdaptiveBreathOscillation(
        _ moments: inout [LightMoment],
        prosody: ProsodicProfile,
        depth: Double = 0.20
    ) {
        for idx in 0..<moments.count {
            guard moments[idx].frequency < 14.0 else { continue }

            let time = moments[idx].time
            let localRate = prosody.speechRate(at: time)

            // Map speech rate to breath Hz:
            // 150 WPM → 0.15 Hz (normal relaxed), 60 WPM → 0.07 Hz (deep trance)
            let rate = mapRange(localRate, from: 60...150, to: 0.07...0.15)
            let modulation = depth * sin(2.0 * .pi * rate * time)

            let original = moments[idx]
            let newFreq = max(0.5, original.frequency + modulation)
            moments[idx] = LightMoment(
                time: original.time,
                frequency: newFreq,
                intensity: original.intensity,
                waveform: original.waveform,
                bilateral: original.bilateral,
                bilateral_transition_duration: original.bilateral_transition_duration,
                color_temperature: original.color_temperature
            )
        }
    }

    // MARK: - Helpers

    /// Finds the frequency of the nearest existing moment at a given time.
    private func findNearestFrequency(
        at time: TimeInterval,
        in moments: [LightMoment]
    ) -> Double {
        guard !moments.isEmpty else { return 7.0 }
        let nearest = moments.min { abs($0.time - time) < abs($1.time - time) }
        return nearest?.frequency ?? 7.0
    }

    /// Linear interpolation between two ranges.
    private func mapRange(
        _ value: Double,
        from source: ClosedRange<Double>,
        to target: ClosedRange<Double>
    ) -> Double {
        let clamped = max(source.lowerBound, min(source.upperBound, value))
        let normalized = (clamped - source.lowerBound) / (source.upperBound - source.lowerBound)
        return target.lowerBound + normalized * (target.upperBound - target.lowerBound)
    }
}
