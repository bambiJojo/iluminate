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
}
