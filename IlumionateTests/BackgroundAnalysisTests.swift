//
//  BackgroundAnalysisTests.swift
//  IlumionateTests
//

import BackgroundTasks
import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct BackgroundAnalysisTests {
    #if os(iOS) && !targetEnvironment(macCatalyst)
    @Test func continuedProcessingUsesConcreteRegisteredIdentifier() {
        let identifier = BackgroundAnalysisScheduler.makeContinuedIdentifier()

        #expect(identifier.hasPrefix(BackgroundAnalysisScheduler.continuedIdentifierPrefix))
        #expect(!identifier.contains("*"))
        #expect(BackgroundAnalysisScheduler.shared.registerContinuedHandler(for: identifier))
    }

    @Test("Continued processing UI is never left queued after foreground analysis")
    func continuedProcessingRequiresImmediateLaunch() {
        #expect(
            BackgroundAnalysisScheduler.continuedSubmissionStrategy == .fail,
            "Analysis starts immediately in-app, so its system progress UI must also launch immediately or fail."
        )
    }
    #else
    @Test("Continued processing is disabled outside native iOS")
    func continuedProcessingIsDisabled() {
        let identifier = BackgroundAnalysisScheduler.makeContinuedIdentifier()
        #expect(!BackgroundAnalysisScheduler.shared.registerContinuedHandler(for: identifier))
    }
    #endif

    @Test("Relaunch cleanup finds every stale continued-analysis request")
    func relaunchCleanupFindsAllContinuedRequests() {
        let firstID = UUID()
        let secondID = UUID()
        let staleIdentifiers = [
            BackgroundAnalysisScheduler.makeContinuedIdentifier(id: firstID),
            BackgroundAnalysisScheduler.makeContinuedIdentifier(id: secondID)
        ]
        let unrelatedIdentifiers = [
            BackgroundAnalysisScheduler.processingIdentifier,
            "com.example.other.continued.task"
        ]

        let result = BackgroundAnalysisScheduler.continuedRequestIdentifiers(
            from: staleIdentifiers + unrelatedIdentifiers
        )

        #expect(result == staleIdentifiers)
    }

    @Test func queuedAnalysisSurvivesProcessTerminationBeforeTranscription() async throws {
        let storeURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let audioFile = AnalysisFixtures.audioFile()
        let store = AnalysisProgressStore(storeURL: storeURL)

        await store.saveQueued(audioFile)

        let reloadedStore = AnalysisProgressStore(storeURL: storeURL)
        let pending = await reloadedStore.allPending()

        #expect(pending.map(\.audioFile.id) == [audioFile.id])
        #expect(pending.first?.resumeStage == .transcribing)
    }

    @Test func attemptCountSurvivesProcessTermination() async throws {
        let storeURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let audioFile = AnalysisFixtures.audioFile()
        let store = AnalysisProgressStore(storeURL: storeURL)
        await store.saveQueued(audioFile)

        #expect(await store.beginAttempt(for: audioFile) == 1)

        let reloadedStore = AnalysisProgressStore(storeURL: storeURL)
        #expect(await reloadedStore.beginAttempt(for: audioFile) == 2)
    }

    @Test func managerPersistsQueueBeforeStartingLongRunningWork() async throws {
        let progressURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        let cacheURL = URL.temporaryDirectory
            .appending(path: "AnalysisCache-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: progressURL)
            try? FileManager.default.removeItem(at: cacheURL)
        }

        let store = AnalysisProgressStore(storeURL: progressURL)
        let transcriber = SuspendedAudioTranscriber()
        let manager = AnalysisStateManager(
            transcriber: transcriber,
            analyzer: MockContentAnalyzer(),
            progressStore: store,
            cacheURL: cacheURL,
            scheduleBackgroundAnalysis: { _ in }
        )
        let audioFile = AnalysisFixtures.audioFile()

        let processing = Task {
            await manager.queueForAnalysis(audioFile)
        }

        while !transcriber.hasStarted {
            await Task.yield()
        }

        let reloadedStore = AnalysisProgressStore(storeURL: progressURL)
        let pendingIDs = await reloadedStore.allPending().map(\.audioFile.id)
        #expect(pendingIDs == [audioFile.id])

        manager.cancelAllAnalyses()
        await processing.value
    }

    @Test func terminalFailureRemovesDurableCheckpoint() async throws {
        let progressURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        let cacheURL = URL.temporaryDirectory
            .appending(path: "AnalysisCache-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: progressURL)
            try? FileManager.default.removeItem(at: cacheURL)
        }

        let store = AnalysisProgressStore(storeURL: progressURL)
        let transcriber = MockAudioTranscriber()
        transcriber.resultToReturn = .failure(AnalyzerError.audioFileInvalid)
        let manager = AnalysisStateManager(
            transcriber: transcriber,
            analyzer: MockContentAnalyzer(),
            progressStore: store,
            cacheURL: cacheURL,
            scheduleBackgroundAnalysis: { _ in }
        )

        await manager.queueForAnalysis(AnalysisFixtures.audioFile())

        #expect(await store.allPending().isEmpty)
        #expect(manager.failedAnalyses.count == 1)
    }

    @Test func recognizedGoldTrackBypassesTranscriptionAndGenericAI() async throws {
        let progressURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        let cacheURL = URL.temporaryDirectory
            .appending(path: "AnalysisCache-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: progressURL)
            try? FileManager.default.removeItem(at: cacheURL)
        }

        let store = AnalysisProgressStore(storeURL: progressURL)
        let transcriber = MockAudioTranscriber()
        let analyzer = MockContentAnalyzer()
        let manager = AnalysisStateManager(
            transcriber: transcriber,
            analyzer: analyzer,
            progressStore: store,
            cacheURL: cacheURL,
            scheduleBackgroundAnalysis: { _ in }
        )
        let audioFile = AudioFile(
            filename: "04 Giggledoll.mp3",
            duration: 394.031,
            fileSize: 1_024
        )

        await manager.queueForAnalysis(audioFile)

        #expect(transcriber.callCount == 0)
        #expect(analyzer.callCount == 0)
        #expect(manager.getCompletedAnalysis(for: audioFile)?.analysis.expertAnalysis?.verdict == .productionReady)
        #expect(await store.allPending().isEmpty)
    }

    @Test func transientFailureIsAutomaticallyRetriedOnceThenWaitsForManualRecovery() async throws {
        let progressURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        let cacheURL = URL.temporaryDirectory
            .appending(path: "AnalysisCache-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: progressURL)
            try? FileManager.default.removeItem(at: cacheURL)
        }

        let store = AnalysisProgressStore(storeURL: progressURL)
        let transcriber = MockAudioTranscriber()
        transcriber.resultToReturn = .failure(
            AnalyzerError.transcriptionFailed(TransientTestError())
        )
        let manager = AnalysisStateManager(
            transcriber: transcriber,
            analyzer: MockContentAnalyzer(),
            progressStore: store,
            cacheURL: cacheURL,
            scheduleBackgroundAnalysis: { _ in }
        )
        let audioFile = AnalysisFixtures.audioFile()

        await manager.queueForAnalysis(audioFile)

        #expect(await store.allPending().isEmpty)
        #expect(await store.manualRecoveryCheckpoints().count == 1)
        #expect(transcriber.callCount == 2)
        #expect(manager.failedAnalyses.count == 1)
    }

    @Test("Background interruption does not consume the content-analysis retry budget")
    func backgroundInterruptionStillAllowsTransientRetry() async throws {
        let progressURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        let cacheURL = URL.temporaryDirectory
            .appending(path: "AnalysisCache-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: progressURL)
            try? FileManager.default.removeItem(at: cacheURL)
        }

        let store = AnalysisProgressStore(storeURL: progressURL)
        let transcriber = MockAudioTranscriber()
        let analyzer = InterruptedThenTransientContentAnalyzer()
        let manager = AnalysisStateManager(
            transcriber: transcriber,
            analyzer: analyzer,
            progressStore: store,
            cacheURL: cacheURL,
            scheduleBackgroundAnalysis: { _ in }
        )
        let audioFile = AnalysisFixtures.audioFile()
        defer { GeneratedSessionStore.shared.delete(for: audioFile) }

        let processing = Task {
            await manager.queueForAnalysis(audioFile)
        }

        while analyzer.callCount == 0 {
            await Task.yield()
        }
        let interruptedCheckpoint = await store.checkpoint(for: audioFile)
        #expect(interruptedCheckpoint?.transcription != nil)

        manager.expireBackgroundProcessing()
        await processing.value

        #expect(manager.failedAnalyses.isEmpty)
        #expect(await store.allPending().map(\.audioFile.id) == [audioFile.id])

        let succeeded = await manager.resumeInterruptedAnalyses()

        #expect(succeeded)
        #expect(transcriber.callCount == 1, "The saved transcript should be reused after backgrounding.")
        #expect(analyzer.callCount == 3, "The resumed transient error should receive one automatic retry.")
        #expect(manager.getCompletedAnalysis(for: audioFile) != nil)
        #expect(await store.manualRecoveryCheckpoints().isEmpty)
    }

    @Test func terminalLateStageFailurePreservesManualRecoveryWithoutBackgroundLoop() async throws {
        let progressURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        let cacheURL = URL.temporaryDirectory
            .appending(path: "AnalysisCache-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: progressURL)
            try? FileManager.default.removeItem(at: cacheURL)
        }

        let audioFile = AnalysisFixtures.audioFile()
        let store = AnalysisProgressStore(storeURL: progressURL)
        await store.saveQueued(audioFile)
        await store.saveTranscription(AnalysisFixtures.basicTranscription, for: audioFile)
        await store.markRequiresManualRetry(
            for: audioFile,
            reason: .contentAnalysis,
            failedStage: .contentAnalysis,
            failedAt: .now
        )

        let reloadedStore = AnalysisProgressStore(storeURL: progressURL)
        #expect(await reloadedStore.allPending().isEmpty)
        let recoveries = await reloadedStore.manualRecoveryCheckpoints()
        #expect(recoveries.count == 1)
        #expect(recoveries.first?.recoveryStage == .transcription)

        let relaunchedManager = AnalysisStateManager(
            transcriber: MockAudioTranscriber(),
            analyzer: MockContentAnalyzer(),
            progressStore: reloadedStore,
            cacheURL: cacheURL,
            scheduleBackgroundAnalysis: { _ in }
        )
        await relaunchedManager.restoreManualRecoveries()

        #expect(relaunchedManager.failedAnalyses.count == 1)
        #expect(relaunchedManager.failedAnalyses.first?.retryState == .manual)
        #expect(relaunchedManager.failedAnalyses.first?.recoveryStage == .transcription)
    }

    @Test func manualRetryContinuesFromSavedTranscriptAndClearsRecovery() async throws {
        let progressURL = URL.temporaryDirectory
            .appending(path: "AnalysisProgress-\(UUID().uuidString).json")
        let cacheURL = URL.temporaryDirectory
            .appending(path: "AnalysisCache-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: progressURL)
            try? FileManager.default.removeItem(at: cacheURL)
        }

        let store = AnalysisProgressStore(storeURL: progressURL)
        let transcriber = MockAudioTranscriber()
        let analyzer = RecoverableContentAnalyzer(failuresRemaining: 2)
        let manager = AnalysisStateManager(
            transcriber: transcriber,
            analyzer: analyzer,
            progressStore: store,
            cacheURL: cacheURL,
            scheduleBackgroundAnalysis: { _ in }
        )
        let audioFile = AnalysisFixtures.audioFile()
        defer { GeneratedSessionStore.shared.delete(for: audioFile) }

        await manager.queueForAnalysis(audioFile)
        _ = await manager.resumeInterruptedAnalyses()

        let failure = try #require(manager.failedAnalyses.first)
        #expect(failure.retryState == .manual)
        #expect(failure.recoveryStage == .transcription)
        #expect(await store.allPending().isEmpty)

        await manager.retryFailedAnalysis(failure)

        #expect(transcriber.callCount == 1)
        #expect(analyzer.callCount == 3)
        #expect(manager.failedAnalyses.isEmpty)
        #expect(manager.getCompletedAnalysis(for: audioFile) != nil)
        #expect(await store.manualRecoveryCheckpoints().isEmpty)
    }
}

