//
//  SessionGenerator.swift
//  Ilumionate
//
//  Created by AI Assistant on 2/24/26.
//

import Foundation

/// Generates synchronized light therapy sessions from audio analysis
@MainActor
class SessionGenerator {

    // MARK: - Configuration

    struct GenerationConfig {
        var intensityMultiplier: Double = 1.0 // Overall intensity adjustment
        var minFrequency: Double = 0.5 // Minimum allowed frequency (Hz)
        var maxFrequency: Double = 30.0 // Maximum allowed frequency (Hz)
        var transitionSmoothness: Double = 0.8 // 0.0 = sharp, 1.0 = very smooth
        var colorTemperatureOverride: Double? // Optional override
        var bilateralMode: Bool = false // Enable bilateral stimulation

        nonisolated static let `default` = GenerationConfig()
    }

    // MARK: - Generation

    /// Generate a complete LightSession from analyzed audio
    func generateSession(
        from audioFile: AudioFile,
        analysis: AnalysisResult,
        config: GenerationConfig = .default
    ) -> LightSession {

        print("🎵 Generating session for: \(audioFile.filename)")
        print("📊 Content type: \(analysis.contentType)")

        // Choose generation strategy based on content type
        let moments: [LightMoment]

        switch analysis.contentType {
        case .hypnosis:
            moments = generateHypnosisSession(analysis: analysis, duration: audioFile.duration, config: config)

        case .meditation:
            moments = generateMeditationSession(analysis: analysis, duration: audioFile.duration, config: config)

        case .music, .guidedImagery, .affirmations, .unknown:
            moments = generateGeneralSession(analysis: analysis, duration: audioFile.duration, config: config)
        }

        // Create session metadata
        let sessionName = "\(audioFile.filename.replacingOccurrences(of: ".m4a", with: "").replacingOccurrences(of: ".mp3", with: "")) - AI Generated"

        return LightSession(
            id: UUID(),
            session_name: sessionName,
            duration_sec: audioFile.duration,
            light_score: moments
        )
    }

    // MARK: - Hypnosis Session Generation

    private func generateHypnosisSession(
        analysis: AnalysisResult,
        duration: TimeInterval,
        config: GenerationConfig
    ) -> [LightMoment] {

        guard let hypnosis = analysis.hypnosisMetadata else {
            print("⚠️ No hypnosis metadata, falling back to general generation")
            return generateGeneralSession(analysis: analysis, duration: duration, config: config)
        }

        print("🎯 Generating hypnosis session with \(hypnosis.phases.count) phases")

        var moments: [LightMoment] = []

        // Generate moments for each phase
        for phase in hypnosis.phases {
            let phaseMoments = generateMomentsForPhase(
                phase: phase,
                analysis: analysis,
                config: config
            )
            moments.append(contentsOf: phaseMoments)
        }

        // Add key moment transitions
        if let temporal = analysis.temporalAnalysis {
            addTemporalTransitions(to: &moments, temporal: temporal, config: config)
        }

        // Ensure smooth transitions
        smoothTransitions(moments: &moments, smoothness: config.transitionSmoothness)

        // Sort by time
        moments.sort { $0.time < $1.time }

        print("✅ Generated \(moments.count) light moments")
        return moments
    }

    private func generateMomentsForPhase(
        phase: PhaseSegment,
        analysis: AnalysisResult,
        config: GenerationConfig
    ) -> [LightMoment] {

        var moments: [LightMoment] = []
        let duration = phase.endTime - phase.startTime

        // Determine frequency range based on phase and trance depth
        let (startFreq, endFreq) = frequencyRangeForPhase(
            phase: phase.phase,
            tranceDepth: phase.tranceDepthEstimate,
            config: config
        )

        // Determine intensity based on phase
        let intensity = intensityForPhase(
            phase: phase.phase,
            tranceDepth: phase.tranceDepthEstimate,
            config: config
        )

        // Color temperature
        let colorTemp = config.colorTemperatureOverride ?? colorTemperatureForPhase(phase.phase)

        // Create start moment
        moments.append(LightMoment(
            time: phase.startTime,
            frequency: startFreq,
            intensity: intensity,
            waveform: waveformTypeForPhase(phase.phase),
            color_temperature: colorTemp
        ))

        // Create mid-phase moments for smooth progression
        let numMidPoints = max(1, Int(duration / 30.0)) // One per 30 seconds
        for pointIndex in 1...numMidPoints {
            let progress = Double(pointIndex) / Double(numMidPoints + 1)
            let time = phase.startTime + (duration * progress)
            let freq = startFreq + (endFreq - startFreq) * progress

            moments.append(LightMoment(
                time: time,
                frequency: freq,
                intensity: intensity,
                waveform: waveformTypeForPhase(phase.phase),
                color_temperature: colorTemp
            ))
        }

        // Create end moment
        moments.append(LightMoment(
            time: phase.endTime,
            frequency: endFreq,
            intensity: intensity,
            waveform: waveformTypeForPhase(phase.phase),
            color_temperature: colorTemp
        ))

        return moments
    }

