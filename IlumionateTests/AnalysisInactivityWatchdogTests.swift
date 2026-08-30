//
//  AnalysisInactivityWatchdogTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct AnalysisInactivityWatchdogTests {
    @Test("Five minutes without a heartbeat stalls the attempt")
    func inactivityTripsAtTheThreshold() {
        let watchdog = AnalysisInactivityWatchdog(
            stage: .transcription,
            progress: 0.1,
            startedAt: .zero,
            timeout: .seconds(300)
        )

        #expect(!watchdog.hasTimedOut(at: Duration.seconds(299)))
        #expect(watchdog.hasTimedOut(at: Duration.seconds(300)))
    }

    @Test("Meaningful progress restarts the inactivity window")
    func progressRestartsTheWindow() {
        var watchdog = AnalysisInactivityWatchdog(
            stage: .transcription,
            progress: 0.1,
            startedAt: .zero,
            timeout: .seconds(300)
        )

        watchdog.observe(
            stage: .transcription,
            progress: 0.2,
            at: .seconds(240)
        )

        #expect(!watchdog.hasTimedOut(at: Duration.seconds(539)))
        #expect(watchdog.hasTimedOut(at: Duration.seconds(540)))
    }

    @Test("A stage transition restarts the inactivity window")
    func stageTransitionRestartsTheWindow() {
        var watchdog = AnalysisInactivityWatchdog(
            stage: .transcription,
            progress: 1,
            startedAt: .zero,
            timeout: .seconds(300)
        )

        watchdog.observe(
            stage: .contentAnalysis,
            progress: 0,
            at: .seconds(240)
        )

        #expect(!watchdog.hasTimedOut(at: Duration.seconds(539)))
        #expect(watchdog.hasTimedOut(at: Duration.seconds(540)))
    }

    @Test("A stalled transcription terminalizes without waiting for its late result", .timeLimit(.minutes(1)))
    func stalledTranscriptionIsTerminalizedExactlyOnce() async throws {
        let progressURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        let cacheURL = URL.temporaryDirectory
            .appending(path: "AnalysisCache-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: progressURL)
            try? FileManager.default.removeItem(at: cacheURL)
        }

        let audioFile = AnalysisFixtures.audioFile(filename: "stalled-transcription.m4a")
        let nextFile = AnalysisFixtures.audioFile(filename: "after-stall.m4a")
        defer { GeneratedSessionStore.shared.delete(for: nextFile) }
        let transcriber = UncooperativeAudioTranscriber()
        let manager = AnalysisStateManager(
            transcriber: transcriber,
            analyzer: MockContentAnalyzer(),
            progressStore: AnalysisProgressStore(storeURL: progressURL),
            cacheURL: cacheURL,
            stageOverlapOverride: false,
            watchdogPolicy: AnalysisWatchdogPolicy(
                noProgressTimeout: .milliseconds(30),
                pollInterval: .milliseconds(5)
            ),
            scheduleBackgroundAnalysis: { _ in }
        )

        // Not `.background`: iOS throttles that QoS hard, and the post-stall
        // resume then took ~14 s to reach transcription where macOS took 0.2 s.
        // The test is about the stall contract, not about how the OS schedules
        // background work, so it drives the queue the way a user action does.
        let processing = Task {
            await manager.queueForAnalysis([audioFile, nextFile], priority: testAnalysisPriority)
        }
        try await waitUntil("the transcriber to start") { transcriber.hasStarted }

        await processing.value

        let failure = try #require(manager.failedAnalyses.first)
        #expect(manager.failedAnalyses.count == 1)
        #expect(failure.reason == .stalled)
        #expect(failure.failedStage == .transcription)
        #expect(failure.retryState == .manual)
        #expect(transcriber.cancelCallCount == 1)
        #expect(manager.completedAnalyses.isEmpty)

        // An implementation that ignores cancellation may still callback.
        // That value belongs to the terminal attempt and must be discarded.
        transcriber.finishLate()
        try await waitUntil("the queue to resume after the stall") {
            manager.completedAnalyses.isEmpty == false
        }

        #expect(manager.failedAnalyses.count == 1)
        #expect(manager.completedAnalyses.map(\.audioFile.id) == [nextFile.id])
    }

    @Test("A stalled content analysis uses the same terminal recovery path", .timeLimit(.minutes(1)))
    func stalledContentAnalysisIsTerminalized() async throws {
        let progressURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        let cacheURL = URL.temporaryDirectory
            .appending(path: "AnalysisCache-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: progressURL)
            try? FileManager.default.removeItem(at: cacheURL)
        }

        let audioFile = AnalysisFixtures.audioFile(filename: "stalled-analysis.m4a")
        let analyzer = UncooperativeContentAnalyzer()
        let manager = AnalysisStateManager(
            transcriber: MockAudioTranscriber(),
            analyzer: analyzer,
            progressStore: AnalysisProgressStore(storeURL: progressURL),
            cacheURL: cacheURL,
            stageOverlapOverride: false,
            watchdogPolicy: AnalysisWatchdogPolicy(
                noProgressTimeout: .milliseconds(30),
                pollInterval: .milliseconds(5)
            ),
            scheduleBackgroundAnalysis: { _ in }
        )

        await manager.queueForAnalysis(audioFile, priority: testAnalysisPriority)

        let failure = try #require(manager.failedAnalyses.first)
        #expect(failure.reason == .stalled)
        #expect(failure.failedStage == .contentAnalysis)
        #expect(analyzer.cancelCallCount == 1)
        #expect(manager.completedAnalyses.isEmpty)

        // The quarantine is the signal that the stalled attempt has not finished
        // unwinding yet. Asserting it is held here keeps the wait below honest —
        // without it, a quarantine that was never taken would make the wait
        // return instantly and the test would assert nothing.
        #expect(manager.isAnalysisResourceQuarantined)

        analyzer.finishLate()
        // Was `Task.sleep(for: .milliseconds(20))`, which only guessed at how long
        // the late result takes to arrive and be discarded. The quarantine lifting
        // is that event, so wait for it instead of for the clock.
        try await waitUntil("the stalled attempt to finish unwinding") {
            manager.isAnalysisResourceQuarantined == false
        }

        #expect(manager.failedAnalyses.count == 1)
        #expect(manager.completedAnalyses.isEmpty)
    }

    @Test("Stall errors map before the ordinary stage fallback")
    func stallReasonMapping() {
        let reason = AnalyticsAnalysisFailureReason(
            error: AnalysisStalledError(stage: .transcription),
            stage: .transcription
        )

        #expect(reason == .stalled)
    }
}

