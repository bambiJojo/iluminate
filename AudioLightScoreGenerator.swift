//
//  AudioLightScoreGenerator.swift
//  Ilumionate
//
//  Generates synchronized light sessions from analyzed audio files
//
//  This generator creates hypnotically-optimized light patterns that:
//  - Use bilateral stimulation for confusion/deepening techniques
//  - Apply theta frequencies (4-7Hz) during deep trance states
//  - Vary waveforms based on hypnotic technique type
//  - Create intensity curves that follow hypnotic depth progression
//  - Use color temperature to enhance phase transitions
//

import Foundation

/// Generates LightScore sessions synchronized to analyzed audio
@MainActor
class AudioLightScoreGenerator {

    /// Generate a light session from analyzed audio
    func generateLightScore(
        from audioFile: AudioFile,
        analysis: AnalysisResult,
        transcription: AudioTranscriptionResult
    ) -> LightSession {

        print("🎨 Generating enhanced hypnotic light score for: \(audioFile.filename)")
        print("📊 Analysis: \(analysis.mood.rawValue), Energy: \(analysis.energyLevel)")
        print("🎯 Frequency range: \(analysis.suggestedFrequencyRange)")

        if let hypnosis = analysis.hypnosisMetadata {
            print("🧠 Hypnosis detected: \(hypnosis.phases.count) phases, \(hypnosis.detectedTechniques.count) techniques")
        }

        // Create session name based on audio file
        let sessionName = generateSessionName(from: audioFile, analysis: analysis)

        // Generate light moments based on analysis
        let lightMoments = generateLightMoments(
            duration: audioFile.duration,
            analysis: analysis,
            transcription: transcription
        )

        print("✨ Generated \(lightMoments.count) light moments")

        return LightSession(
            session_name: sessionName,
            duration_sec: audioFile.duration,
            light_score: lightMoments
        )
    }

    // MARK: - Private Methods

    private func generateSessionName(from audioFile: AudioFile, analysis: AnalysisResult) -> String {
        let baseName = audioFile.filename
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".m4a", with: "")
            .replacingOccurrences(of: ".wav", with: "")