    // MARK: - Meditation Session Generation

    private func generateMeditationSession(
        analysis: AnalysisResult,
        duration: TimeInterval,
        config: GenerationConfig
    ) -> [LightMoment] {

        print("🧘 Generating meditation session")

        var moments: [LightMoment] = []

        // Start with alert state
        moments.append(LightMoment(
            time: 0,
            frequency: 10.0, // Alpha
            intensity: 0.3 * config.intensityMultiplier,
            waveform: .sine,
            color_temperature: 3000
        ))

        // Gradual descent into deeper meditation
        let numSegments = max(3, Int(duration / 120.0)) // Segments every 2 minutes
        for segmentIndex in 1..<numSegments {
            let progress = Double(segmentIndex) / Double(numSegments)
            let time = duration * progress
            let frequency = 10.0 - (4.0 * progress) // 10Hz → 6Hz (alpha to theta)
            let intensity = 0.3 + (0.2 * progress) // Gradually increase

            moments.append(LightMoment(
                time: time,
                frequency: frequency,
                intensity: intensity * config.intensityMultiplier,
                waveform: .sine,
                color_temperature: 2500
            ))
        }

        // End moment
        moments.append(LightMoment(
            time: duration,
            frequency: 6.0, // Deep theta
            intensity: 0.5 * config.intensityMultiplier,
            waveform: .sine,
            color_temperature: 2200
        ))

        // Add key moments from analysis
        for keyMoment in analysis.keyMoments {
            if let adjustment = adjustmentForKeyMoment(keyMoment, config: config) {
                moments.append(adjustment)
            }
        }

        moments.sort { $0.time < $1.time }
        return moments
    }

    // MARK: - General Session Generation

    private func generateGeneralSession(
        analysis: AnalysisResult,
        duration: TimeInterval,
        config: GenerationConfig
    ) -> [LightMoment] {

        print("🎼 Generating general session")

        var moments: [LightMoment] = []

        // Use suggested frequency range from analysis
        let freqRange = analysis.suggestedFrequencyRange
        let baseIntensity = analysis.suggestedIntensity * config.intensityMultiplier
        let colorTemp = config.colorTemperatureOverride ?? analysis.suggestedColorTemperature ?? 3000

        // Start
        moments.append(LightMoment(
            time: 0,
            frequency: freqRange.lowerBound,
            intensity: baseIntensity,
            waveform: .sine,
            color_temperature: colorTemp
        ))

        // Key moments
        for keyMoment in analysis.keyMoments {
            if let adjustment = adjustmentForKeyMoment(keyMoment, config: config) {
                moments.append(adjustment)
            }
        }

        // End
        moments.append(LightMoment(
            time: duration,
            frequency: freqRange.upperBound,
            intensity: baseIntensity,
            waveform: .sine,
            color_temperature: colorTemp
        ))

        moments.sort { $0.time < $1.time }
        return moments
    }

    // MARK: - Helper Methods

    private func frequencyRangeForPhase(
        phase: HypnosisMetadata.Phase,
        tranceDepth: Double,
        config: GenerationConfig
    ) -> (start: Double, end: Double) {

        switch phase {
        case .preTalk:
            return (12.0, 10.0) // Beta to Alpha

        case .induction:
            return (10.0, 7.0) // Alpha to Theta

        case .deepening:
            let deepFreq = 4.0 + (3.0 * (1.0 - tranceDepth)) // Deeper = lower freq
            return (7.0, deepFreq)

        case .therapy, .suggestions:
            let therapeuticFreq = 5.0 + (2.0 * (1.0 - tranceDepth))
            return (therapeuticFreq, therapeuticFreq) // Maintain steady

        case .conditioning:
            return (6.0, 8.0) // Slight increase for post-hypnotic work

        case .emergence:
            return (8.0, 12.0) // Theta back to Beta

        case .transitional:
            return (7.0, 7.0) // Maintain current state
        }
    }

    private func intensityForPhase(
        phase: HypnosisMetadata.Phase,
        tranceDepth: Double,
        config: GenerationConfig
    ) -> Double {

        let baseIntensity: Double

        switch phase {
        case .preTalk:
            baseIntensity = 0.2
        case .induction:
            baseIntensity = 0.3
        case .deepening:
            baseIntensity = 0.4 + (0.2 * tranceDepth)
        case .therapy, .suggestions:
            baseIntensity = 0.5 + (0.3 * tranceDepth)
        case .conditioning:
            baseIntensity = 0.4
        case .emergence:
            baseIntensity = 0.3
        case .transitional:
            baseIntensity = 0.4
        }

        return min(1.0, baseIntensity * config.intensityMultiplier)
    }

