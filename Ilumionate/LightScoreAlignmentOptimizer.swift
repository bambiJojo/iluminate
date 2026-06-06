//
//  LightScoreAlignmentOptimizer.swift
//  Ilumionate
//
//  Iterative repair loop for generated light scores. It turns the 90% target
//  from a passive warning into an active generation constraint.
//

import Foundation

struct LightScoreAlignmentOptimizationResult: Sendable {
    let moments: [LightMoment]
    let report: LightScoreAlignmentReport
    let iterationCount: Int
}

struct LightScoreAlignmentOptimizer: Sendable {

    private let maximumIterations = 3
    private let minimumImprovement = 0.002
    private let postProcessor = LightScorePostProcessor()
    private let scorer = LightScoreAlignmentScorer()

    func optimize(
        rawMoments: [LightMoment],
        duration: TimeInterval,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig
    ) -> LightScoreAlignmentOptimizationResult {
        var bestMoments = postProcessor.process(
            moments: rawMoments,
            duration: duration,
            analysis: analysis,
            config: config
        )
        var bestReport = score(moments: bestMoments, duration: duration, analysis: analysis, config: config)

        guard !bestReport.meetsProductionTarget else {
            return LightScoreAlignmentOptimizationResult(
                moments: bestMoments,
                report: bestReport,
                iterationCount: 0
            )
        }

        var attemptedIterations = 0
        for iteration in 1...maximumIterations {
            attemptedIterations = iteration
            var repaired = bestMoments
            repaired.append(contentsOf: correctiveMoments(
                report: bestReport,
                duration: duration,
                analysis: analysis,
                config: config,
                iteration: iteration
            ))

            repaired = postProcessor.process(
                moments: repaired,
                duration: duration,
                analysis: analysis,
                config: config
            )

            let repairedReport = score(
                moments: repaired,
                duration: duration,
                analysis: analysis,
                config: config
            )

            guard repairedReport.overallScore >= bestReport.overallScore + minimumImprovement else {
                break
            }

            bestMoments = repaired
            bestReport = repairedReport

            if bestReport.meetsProductionTarget {
                break
            }
        }

        return LightScoreAlignmentOptimizationResult(
            moments: bestMoments,
            report: bestReport,
            iterationCount: attemptedIterations
        )
    }

    // MARK: - Corrective Moment Generation

    private func correctiveMoments(
        report: LightScoreAlignmentReport,
        duration: TimeInterval,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig,
        iteration: Int
    ) -> [LightMoment] {
        var moments: [LightMoment] = []

        if shouldRepairPhaseAlignment(report) {
            moments.append(contentsOf: phaseCorrectionMoments(
                duration: duration,
                analysis: analysis,
                config: config,
                iteration: iteration
            ))
        }

        if report.pauseResponseScore < 0.95 {
            moments.append(contentsOf: pauseCorrectionMoments(
                duration: duration,
                analysis: analysis,
                config: config
            ))
        }

        let hasExplicitPhases = analysis.hypnosisMetadata?.phases.isEmpty == false
        if report.phaseFrequencyScore < 0.75, !hasExplicitPhases {
            moments.append(contentsOf: suggestedRangeCorrectionMoments(
                duration: duration,
                analysis: analysis,
                config: config
            ))
        }

        return moments
    }

    private func shouldRepairPhaseAlignment(_ report: LightScoreAlignmentReport) -> Bool {
        report.phaseFrequencyScore < 0.98
            || report.boundaryScore < 0.98
            || report.depthCorrelationScore < 0.92
    }

    private func phaseCorrectionMoments(
        duration: TimeInterval,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig,
        iteration: Int
    ) -> [LightMoment] {
        guard let phases = analysis.hypnosisMetadata?.phases, !phases.isEmpty else { return [] }

        return phases
            .filter { $0.endTime > 0 && $0.startTime < duration }
            .sorted { $0.startTime < $1.startTime }
            .flatMap { phase -> [LightMoment] in
                let start = clamp(phase.startTime, lower: 0, upper: duration)
                let end = clamp(phase.endTime, lower: start, upper: duration)
                let phaseDuration = end - start
                guard phaseDuration > 0 else { return [] }

                let progressValues = correctionProgressValues(duration: phaseDuration, iteration: iteration)
                return progressValues.map { progress in
                    phaseMoment(
                        phase: phase,
                        time: start + phaseDuration * progress,
                        progress: progress,
                        phaseDuration: phaseDuration,
                        config: config
                    )
                }
            }
    }

    private func correctionProgressValues(duration: TimeInterval, iteration: Int) -> [Double] {
        let base: [Double]
        if duration >= 120 {
            base = [0.0, 0.18, 0.33, 0.50, 0.67, 0.84, 0.96]
        } else if duration >= 45 {
            base = [0.0, 0.25, 0.50, 0.75, 0.96]
        } else if duration >= 20 {
            base = [0.0, 0.50, 0.96]
        } else {
            base = [0.0]
        }

        guard iteration > 1, duration >= 30 else { return base }
        return Array(Set(base + [0.08, 0.42, 0.58, 0.92])).sorted()
    }

