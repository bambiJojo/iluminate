//
//  SessionGeneratorTests.swift
//  IlumionateTests
//
//  Tests for Step 3.3: SessionGenerator structural invariants.
//  Covers frequency mapping, phase-to-parameter helpers, and the clamp utility.
//

import Testing
import Foundation
@testable import Ilumionate

@Suite("Full-screen flash ceiling")
@MainActor
struct LightSafetyTests {
    @Test("Requested rates never exceed three visible flashes per second")
    func clampsRequestedRates() {
        #expect(LightSafety.clampFlashHz(0.5) == 0.5)
        #expect(LightSafety.clampFlashHz(3.0) == 3.0)
        #expect(LightSafety.clampFlashHz(10.0) == 3.0)
        #expect(LightSafety.clampFlashHz(40.0) == 3.0)
    }

    @Test("Invalid and non-positive input cannot destabilize the oscillator")
    func normalizesInvalidRates() {
        #expect(LightSafety.clampFlashHz(.infinity) == LightSafety.maxFlashHz)
        #expect(LightSafety.clampFlashHz(.nan) == LightSafety.maxFlashHz)
        #expect(LightSafety.clampFlashHz(0) == 0.1)
        #expect(LightSafety.clampFlashHz(-10) == 0.1)
    }

    @Test("Both full-screen rendering engines enforce the ceiling at input")
    func enginesEnforceCeiling() {
        let engine = LightEngine()
        engine.targetFrequency = 40
        #expect(engine.targetFrequency == LightSafety.maxFlashHz)

        let controller = FlashController(
            frequency: 40,
            intensity: 1,
            pattern: .square
        )
        #expect(controller.frequency == LightSafety.maxFlashHz)
    }
}

// MARK: - FrequencyRangeForPhase

@MainActor
struct FrequencyRangeForPhaseTests {

    @Test func allPhasesHaveValidRange() {
        let phases: [HypnosisMetadata.Phase] = [
            .preTalk, .induction, .deepening, .therapy,
            .suggestions, .conditioning, .emergence, .transitional
        ]
        for phase in phases {
            let range = LightScorePhaseTargeting.frequencyRange(for: phase)
            #expect(range.lowerBound < range.upperBound,
                "\(phase.rawValue): lowerBound must be < upperBound")
            #expect(range.lowerBound >= 0.5, "\(phase.rawValue) lower bound below 0.5 Hz")
            #expect(
                range.upperBound <= LightSafety.maxFlashHz,
                "\(phase.rawValue) upper bound exceeds the full-screen flash ceiling"
            )
        }
    }

    @Test func quieterPhasesUseTheLowerPartOfTheVisualRange() {
        for phase in [HypnosisMetadata.Phase.therapy, .deepening] {
            let range = LightScorePhaseTargeting.frequencyRange(for: phase)
            #expect(range.upperBound <= 2.0)
        }
    }

    @Test func emergenceUsesTheFastPartOfTheVisualRange() {
        let range = LightScorePhaseTargeting.frequencyRange(for: .emergence)
        #expect(range.lowerBound >= 2.0)
        #expect(range.upperBound <= LightSafety.maxFlashHz)
    }
}

// MARK: - targetFrequencyForPhase

@MainActor
struct TargetFrequencyForPhaseTests {

    private let config = SessionGenerator.GenerationConfig.default

    @Test func targetFrequencyIsWithinPhaseRange() {
        let phases: [HypnosisMetadata.Phase] = [
            .preTalk, .induction, .deepening, .therapy,
            .suggestions, .conditioning, .emergence, .transitional
        ]
        for phase in phases {
            let range = LightScorePhaseTargeting.frequencyRange(for: phase)
            let target = targetFrequency(for: phase, config: config)
            #expect(target >= range.lowerBound - 0.01,
                "\(phase.rawValue) target \(target) Hz below range lower \(range.lowerBound)")
            #expect(target <= range.upperBound + 0.01,
                "\(phase.rawValue) target \(target) Hz above range upper \(range.upperBound)")
        }
    }

    @Test func deepestPhaseHasLowestTarget() {
        let therapyFreq = targetFrequency(for: .therapy, config: config)
        let preTalkFreq = targetFrequency(for: .preTalk, config: config)
        #expect(therapyFreq < preTalkFreq,
            "therapy (\(therapyFreq) Hz) must be lower than pre_talk (\(preTalkFreq) Hz)")
    }

    @Test func configMaxClamps() {
        let tight = SessionGenerator.GenerationConfig(maxFrequency: 1.5)
        let target = targetFrequency(for: .preTalk, config: tight)
        #expect(target <= 1.5, "target must be clamped to config.maxFrequency")
    }

    private func targetFrequency(
        for phase: HypnosisMetadata.Phase,
        config: SessionGenerator.GenerationConfig
    ) -> Double {
        LightScorePhaseTargeting.targetFrequency(
            phase: phase,
            tranceDepth: LightScorePhaseTargeting.expectedDepth(for: phase),
            progress: 0,
            config: config
        )
    }
}