    private func colorTemperatureForPhase(_ phase: HypnosisMetadata.Phase) -> Double {
        switch phase {
        case .preTalk:
            return 4000 // Neutral
        case .induction:
            return 3000 // Warm
        case .deepening:
            return 2500 // Warmer
        case .therapy, .suggestions:
            return 2200 // Very warm
        case .conditioning:
            return 2800 // Warm
        case .emergence:
            return 4500 // Cool (alerting)
        case .transitional:
            return 3000
        }
    }

    private func waveformTypeForPhase(_ phase: HypnosisMetadata.Phase) -> WaveformType {
        switch phase {
        case .preTalk, .emergence:
            return .sine
        case .induction:
            return .sine
        case .deepening:
            return .sine // Could use .triangle for deeper effect
        case .therapy, .suggestions:
            return .sine
        case .conditioning:
            return .sine
        case .transitional:
            return .sine
        }
    }

    private func adjustmentForKeyMoment(_ keyMoment: KeyMoment, config: GenerationConfig) -> LightMoment? {
        // Parse suggested action
        let action = keyMoment.suggestedAction.lowercased()

        var frequency: Double = 7.0
        var intensity: Double = 0.5
        var colorTemp: Double = 3000

        if action.contains("increase intensity") {
            intensity = 0.7
        } else if action.contains("decrease intensity") {
            intensity = 0.3
        }

        if action.contains("warmer") || action.contains("warm") {
            colorTemp = 2500
        } else if action.contains("cooler") || action.contains("cool") {
            colorTemp = 4500
        }

        if action.contains("faster") || action.contains("energize") {
            frequency = 12.0
        } else if action.contains("slower") || action.contains("deepen") {
            frequency = 5.0
        }

        return LightMoment(
            time: keyMoment.time,
            frequency: frequency,
            intensity: intensity * config.intensityMultiplier,
            waveform: .sine,
            color_temperature: colorTemp
        )
    }

    private func addTemporalTransitions(to moments: inout [LightMoment], temporal: TemporalAnalysis, config: GenerationConfig) {
        // Add moments based on temporal curves
        let interval = temporal.samplingInterval

        for (index, depth) in temporal.tranceDepthCurve.enumerated() {
            let time = Double(index) * interval
            let frequency = 12.0 - (depth * 8.0) // Map depth to frequency
            let intensity = 0.3 + (depth * 0.4)

            moments.append(LightMoment(
                time: time,
                frequency: frequency,
                intensity: intensity * config.intensityMultiplier,
                waveform: .sine,
                color_temperature: 2500
            ))
        }
    }

    private func smoothTransitions(moments: inout [LightMoment], smoothness: Double) {
        // Ensure gradual transitions between moments
        guard moments.count > 1 else { return }

        var smoothedMoments: [LightMoment] = [moments[0]]

        for momentIndex in 1..<moments.count {
            let prev = moments[momentIndex - 1]
            let current = moments[momentIndex]
            let timeDiff = current.time - prev.time

            // If time gap is large and changes are abrupt, add intermediate moments
            if timeDiff > 10.0 {
                let freqDiff = abs(current.frequency - prev.frequency)
                let intensityDiff = abs(current.intensity - prev.intensity)

                if freqDiff > 3.0 || intensityDiff > 0.3 {
                    let numIntermediate = Int(smoothness * 3.0)
                    for intermediateIndex in 1...numIntermediate {
                        let progress = Double(intermediateIndex) / Double(numIntermediate + 1)
                        let intermediateTime = prev.time + (timeDiff * progress)
                        let intermediateFreq = prev.frequency + ((current.frequency - prev.frequency) * progress)
                        let intermediateIntensity = prev.intensity + ((current.intensity - prev.intensity) * progress)
                        let intermediateTemp: Double?
                        if let prevTemp = prev.color_temperature, let currTemp = current.color_temperature {
                            intermediateTemp = prevTemp + ((currTemp - prevTemp) * progress)
                        } else {
                            intermediateTemp = nil
                        }

                        smoothedMoments.append(LightMoment(
                            time: intermediateTime,
                            frequency: intermediateFreq,
                            intensity: intermediateIntensity,
                            waveform: prev.waveform,
                            color_temperature: intermediateTemp
                        ))
                    }
                }
            }

            smoothedMoments.append(current)
        }

        moments = smoothedMoments
    }
}