    private func phaseMoment(
        phase: PhaseSegment,
        time: TimeInterval,
        progress: Double,
        phaseDuration: TimeInterval,
        config: SessionGenerator.GenerationConfig
    ) -> LightMoment {
        let useBilateral = LightScorePhaseTargeting.bilateral(for: phase.phase)
        return LightMoment(
            time: time,
            frequency: LightScorePhaseTargeting.targetFrequency(
                phase: phase.phase,
                tranceDepth: phase.tranceDepthEstimate,
                progress: progress,
                config: config
            ),
            intensity: clamp(
                LightScorePhaseTargeting.intensity(
                    phase: phase.phase,
                    tranceDepth: phase.tranceDepthEstimate,
                    confidence: phase.confidenceLevel
                ) * config.intensityMultiplier,
                lower: 0.02,
                upper: 1.0
            ),
            waveform: LightScorePhaseTargeting.waveform(
                for: phase.phase,
                longSegment: phaseDuration >= 120
            ),
            ramp_duration: min(max(phaseDuration * 0.08, 3.0), 18.0),
            bilateral: useBilateral ? true : nil,
            bilateral_transition_duration: useBilateral ? 3.0 : nil,
            color_temperature: config.colorTemperatureOverride
                ?? LightScorePhaseTargeting.colorTemperature(for: phase.phase)
        )
    }

    private func pauseCorrectionMoments(
        duration: TimeInterval,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig
    ) -> [LightMoment] {
        guard let prosody = analysis.prosodicProfile else { return [] }

        return prosody.pauses.compactMap { pause -> LightMoment? in
            guard pause.category != .natural else { return nil }
            guard pause.startTime >= 0, pause.startTime <= duration else { return nil }

            let phase = phaseContaining(time: pause.startTime, analysis: analysis)
            let frequencyBase: Double
            let intensityBase: Double
            let bilateral: Bool?
            let colorTemperature: Double?

            if let phase {
                let progress = progressWithin(phase: phase, time: pause.startTime)
                frequencyBase = LightScorePhaseTargeting.targetFrequency(
                    phase: phase.phase,
                    tranceDepth: phase.tranceDepthEstimate,
                    progress: progress,
                    config: config
                )
                intensityBase = LightScorePhaseTargeting.intensity(
                    phase: phase.phase,
                    tranceDepth: phase.tranceDepthEstimate,
                    confidence: phase.confidenceLevel
                )
                bilateral = LightScorePhaseTargeting.bilateral(for: phase.phase) ? true : nil
                colorTemperature = LightScorePhaseTargeting.colorTemperature(for: phase.phase)
            } else {
                frequencyBase = clamp(
                    (analysis.suggestedFrequencyRange.lowerBound + analysis.suggestedFrequencyRange.upperBound) / 2,
                    lower: config.minFrequency,
                    upper: config.maxFrequency
                )
                intensityBase = analysis.suggestedIntensity
                bilateral = nil
                colorTemperature = analysis.suggestedColorTemperature
            }

            let frequencyDrop: Double
            let intensityScale: Double
            switch pause.category {
            case .natural:
                return nil
            case .deliberate:
                frequencyDrop = 0.45
                intensityScale = 0.84
            case .silence:
                frequencyDrop = 0.70
                intensityScale = 0.72
            case .musicOnly:
                frequencyDrop = 0.10
                intensityScale = 0.78
            }

            return LightMoment(
                time: pause.startTime,
                frequency: clamp(
                    frequencyBase - frequencyDrop,
                    lower: config.minFrequency,
                    upper: config.maxFrequency
                ),
                intensity: clamp(intensityBase * intensityScale * config.intensityMultiplier, lower: 0.02, upper: 1.0),
                waveform: .noiseModulatedSine,
                ramp_duration: min(max(pause.duration * 0.35, 2.0), 8.0),
                bilateral: bilateral,
                bilateral_transition_duration: bilateral == true ? 3.0 : nil,
                color_temperature: config.colorTemperatureOverride ?? colorTemperature
            )
        }
    }

    private func suggestedRangeCorrectionMoments(
        duration: TimeInterval,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig
    ) -> [LightMoment] {
        guard duration > 0 else { return [] }
        let range = analysis.suggestedFrequencyRange
        let center = clamp((range.lowerBound + range.upperBound) / 2, lower: config.minFrequency, upper: config.maxFrequency)
        let intensity = clamp(analysis.suggestedIntensity * config.intensityMultiplier, lower: 0.02, upper: 1.0)
        let color = config.colorTemperatureOverride ?? analysis.suggestedColorTemperature

        return [0.0, 0.5, 1.0].map { progress in
            LightMoment(
                time: duration * progress,
                frequency: center,
                intensity: intensity,
                waveform: .sine,
                ramp_duration: 8.0,
                color_temperature: color
            )
        }
    }

    // MARK: - Scoring Helpers

    private func score(
        moments: [LightMoment],
        duration: TimeInterval,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig
    ) -> LightScoreAlignmentReport {
        let session = LightSession(
            session_name: "Alignment Draft",
            duration_sec: duration,
            light_score: moments
        )
        return scorer.score(session: session, analysis: analysis, config: config)
    }

    private func phaseContaining(time: TimeInterval, analysis: AnalysisResult) -> PhaseSegment? {
        analysis.hypnosisMetadata?.phases.first {
            time >= $0.startTime && time <= $0.endTime
        }
    }

    private func progressWithin(phase: PhaseSegment, time: TimeInterval) -> Double {
        let duration = max(phase.endTime - phase.startTime, 0.001)
        return clamp((time - phase.startTime) / duration, lower: 0, upper: 1)
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