// MARK: - intensityForPhase

@MainActor
struct IntensityForPhaseTests {

    @Test func allIntensitiesInRange() {
        let phases: [HypnosisMetadata.Phase] = [
            .preTalk, .induction, .deepening, .therapy,
            .suggestions, .conditioning, .emergence, .transitional
        ]
        for phase in phases {
            let intensity = canonicalIntensity(for: phase)
            #expect(intensity >= 0.0 && intensity <= 1.0,
                "\(phase.rawValue) intensity \(intensity) out of [0, 1]")
        }
    }

    @Test func therapyIntensityIsLowest() {
        let therapy = canonicalIntensity(for: .therapy)
        let preTalk = canonicalIntensity(for: .preTalk)
        #expect(therapy < preTalk, "therapy must be dimmer than pre_talk")
    }

    private func canonicalIntensity(for phase: HypnosisMetadata.Phase) -> Double {
        LightScorePhaseTargeting.intensity(
            phase: phase,
            tranceDepth: LightScorePhaseTargeting.expectedDepth(for: phase),
            confidence: .high
        )
    }
}

// MARK: - colorTemperatureForPhase

@MainActor
struct ColorTemperatureForPhaseTests {

    @Test func deepStatesAreWarm() {
        for phase in [HypnosisMetadata.Phase.therapy, .deepening] {
            let kelvin = LightScorePhaseTargeting.colorTemperature(for: phase)
            #expect(kelvin <= 3000, "\(phase.rawValue) must be ≤3000K, got \(kelvin)K")
        }
    }

    @Test func emergenceIsCool() {
        let kelvin = LightScorePhaseTargeting.colorTemperature(for: .emergence)
        #expect(kelvin >= 4000, "emergence must be ≥4000K, got \(kelvin)K")
    }

    @Test func allTemperaturesInValidRange() {
        let phases: [HypnosisMetadata.Phase] = [
            .preTalk, .induction, .deepening, .therapy,
            .suggestions, .conditioning, .emergence, .transitional
        ]
        for phase in phases {
            let kelvin = LightScorePhaseTargeting.colorTemperature(for: phase)
            #expect(kelvin >= 2000 && kelvin <= 7000,
                "\(phase.rawValue) color temp \(kelvin)K out of range [2000, 7000]")
        }
    }
}

// MARK: - clamp utility

@MainActor
struct ClampTests {

    private let gen = SessionGenerator()

    @Test func valueWithinRangePassesThrough() {
        #expect(gen.clamp(5.0, lower: 0.0, upper: 10.0) == 5.0)
    }

    @Test func valueBelowLowerClamped() {
        #expect(gen.clamp(-1.0, lower: 0.0, upper: 10.0) == 0.0)
    }

    @Test func valueAboveUpperClamped() {
        #expect(gen.clamp(15.0, lower: 0.0, upper: 10.0) == 10.0)
    }

    @Test func equalBoundsReturnsTheBound() {
        #expect(gen.clamp(5.0, lower: 5.0, upper: 5.0) == 5.0)
    }
}

// MARK: - Expanded Content Types

struct AudioContentTypeTests {

    @Test func parseRecognizesExpandedAliases() {
        #expect(AudioContentType.parse("eroticHypnosis") == .eroticHypnosis)
        #expect(AudioContentType.parse("sleep_hypnosis") == .sleepHypnosis)
        #expect(AudioContentType.parse("brainwave entrainment") == .brainwave)
        #expect(AudioContentType.parse("ASMR") == .asmr)
    }

