//
//  StagedAnalysisPipelineTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct StagedAnalysisPipelineTests {
    @Test("The next file transcribes while the current file is analyzed", .timeLimit(.minutes(1)))
    func overlapsIndependentFileStagesWithoutRepeatingTranscription() async {
        let progressURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        let cacheURL = URL.temporaryDirectory
            .appending(path: "AnalysisCache-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: progressURL)
            try? FileManager.default.removeItem(at: cacheURL)
        }

        let firstFile = AnalysisFixtures.audioFile(filename: "pipeline-first.m4a")
        let secondFile = AnalysisFixtures.audioFile(filename: "pipeline-second.m4a")
        defer {
            GeneratedSessionStore.shared.delete(for: firstFile)
            GeneratedSessionStore.shared.delete(for: secondFile)
        }

        let probe = StagedAnalysisProbe()
        let transcriber = StagedAudioTranscriber(probe: probe)
        let analyzer = GatedContentAnalyzer(probe: probe)
        let manager = AnalysisStateManager(
            transcriber: transcriber,
            analyzer: analyzer,
            progressStore: AnalysisProgressStore(storeURL: progressURL),
            cacheURL: cacheURL,
            stageOverlapOverride: true,
            scheduleBackgroundAnalysis: { _ in }
        )

        let processing = Task {
            await manager.queueForAnalysis([firstFile, secondFile])
        }

        let observedOverlap = await waitUntil {
            await probe.didObserveAnalysisAndTranscriptionOverlap
        }
        await probe.releaseFirstAnalysis()
        await processing.value

        #expect(observedOverlap, "The second transcription should begin before the first analysis finishes.")
        #expect(transcriber.callCount == 2, "Each file should be transcribed exactly once.")
        #expect(analyzer.callCount == 2, "Each file should be analyzed exactly once.")
        #expect(manager.completedAnalyses.count == 2)
    }

    // Generous deadline: a cold first run needs several seconds to reach the
    // overlap, while a warm run gets there in ~0.1s. Polling returns as soon
    // as the condition holds, so the extra headroom costs nothing when fast.
    private func waitUntil(
        timeout: Duration = .seconds(15),
        condition: () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

private actor StagedAnalysisProbe {
    private var activeAnalysisCount = 0
    private var observedOverlap = false
    private var firstAnalysisReleased = false
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    var didObserveAnalysisAndTranscriptionOverlap: Bool {
        observedOverlap
    }

    func transcriptionStarted() {
        if activeAnalysisCount > 0 {
            observedOverlap = true
        }
    }

    func analysisStarted() {
        activeAnalysisCount += 1
    }

    func analysisFinished() {
        activeAnalysisCount -= 1
    }

    func waitForFirstAnalysisRelease() async {
        guard firstAnalysisReleased == false else { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    func releaseFirstAnalysis() {
        firstAnalysisReleased = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

@MainActor
private final class StagedAudioTranscriber: AudioTranscribingService {
    var progress = 0.0
    var statusMessage = ""
    private(set) var callCount = 0

    private let probe: StagedAnalysisProbe

    init(probe: StagedAnalysisProbe) {
        self.probe = probe
    }

    func transcribe(audioFile: AudioFile) async throws -> AudioTranscriptionResult {
        callCount += 1
        await probe.transcriptionStarted()
        progress = 1
        return AnalysisFixtures.basicTranscription
    }

    func cancelTranscription() async {}
    func releaseResources() async {}
}

@MainActor
private final class GatedContentAnalyzer: ContentAnalyzingService {
    var progress = 0.0
    var statusMessage = ""
    var isModelAvailable = true
    private(set) var callCount = 0

    private let probe: StagedAnalysisProbe

    init(probe: StagedAnalysisProbe) {
        self.probe = probe
    }

    func analyzeContent(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile
    ) async throws -> AnalysisResult {
        callCount += 1
        await probe.analysisStarted()
        if callCount == 1 {
            await probe.waitForFirstAnalysisRelease()
        }
        await probe.analysisFinished()
        progress = 1
        return AnalysisFixtures.hypnosisAnalysis
    }

    func analyzeWithoutTranscription(
        audioFile: AudioFile,
        audioFeatures: AudioFeatures
    ) async throws -> AnalysisResult {
        try await analyzeContent(
            transcription: AnalysisFixtures.basicTranscription,
            audioFile: audioFile
        )
    }

    func cancelAnalysis() async {}
}