        return "\(baseName) - Light Session"
    }

    private func generateLightMoments(
        duration: TimeInterval,
        analysis: AnalysisResult,
        transcription: AudioTranscriptionResult
    ) -> [LightMoment] {

        var moments: [LightMoment] = []

        // 1. Add opening moment at the start
        moments.append(createOpeningMoment(analysis: analysis))

        // 2. Add moments for key transitions (based on analysis key moments)
        for keyMoment in analysis.keyMoments {
            if let lightMoment = createMomentFromKeyMoment(keyMoment, analysis: analysis) {
                moments.append(lightMoment)
            }
        }

        // 3. Add moments for hypnosis phase transitions (if available)
        if let hypnosisMetadata = analysis.hypnosisMetadata,
           let temporal = analysis.temporalAnalysis {
            moments.append(contentsOf: createHypnosisPhaseMoments(
                metadata: hypnosisMetadata,
                temporal: temporal,
                analysis: analysis
            ))

            // 3b. Add technique-specific moments (confusion, fractionation, etc.)
            moments.append(contentsOf: createTechniqueMoments(
                metadata: hypnosisMetadata,
                analysis: analysis
            ))
        }

        // 4. Add intermediate moments for smooth progression
        moments.append(contentsOf: createIntermediateMoments(
            duration: duration,
            existingMoments: moments,
            analysis: analysis
        ))

        // 5. Add closing moment
        moments.append(createClosingMoment(duration: duration, analysis: analysis))

        // Sort by time and return
        return moments.sorted { $0.time < $1.time }
    }

    private func createOpeningMoment(analysis: AnalysisResult) -> LightMoment {
        // Start in alert but relaxed alpha range
        // This helps establish baseline before induction begins
        let startFrequency = 10.0 // Alpha frequency

        return LightMoment(
            time: 0,
            frequency: startFrequency,
            intensity: 0.15, // Very gentle start
            waveform: WaveformType.sine,
            ramp_duration: 8.0, // Slow, gentle entry
            bilateral: false,
            bilateral_transition_duration: 2.0,
            color_temperature: 5000 // Neutral white at start
        )
    }

    private func createMomentFromKeyMoment(_ keyMoment: KeyMoment, analysis: AnalysisResult) -> LightMoment? {
        let intensity: Double
        let frequency: Double
        let waveform: WaveformType
        let rampDuration: Double
        let bilateral: Bool
        let bilateralTransition: Double
        let colorTemp: Double?

        switch keyMoment.action {
        case .deepen:
            intensity = 0.9
            frequency = 4.5  // Deep theta
            waveform = .softPulse
            rampDuration = 25.0
            bilateral = false
            bilateralTransition = 4.0
            colorTemp = 2300  // Warm amber
        case .energize:
            intensity = 0.6
            frequency = 12.0 // Alpha/beta border
            waveform = .softPulse
            rampDuration = 8.0
            bilateral = false
            bilateralTransition = 2.0
            colorTemp = 4500
        case .reduceIntensity:
            intensity = 0.7
            frequency = 6.0  // Theta
            waveform = .sine
            rampDuration = 15.0
            bilateral = false
            bilateralTransition = 3.0
            colorTemp = 2800
        case .increaseIntensity:
            intensity = 0.85
            frequency = 5.0  // Mid theta — receptive state
            waveform = .sine
            rampDuration = 12.0
            bilateral = false
            bilateralTransition = 3.0
            colorTemp = 2500
        case .warm:
            intensity = 0.65
            frequency = 7.0  // Theta-alpha border
            waveform = .sine
            rampDuration = 12.0
            bilateral = false
            bilateralTransition = 3.0
            colorTemp = 2800
        case .cool:
            intensity = 0.55
            frequency = 10.0 // Alpha
            waveform = .sine
            rampDuration = 8.0
            bilateral = false
            bilateralTransition = 2.0
            colorTemp = 5000
        }

        return LightMoment(
            time: keyMoment.time,
            frequency: frequency,
            intensity: intensity,
            waveform: waveform,
            ramp_duration: rampDuration,
            bilateral: bilateral,
            bilateral_transition_duration: bilateralTransition,
            color_temperature: colorTemp
        )
    }

    private func createHypnosisPhaseMoments(
        metadata: HypnosisMetadata,
        temporal: TemporalAnalysis,
        analysis: AnalysisResult
    ) -> [LightMoment] {

        var moments: [LightMoment] = []

        // Use phase segments from metadata to create light moments
        for phaseSegment in metadata.phases {
            let lightMoment = createMomentForPhase(
                phase: phaseSegment,
                analysis: analysis,
                metadata: metadata
            )
            moments.append(lightMoment)
        }

        return moments
    }

    private func createMomentForPhase(
        phase: PhaseSegment,
        analysis: AnalysisResult,
        metadata: HypnosisMetadata
    ) -> LightMoment {

        let frequency: Double
        let intensity: Double
        let waveform: WaveformType
        let rampDuration: Double
        let bilateral: Bool
        let bilateralTransition: Double
        let colorTemp: Double?

        switch phase.phase {
        case .preTalk:
            // Alert, attentive - alpha range
            frequency = 10.0
            intensity = 0.25
            waveform = .sine
            rampDuration = 8.0
            bilateral = false
            bilateralTransition = 2.0
            colorTemp = 5000 // Neutral white

        case .induction:
            // Beginning relaxation - alpha/theta border
            frequency = 8.5
            intensity = 0.45
            waveform = .sine
            rampDuration = 20.0 // Slow, gentle transition
            bilateral = false
            bilateralTransition = 3.0
            colorTemp = 3500 // Warm white

        case .deepening:
            // Deep theta - this is where the magic happens
            frequency = 5.5 // Deep theta (4-7Hz range)
            intensity = 0.85 // Strong, deep entrainment
            waveform = .softPulse // Pulsing for deeper effect
            rampDuration = 30.0 // Very slow descent
            bilateral = true // Enable bilateral for deepening
            bilateralTransition = 5.0 // Slow bilateral fade-in
            colorTemp = 2500 // Warm amber - calming

        case .therapy, .suggestions:
            // Deepest state - low theta
            frequency = 4.5 // Very deep theta
            intensity = 0.95 // Maximum intensity for deepest trance
            waveform = .sine // Pure, smooth for suggestion acceptance
            rampDuration = 20.0
            bilateral = true // Keep bilateral active
            bilateralTransition = 4.0
            colorTemp = 2200 // Deep warm - maximum relaxation

        case .conditioning:
            // Anchoring state - theta with slight lift
            frequency = 5.0
            intensity = 0.88
            waveform = .softPulse // Pulsing to "install" suggestions
            rampDuration = 25.0
            bilateral = true
            bilateralTransition = 4.0
            colorTemp = 2800 // Still warm

        case .emergence:
            // Rising back up - theta to alpha
            frequency = 10.0 // Back to alpha
            intensity = 0.4 // Gentle
            waveform = .sine
            rampDuration = 15.0 // Gradual awakening
            bilateral = false // Turn off bilateral
            bilateralTransition = 6.0 // Slow bilateral fade-out
            colorTemp = 4500 // Return to neutral

        case .transitional:
            // Smooth bridge between phases
            frequency = 7.0 // Mid theta-alpha
            intensity = 0.65
            waveform = .sine
            rampDuration = 15.0
            bilateral = false
            bilateralTransition = 3.0
            colorTemp = 3500
        }

        return LightMoment(
            time: phase.startTime,
            frequency: frequency,
            intensity: intensity,
            waveform: waveform,
            ramp_duration: rampDuration,
            bilateral: bilateral,
            bilateral_transition_duration: bilateralTransition,
            color_temperature: colorTemp
        )
    }

    /// Create light moments for specific hypnotic techniques detected in the audio
    private func createTechniqueMoments(
        metadata: HypnosisMetadata,
        analysis: AnalysisResult
    ) -> [LightMoment] {

        var moments: [LightMoment] = []

        for technique in metadata.detectedTechniques {
            let techniqueLower = technique.technique.lowercased()
            let description = technique.description.lowercased()

            // Confusion techniques - rapid bilateral alternation
            if techniqueLower.contains("confusion") ||
               description.contains("confusion") ||
               techniqueLower.contains("interrupt") ||
               techniqueLower.contains("overload") {

                print("🌀 Detected confusion technique at \(Int(technique.timestamp))s")
                moments.append(LightMoment(
                    time: technique.timestamp,
                    frequency: 12.0, // Higher frequency for mental activity
                    intensity: 0.75,
                    waveform: .triangle, // Sharp, distinct for confusion effect
                    ramp_duration: 2.0, // Quick onset
                    bilateral: true, // CRITICAL: bilateral for confusion
                    bilateral_transition_duration: 0.5, // Rapid bilateral activation
                    color_temperature: 4000
                ))
            }

            // Fractionation - rhythmic deepening/lightening
            else if techniqueLower.contains("fraction") ||
                    description.contains("up and down") ||
                    description.contains("deeper and back") {

                print("📊 Detected fractionation at \(Int(technique.timestamp))s")
                // Create a series of 3-4 moments for the fractionation pattern
                let baseTime = technique.timestamp

                // Down
                moments.append(LightMoment(
                    time: baseTime,
                    frequency: 6.0,
                    intensity: 0.8,
                    waveform: .softPulse,
                    ramp_duration: 8.0,
                    bilateral: false,
                    color_temperature: 2800
                ))

                // Up
                moments.append(LightMoment(
                    time: baseTime + 15,
                    frequency: 10.0,
                    intensity: 0.4,
                    waveform: .sine,
                    ramp_duration: 5.0,
                    bilateral: false,
                    color_temperature: 3800
                ))

                // Deeper down
                moments.append(LightMoment(
                    time: baseTime + 25,
                    frequency: 4.5,
                    intensity: 0.9,
                    waveform: .softPulse,
                    ramp_duration: 10.0,
                    bilateral: false,
                    color_temperature: 2500
                ))
            }

            // EMDR / Bilateral stimulation
            else if techniqueLower.contains("emdr") ||
                    techniqueLower.contains("bilateral") ||
                    techniqueLower.contains("alternating") ||
                    techniqueLower.contains("left and right") {

                print("👁️ Detected bilateral technique at \(Int(technique.timestamp))s")
                moments.append(LightMoment(
                    time: technique.timestamp,
                    frequency: 7.0, // Mid theta
                    intensity: 0.8,
                    waveform: .sine,
                    ramp_duration: 5.0,
                    bilateral: true,
                    bilateral_transition_duration: 1.0, // Quick bilateral activation
                    color_temperature: 3200
                ))
            }

            // Progressive relaxation - slow descent
            else if techniqueLower.contains("progressive") ||
                    techniqueLower.contains("body scan") ||
                    description.contains("relax") && description.contains("muscle") {

                print("🧘 Detected progressive relaxation at \(Int(technique.timestamp))s")
                moments.append(LightMoment(
                    time: technique.timestamp,
                    frequency: 7.0,
                    intensity: 0.6,
                    waveform: .sine,
                    ramp_duration: 30.0, // Very slow descent
                    bilateral: false,
                    color_temperature: 2700
                ))
            }

            // Rapid induction - quick drop
            else if techniqueLower.contains("rapid") ||
                    techniqueLower.contains("instant") ||
                    techniqueLower.contains("shock") {

                print("⚡ Detected rapid induction at \(Int(technique.timestamp))s")
                moments.append(LightMoment(
                    time: technique.timestamp,
                    frequency: 5.0,
                    intensity: 0.95,
                    waveform: .triangle, // Sharp for shock effect
                    ramp_duration: 1.0, // Very fast drop
                    bilateral: true, // Bilateral for disorientation
                    bilateral_transition_duration: 0.3,
                    color_temperature: 2300
                ))
            }

            // Deepening anchors (counting down, stairs, etc.)
            else if techniqueLower.contains("count") ||
                    techniqueLower.contains("stair") ||
                    techniqueLower.contains("elevator") ||
                    techniqueLower.contains("going down") {

                print("🔽 Detected deepening anchor at \(Int(technique.timestamp))s")
                moments.append(LightMoment(
                    time: technique.timestamp,
                    frequency: 5.0,
                    intensity: 0.85,
                    waveform: .softPulse, // Pulsing rhythm with counting
                    ramp_duration: 20.0,
                    bilateral: false,
                    color_temperature: 2400
                ))
            }

            // Visualization / Guided imagery
            else if techniqueLower.contains("visual") ||
                    techniqueLower.contains("imagine") ||
                    techniqueLower.contains("picture") {

                print("🎨 Detected visualization at \(Int(technique.timestamp))s")
                moments.append(LightMoment(
                    time: technique.timestamp,
                    frequency: 6.5, // Theta for imagery
                    intensity: 0.7,
                    waveform: .sine,
                    ramp_duration: 12.0,
                    bilateral: false,
                    color_temperature: 3000 // Slightly warmer for comfort
                ))
            }
        }

        return moments
    }

    private func createIntermediateMoments(
        duration: TimeInterval,
        existingMoments: [LightMoment],
        analysis: AnalysisResult
    ) -> [LightMoment] {

        var moments: [LightMoment] = []
        let sortedExisting = existingMoments.sorted { $0.time < $1.time }

        // Add intermediate moments between large time gaps
        for i in 0..<(sortedExisting.count - 1) {
            let current = sortedExisting[i]
            let next = sortedExisting[i + 1]
            let gap = next.time - current.time

            // If gap is larger than 2 minutes, add intermediate moments
            if gap > 120 {
                let numIntermediateMoments = Int(gap / 120) // One every 2 minutes

                for j in 1...numIntermediateMoments {
                    let progress = Double(j) / Double(numIntermediateMoments + 1)
                    let time = current.time + (gap * progress)

                    // Interpolate parameters
                    let frequency = current.frequency + (next.frequency - current.frequency) * progress
                    let intensity = current.intensity + (next.intensity - current.intensity) * progress

                    moments.append(LightMoment(
                        time: time,
                        frequency: frequency,
                        intensity: intensity,
                        waveform: current.waveform,
                        ramp_duration: 15.0,
                        bilateral: current.bilateral,
                        color_temperature: analysis.suggestedColorTemperature
                    ))
                }
            }
        }

        return moments
    }

    private func createClosingMoment(duration: TimeInterval, analysis: AnalysisResult) -> LightMoment {
        // End with alert alpha, ready to return to full awareness
        // This supports the emergence phase
        let endFrequency = 12.0 // High alpha, approaching beta

        return LightMoment(
            time: max(duration - 20, duration * 0.95), // Near the end
            frequency: endFrequency,
            intensity: 0.25, // Gentle, not jarring
            waveform: .sine,
            ramp_duration: 8.0,
            bilateral: false,
            bilateral_transition_duration: 3.0, // Ensure bilateral is off
            color_temperature: 5500 // Cool white - alertness
        )
    }

    private func shouldUseBilateral(for keyMoment: KeyMoment, analysis: AnalysisResult) -> Bool {
        // Check if hypnosis metadata has bilateral techniques
        if let hypnosisMetadata = analysis.hypnosisMetadata {
            let hasBilateral = hypnosisMetadata.detectedTechniques.contains { technique in
                technique.technique.lowercased().contains("bilateral") ||
                technique.technique.lowercased().contains("alternating") ||
                technique.technique.lowercased().contains("emdr")
            }
            if hasBilateral {
                return true
            }
        }

        // Or if the key moment description mentions bilateral/alternating
        let description = keyMoment.description.lowercased()
        return description.contains("bilateral") ||
               description.contains("alternating") ||
               description.contains("emdr")
    }
}
