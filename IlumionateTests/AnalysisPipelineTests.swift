//
//  AnalysisPipelineTests.swift
//  IlumionateTests
//
//  End-to-end tests for AnalysisPipeline using mock services.
//  No real ML, no real audio files required.
//

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct AnalysisPipelineTests {

    // MARK: - Happy Path

    @Test func happyPath_producesCompleteResult() async throws {
        let pipeline = makePipeline()
        let result = try await pipeline.run(audioFile: AnalysisFixtures.audioFile())

        #expect(!result.transcription.fullText.isEmpty)
        #expect(result.analysis.contentType == .hypnosis)
        #expect(result.session.duration_sec > 0)
    }

    @Test func happyPath_callsEachServiceOnce() async throws {
        let transcriber = MockAudioTranscriber()
        let analyzer    = MockContentAnalyzer()
        let generator   = MockSessionGenerator()
        let pipeline    = AnalysisPipeline(
            transcriber: transcriber, analyzer: analyzer, generator: generator
        )

        _ = try await pipeline.run(audioFile: AnalysisFixtures.audioFile())

        #expect(transcriber.callCount == 1)
        #expect(analyzer.callCount    == 1)
        #expect(generator.callCount   == 1)
    }

    // MARK: - Error Propagation

    @Test func transcriptionFailure_throws() async throws {
        let transcriber = MockAudioTranscriber()
        transcriber.resultToReturn = .failure(AnalyzerError.noAudioData)
        let pipeline = AnalysisPipeline(
            transcriber: transcriber,
            analyzer: MockContentAnalyzer(),
            generator: MockSessionGenerator()
        )

        await #expect(throws: AnalyzerError.self) {
            try await pipeline.run(audioFile: AnalysisFixtures.audioFile())
        }
    }

    @Test func transcriptionFailure_doesNotCallAnalyzer() async throws {
        let transcriber = MockAudioTranscriber()
        transcriber.resultToReturn = .failure(AnalyzerError.noAudioData)
        let analyzer = MockContentAnalyzer()
        let pipeline = AnalysisPipeline(
            transcriber: transcriber, analyzer: analyzer, generator: MockSessionGenerator()
        )

        _ = try? await pipeline.run(audioFile: AnalysisFixtures.audioFile())
        #expect(analyzer.callCount == 0)
    }

    @Test func aiUnavailable_throws() async throws {
        let analyzer = MockContentAnalyzer()
        analyzer.isModelAvailable = false
        let pipeline = AnalysisPipeline(
            transcriber: MockAudioTranscriber(),
            analyzer: analyzer,
            generator: MockSessionGenerator()
        )

        await #expect(throws: AIAnalyzerError.self) {
            try await pipeline.run(audioFile: AnalysisFixtures.audioFile())
        }
    }

    @Test func aiUnavailable_doesNotCallGenerator() async throws {
        let analyzer = MockContentAnalyzer()
        analyzer.isModelAvailable = false
        let generator = MockSessionGenerator()
        let pipeline = AnalysisPipeline(
            transcriber: MockAudioTranscriber(),
            analyzer: analyzer,
            generator: generator
        )

        _ = try? await pipeline.run(audioFile: AnalysisFixtures.audioFile())
        #expect(generator.callCount == 0)
    }

    // MARK: - Progress Events

    @Test func progressReported_inCanonicalOrder() async throws {
        let pipeline = makePipeline()
        var stages: [AnalysisStage] = []

        _ = try await pipeline.run(audioFile: AnalysisFixtures.audioFile()) { progress in
            stages.append(progress.stage)
        }

        // Must pass through these stages in order
        let expected: [AnalysisStage] = [.starting, .transcribing, .analyzing, .generatingSession, .complete]
        for stage in expected {
            #expect(stages.contains(stage),
                    "Expected stage '\(stage)' in progress events: \(stages)")
        }
        #expect(stages.last == .complete)
    }

    @Test func progressFractions_increaseMonotonically() async throws {
        let pipeline = makePipeline()
        var fractions: [Double] = []

        _ = try await pipeline.run(audioFile: AnalysisFixtures.audioFile()) { progress in
            fractions.append(progress.fraction)
        }

        var previous = -1.0
        for fraction in fractions {
            #expect(fraction >= previous,
                    "Progress fraction decreased: \(previous) → \(fraction)")
            previous = fraction
        }
        #expect(fractions.last == 1.0)
    }

    @Test func sessionGeneration_usesAnalysisPreferenceOverrides() async throws {
        let preferences = AnalysisPreferences.shared
        preferences.resetToDefaults()
        defer { preferences.resetToDefaults() }

        preferences.intensityMultiplier = 1.25
        preferences.frequencyProfile = .deep
        preferences.transitionStyle = .fluid
        preferences.colorTempMode = .cool
        preferences.bilateralMode = true

        let generator = MockSessionGenerator()
        let pipeline = AnalysisPipeline(
            transcriber: MockAudioTranscriber(),
            analyzer: MockContentAnalyzer(),
            generator: generator
        )

        _ = try await pipeline.run(audioFile: AnalysisFixtures.audioFile())

        #expect(generator.lastConfig?.intensityMultiplier == 1.25)
        #expect(generator.lastConfig?.minFrequency == FrequencyProfile.deep.minFrequency)
        #expect(generator.lastConfig?.maxFrequency == FrequencyProfile.deep.maxFrequency)
        #expect(generator.lastConfig?.transitionSmoothness == TransitionStyle.fluid.smoothness)
        #expect(generator.lastConfig?.colorTemperatureOverride == ColorTempMode.cool.kelvin)
        #expect(generator.lastConfig?.bilateralMode == true)
    }

    // MARK: - All Content Types

    @Test func hypnosisAnalysis_producesSession()      async throws { try await assertSessionGenerated(analysis: AnalysisFixtures.hypnosisAnalysis)     }
    @Test func meditationAnalysis_producesSession()    async throws { try await assertSessionGenerated(analysis: AnalysisFixtures.meditationAnalysis)   }
    @Test func musicAnalysis_producesSession()         async throws { try await assertSessionGenerated(analysis: AnalysisFixtures.musicAnalysis)         }
    @Test func affirmationsAnalysis_producesSession()  async throws { try await assertSessionGenerated(analysis: AnalysisFixtures.affirmationsAnalysis)  }
    @Test func unknownAnalysis_producesSession()       async throws { try await assertSessionGenerated(analysis: AnalysisFixtures.unknownAnalysis)       }

    // MARK: - Helpers

    private func makePipeline() -> AnalysisPipeline {
        AnalysisPipeline(
            transcriber: MockAudioTranscriber(),
            analyzer:    MockContentAnalyzer(),
            generator:   MockSessionGenerator()
        )
    }

    private func assertSessionGenerated(analysis: AnalysisResult) async throws {
        let mockAnalyzer = MockContentAnalyzer()
        mockAnalyzer.analysisToReturn = analysis
        let pipeline = AnalysisPipeline(
            transcriber: MockAudioTranscriber(),
            analyzer:    mockAnalyzer,
            generator:   MockSessionGenerator()
        )
        let result = try await pipeline.run(audioFile: AnalysisFixtures.audioFile())
        #expect(result.session.duration_sec > 0)
        #expect(result.analysis.contentType == analysis.contentType)
    }
}