    @Test func displayNamesStayHumanReadable() {
        #expect(AudioContentType.eroticHypnosis.displayName == "Erotic Hypnosis")
        #expect(AudioContentType.sleepHypnosis.displayName == "Sleep Hypnosis")
        #expect(AudioContentType.guidedImagery.displayName == "Guided Imagery")
    }
}

// MARK: - Advanced Strategy Tests

@MainActor
struct AdvancedSessionStrategyTests {

    private let gen = SessionGenerator()
    private let config = SessionGenerator.GenerationConfig.default

    @Test func broadFrequencyRangeIsLimitedAtTheVisualOutputBoundary() {
        let analysis = AnalysisResult(
            mood: .meditative,
            energyLevel: 0.2,
            suggestedFrequencyRange: 1.0...40.0,
            suggestedIntensity: 0.4,
            suggestedColorTemperature: 4000,
            keyMoments: [],
            aiSummary: "test",
            recommendedPreset: "Brainwave Session",
            contentType: .brainwave
        )

        let moments = gen.generateBrainwaveSession(analysis: analysis, duration: 600, config: config)

        #expect(moments.first?.frequency == LightSafety.maxFlashHz)
    }

    @Test func hypnosisFromPhasesCanSkipEmergenceRamp() {
        let phases = [
            PhaseSegment(phase: .induction, startTime: 0, endTime: 120, characteristics: "induction", tranceDepthEstimate: 0.3),
            PhaseSegment(phase: .deepening, startTime: 120, endTime: 240, characteristics: "deepening", tranceDepthEstimate: 0.7),
            PhaseSegment(phase: .emergence, startTime: 240, endTime: 300, characteristics: "emergence", tranceDepthEstimate: 0.2)
        ]

        let moments = gen.generateHypnosisFromPhases(
            phases: phases.filter { $0.phase != .emergence },
            duration: 300,
            config: config,
            includeEmergence: false
        )

        #expect((moments.last?.frequency ?? 99) < 10.0)
    }

    @Test func longInductionKeepsCanonicalSineWaveform() {
        let moments = gen.generateHypnosisFromPhases(
            phases: [
                PhaseSegment(
                    phase: .induction,
                    startTime: 0,
                    endTime: 180,
                    characteristics: "induction",
                    tranceDepthEstimate: 0.3
                )
            ],
            duration: 180,
            config: config,
            includeEmergence: false
        )

        let inductionMoments = moments.filter { $0.time > 0 }
        #expect(inductionMoments.isEmpty == false)
        #expect(inductionMoments.allSatisfy { $0.waveform == .sine })
    }
}

// MARK: - Confusion Technique Response

@MainActor
struct ConfusionTechniqueLightResponseTests {

    private let generator = SessionGenerator()

    @Test func overlayInheritsAndRestoresHostStateWithoutProsody() throws {
        var moments = hostMoments()

        generator.applyProsodicModulation(
            moments: &moments,
            analysis: analysis(confusionEvents: [(time: 30, strength: 0.75)]),
            config: .default
        )

        let overlay = moments
            .filter { $0.time >= 30 && $0.time <= 38 }
            .sorted { $0.time < $1.time }
        #expect(overlay.count == 4)
        #expect(overlay.dropLast().allSatisfy { $0.waveform == .noiseModulatedSine })
        #expect(overlay.allSatisfy { abs($0.frequency - 2.0) <= 0.45 })
        #expect(overlay.allSatisfy { $0.intensity <= 0.40 })

        let restored = try #require(overlay.last)
        #expect(restored.time == 38)
        #expect(restored.frequency == 2.0)
        #expect(restored.intensity == 0.40)
        #expect(restored.waveform == .softPulse)
        #expect(restored.bilateral == true)
        #expect(restored.color_temperature == 3000)
    }

    @Test func weakConfusionMarkerDoesNotCreateOverlay() {
        var moments = hostMoments()

        generator.applyProsodicModulation(
            moments: &moments,
            analysis: analysis(confusionEvents: [(time: 30, strength: 0.59)]),
            config: .default
        )

        #expect(moments.count == 2)
    }

