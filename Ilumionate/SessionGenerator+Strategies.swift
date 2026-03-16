//
//  SessionGenerator+Strategies.swift
//  Ilumionate
//
//  Per-content-type session generation strategies grounded in audiovisual
//  entrainment (AVE) research. All sessions follow the canonical arc:
//    Beta entrance → Alpha descent → Theta hold → Alpha emergence → Beta return
//
//  Scientific references baked in:
//  • SSVEP works through closed eyelids at 8–10% transmission.
//  • Theta 4–8 Hz is the hypnagogic sweet spot (strongest thalamic resonance).
//  • 10 Hz alpha is most studied for relaxation; 40 Hz gamma for cognition.
//  • Bilateral mode (0.5 phase offset) at 4–12 Hz promotes interhemispheric coherence.
//  • Warm color (2200–2800 K) for deep states; cool (4500–6500 K) for alerting/emergence.
//  • noiseModulatedSine prevents neural habituation on long holds.
//

import Foundation

// MARK: - SessionArc

/// Converts a session duration into absolute-time phase boundaries with minimum-duration guards.
///
/// Pure percentage waypoints break at the extremes:
/// - A 5-min session with `duration * 0.05` gives only 15 s of beta entrance.
/// - A 2-hour session with `duration * 0.88` starts emergence too late.
///
/// `SessionArc` applies percentage targets *and* floors so every phase is long enough
/// to produce its intended neurological effect. The hard guarantee is:
///   **emergence ≥ `minEmergenceDuration` seconds** (60 s on any session length).
struct SessionArc: Sendable {

    // MARK: Boundaries (absolute seconds from start)

    /// End of the beta-entrance ramp; beginning of alpha descent.
    let betaEntranceEnd: TimeInterval
    /// End of alpha descent; beginning of theta induction.
    let alphaDescentEnd: TimeInterval
    /// End of theta induction; beginning of deep-theta hold.
    let thetaInductionEnd: TimeInterval
    /// End of deep-theta hold; beginning of suggestions layer.
    let deepHoldEnd: TimeInterval
    /// Start of emergence ramp; end of suggestions layer.
    let emergenceStart: TimeInterval
    /// Total session duration.
    let duration: TimeInterval

    /// Guaranteed minimum for the emergence phase (seconds).
    static let minEmergenceDuration: TimeInterval = 60.0

    // MARK: Init

    init(duration: TimeInterval) {
        let d = max(duration, 120.0) // guard against very short edge cases
        self.duration = d

        // Emergence: percentage target, clamped so ≥60 s is always reserved at the end.
        let pctEmergence  = d * 0.88
        let maxEmergence  = d - SessionArc.minEmergenceDuration
        let halfwayPoint  = d * 0.50 // never start emergence before the halfway mark
        emergenceStart = max(halfwayPoint, min(maxEmergence, pctEmergence))

        // Time available for beta + alpha + theta phases before emergence.
        let available = emergenceStart

        // Scale minimum phase durations down if the session is too short to fit
        // all hard-minimum phases (30+45+45 = 120 s) before the emergence window.
        // A scale of 1.0 means the minimums are not binding; <1.0 compresses them.
        let rawMinTotal = 30.0 + 45.0 + 45.0 // 120 s combined
        let scale = min(1.0, (available * 0.90) / rawMinTotal)
        let minBeta  = 30.0 * scale
        let minAlpha = 45.0 * scale
        let minTheta = 45.0 * scale

        // Beta entrance
        betaEntranceEnd = max(minBeta, min(d * 0.05, available * 0.10))

        // Alpha descent
        alphaDescentEnd = max(betaEntranceEnd + minAlpha, min(d * 0.20, available * 0.25))

        // Theta induction — clamped to stay strictly before emergence.
        thetaInductionEnd = min(
            max(alphaDescentEnd + minTheta, min(d * 0.35, available * 0.40)),
            emergenceStart - 1.0
        )

        // Deep hold: fills up to the suggestions layer (last 15% before emergence),
        // clamped to stay strictly before emergence.
        deepHoldEnd = min(
            max(thetaInductionEnd, emergenceStart * 0.85),
            emergenceStart - 1.0
        )
    }

    /// Duration of the guaranteed emergence window (always ≥ `minEmergenceDuration`).
    var emergenceDuration: TimeInterval { duration - emergenceStart }
}

extension SessionGenerator {

    // MARK: - Hypnosis

