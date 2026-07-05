//
//  SessionGenerationIntegrationTests.swift
//  IlumionateTests
//
//  Integration tests for SessionGenerator using fixture AnalysisResult objects.
//  No AI or WhisperKit required — only the deterministic generation strategies.
//

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct SessionGenerationIntegrationTests {

    private let generator = SessionGenerator()

    // MARK: - Hypnosis

    @Test func hypnosis_sessionHasEmergence() {
        let session = generator.generateSession(
            from: AnalysisFixtures.audioFile(duration: 300),
            analysis: AnalysisFixtures.hypnosisAnalysis
        )
        let lastFrequency = session.light_score.last?.frequency ?? 0
        #expect(lastFrequency >= 10.0,
                "Emergence should bring frequency back to ≥10 Hz; got \(lastFrequency) Hz")
    }

    @Test func hypnosis_sessionHasMoments() {
        let session = generator.generateSession(
            from: AnalysisFixtures.audioFile(duration: 300),
            analysis: AnalysisFixtures.hypnosisAnalysis
        )
        #expect(session.light_score.isEmpty == false)
    }

    @Test func hypnosis_firstMomentIsHighFrequency() {
        let session = generator.generateSession(
            from: AnalysisFixtures.audioFile(duration: 300),
            analysis: AnalysisFixtures.hypnosisAnalysis
        )
        let firstFrequency = session.light_score.first?.frequency ?? 0
        #expect(firstFrequency >= 10.0,
                "Session should open in beta/alpha range (≥10 Hz); got \(firstFrequency) Hz")
    }

    // MARK: - Meditation

    @Test func meditation_sessionArcIsValid() {
        let session = generator.generateSession(
            from: AnalysisFixtures.audioFile(duration: 300),
            analysis: AnalysisFixtures.meditationAnalysis
        )
        #expect(session.light_score.isEmpty == false)
        let freqs = session.light_score.map(\.frequency)
        #expect(freqs.allSatisfy { $0 >= 0.5 && $0 <= 40.0 },
                "All frequencies must be within the valid AVE range [0.5, 40] Hz")
    }

    // MARK: - Music

    @Test func music_sessionProduced() {
        let session = generator.generateSession(
            from: AnalysisFixtures.audioFile(duration: 300),
            analysis: AnalysisFixtures.musicAnalysis
        )
        #expect(session.duration_sec == 300)
        #expect(session.light_score.isEmpty == false)
    }

    // MARK: - Unknown Content Type

    @Test func unknownType_doesNotCrash() {
        let session = generator.generateSession(
            from: AnalysisFixtures.audioFile(duration: 300),
            analysis: AnalysisFixtures.unknownAnalysis
        )
        #expect(session.light_score.isEmpty == false,
                "Unknown content type should produce a fallback session")
    }

    // MARK: - Edge Cases

    @Test func veryShortDuration_doesNotCrash() {
        let file = AnalysisFixtures.audioFile(duration: 10)
        let session = generator.generateSession(
            from: file,
            analysis: AnalysisFixtures.hypnosisAnalysis
        )
        #expect(session.duration_sec >= 0)
    }

    @Test func intensitiesInValidRange() {
        for analysis in [
            AnalysisFixtures.hypnosisAnalysis,
            AnalysisFixtures.meditationAnalysis,
            AnalysisFixtures.musicAnalysis,
        ] {
            let session = generator.generateSession(
                from: AnalysisFixtures.audioFile(duration: 300),
                analysis: analysis
            )
            for moment in session.light_score {
                #expect(moment.intensity >= 0.0 && moment.intensity <= 1.0,
                        "Intensity \(moment.intensity) out of range [0, 1] at t=\(moment.time)")
            }
        }
    }

    @Test func momentsAreSortedByTime() {
        let session = generator.generateSession(
            from: AnalysisFixtures.audioFile(duration: 600),
            analysis: AnalysisFixtures.hypnosisAnalysis
        )
        let times = session.light_score.map(\.time)
        #expect(times == times.sorted(),
                "Light moments must be sorted by time for correct playback")
    }

    @Test func generatedScoreHasUniqueSyncTimes() {
        let session = generator.generateSession(
            from: AnalysisFixtures.audioFile(duration: 300),
            analysis: AnalysisFixtures.hypnosisAnalysis
        )
        let times = session.light_score.map { ($0.time * 1000).rounded() / 1000 }
        #expect(Set(times).count == times.count,
                "Post-processing should remove duplicate light moments at the same timestamp")
    }

    @Test func hypnosisLightScoreMeetsNinetyPercentAlignmentTarget() {
        let session = generator.generateSession(
            from: AnalysisFixtures.audioFile(duration: 300),
            analysis: AnalysisFixtures.hypnosisAnalysis
        )
        let report = LightScoreAlignmentScorer().score(
            session: session,
            analysis: AnalysisFixtures.hypnosisAnalysis
        )

        #expect(report.overallScore >= LightScoreAlignmentReport.productionTarget,
                "Expected >=90% light-score alignment, got \(report.overallScore)")
    }

    @Test func generatedSessionStoresAlignmentReport() throws {
        let session = generator.generateSession(
            from: AnalysisFixtures.audioFile(duration: 300),
            analysis: AnalysisFixtures.hypnosisAnalysis
        )
        let report = try #require(session.alignment_report)

        #expect(report.overallScore >= LightScoreAlignmentReport.productionTarget)
    }

    @Test func optimizerRepairsWeakHypnosisScoreToTarget() {
        let weakMoments = [
            LightMoment(time: 0, frequency: 18, intensity: 0.5, waveform: .sine),
            LightMoment(time: 300, frequency: 18, intensity: 0.5, waveform: .sine)
        ]

        let optimized = LightScoreAlignmentOptimizer().optimize(
            rawMoments: weakMoments,
            duration: 300,
            analysis: AnalysisFixtures.hypnosisAnalysis,
            config: .default
        )

        #expect(optimized.report.overallScore >= LightScoreAlignmentReport.productionTarget,
                "Expected optimizer to repair weak score to >=90%, got \(optimized.report.overallScore)")
    }

    @Test func phaseBackedUnknownAnalysisRoutesThroughHypnosisGenerator() throws {
        let duration: TimeInterval = 1771.964082
        let analysis = longHypnosisAnalysis(contentType: .unknown, duration: duration)
        let session = generator.generateSession(
            from: AnalysisFixtures.audioFile(duration: duration, filename: "Pretend.mp3.mp3"),
            analysis: analysis
        )

        #expect(generator.effectiveContentType(for: analysis) == .hypnosis)
        let coreMoment = try #require(interpolatedMoment(at: 900, in: session.light_score))
        #expect(coreMoment.frequency < 8.0, "Core hypnosis work should be in theta, got \(coreMoment.frequency) Hz")
        #expect(session.light_score.contains { $0.waveform == .softPulse || $0.waveform == .noiseModulatedSine })
        #expect((session.alignment_report?.overallScore ?? 0) >= LightScoreAlignmentReport.productionTarget)
    }

    @Test func longHypnosisPostProcessingRemovesDenseMicroSpikes() {
        let duration: TimeInterval = 1771.964082
        let analysis = longHypnosisAnalysis(
            contentType: .hypnosis,
            duration: duration,
            prosody: densePauseProsody(duration: duration)
        )
        var rawMoments = stride(from: 0.0, through: duration, by: 5.0).enumerated().map { pair in
            let index = pair.offset
            let time = pair.element
            return LightMoment(
                time: time,
                frequency: index.isMultiple(of: 2) ? 14.6 : 5.2,
                intensity: index.isMultiple(of: 3) ? 0.72 : 0.28,
                waveform: index.isMultiple(of: 2) ? .sine : .softPulse
            )
        }
        if rawMoments.last?.time != duration {
            rawMoments.append(LightMoment(time: duration, frequency: 12.0, intensity: 0.24, waveform: .sine))
        }

        let processed = LightScorePostProcessor().process(
            moments: rawMoments,
            duration: duration,
            analysis: analysis,
            config: .default
        )
        let denseGapCount = zip(processed, processed.dropFirst())
            .filter { nextPair in nextPair.1.time - nextPair.0.time < 8.0 }
            .count
        let report = LightScoreAlignmentScorer().score(
            session: LightSession(session_name: "Processed", duration_sec: duration, light_score: processed),
            analysis: analysis
        )
        let phaseDiagnostics = phaseFrequencyDiagnostics(
            moments: processed,
            analysis: analysis
        )

        #expect(processed.count < rawMoments.count / 2)
        #expect(denseGapCount < 12, "Expected dense local clusters to be pruned, found \(denseGapCount)")
        #expect(report.overallScore >= LightScoreAlignmentReport.productionTarget,
                """
                Expected processed score to meet target. overall=\(report.overallScore), phase=\(report.phaseFrequencyScore), boundary=\(report.boundaryScore), depth=\(report.depthCorrelationScore), pause=\(report.pauseResponseScore), structural=\(report.structuralScore), processed=\(processed.count), raw=\(rawMoments.count), denseGaps=\(denseGapCount), phaseSamples=\(phaseDiagnostics)
                """)
    }

    private func longHypnosisAnalysis(
        contentType: AudioContentType,
        duration: TimeInterval,
        prosody: ProsodicProfile? = nil
    ) -> AnalysisResult {
        let phases = [
            PhaseSegment(
                phase: .induction,
                startTime: 0,
                endTime: 300,
                characteristics: "Eye closure and breathing induction",
                tranceDepthEstimate: 0.28
            ),
            PhaseSegment(
                phase: .deepening,
                startTime: 300,
                endTime: 720,
                characteristics: "Deepening into trance",
                tranceDepthEstimate: 0.62
            ),
            PhaseSegment(
                phase: .suggestions,
                startTime: 720,
                endTime: 1500,
                characteristics: "Core suggestion work",
                tranceDepthEstimate: 0.74
            ),
            PhaseSegment(
                phase: .emergence,
                startTime: 1500,
                endTime: duration,
                characteristics: "Return and reorientation",
                tranceDepthEstimate: 0.20
            )
        ]

        return AnalysisResult(
            mood: .relaxing,
            energyLevel: 0.2,
            suggestedFrequencyRange: 4.0...8.0,
            suggestedIntensity: 0.45,
            suggestedColorTemperature: 2600,
            keyMoments: [],
            aiSummary: "Long hypnosis fixture",
            recommendedPreset: "Phase Guided Hypnosis",
            contentType: contentType,
            hypnosisMetadata: HypnosisMetadata(
                phases: phases,
                inductionStyle: .permissive,
                estimatedTranceDeph: .deep,
                suggestionDensity: nil,
                languagePatterns: [],
                detectedTechniques: []
            ),
            prosodicProfile: prosody
        )
    }

    private func densePauseProsody(duration: TimeInterval) -> ProsodicProfile {
        let windowCount = Int(ceil(duration / 5.0))
        let pauses = stride(from: 90.0, to: duration - 120.0, by: 6.0).enumerated().map { pair in
            let index = pair.offset
            let time = pair.element
            return DetectedPause(
                startTime: time,
                duration: index.isMultiple(of: 2) ? 4.5 : 7.0,
                precedingText: "deeper",
                followingText: "now",
                category: index.isMultiple(of: 2) ? .deliberate : .silence
            )
        }

        return ProsodicProfile(
            windowDuration: 5,
            speechRateCurve: Array(repeating: 78, count: windowCount),
            volumeCurve: Array(repeating: 0.42, count: windowCount),
            pitchCurve: Array(repeating: 145, count: windowCount),
            speechSilenceRatio: Array(repeating: 0.48, count: windowCount),
            pauses: pauses,
            totalDuration: duration
        )
    }

    private func interpolatedMoment(
        at time: TimeInterval,
        in moments: [LightMoment]
    ) -> LightMoment? {
        guard !moments.isEmpty else { return nil }
        let ordered = moments.sorted { $0.time < $1.time }
        guard time > ordered[0].time else { return ordered[0] }
        guard time < ordered[ordered.count - 1].time else { return ordered.last }

        for index in 1..<ordered.count where ordered[index].time >= time {
            let previous = ordered[index - 1]
            let next = ordered[index]
            let span = max(next.time - previous.time, 0.001)
            let alpha = max(0, min(1, (time - previous.time) / span))
            return LightMoment(
                time: time,
                frequency: previous.frequency + (next.frequency - previous.frequency) * alpha,
                intensity: previous.intensity + (next.intensity - previous.intensity) * alpha,
                waveform: previous.waveform
            )
        }

        return ordered.last
    }

    private func phaseFrequencyDiagnostics(
        moments: [LightMoment],
        analysis: AnalysisResult
    ) -> String {
        guard let phases = analysis.hypnosisMetadata?.phases else { return "none" }

        let diagnostics = phases.flatMap { phase -> [(time: TimeInterval, actual: Double, target: Double, score: Double)] in
            let phaseDuration = max(0, phase.endTime - phase.startTime)
            guard phaseDuration > 0 else { return [] }

            let progressValues: [Double]
            if phaseDuration >= 120 {
                progressValues = [0.0, 0.25, 0.50, 0.75, 0.92]
            } else if phaseDuration >= 45 {
                progressValues = [0.0, 0.33, 0.66, 0.92]
            } else {
                progressValues = [0.0, 0.50, 0.92]
            }

            return progressValues.compactMap { progress in
                let time = phase.startTime + phaseDuration * progress
                guard let moment = interpolatedMoment(at: time, in: moments) else { return nil }
                let target = LightScorePhaseTargeting.targetFrequency(
                    phase: phase.phase,
                    tranceDepth: phase.tranceDepthEstimate,
                    progress: progress,
                    config: .default
                )
                let tolerance = max(0.75, target * 0.16)
                let score = max(0, min(1, 1 - abs(moment.frequency - target) / tolerance))
                return (time, moment.frequency, target, score)
            }
        }

        return diagnostics
            .sorted { $0.score < $1.score }
            .prefix(5)
            .map {
                String(
                    format: "t=%.1f actual=%.2f target=%.2f score=%.2f",
                    $0.time,
                    $0.actual,
                    $0.target,
                    $0.score
                )
            }
            .joined(separator: "; ")
    }
}