    @Test func nearbyConfusionDetectionsCoalesceIntoOneOverlay() {
        var moments = hostMoments()

        generator.applyProsodicModulation(
            moments: &moments,
            analysis: analysis(confusionEvents: [
                (time: 30, strength: 0.75),
                (time: 34, strength: 0.80)
            ]),
            config: .default
        )

        #expect(moments.count == 6)
    }

    @Test func legacyConfusionPhaseUsesDeepeningTargets() {
        #expect(
            LightScorePhaseTargeting.targetFrequency(
                phase: .confusion,
                tranceDepth: LightScorePhaseTargeting.expectedDepth(for: .confusion),
                progress: 0,
                config: .default
            )
                == LightScorePhaseTargeting.targetFrequency(
                    phase: .deepening,
                    tranceDepth: LightScorePhaseTargeting.expectedDepth(for: .deepening),
                    progress: 0,
                    config: .default
                )
        )
        #expect(LightScorePhaseTargeting.frequencyRange(for: .confusion) == LightScorePhaseTargeting.frequencyRange(for: .deepening))
        #expect(LightScorePhaseTargeting.waveform(for: .confusion) == LightScorePhaseTargeting.waveform(for: .deepening))
    }

    private func hostMoments() -> [LightMoment] {
        [
            LightMoment(
                time: 0,
                frequency: 2.0,
                intensity: 0.40,
                waveform: .softPulse,
                bilateral: true,
                color_temperature: 3000
            ),
            LightMoment(
                time: 100,
                frequency: 2.0,
                intensity: 0.40,
                waveform: .softPulse,
                bilateral: true,
                color_temperature: 3000
            )
        ]
    }

    private func analysis(
        confusionEvents: [(time: TimeInterval, strength: Double)]
    ) -> AnalysisResult {
        let techniques = confusionEvents.map { event in
            HypnoticTechnique(
                technique: "confusion_technique",
                timestamp: event.time,
                description: "Confusion technique",
                suggestedLightSync: "bounded_host_modulation"
            )
        }
        let markers = confusionEvents.map { event in
            LinguisticMarker(
                type: .confusionTechnique,
                timestamp: event.time,
                textSnippet: "the more you try",
                strength: event.strength
            )
        }

        return AnalysisResult(
            mood: .meditative,
            energyLevel: 0.2,
            suggestedFrequencyRange: 5.0...8.0,
            suggestedIntensity: 0.4,
            keyMoments: [],
            aiSummary: "Confusion technique fixture",
            recommendedPreset: "Deepening",
            contentType: .hypnosis,
            techniqueDetection: TechniqueDetectionResult(
                techniques: techniques,
                markers: markers
            )
        )
    }
}

// MARK: - Transcript Feature Analysis

struct TranscriptFeatureAnalysisTests {

    @Test func transcriptFeaturesNormalizeAgainstTheCurrentFile() {
        let transcription = AudioTranscriptionResult(
            fullText: """
            relax soften settle into comfort and drift
            obey now obey now obey now obey now obey now obey now
            awake alert refreshed aware and back in the room
            """,
            segments: [
                AudioTranscriptionSegment(
                    text: "relax soften settle into comfort and drift",
                    timestamp: 0,
                    duration: 60,
                    confidence: 0.95
                ),
                AudioTranscriptionSegment(
                    text: "obey now obey now obey now obey now obey now obey now",
                    timestamp: 60,
                    duration: 60,
                    confidence: 0.95
                ),
                AudioTranscriptionSegment(
                    text: "awake alert refreshed aware and back in the room",
                    timestamp: 120,
                    duration: 60,
                    confidence: 0.95
                )
            ],
            duration: 180,
            detectedLanguage: "en"
        )

        let phases = [
            PhaseSegment(phase: .induction, startTime: 0, endTime: 60, characteristics: "induction", tranceDepthEstimate: 0.2),
            PhaseSegment(phase: .brainwashing, startTime: 60, endTime: 120, characteristics: "brainwashing", tranceDepthEstimate: 0.8),
            PhaseSegment(phase: .emergence, startTime: 120, endTime: 180, characteristics: "emergence", tranceDepthEstimate: 0.2)
        ]

        let analysis = TranscriptFeatureAnalyzer().analyze(
            transcription: transcription,
            phases: phases
        )

        let induction = analysis.sections.first { $0.phase == .induction }
        let brainwashing = analysis.sections.first { $0.phase == .brainwashing }
        let emergence = analysis.sections.first { $0.phase == .emergence }

        #expect(induction != nil)
        #expect(brainwashing != nil)
        #expect(emergence != nil)
        #expect((brainwashing?.normalizedWordsPerMinute ?? 0) > 1.0)
        #expect((induction?.normalizedWordsPerMinute ?? 99) < 1.0)
        #expect((brainwashing?.normalizedRepetitionDensity ?? 0) > 1.5)
        #expect(brainwashing?.topDistinctiveWords.first?.word == "obey")
        #expect((emergence?.topDistinctiveWords.first?.word ?? "").contains("alert")
            || (emergence?.topDistinctiveWords.first?.word ?? "").contains("awake"))
    }
}