    func generateHypnosisSession(
        analysis: AnalysisResult,
        duration: TimeInterval,
        config: GenerationConfig
    ) -> [LightMoment] {
        if let phases = analysis.hypnosisMetadata?.phases, !phases.isEmpty {
            return generateHypnosisFromPhases(phases: phases, duration: duration, config: config)
        }
        return generateHypnosisFromDuration(duration: duration, config: config)
    }

    /// Phase-accurate generation when the AI returned explicit hypnosis phases.
    /// Uses calibrated band-fraction targets (e.g. therapy=10% of band = deepest theta)
    /// and applies breath oscillation to prevent neural habituation.
    func generateHypnosisFromPhases(
        phases: [PhaseSegment],
        duration: TimeInterval,
        config: GenerationConfig
    ) -> [LightMoment] {
        var moments: [LightMoment] = []
        let mul = config.intensityMultiplier

        // Beta entrance
        moments.append(moment(time: 0, freq: 18.0, amp: 0.60 * mul, waveform: .sine, colorTemp: 5500))

        for seg in phases {
            let baseFreq   = targetFrequencyForPhase(seg.phase, config: config)
            let baseAmp    = intensityForPhase(seg.phase) * mul
            let colorTemp  = colorTemperatureForPhase(seg.phase)
            let waveform   = waveformTypeForPhase(seg.phase)
            let useBilat   = bilateralForPhase(seg.phase)

            moments.append(moment(
                time: seg.startTime,
                freq: baseFreq,
                amp: baseAmp,
                waveform: waveform,
                colorTemp: colorTemp,
                bilateral: useBilat ? true : nil,
                bilateralTransition: useBilat ? 4.0 : nil
            ))

            let segDuration = seg.endTime - seg.startTime
            if segDuration > 30 {
                let midTime = (seg.startTime + seg.endTime) / 2.0
                moments.append(moment(
                    time: midTime,
                    freq: baseFreq,
                    amp: baseAmp * 0.95,
                    waveform: segDuration > 120 ? .noiseModulatedSine : waveform,
                    colorTemp: colorTemp,
                    bilateral: useBilat ? true : nil
                ))
            }
        }

        ensureEmergence(moments: &moments, duration: duration, config: config)
        smoothTransitions(moments: &moments, smoothness: config.transitionSmoothness)
        var sorted = moments.sorted { $0.time < $1.time }
        applyBreathOscillation(&sorted, duration: duration)
        return sorted
    }

    /// Fallback generation when no phase data is available — uses canonical arc.
    /// Waypoints are computed by `SessionArc` which guarantees ≥60 s emergence
    /// and minimum-duration floors for every phase.
    func generateHypnosisFromDuration(duration: TimeInterval, config: GenerationConfig) -> [LightMoment] {
        let arc = SessionArc(duration: duration)
        var moments: [LightMoment] = []
        let mul = config.intensityMultiplier

        // Beta entrance (0 → arc.betaEntranceEnd)
        moments.append(moment(time: 0,                   freq: 18.0, amp: 0.60 * mul, waveform: .sine,      colorTemp: 5500))
        moments.append(moment(time: arc.betaEntranceEnd, freq: 14.0, amp: 0.52 * mul, waveform: .sine,      colorTemp: 5000))

        // Alpha descent (betaEntranceEnd → alphaDescentEnd)
        let alphaMid = (arc.betaEntranceEnd + arc.alphaDescentEnd) / 2.0
        moments.append(moment(time: alphaMid,            freq: 10.0, amp: 0.45 * mul, waveform: .sine,      colorTemp: 4000))
        moments.append(moment(time: arc.alphaDescentEnd, freq: 8.0,  amp: 0.40 * mul, waveform: .softPulse, colorTemp: 3500))

        // Theta induction (alphaDescentEnd → thetaInductionEnd) — bilateral introduced
        let thetaMid = (arc.alphaDescentEnd + arc.thetaInductionEnd) / 2.0
        moments.append(moment(
            time: arc.alphaDescentEnd, freq: 6.5, amp: 0.38 * mul,
            waveform: .softPulse, colorTemp: 3000,
            bilateral: true, bilateralTransition: 4.0
        ))
        moments.append(moment(time: thetaMid,              freq: 5.5, amp: 0.34 * mul, waveform: .softPulse, colorTemp: 2800))
        moments.append(moment(time: arc.thetaInductionEnd, freq: 4.5, amp: 0.30 * mul, waveform: .softPulse, colorTemp: 2400))

        // Deep theta hold (thetaInductionEnd → deepHoldEnd) — noise-modulated to prevent habituation
        let holdMid = (arc.thetaInductionEnd + arc.deepHoldEnd) / 2.0
        moments.append(moment(time: arc.thetaInductionEnd, freq: 4.5, amp: 0.30 * mul,
                               waveform: .noiseModulatedSine, colorTemp: 2200, bilateral: true))
        moments.append(moment(time: holdMid,               freq: 5.0, amp: 0.32 * mul,
                               waveform: .noiseModulatedSine, colorTemp: 2200, bilateral: true))
        moments.append(moment(time: arc.deepHoldEnd,       freq: 4.5, amp: 0.30 * mul,
                               waveform: .noiseModulatedSine, colorTemp: 2200, bilateral: true))

        // Suggestions layer (deepHoldEnd → emergenceStart) — slight uplift while bilateral continues
        let suggestMid = (arc.deepHoldEnd + arc.emergenceStart) / 2.0
        moments.append(moment(time: suggestMid,
                               freq: 5.5, amp: 0.34 * mul,
                               waveform: .softPulse, colorTemp: 2600, bilateral: true))

        // Emergence ramp start — ensureEmergence fills in the full ≥60s ramp
        moments.append(moment(time: arc.emergenceStart, freq: 7.83, amp: 0.36 * mul, waveform: .sine, colorTemp: 3000))

        ensureEmergence(moments: &moments, duration: duration, config: config)
        smoothTransitions(moments: &moments, smoothness: config.transitionSmoothness)
        var sorted = moments.sorted { $0.time < $1.time }
        applyBreathOscillation(&sorted, duration: duration)
        return sorted
    }

