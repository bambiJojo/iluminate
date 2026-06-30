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
        if let prosody = analysis.prosodicProfile {
            // 1. Modulate existing moments based on vocal delivery
            modulateMomentsWithProsody(
                &moments, prosody: prosody, config: config
            )
        }

        // 2. Technique timing comes from the transcript, so these overlays do
        // not depend on raw-audio prosody being available.
        if let techniques = analysis.techniqueDetection {
            insertTechniqueMoments(
                &moments,
                techniques: techniques,
                prosody: analysis.prosodicProfile,
                config: config
            )
        }

        // 3. Use transcript-relative pace and repetition shifts even when
        // raw prosody is missing, so modulation follows the speaker's local
        // rhythm instead of absolute thresholds.
        applyTranscriptAdaptiveModulation(&moments, analysis: analysis, config: config)
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

    func applyTranscriptAdaptiveModulation(
        _ moments: inout [LightMoment],
        analysis: AnalysisResult,
        config: GenerationConfig
    ) {
        guard let transcriptAnalysis = analysis.transcriptAnalysis else { return }

        for index in 0..<moments.count {
            guard let section = transcriptAnalysis.section(at: moments[index].time) else { continue }

            let paceDelta = clamp(section.normalizedWordsPerMinute - 1.0, lower: -0.45, upper: 0.45)
            let repetitionLift = clamp(section.normalizedRepetitionDensity - 1.0, lower: -0.5, upper: 1.5)
            let coverageDelta = clamp(section.normalizedSpeechCoverage - 1.0, lower: -0.5, upper: 0.5)
            let lexicalTightness = clamp(section.normalizedLexicalTightness - 1.0, lower: -0.5, upper: 1.5)

            let original = moments[index]
            let frequencyShift = (paceDelta * 1.2) - max(0, repetitionLift) * 0.55 - max(0, lexicalTightness) * 0.35
            let intensityShift = max(0, repetitionLift) * 0.05 + coverageDelta * 0.04 + max(0, lexicalTightness) * 0.03

            let waveform: WaveformType
            if max(repetitionLift, lexicalTightness) > 0.9, original.frequency < 12.0 {
                waveform = .noiseModulatedSine
            } else if max(repetitionLift, lexicalTightness) > 0.35, original.frequency < 12.0 {
                waveform = .softPulse
            } else {
                waveform = original.waveform
            }

            let warmedColor: Double?
            if let originalColor = original.color_temperature {
                warmedColor = max(2000, originalColor - max(0, repetitionLift) * 220 - max(0, lexicalTightness) * 120)
            } else {
                warmedColor = nil
            }

            moments[index] = LightMoment(
                time: original.time,
                frequency: clamp(
                    original.frequency + frequencyShift,
                    lower: config.minFrequency,
                    upper: config.maxFrequency
                ),
                intensity: clamp(original.intensity + intensityShift, lower: 0.10, upper: 1.0),
                waveform: waveform,
                bilateral: original.bilateral ?? (max(repetitionLift, lexicalTightness) > 0.8 ? true : nil),
                bilateral_transition_duration: original.bilateral_transition_duration,
                color_temperature: warmedColor
            )
        }
    }

    // MARK: - Technique-Responsive Moments

    /// Inserts additional light moments at detected technique timestamps.
    private func insertTechniqueMoments(
        _ moments: inout [LightMoment],
        techniques: TechniqueDetectionResult,
        prosody: ProsodicProfile?,
        config: GenerationConfig
    ) {
        var lastConfusionTimestamp: TimeInterval?

        for technique in techniques.sortedTechniques {
            let strength = techniqueStrength(technique, in: techniques)

            if technique.technique == "confusion_technique" {
                guard strength >= 0.60 else { continue }
                if let lastConfusionTimestamp,
                   technique.timestamp - lastConfusionTimestamp < 8.0 {
                    continue
                }
                lastConfusionTimestamp = technique.timestamp
            }

            let newMoments = momentsForTechnique(
                technique, prosody: prosody,
                strength: strength,
                existingMoments: moments,
                config: config
            )
            moments.append(contentsOf: newMoments)
        }
    }

    /// Returns light moments for a single detected technique.
    private func momentsForTechnique(
        _ technique: HypnoticTechnique,
        prosody: ProsodicProfile?,
        strength: Double,
        existingMoments: [LightMoment],
        config: GenerationConfig
    ) -> [LightMoment] {
        let time = technique.timestamp
        let mul = config.intensityMultiplier
        let localFreq = findNearestFrequency(at: time, in: existingMoments)

        switch technique.technique {
        case "countdown":
            let baseFreq = (prosody?.speechRate(at: time) ?? 120) < 100 ? 5.0 : 6.0
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
            let rate = prosody?.speechRate(at: time) ?? 120
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

        case "confusion_technique":
            return confusionOverlayMoments(
                at: time,
                strength: strength,
                existingMoments: existingMoments,
                config: config
            )

        default:
            return []
        }
    }

    /// Confusion is a short technique inside the surrounding structural phase.
    /// It perturbs that host state briefly, then restores the state that would
    /// otherwise have been active; it never selects a separate frequency band.
    private func confusionOverlayMoments(
        at startTime: TimeInterval,
        strength: Double,
        existingMoments: [LightMoment],
        config: GenerationConfig
    ) -> [LightMoment] {
        guard let sessionEnd = existingMoments.map(\.time).max(), startTime < sessionEnd else {
            return []
        }

        let endTime = min(startTime + 8.0, sessionEnd)
        let duration = endTime - startTime
        guard duration >= 2.0 else { return [] }

        let normalizedStrength = clamp(strength, lower: 0, upper: 1)
        let rampDuration = min(2.0, duration * 0.25)
        let points: [(progress: Double, frequencyShift: Double, intensityReduction: Double)] = [
            (0.00,  0.25, 0.06),
            (0.27, -0.45, 0.12),
            (0.58,  0.22, 0.08),
            (1.00,  0.00, 0.00)
        ]

        return points.map { point in
            let time = startTime + duration * point.progress
            let host = interpolatedHostMoment(at: time, in: existingMoments)
            let isRestoration = point.progress == 1.0

            return moment(
                time: time,
                freq: clamp(
                    host.frequency + point.frequencyShift * normalizedStrength,
                    lower: config.minFrequency,
                    upper: config.maxFrequency
                ),
                amp: clamp(
                    host.intensity * (1.0 - point.intensityReduction * normalizedStrength),
                    lower: 0.05,
                    upper: 1.0
                ),
                waveform: isRestoration ? host.waveform : .noiseModulatedSine,
                ramp: rampDuration,
                colorTemp: host.color_temperature,
                bilateral: host.bilateral,
                bilateralTransition: host.bilateral_transition_duration
            )
        }
    }

    private func techniqueStrength(
        _ technique: HypnoticTechnique,
        in detection: TechniqueDetectionResult
    ) -> Double {
        guard technique.technique == "confusion_technique" else { return 1.0 }

        return detection.markers
            .filter { $0.type == .confusionTechnique }
            .min { abs($0.timestamp - technique.timestamp) < abs($1.timestamp - technique.timestamp) }?
            .strength ?? 0.75
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

    private func interpolatedHostMoment(
        at time: TimeInterval,
        in moments: [LightMoment]
    ) -> LightMoment {
        let sorted = moments.sorted { $0.time < $1.time }
        guard let first = sorted.first else {
            return moment(time: time, freq: 7.0, amp: 0.35, waveform: .softPulse)
        }
        guard time > first.time else { return first }
        guard let last = sorted.last, time < last.time else { return sorted.last ?? first }

        guard let nextIndex = sorted.firstIndex(where: { $0.time >= time }), nextIndex > 0 else {
            return first
        }

        let previous = sorted[nextIndex - 1]
        let next = sorted[nextIndex]
        let span = max(next.time - previous.time, 0.001)
        let progress = clamp((time - previous.time) / span, lower: 0, upper: 1)
        let colorTemperature: Double?
        if let previousColor = previous.color_temperature,
           let nextColor = next.color_temperature {
            colorTemperature = previousColor + (nextColor - previousColor) * progress
        } else {
            colorTemperature = previous.color_temperature ?? next.color_temperature
        }

        return LightMoment(
            time: time,
            frequency: previous.frequency + (next.frequency - previous.frequency) * progress,
            intensity: previous.intensity + (next.intensity - previous.intensity) * progress,
            waveform: previous.waveform,
            bilateral: previous.bilateral,
            bilateral_transition_duration: previous.bilateral_transition_duration,
            color_temperature: colorTemperature
        )
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
