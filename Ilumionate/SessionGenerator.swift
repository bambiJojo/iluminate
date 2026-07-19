//
//  SessionGenerator.swift
//  Ilumionate
//
//  Generates synchronized light therapy sessions from audio analysis.
//  Session design is grounded in audiovisual entrainment (AVE) research.
//  See SessionGenerator+Strategies.swift for per-content-type implementations.
//

import Foundation
import os

/// Generates synchronized light therapy sessions from audio analysis.
@MainActor
@Observable
class SessionGenerator {

    // MARK: - Analyzer Config

    let analyzerConfig: AnalyzerConfig.SessionGeneration

    init(config: AnalyzerConfig.SessionGeneration? = nil) {
        self.analyzerConfig = config ?? AnalyzerConfigLoader.load().sessionGeneration
    }

    // MARK: - Configuration

    struct GenerationConfig {
        var intensityMultiplier: Double = 1.0
        var minFrequency: Double = 0.5
        var maxFrequency: Double = 40.0
        var transitionSmoothness: Double = 0.8
        var colorTemperatureOverride: Double?
        var bilateralMode: Bool = false

        nonisolated init(
            intensityMultiplier: Double = 1.0,
            minFrequency: Double = 0.5,
            maxFrequency: Double = 40.0,
            transitionSmoothness: Double = 0.8,
            colorTemperatureOverride: Double? = nil,
            bilateralMode: Bool = false
        ) {
            self.intensityMultiplier = intensityMultiplier
            self.minFrequency = minFrequency
            self.maxFrequency = maxFrequency
            self.transitionSmoothness = transitionSmoothness
            self.colorTemperatureOverride = colorTemperatureOverride
            self.bilateralMode = bilateralMode
        }

        nonisolated static let `default` = GenerationConfig()
    }

    // MARK: - Generation

    func generateSession(
        from audioFile: AudioFile,
        analysis: AnalysisResult,
        config: GenerationConfig = .default
    ) -> LightSession {
        Log.analysis.info("🎵 Generating session for: \(audioFile.filename)")
        let contentType = effectiveContentType(for: analysis)
        Log.analysis.info("📊 Content type: \(String(describing: contentType))")

        let rawMoments: [LightMoment]
        switch contentType {
        case .hypnosis:
            rawMoments = generateHypnosisSession(analysis: analysis, duration: audioFile.duration, config: config)
        case .meditation:
            rawMoments = generateMeditationSession(analysis: analysis, duration: audioFile.duration, config: config)
        case .music:
            rawMoments = generateMusicSession(analysis: analysis, duration: audioFile.duration, config: config)
        case .guidedImagery:
            rawMoments = generateGuidedImagerySession(analysis: analysis, duration: audioFile.duration, config: config)
        case .affirmations:
            rawMoments = generateAffirmationsSession(analysis: analysis, duration: audioFile.duration, config: config)
        case .eroticHypnosis:
            rawMoments = generateEroticHypnosisSession(analysis: analysis, duration: audioFile.duration, config: config)
        case .brainwave:
            rawMoments = generateBrainwaveSession(analysis: analysis, duration: audioFile.duration, config: config)
        case .asmr:
            rawMoments = generateASMRSession(analysis: analysis, duration: audioFile.duration, config: config)
        case .sleepHypnosis:
            rawMoments = generateSleepHypnosisSession(analysis: analysis, duration: audioFile.duration, config: config)
        case .unknown:
            rawMoments = generateGeneralSession(analysis: analysis, duration: audioFile.duration, config: config)
        }

        let optimized = LightScoreAlignmentOptimizer().optimize(
            rawMoments: rawMoments,
            duration: audioFile.duration,
            analysis: analysis,
            config: config
        )
        let session = LightSession(
            id: UUID(),
            session_name: "\(audioFile.displayName) — AI Light Session",
            duration_sec: audioFile.duration,
            light_score: optimized.moments,
            alignment_report: optimized.report
        )

        if optimized.report.meetsProductionTarget {
            Log.analysis.info("✅ Light score alignment: \(Int(optimized.report.overallScore * 100))%")
        } else {
            let report = optimized.report
            Log.analysis.info("⚠️ Light score alignment below target after \(optimized.iterationCount) repair pass(es): \(Int(report.overallScore * 100))% [phase=\(Int(report.phaseFrequencyScore * 100)) boundary=\(Int(report.boundaryScore * 100)) depth=\(Int(report.depthCorrelationScore * 100)) pause=\(Int(report.pauseResponseScore * 100)) structural=\(Int(report.structuralScore * 100))]")
        }

        return session
    }