@MainActor
private final class UncooperativeAudioTranscriber: AudioTranscribingService {
    var progress = 0.1
    var statusMessage = "Waiting"
    private(set) var hasStarted = false
    private(set) var cancelCallCount = 0
    private var callCount = 0
    private var continuation: CheckedContinuation<AudioTranscriptionResult, Error>?

    func transcribe(audioFile: AudioFile) async throws -> AudioTranscriptionResult {
        hasStarted = true
        callCount += 1
        if callCount > 1 {
            progress = 1
            return AnalysisFixtures.basicTranscription
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancelTranscription() async {
        cancelCallCount += 1
    }

    func finishLate() {
        continuation?.resume(returning: AnalysisFixtures.basicTranscription)
        continuation = nil
    }
}

@MainActor
private final class UncooperativeContentAnalyzer: ContentAnalyzingService {
    var progress = 0.1
    var statusMessage = "Waiting"
    var isModelAvailable = true
    private(set) var cancelCallCount = 0
    private var continuation: CheckedContinuation<AnalysisResult, Error>?

    func analyzeContent(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile
    ) async throws -> AnalysisResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
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

    func cancelAnalysis() async {
        cancelCallCount += 1
    }

    func finishLate() {
        continuation?.resume(returning: AnalysisFixtures.hypnosisAnalysis)
        continuation = nil
    }
}