    // MARK: - Meditation

    func generateMeditationSession(
        analysis: AnalysisResult,
        duration: TimeInterval,
        config: GenerationConfig
    ) -> [LightMoment] {
        var moments: [LightMoment] = []
        let mul = config.intensityMultiplier
        let mul90 = mul * 0.9

        // Beta entrance
        moments.append(moment(time: 0,             freq: 14.0, amp: 0.50 * mul,   waveform: .sine,            colorTemp: 5000))
        moments.append(moment(time: duration * 0.08, freq: 10.0, amp: 0.44 * mul, waveform: .sine,            colorTemp: 4500))

        // Alpha rest (8–22%)
        moments.append(moment(time: duration * 0.15, freq: 9.0,  amp: 0.40 * mul,   waveform: .sine,          colorTemp: 4000))
        moments.append(moment(time: duration * 0.22, freq: 7.83, amp: 0.36 * mul90, waveform: .softPulse,     colorTemp: 3500))

        // Theta meditation (22–80%) — Schumann resonance anchor
        let thetaRegion = duration * 0.22
        let thetaHoldEnd = duration * 0.80
        let numHoldPoints = max(2, Int((thetaHoldEnd - thetaRegion) / 60.0))

        for idx in 0..<numHoldPoints {
            let progress   = Double(idx) / Double(numHoldPoints)
            let pointTime  = thetaRegion + progress * (thetaHoldEnd - thetaRegion)
            let oscillation = sin(progress * .pi) * 0.5
            let holdFreq   = 7.83 - oscillation
            let holdAmp    = (0.34 - progress * 0.04) * mul
            let bilateral  = progress > 0.15
            moments.append(moment(
                time: pointTime,
                freq: max(config.minFrequency, holdFreq),
                amp: max(0.20, holdAmp),
                waveform: idx > 0 ? .noiseModulatedSine : .softPulse,
                colorTemp: 2800 - progress * 400,
                bilateral: bilateral ? true : nil,
                bilateralTransition: bilateral && idx == 1 ? 5.0 : nil
            ))
        }

        // Emergence
        ensureEmergence(moments: &moments, duration: duration, config: config)
        smoothTransitions(moments: &moments, smoothness: config.transitionSmoothness)
        var sorted = moments.sorted { $0.time < $1.time }
        applyBreathOscillation(&sorted, duration: duration)
        return sorted
    }

    // MARK: - Guided Imagery

