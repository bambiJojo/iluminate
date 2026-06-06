//
//  LightScorePostProcessor.swift
//  Ilumionate
//
//  Final normalization pass for generated light scores.
//  Keeps playback-safe timing while preserving the analyzer's phase intent.
//

import Foundation

struct LightScorePostProcessor: Sendable {

    private let duplicateWindow: TimeInterval = 0.25

    func process(
        moments: [LightMoment],
        duration: TimeInterval,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig
    ) -> [LightMoment] {
        guard duration > 0 else { return [] }

        var normalized = moments.map { normalize($0, duration: duration, config: config) }
        normalized.append(contentsOf: phaseAnchorMoments(
            analysis: analysis,
            duration: duration,
            config: config
        ))
        normalized.append(contentsOf: pauseResponseMoments(
            baseMoments: normalized,
            prosody: analysis.prosodicProfile,
            duration: duration,
            config: config
        ))

        normalized = coalesceMoments(normalized, duration: duration, config: config)
        normalized = ensureEndpointCoverage(normalized, duration: duration, config: config)

        return normalized
    }

    // MARK: - Normalization

    private func normalize(
        _ moment: LightMoment,
        duration: TimeInterval,
        config: SessionGenerator.GenerationConfig
    ) -> LightMoment {
        let frequency = clamp(moment.frequency, lower: config.minFrequency, upper: config.maxFrequency)
        let intensity = clamp(moment.intensity, lower: 0.0, upper: 1.0)
        let colorTemperature = config.colorTemperatureOverride ?? moment.color_temperature
        let shouldForceBilateral = config.bilateralMode && frequency < 14.0
        let bilateral = shouldForceBilateral ? true : moment.bilateral
        let bilateralTransition = shouldForceBilateral && moment.bilateral != true
            ? (moment.bilateral_transition_duration ?? 4.0)
            : moment.bilateral_transition_duration

        return LightMoment(
            time: clamp(moment.time, lower: 0.0, upper: duration),
            frequency: frequency,
            intensity: intensity,
            waveform: moment.waveform,
            ramp_duration: moment.ramp_duration,
            bilateral: bilateral,
            bilateral_transition_duration: bilateralTransition,
            color_temperature: colorTemperature
        )
    }

    private func coalesceMoments(
        _ moments: [LightMoment],
        duration: TimeInterval,
        config: SessionGenerator.GenerationConfig
    ) -> [LightMoment] {
        let ordered = moments
            .enumerated()
            .sorted {
                if abs($0.element.time - $1.element.time) > 0.0001 {
                    return $0.element.time < $1.element.time
                }
                return $0.offset < $1.offset
            }

        var result: [LightMoment] = []
        for pair in ordered {
            let current = normalize(pair.element, duration: duration, config: config)
            guard let last = result.last else {
                result.append(current)
                continue
            }

            if current.time - last.time < duplicateWindow {
                result[result.count - 1] = merge(last, with: current)
            } else {
                result.append(current)
            }
        }

        return result
    }

    private func merge(_ earlier: LightMoment, with later: LightMoment) -> LightMoment {
        LightMoment(
            time: max(earlier.time, later.time),
            frequency: later.frequency,
            intensity: later.intensity,
            waveform: later.waveform,
            ramp_duration: later.ramp_duration ?? earlier.ramp_duration,
            bilateral: later.bilateral ?? earlier.bilateral,
            bilateral_transition_duration: later.bilateral_transition_duration ?? earlier.bilateral_transition_duration,
            color_temperature: later.color_temperature ?? earlier.color_temperature
        )
    }

    private func ensureEndpointCoverage(
        _ moments: [LightMoment],
        duration: TimeInterval,
        config: SessionGenerator.GenerationConfig
    ) -> [LightMoment] {
        guard var first = moments.first else {
            return [
                LightMoment(
                    time: 0,
                    frequency: clamp(10.0, lower: config.minFrequency, upper: config.maxFrequency),
                    intensity: 0.25,
                    waveform: .sine,
                    color_temperature: config.colorTemperatureOverride ?? 4000
                )
            ]
        }

        var result = moments
        if first.time > 0.001 {
            first = copy(first, time: 0)
            result.insert(first, at: 0)
        }

        guard let last = result.last else { return result }
        if duration - last.time > 0.001 {
            result.append(copy(last, time: duration))
        }

        return result
    }

    // MARK: - Phase Anchors