    func effectiveContentType(for analysis: AnalysisResult) -> AudioContentType {
        guard !analysis.contentType.isHypnosisLike else { return analysis.contentType }
        guard analysis.contentType != .music, analysis.contentType != .brainwave else {
            return analysis.contentType
        }
        guard let phases = analysis.hypnosisMetadata?.phases, phases.count >= 2 else {
            return analysis.contentType
        }

        let canonicalPhases = Set(phases.map { $0.phase.labelingPhase })
        let hasTranceWork = canonicalPhases.contains(.deepening)
            || canonicalPhases.contains(.suggestions)
            || canonicalPhases.contains(.brainwashing)
        return canonicalPhases.contains(.induction) && hasTranceWork
            ? .hypnosis
            : analysis.contentType
    }

    // MARK: - Emergence Guard
    //
    // Ensures no session ends below 10 Hz without a proper ramp back.
    // Abrupt session endings at theta cause disorientation.

    func ensureEmergence(
        moments: inout [LightMoment],
        duration: TimeInterval,
        config: GenerationConfig
    ) {
        guard let lastMoment = moments.last, lastMoment.frequency < 10.0 else { return }

        let rampDuration = min(
            duration - lastMoment.time,
            max(30.0, (10.0 - lastMoment.frequency) * 10.0)
        )
        let step = rampDuration / 3.0
        let startTime = lastMoment.time
        let mul = config.intensityMultiplier

        moments.append(LightMoment(
            time: startTime + step,
            frequency: lastMoment.frequency + 2.0,
            intensity: 0.35 * mul,
            waveform: .sine,
            color_temperature: 3000))
        moments.append(LightMoment(
            time: startTime + step * 2,
            frequency: lastMoment.frequency + 4.0,
            intensity: 0.28 * mul,
            waveform: .sine,
            color_temperature: 3800))
        moments.append(LightMoment(
            time: duration,
            frequency: 12.0,
            intensity: 0.22 * mul,
            waveform: .sine,
            color_temperature: 4500))
    }

    // MARK: - Smooth Transitions

    func smoothTransitions(moments: inout [LightMoment], smoothness: Double) {
        guard moments.count > 1 else { return }

        var smoothed: [LightMoment] = [moments[0]]

        for idx in 1..<moments.count {
            let prev = moments[idx - 1]
            let curr = moments[idx]
            let timeDiff = curr.time - prev.time

            if timeDiff > 8.0 {
                let freqDiff = abs(curr.frequency - prev.frequency)
                let ampDiff = abs(curr.intensity - prev.intensity)

                if freqDiff > 2.0 || ampDiff > 0.2 {
                    let interpCount = max(1, Int(smoothness * 4.0))
                    for stepIndex in 1...interpCount {
                        let progress = Double(stepIndex) / Double(interpCount + 1)
                        let interpTime = prev.time + timeDiff * progress
                        let interpFreq = prev.frequency + (curr.frequency - prev.frequency) * progress
                        let interpAmp = prev.intensity + (curr.intensity - prev.intensity) * progress
                        let interpColorTemp: Double?
                        if let prevK = prev.color_temperature, let currK = curr.color_temperature {
                            interpColorTemp = prevK + (currK - prevK) * progress
                        } else {
                            interpColorTemp = prev.color_temperature ?? curr.color_temperature
                        }
                        smoothed.append(LightMoment(
                            time: interpTime,
                            frequency: interpFreq,
                            intensity: interpAmp,
                            waveform: prev.waveform,
                            color_temperature: interpColorTemp))
                    }
                }
            }
            smoothed.append(curr)
        }

        moments = smoothed
    }

    // MARK: - Convenience Moment Builder

    func moment(
        time: Double,
        freq: Double,
        amp: Double,
        waveform: WaveformType,
        ramp: Double? = nil,
        colorTemp: Double? = nil,
        bilateral: Bool? = nil,
        bilateralTransition: Double? = nil
    ) -> LightMoment {
        LightMoment(
            time: time,
            frequency: freq,
            intensity: max(0, min(1, amp)),
            waveform: waveform,
            ramp_duration: ramp,
            bilateral: bilateral,
            bilateral_transition_duration: bilateralTransition,
            color_temperature: colorTemp
        )
    }
}