    func generateGuidedImagerySession(
        analysis: AnalysisResult,
        duration: TimeInterval,
        config: GenerationConfig
    ) -> [LightMoment] {
        var moments: [LightMoment] = []
        let mul = config.intensityMultiplier

        // Lighter descent — stay mostly in alpha for imagination
        moments.append(moment(time: 0,              freq: 14.0, amp: 0.55 * mul, waveform: .sine,      colorTemp: 5000))
        moments.append(moment(time: duration * 0.10, freq: 10.0, amp: 0.46 * mul, waveform: .sine,     colorTemp: 4500))
        moments.append(moment(time: duration * 0.20, freq: 8.0,  amp: 0.40 * mul, waveform: .softPulse, colorTemp: 4000))

        // Alpha-theta boundary (ideal for vivid imagery)
        let imageryStart = duration * 0.25
        let imageryEnd   = duration * 0.80
        let numPoints    = max(3, Int((imageryEnd - imageryStart) / 45.0))

        for idx in 0..<numPoints {
            let progress  = Double(idx) / Double(numPoints)
            let pointTime = imageryStart + progress * (imageryEnd - imageryStart)
            // Gentle oscillation between alpha and theta
            let freqBase  = 7.5 + sin(progress * .pi * 2.0) * 1.5
            moments.append(moment(
                time: pointTime,
                freq: max(config.minFrequency, freqBase),
                amp: (0.38 - progress * 0.06) * mul,
                waveform: .noiseModulatedSine,
                colorTemp: 3200 - progress * 600
            ))
        }

        // Color-temperature response to key moments in analysis
        for keyMoment in analysis.keyMoments {
            let adjustment = adjustmentForKeyMoment(keyMoment)
            if keyMoment.time < imageryEnd {
                moments.append(moment(
                    time: keyMoment.time,
                    freq: adjustment.frequency,
                    amp: adjustment.intensity * mul,
                    waveform: .sine,
                    colorTemp: adjustment.colorTemperature
                ))
            }
        }

        ensureEmergence(moments: &moments, duration: duration, config: config)
        smoothTransitions(moments: &moments, smoothness: config.transitionSmoothness)
        return moments.sorted { $0.time < $1.time }
    }

    // MARK: - Affirmations

    func generateAffirmationsSession(
        analysis: AnalysisResult,
        duration: TimeInterval,
        config: GenerationConfig
    ) -> [LightMoment] {
        var moments: [LightMoment] = []
        let mul = config.intensityMultiplier

        // Light alpha — receptivity without drowsiness
        moments.append(moment(time: 0,              freq: 12.0, amp: 0.50 * mul, waveform: .sine,      colorTemp: 4500))
        moments.append(moment(time: duration * 0.10, freq: 10.0, amp: 0.44 * mul, waveform: .sine,     colorTemp: 4200))
        moments.append(moment(time: duration * 0.20, freq: 9.0,  amp: 0.40 * mul, waveform: .softPulse, colorTemp: 4000))

        // Alpha hold (20–80%) — 10 Hz is prime for hypnotic suggestibility
        let holdStart = duration * 0.20
        let holdEnd   = duration * 0.80
        let numPoints = max(2, Int((holdEnd - holdStart) / 60.0))

        for idx in 0..<numPoints {
            let progress  = Double(idx) / Double(numPoints)
            let pointTime = holdStart + progress * (holdEnd - holdStart)
            let freqOsc   = 10.0 + sin(progress * .pi) * 1.0
            moments.append(moment(
                time: pointTime,
                freq: freqOsc,
                amp: 0.40 * mul,
                waveform: .noiseModulatedSine,
                colorTemp: 4000 - progress * 500
            ))
        }

        // Gentle emergence to leave the listener alert
        moments.append(moment(time: holdEnd,      freq: 12.0, amp: 0.44 * mul, waveform: .sine, colorTemp: 4500))
        moments.append(moment(time: duration,     freq: 14.0, amp: 0.50 * mul, waveform: .sine, colorTemp: 5000))

        smoothTransitions(moments: &moments, smoothness: config.transitionSmoothness)
        return moments.sorted { $0.time < $1.time }
    }

    // MARK: - Music