// MARK: - Transcript Adaptive Modulation

@MainActor
struct TranscriptAdaptiveModulationTests {

    private let gen = SessionGenerator()

    @Test func slowRepetitiveSectionsDeepenTheGeneratedMoment() {
        let overall = TranscriptSectionMetrics(
            id: UUID(),
            phase: nil,
            startTime: 0,
            endTime: 180,
            duration: 180,
            wordCount: 30,
            uniqueWordCount: 18,
            wordsPerMinute: 10,
            normalizedWordsPerMinute: 1.0,
            speechCoverage: 0.55,
            normalizedSpeechCoverage: 1.0,
            lexicalDiversity: 0.60,
            normalizedLexicalDiversity: 1.0,
            repetitionDensity: 1.0,
            normalizedRepetitionDensity: 1.0,
            topWords: [],
            topDistinctiveWords: []
        )

        let slowLoop = TranscriptSectionMetrics(
            id: UUID(),
            phase: .brainwashing,
            startTime: 40,
            endTime: 80,
            duration: 40,
            wordCount: 8,
            uniqueWordCount: 3,
            wordsPerMinute: 6,
            normalizedWordsPerMinute: 0.6,
            speechCoverage: 0.70,
            normalizedSpeechCoverage: 1.27,
            lexicalDiversity: 0.35,
            normalizedLexicalDiversity: 0.58,
            repetitionDensity: 3.5,
            normalizedRepetitionDensity: 3.5,
            topWords: [],
            topDistinctiveWords: [
                TranscriptWordStatistic(word: "obey", count: 5, share: 0.62, normalizedShareLift: 3.0)
            ]
        )

        let transcriptAnalysis = TranscriptAnalysis(overall: overall, sections: [slowLoop])
        let analysis = AnalysisResult(
            mood: .relaxing,
            energyLevel: 0.2,
            suggestedFrequencyRange: 4.0...8.0,
            suggestedIntensity: 0.3,
            keyMoments: [],
            aiSummary: "test",
            recommendedPreset: "test",
            contentType: .hypnosis,
            transcriptAnalysis: transcriptAnalysis
        )

        var moments = [
            LightMoment(
                time: 55,
                frequency: 7.0,
                intensity: 0.30,
                waveform: .sine,
                bilateral: nil,
                color_temperature: 3000
            )
        ]

        gen.applyTranscriptAdaptiveModulation(&moments, analysis: analysis, config: .default)

        #expect(moments[0].frequency < 7.0)
        #expect(moments[0].intensity > 0.30)
        #expect(moments[0].bilateral == true)
        #expect(moments[0].waveform == .softPulse || moments[0].waveform == .noiseModulatedSine)
        #expect((moments[0].color_temperature ?? 9999) < 3000)
    }
}

// MARK: - Light Score Post-Processing

@MainActor
struct LightScorePostProcessorTests {

