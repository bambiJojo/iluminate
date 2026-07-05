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
            analysis: analysis,
            duration: duration,
            config: config
        ))

        normalized = coalesceMoments(normalized, duration: duration, config: config)
        normalized = ensureEndpointCoverage(normalized, duration: duration, config: config)
        normalized = stabilizeLongFormContour(
            normalized,
            duration: duration,
            analysis: analysis,
            config: config
        )
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
        analysis: AnalysisResult,
        duration: TimeInterval,
        config: SessionGenerator.GenerationConfig
    ) -> [LightMoment] {
        guard let prosody else { return [] }
        let denseLongForm = duration >= 600
            || prosody.pauses.count > max(30, Int(duration / 10.0))
        let minimumSpacing = longFormMinimumSpacing(
            duration: duration,
            hasPhases: analysis.hypnosisMetadata?.phases.isEmpty == false
        )
        let structuralSpacing = max(8.0, minimumSpacing * 0.75)
        let structuralTimes = denseLongForm
            ? structuralContourTimes(analysis: analysis, duration: duration)
            : []

        return prosody.pauses.compactMap { pause -> LightMoment? in
            guard pause.startTime >= 0, pause.startTime <= duration else { return nil }
            guard pause.category != .natural else { return nil }
            if denseLongForm,
               structuralTimes.contains(where: { abs($0 - pause.startTime) < structuralSpacing }) {
                return nil
            }

            let base = phasePauseBaseMoment(
                at: pause.startTime,
                analysis: analysis,
                config: config
            )
                ?? interpolatedMoment(at: pause.startTime, in: baseMoments)
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

    // MARK: - Long-Form Contour Stabilization

    private func stabilizeLongFormContour(
        _ moments: [LightMoment],
        duration: TimeInterval,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig
    ) -> [LightMoment] {
        let ordered = moments.sorted { $0.time < $1.time }
        guard ordered.count > 2 else { return ordered }

        let shouldStabilize = duration >= 600
            || ordered.count > max(80, Int(duration / 6.0))
        guard shouldStabilize else { return ordered }

        let hasPhases = analysis.hypnosisMetadata?.phases.isEmpty == false
        let minimumSpacing = longFormMinimumSpacing(duration: duration, hasPhases: hasPhases)
        let protectedTimes = protectedContourTimes(
            analysis: analysis,
            duration: duration,
            minimumSpacing: minimumSpacing
        )

        var stabilized = pruneDenseMoments(
            ordered,
            protectedTimes: protectedTimes,
            minimumSpacing: minimumSpacing
        )
        stabilized = pullMomentsTowardPhaseTargets(
            stabilized,
            analysis: analysis,
            config: config,
            protectedTimes: protectedTimes
        )
        stabilized = dampIsolatedSpikes(
            stabilized,
            protectedTimes: protectedTimes,
            config: config,
            maximumLocalSpan: minimumSpacing * 2.6
        )

        return stabilized
    }

    private func longFormMinimumSpacing(
        duration: TimeInterval,
        hasPhases: Bool
    ) -> TimeInterval {
        let divisor = hasPhases ? 140.0 : 120.0
        return clamp(duration / divisor, lower: 10.0, upper: 22.0)
    }

    private func protectedContourTimes(
        analysis: AnalysisResult,
        duration: TimeInterval,
        minimumSpacing: TimeInterval
    ) -> [TimeInterval] {
        let structuralTimes = structuralContourTimes(analysis: analysis, duration: duration)
        var times = structuralTimes

        let pauseSpacing = max(14.0, minimumSpacing * 1.25)
        let structuralSpacing = max(8.0, minimumSpacing * 0.75)
        var lastPauseTime = -Double.infinity
        let pauses = analysis.prosodicProfile?.pauses
            .filter { $0.category != .natural }
            .sorted { $0.startTime < $1.startTime } ?? []

        for pause in pauses where pause.startTime >= 0 && pause.startTime <= duration {
            guard pause.startTime - lastPauseTime >= pauseSpacing else { continue }
            guard !structuralTimes.contains(where: { abs($0 - pause.startTime) < structuralSpacing }) else {
                continue
            }
            times.append(pause.startTime)
            lastPauseTime = pause.startTime
        }

        return uniqueTimes(times, tolerance: 0.50)
    }

    private func structuralContourTimes(
        analysis: AnalysisResult,
        duration: TimeInterval
    ) -> [TimeInterval] {
        var times: [TimeInterval] = [0, duration]

        for phase in analysis.hypnosisMetadata?.phases ?? [] {
            let start = clamp(phase.startTime, lower: 0, upper: duration)
            let end = clamp(phase.endTime, lower: start, upper: duration)
            let phaseDuration = end - start
            guard phaseDuration > 0 else { continue }

            times.append(start)
            times.append(end)
            for progress in phaseProgressValues(duration: phaseDuration) {
                times.append(start + phaseDuration * progress)
            }
        }

        return uniqueTimes(times, tolerance: 0.50)
    }

    private func phaseProgressValues(duration: TimeInterval) -> [Double] {
        if duration >= 120 { return [0.0, 0.25, 0.50, 0.75, 0.92] }
        if duration >= 45 { return [0.0, 0.33, 0.66, 0.92] }
        if duration >= 20 { return [0.0, 0.50, 0.92] }
        return [0.0]
    }

    private func pruneDenseMoments(
        _ moments: [LightMoment],
        protectedTimes: [TimeInterval],
        minimumSpacing: TimeInterval
    ) -> [LightMoment] {
        var result: [LightMoment] = []

        for moment in moments {
            guard let last = result.last else {
                result.append(moment)
                continue
            }

            if isProtected(time: moment.time, protectedTimes: protectedTimes) {
                if let last = result.last,
                   moment.time - last.time < minimumSpacing,
                   !isProtected(time: last.time, protectedTimes: protectedTimes) {
                    result.removeLast()
                }
                result.append(moment)
                continue
            }

            guard moment.time - last.time >= minimumSpacing else { continue }
            result.append(moment)
        }

        return result
    }

    private func pullMomentsTowardPhaseTargets(
        _ moments: [LightMoment],
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig,
        protectedTimes: [TimeInterval]
    ) -> [LightMoment] {
        guard let phases = analysis.hypnosisMetadata?.phases, !phases.isEmpty else {
            return moments
        }

        return moments.map { moment in
            guard !isProtected(time: moment.time, protectedTimes: protectedTimes),
                  let phase = phaseContaining(time: moment.time, in: phases) else {
                return moment
            }

            let progress = progressWithin(phase: phase, time: moment.time)
            let target = LightScorePhaseTargeting.targetFrequency(
                phase: phase.phase,
                tranceDepth: phase.tranceDepthEstimate,
                progress: progress,
                config: config
            )
            let targetIntensity = LightScorePhaseTargeting.intensity(
                phase: phase.phase,
                tranceDepth: phase.tranceDepthEstimate,
                confidence: phase.confidenceLevel
            ) * config.intensityMultiplier
            let tolerance = max(0.12, target * 0.02)
            let miss = moment.frequency - target
            let intensityTolerance = 0.04
            let intensityMiss = moment.intensity - targetIntensity
            guard abs(miss) > tolerance || abs(intensityMiss) > intensityTolerance else {
                return moment
            }

            return copy(
                moment,
                frequency: target + clamp(miss, lower: -tolerance, upper: tolerance),
                intensity: targetIntensity + clamp(
                    intensityMiss,
                    lower: -intensityTolerance,
                    upper: intensityTolerance
                ),
                config: config
            )
        }
    }

    private func dampIsolatedSpikes(
        _ moments: [LightMoment],
        protectedTimes: [TimeInterval],
        config: SessionGenerator.GenerationConfig,
        maximumLocalSpan: TimeInterval
    ) -> [LightMoment] {
        guard moments.count >= 3 else { return moments }

        var result = moments
        for index in 1..<(result.count - 1) {
            let previous = result[index - 1]
            let current = result[index]
            let next = result[index + 1]

            guard !isProtected(time: current.time, protectedTimes: protectedTimes) else { continue }
            guard current.time - previous.time <= maximumLocalSpan,
                  next.time - current.time <= maximumLocalSpan else { continue }

            let span = max(next.time - previous.time, 0.001)
            let alpha = clamp((current.time - previous.time) / span, lower: 0, upper: 1)
            let expectedFrequency = previous.frequency + (next.frequency - previous.frequency) * alpha
            let expectedIntensity = previous.intensity + (next.intensity - previous.intensity) * alpha
            let frequencyDeviation = current.frequency - expectedFrequency
            let intensityDeviation = current.intensity - expectedIntensity

            guard abs(frequencyDeviation) > 1.10 || abs(intensityDeviation) > 0.16 else {
                continue
            }

            result[index] = copy(
                current,
                frequency: expectedFrequency + clamp(frequencyDeviation, lower: -0.65, upper: 0.65),
                intensity: expectedIntensity + clamp(intensityDeviation, lower: -0.08, upper: 0.08),
                config: config
            )
        }

        return result
    }

    private func phaseContaining(
        time: TimeInterval,
        in phases: [PhaseSegment]
    ) -> PhaseSegment? {
        phases.first {
            time >= $0.startTime && time <= $0.endTime
        }
    }

    private func progressWithin(
        phase: PhaseSegment,
        time: TimeInterval
    ) -> Double {
        let duration = max(phase.endTime - phase.startTime, 0.001)
        return clamp((time - phase.startTime) / duration, lower: 0, upper: 1)
    }

    private func phasePauseBaseMoment(
        at time: TimeInterval,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig
    ) -> LightMoment? {
        guard let phases = analysis.hypnosisMetadata?.phases,
              let phase = phaseContaining(time: time, in: phases) else {
            return nil
        }

        let progress = progressWithin(phase: phase, time: time)
        let phaseDuration = max(phase.endTime - phase.startTime, 0)
        let useBilateral = LightScorePhaseTargeting.bilateral(for: phase.phase)

        return LightMoment(
            time: time,
            frequency: LightScorePhaseTargeting.targetFrequency(
                phase: phase.phase,
                tranceDepth: phase.tranceDepthEstimate,
                progress: progress,
                config: config
            ),
            intensity: LightScorePhaseTargeting.intensity(
                phase: phase.phase,
                tranceDepth: phase.tranceDepthEstimate,
                confidence: phase.confidenceLevel
            ) * config.intensityMultiplier,
            waveform: LightScorePhaseTargeting.waveform(
                for: phase.phase,
                longSegment: phaseDuration >= 120
            ),
            ramp_duration: nil,
            bilateral: useBilateral ? true : nil,
            bilateral_transition_duration: useBilateral ? 4.0 : nil,
            color_temperature: config.colorTemperatureOverride
                ?? LightScorePhaseTargeting.colorTemperature(for: phase.phase)
        )
    }

    private func uniqueTimes(
        _ times: [TimeInterval],
        tolerance: TimeInterval
    ) -> [TimeInterval] {
        times.sorted().reduce(into: []) { result, time in
            guard let last = result.last else {
                result.append(time)
                return
            }
            if abs(time - last) > tolerance {
                result.append(time)
            }
        }
    }

    private func isProtected(
        time: TimeInterval,
        protectedTimes: [TimeInterval]
    ) -> Bool {
        protectedTimes.contains { abs($0 - time) <= 0.50 }
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

    private func copy(
        _ moment: LightMoment,
        frequency: Double,
        intensity: Double,
        config: SessionGenerator.GenerationConfig
    ) -> LightMoment {
        LightMoment(
            time: moment.time,
            frequency: clamp(frequency, lower: config.minFrequency, upper: config.maxFrequency),
            intensity: clamp(intensity, lower: 0.0, upper: 1.0),
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