    func generateMusicSession(
        analysis: AnalysisResult,
        duration: TimeInterval,
        config: GenerationConfig
    ) -> [LightMoment] {
        var moments: [LightMoment] = []
        let mul = config.intensityMultiplier
        let targetFreq = clamp(
            analysis.suggestedFrequencyRange.lowerBound,
            lower: config.minFrequency,
            upper: config.maxFrequency
        )
        let baseAmp = analysis.suggestedIntensity * mul

        // Music: follow energy without deep theta descent
        moments.append(moment(time: 0, freq: 10.0, amp: baseAmp, waveform: .sine, colorTemp: 4000))

        let numPoints = max(4, Int(duration / 30.0))
        for idx in 1...numPoints {
            let progress  = Double(idx) / Double(numPoints)
            let pointTime = progress * duration
            let wave: WaveformType = progress < 0.8 ? .noiseModulatedSine : .sine
            moments.append(moment(
                time: pointTime,
                freq: targetFreq,
                amp: baseAmp * (0.9 + sin(progress * .pi * 2.0) * 0.1),
                waveform: wave,
                colorTemp: analysis.suggestedColorTemperature
            ))
        }

        // Honor key moments from analysis
        for keyMoment in analysis.keyMoments {
            let adjustment = adjustmentForKeyMoment(keyMoment)
            moments.append(moment(
                time: keyMoment.time,
                freq: clamp(adjustment.frequency, lower: config.minFrequency, upper: config.maxFrequency),
                amp: adjustment.intensity * mul,
                waveform: .sine,
                colorTemp: adjustment.colorTemperature
            ))
        }

        smoothTransitions(moments: &moments, smoothness: config.transitionSmoothness)
        return moments.sorted { $0.time < $1.time }
    }

    // MARK: - General Fallback

    func generateGeneralSession(
        analysis: AnalysisResult,
        duration: TimeInterval,
        config: GenerationConfig
    ) -> [LightMoment] {
        var moments: [LightMoment] = []
        let mul = config.intensityMultiplier
        let targetFreq = clamp(
            analysis.suggestedFrequencyRange.lowerBound,
            lower: config.minFrequency,
            upper: config.maxFrequency
        )

        moments.append(moment(time: 0, freq: 14.0, amp: 0.55 * mul, waveform: .sine, colorTemp: 5000))

        let numPoints = max(4, Int(duration / 30.0))
        for idx in 1...numPoints {
            let progress  = Double(idx) / Double(numPoints)
            let pointTime = progress * duration
            let freqVal   = 14.0 + (targetFreq - 14.0) * min(1.0, progress * 2.0)
            let ampVal    = (0.55 - progress * 0.15) * mul
            moments.append(moment(
                time: pointTime,
                freq: clamp(freqVal, lower: config.minFrequency, upper: config.maxFrequency),
                amp: max(0.20, ampVal),
                waveform: progress > 0.2 ? .noiseModulatedSine : .sine,
                colorTemp: analysis.suggestedColorTemperature
            ))
        }

        for keyMoment in analysis.keyMoments {
            let adjustment = adjustmentForKeyMoment(keyMoment)
            moments.append(moment(
                time: keyMoment.time,
                freq: clamp(adjustment.frequency, lower: config.minFrequency, upper: config.maxFrequency),
                amp: adjustment.intensity * mul,
                waveform: .sine,
                colorTemp: adjustment.colorTemperature
            ))
        }

        ensureEmergence(moments: &moments, duration: duration, config: config)
        smoothTransitions(moments: &moments, smoothness: config.transitionSmoothness)
        return moments.sorted { $0.time < $1.time }
    }

    // MARK: - Phase Mapping Helpers

    /// Returns the calibrated target frequency for a phase using research-backed
    /// band-fraction targets. Fractions sourced from AVE phase-response studies:
    ///   preTalk=100%, induction=75%, deepening=40%, therapy=10%,
    ///   suggestions=25%, conditioning=40%, emergence=60%
    func targetFrequencyForPhase(_ phase: HypnosisMetadata.Phase, config: GenerationConfig) -> Double {
        let range = frequencyRangeForPhase(phase)
        let lo = range.lowerBound
        let hi = range.upperBound
        let bandWidth = hi - lo

        let fraction: Double
        switch phase {
        case .preTalk:      fraction = 1.00   // top of beta band
        case .induction:    fraction = 0.75   // upper alpha
        case .deepening:    fraction = 0.40   // mid alpha-theta
        case .therapy:      fraction = 0.10   // deep theta floor
        case .suggestions:  fraction = 0.25   // lower theta (active commands need slight uplift)
        case .conditioning: fraction = 0.40   // mid theta
        case .emergence:    fraction = 0.60   // alpha-SMR
        case .transitional: fraction = 0.50   // midpoint
        }

        let target = lo + bandWidth * fraction
        return clamp(target, lower: config.minFrequency, upper: config.maxFrequency)
    }