private struct TransientTestError: LocalizedError {
    var errorDescription: String? { "Temporary transcription failure" }
}

@MainActor
private final class RecoverableContentAnalyzer: ContentAnalyzingService {
    var progress = 0.0
    var statusMessage = ""
    var isModelAvailable = true
    private(set) var callCount = 0
    private var failuresRemaining: Int

    init(failuresRemaining: Int) {
        self.failuresRemaining = failuresRemaining
    }

    func analyzeContent(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile
    ) async throws -> AnalysisResult {
        callCount += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw TransientTestError()
        }
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

@MainActor
private final class InterruptedThenTransientContentAnalyzer: ContentAnalyzingService {
    var progress = 0.0
    var statusMessage = ""
    var isModelAvailable = true
    private(set) var callCount = 0

    func analyzeContent(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile
    ) async throws -> AnalysisResult {
        callCount += 1

        if callCount == 1 {
            while !Task.isCancelled {
                await Task.yield()
            }
            throw CancellationError()
        }

        if callCount == 2 {
            throw TransientTestError()
        }

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

@MainActor
private final class SuspendedAudioTranscriber: AudioTranscribingService {
    var progress = 0.1
    var statusMessage = "Waiting"
    private(set) var hasStarted = false
    private var continuation: CheckedContinuation<AudioTranscriptionResult, Error>?

    func transcribe(audioFile: AudioFile) async throws -> AudioTranscriptionResult {
        hasStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancelTranscription() async {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func releaseResources() async {}
}