    @Test func postProcessorClampsCoalescesAndAppliesUserOverrides() {
        let config = SessionGenerator.GenerationConfig(
            colorTemperatureOverride: 6000,
            bilateralMode: true
        )
        let processed = LightScorePostProcessor().process(
            moments: [
                LightMoment(time: -1, frequency: 4, intensity: 0.4, waveform: .sine),
                LightMoment(time: 0, frequency: 8, intensity: 1.2, waveform: .softPulse, color_temperature: 2600)
            ],
            duration: 60,
            analysis: AnalysisFixtures.hypnosisAnalysis,
            config: config
        )

        let times = processed.map(\.time)
        #expect(processed.first?.time == 0)
        #expect(processed.last?.time == 60)
        #expect(Set(times).count == times.count)
        #expect(processed.allSatisfy { $0.intensity >= 0 && $0.intensity <= 1 })
        #expect(processed.allSatisfy { $0.color_temperature == 6000 })
        #expect(processed.first?.bilateral == true)
    }

    @Test func deliberatePauseAddsDeepeningResponseMoment() {
        let analysis = AnalysisResult(
            mood: .relaxing,
            energyLevel: 0.2,
            suggestedFrequencyRange: 4.0...8.0,
            suggestedIntensity: 0.3,
            keyMoments: [],
            aiSummary: "test",
            recommendedPreset: "test",
            contentType: .hypnosis,
            prosodicProfile: AnalysisFixtures.prosodicProfile
        )

        let processed = LightScorePostProcessor().process(
            moments: [
                LightMoment(time: 0, frequency: 8.0, intensity: 0.50, waveform: .sine, color_temperature: 3000),
                LightMoment(time: 120, frequency: 6.0, intensity: 0.40, waveform: .sine, color_temperature: 2600)
            ],
            duration: 120,
            analysis: analysis,
            config: .default
        )

        let pauseMoment = processed.first { abs($0.time - 42) < 0.001 }
        #expect(pauseMoment != nil)
        #expect((pauseMoment?.frequency ?? 99) < 8.0)
        #expect(pauseMoment?.waveform == .noiseModulatedSine)
    }

    @Test func scorerDetectsWeakPhaseAlignment() {
        let weakSession = LightSession(
            session_name: "Weak",
            duration_sec: 300,
            light_score: [
                LightMoment(time: 0, frequency: 18, intensity: 0.5, waveform: .sine),
                LightMoment(time: 300, frequency: 18, intensity: 0.5, waveform: .sine)
            ]
        )

        let report = LightScoreAlignmentScorer().score(
            session: weakSession,
            analysis: AnalysisFixtures.hypnosisAnalysis
        )

        #expect(report.overallScore < LightScoreAlignmentReport.productionTarget)
    }
}

struct PhaseTimelineNormalizerTests {

    @Test func normalizerFillsGapsAndAddsEmergenceForHypnosis() {
        let phases = [
            PhaseSegment(
                phase: .induction,
                startTime: 10,
                endTime: 90,
                characteristics: "Induction",
                tranceDepthEstimate: 0.3
            ),
            PhaseSegment(
                phase: .therapy,
                startTime: 120,
                endTime: 200,
                characteristics: "Therapy",
                tranceDepthEstimate: 0.8
            )
        ]

        let normalized = PhaseTimelineNormalizer().normalize(
            phases,
            duration: 300,
            contentType: .hypnosis
        )

        #expect(normalized.first?.startTime == 0)
        #expect(normalized.last?.endTime == 300)
        #expect(normalized.contains { $0.phase == .induction && $0.startTime == 0 && $0.endTime == 10 })
        #expect(normalized.contains { $0.phase == .transitional && $0.startTime == 90 && $0.endTime == 120 })
        #expect(normalized.last?.phase == .emergence)

        for index in 1..<normalized.count {
            #expect(abs(normalized[index - 1].endTime - normalized[index].startTime) < 0.001)
        }
    }

    @Test func normalizerDoesNotForceEmergenceForSleepHypnosis() {
        let phases = [
            PhaseSegment(
                phase: .deepening,
                startTime: 0,
                endTime: 120,
                characteristics: "Sleep deepening",
                tranceDepthEstimate: 0.7
            )
        ]

        let normalized = PhaseTimelineNormalizer().normalize(
            phases,
            duration: 300,
            contentType: .sleepHypnosis
        )

        #expect(normalized.last?.endTime == 300)
        #expect(normalized.contains { $0.phase == .emergence } == false)
    }
}