    /// Returns the breath oscillation rate for a given session duration.
    ///
    /// Longer sessions enter deeper trance where subjects breathe more slowly.
    /// The rate decreases linearly from 0.15 Hz (5 min / fast) to 0.08 Hz (60 min / slow),
    /// clamped so very short or very long recordings stay within physiological range.
    ///
    ///   5 min  → 0.150 Hz (~1 cycle / 6.7 s, normal relaxed breathing)
    ///   15 min → 0.137 Hz
    ///   30 min → 0.118 Hz
    ///   60 min → 0.080 Hz (~1 cycle / 12.5 s, deep meditative breathing)
    nonisolated static func breathRate(for duration: Double) -> Double {
        let rate = 0.15 - (duration - 300.0) / 3300.0 * 0.07
        return max(0.08, min(0.15, rate))
    }

    /// Applies duration-scaled breath-rate frequency modulation to prevent neural habituation.
    /// `freq += depth × sin(2π × rate × t)` — mirrors the lightMapCreationTool approach.
    /// Only modulates moments below 14 Hz (entrainment range) to avoid disrupting
    /// emergence/beta segments.
    func applyBreathOscillation(
        _ moments: inout [LightMoment],
        duration: Double,
        depth: Double = 0.20   // Hz amplitude of modulation
    ) {
        let rate = SessionGenerator.breathRate(for: duration)
        for idx in 0..<moments.count {
            guard moments[idx].frequency < 14.0 else { continue }
            let modulation = depth * sin(2.0 * .pi * rate * moments[idx].time)
            let newFreq = max(0.5, moments[idx].frequency + modulation)
            let original = moments[idx]
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

    func frequencyRangeForPhase(_ phase: HypnosisMetadata.Phase) -> ClosedRange<Double> {
        switch phase {
        case .preTalk:    return 12.0...18.0
        case .induction:  return 8.0...12.0
        case .deepening:  return 5.0...8.0
        case .therapy:    return 4.5...6.5
        case .suggestions: return 5.0...7.0
        case .conditioning: return 5.5...7.5
        case .emergence:  return 8.0...14.0
        case .transitional: return 6.0...10.0
        }
    }

    func intensityForPhase(_ phase: HypnosisMetadata.Phase) -> Double {
        switch phase {
        case .preTalk:     return 0.55
        case .induction:   return 0.45
        case .deepening:   return 0.38
        case .therapy:     return 0.32
        case .suggestions: return 0.34
        case .conditioning: return 0.36
        case .emergence:   return 0.44
        case .transitional: return 0.40
        }
    }

    func colorTemperatureForPhase(_ phase: HypnosisMetadata.Phase) -> Double {
        switch phase {
        case .preTalk:     return 5000
        case .induction:   return 4000
        case .deepening:   return 3000
        case .therapy:     return 2400
        case .suggestions: return 2600
        case .conditioning: return 2800
        case .emergence:   return 4500
        case .transitional: return 3500
        }
    }

    func waveformTypeForPhase(_ phase: HypnosisMetadata.Phase) -> WaveformType {
        switch phase {
        case .preTalk:      return .sine
        case .induction:    return .sine
        case .deepening:    return .softPulse
        case .therapy:      return .noiseModulatedSine
        case .suggestions:  return .softPulse
        case .conditioning: return .softPulse
        case .emergence:    return .sine
        case .transitional: return .sine
        }
    }

    func bilateralForPhase(_ phase: HypnosisMetadata.Phase) -> Bool {
        switch phase {
        case .deepening, .therapy, .suggestions, .conditioning: return true
        default: return false
        }
    }

    // MARK: - Key Moment Adjustment

    struct MomentAdjustment {
        let frequency: Double
        let intensity: Double
        let colorTemperature: Double
    }

    func adjustmentForKeyMoment(_ keyMoment: KeyMoment) -> MomentAdjustment {
        switch keyMoment.action {
        case .energize, .increaseIntensity:
            return MomentAdjustment(frequency: 14.0, intensity: 0.55, colorTemperature: 5000)
        case .deepen, .reduceIntensity:
            return MomentAdjustment(frequency: 5.5,  intensity: 0.30, colorTemperature: 2600)
        case .warm:
            return MomentAdjustment(frequency: 8.0,  intensity: 0.40, colorTemperature: 3000)
        case .cool:
            return MomentAdjustment(frequency: 12.0, intensity: 0.48, colorTemperature: 5000)
        }
    }

    // MARK: - Utility

    func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
