//
//  BackgroundAnalysisTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct BackgroundAnalysisTests {
    @Test func continuedProcessingUsesConcreteRegisteredIdentifier() {
        let identifier = BackgroundAnalysisScheduler.makeContinuedIdentifier()

        #expect(identifier.hasPrefix(BackgroundAnalysisScheduler.continuedIdentifierPrefix))
        #expect(!identifier.contains("*"))
        #expect(BackgroundAnalysisScheduler.shared.registerContinuedHandler(for: identifier))
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

    @Test func transientFailureIsRetriedOnceThenRemovesDurableCheckpoint() async throws {
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
        #expect(await store.allPending().map(\.audioFile.id) == [audioFile.id])

        let succeeded = await manager.resumeInterruptedAnalyses()

        #expect(succeeded)
        #expect(await store.allPending().isEmpty)
        #expect(transcriber.callCount == 2)
        #expect(manager.failedAnalyses.count == 2)
    }
}

private struct TransientTestError: LocalizedError {
    var errorDescription: String? { "Temporary transcription failure" }
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