    private func phaseAnchorMoments(
        analysis: AnalysisResult,
        duration: TimeInterval,
        config: SessionGenerator.GenerationConfig
    ) -> [LightMoment] {
        guard let phases = analysis.hypnosisMetadata?.phases, !phases.isEmpty else { return [] }

        return phases.flatMap { phase -> [LightMoment] in
            let start = clamp(phase.startTime, lower: 0, upper: duration)
            let end = clamp(phase.endTime, lower: start, upper: duration)
            let phaseDuration = end - start
            guard phaseDuration > 0 else { return [] }

            let progressValues: [Double]
            if phaseDuration >= 120 {
                progressValues = [0.0, 0.25, 0.50, 0.75, 0.92]
            } else if phaseDuration >= 45 {
                progressValues = [0.0, 0.33, 0.66, 0.92]
            } else if phaseDuration >= 20 {
                progressValues = [0.0, 0.50, 0.92]
            } else {
                progressValues = [0.0]
            }

            return progressValues.map { progress in
                let frequency = LightScorePhaseTargeting.targetFrequency(
                    phase: phase.phase,
                    tranceDepth: phase.tranceDepthEstimate,
                    progress: progress,
                    config: config
                )
                let useBilateral = LightScorePhaseTargeting.bilateral(for: phase.phase)
                return LightMoment(
                    time: start + phaseDuration * progress,
                    frequency: frequency,
                    intensity: LightScorePhaseTargeting.intensity(
                        phase: phase.phase,
                        tranceDepth: phase.tranceDepthEstimate,
                        confidence: phase.confidenceLevel
                    ) * config.intensityMultiplier,
                    waveform: LightScorePhaseTargeting.waveform(
                        for: phase.phase,
                        longSegment: phaseDuration >= 120
                    ),
                    ramp_duration: min(max(phaseDuration * 0.10, 4.0), 24.0),
                    bilateral: useBilateral ? true : nil,
                    bilateral_transition_duration: useBilateral ? 4.0 : nil,
                    color_temperature: config.colorTemperatureOverride
                        ?? LightScorePhaseTargeting.colorTemperature(for: phase.phase)
                )
            }
        }
    }

    // MARK: - Pause Response

    private func pauseResponseMoments(
        baseMoments: [LightMoment],
        prosody: ProsodicProfile?,
        duration: TimeInterval,
        config: SessionGenerator.GenerationConfig
    ) -> [LightMoment] {
        guard let prosody else { return [] }

        return prosody.pauses.compactMap { pause -> LightMoment? in
            guard pause.startTime >= 0, pause.startTime <= duration else { return nil }
            guard pause.category != .natural else { return nil }

            let base = interpolatedMoment(at: pause.startTime, in: baseMoments)
                ?? baseMoments.last
                ?? LightMoment(time: pause.startTime, frequency: 8.0, intensity: 0.3, waveform: .sine)

            let volume = prosody.volume(at: pause.startTime)
            let nextFrequency: Double
            let nextIntensity: Double
            let waveform: WaveformType
            let colorTemperature: Double?

            switch pause.category {
            case .natural:
                return nil
            case .deliberate:
                nextFrequency = base.frequency - 0.4
                nextIntensity = base.intensity * 0.86
                waveform = .noiseModulatedSine
                colorTemperature = warmed(base.color_temperature, by: 150)
            case .silence:
                nextFrequency = base.frequency - 0.7
                nextIntensity = base.intensity * 0.72
                waveform = .noiseModulatedSine
                colorTemperature = warmed(base.color_temperature, by: 250)
            case .musicOnly:
                nextFrequency = base.frequency
                nextIntensity = clamp(0.22 + volume * 0.26, lower: 0.18, upper: 0.55)
                waveform = .noiseModulatedSine
                colorTemperature = base.color_temperature
            }

            return LightMoment(
                time: pause.startTime,
                frequency: clamp(nextFrequency, lower: config.minFrequency, upper: config.maxFrequency),
                intensity: clamp(nextIntensity, lower: 0.02, upper: 1.0),
                waveform: waveform,
                ramp_duration: min(max(2.0, pause.duration * 0.35), 8.0),
                bilateral: base.bilateral,
                bilateral_transition_duration: base.bilateral_transition_duration,
                color_temperature: config.colorTemperatureOverride ?? colorTemperature
            )
        }
    }

    private func interpolatedMoment(
        at time: TimeInterval,
        in moments: [LightMoment]
    ) -> LightMoment? {
        let ordered = moments.sorted { $0.time < $1.time }
        guard !ordered.isEmpty else { return nil }
        guard time > ordered[0].time else { return ordered[0] }
        guard time < ordered[ordered.count - 1].time else { return ordered.last }

        for index in 1..<ordered.count where ordered[index].time >= time {
            let previous = ordered[index - 1]
            let next = ordered[index]
            let span = max(next.time - previous.time, 0.001)
            let alpha = clamp((time - previous.time) / span, lower: 0.0, upper: 1.0)
            let colorTemperature: Double?
            if let previousColor = previous.color_temperature,
               let nextColor = next.color_temperature {
                colorTemperature = previousColor + (nextColor - previousColor) * alpha
            } else {
                colorTemperature = next.color_temperature ?? previous.color_temperature
            }

            return LightMoment(
                time: time,
                frequency: previous.frequency + (next.frequency - previous.frequency) * alpha,
                intensity: previous.intensity + (next.intensity - previous.intensity) * alpha,
                waveform: previous.waveform,
                ramp_duration: next.ramp_duration,
                bilateral: previous.bilateral,
                bilateral_transition_duration: next.bilateral_transition_duration,
                color_temperature: colorTemperature
            )
        }

        return ordered.last
    }

    // MARK: - Helpers

    private func copy(_ moment: LightMoment, time: TimeInterval) -> LightMoment {
        LightMoment(
            time: time,
            frequency: moment.frequency,
            intensity: moment.intensity,
            waveform: moment.waveform,
            ramp_duration: moment.ramp_duration,
            bilateral: moment.bilateral,
            bilateral_transition_duration: moment.bilateral_transition_duration,
            color_temperature: moment.color_temperature
        )
    }

    private func warmed(_ colorTemperature: Double?, by amount: Double) -> Double? {
        guard let colorTemperature else { return nil }
        return max(2000, colorTemperature - amount)
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
