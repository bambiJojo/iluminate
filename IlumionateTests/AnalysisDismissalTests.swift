//
//  AnalysisDismissalTests.swift
//  IlumionateTests
//
//  ERR-013: dismissal must survive relaunch without discarding resumable work.
//

import Testing
import Foundation
@testable import Ilumionate

private func makeAudioFile(id: UUID = UUID()) -> AudioFile {
    AudioFile(
        id: id,
        filename: "test_\(id.uuidString).m4a",
        duration: 300,
        fileSize: 1_024_000,
        createdDate: Date(timeIntervalSince1970: 0)
    )
}

private func temporaryStoreURL() -> URL {
    URL.temporaryDirectory.appending(path: "AnalysisProgress-\(UUID().uuidString).json")
}

struct AnalysisDismissalTests {

    @Test func dismissedRecoveryRoundTripsThroughANewStore() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let failedAt = Date(timeIntervalSince1970: 100)

        let store = AnalysisProgressStore(storeURL: url)
        await store.saveTranscription(AnalysisFixtures.basicTranscription, for: file)
        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription, failedAt: failedAt
        )
        let dismissed = await store.dismiss(fileID: file.id, expectingFailedAt: failedAt)
        #expect(dismissed)

        let reloaded = AnalysisProgressStore(storeURL: url)
        let checkpoint = await reloaded.checkpoint(for: file)
        #expect(checkpoint?.manualRecovery?.dismissedAt != nil)
        // The whole point: dismissal must not discard resumable work.
        #expect(checkpoint?.transcription != nil)
    }

    @Test func staleFailedAtCannotDismissANewerOccurrence() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)

        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription,
            failedAt: Date(timeIntervalSince1970: 300)
        )
        let dismissed = await store.dismiss(
            fileID: file.id, expectingFailedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(dismissed == false)
        let checkpoint = await store.checkpoint(for: file)
        #expect(checkpoint?.manualRecovery?.dismissedAt == nil)
    }

    @Test func newFailureOccurrenceStartsUndismissed() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)
        let first = Date(timeIntervalSince1970: 100)

        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription, failedAt: first
        )
        _ = await store.dismiss(fileID: file.id, expectingFailedAt: first)

        let second = Date(timeIntervalSince1970: 500)
        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription, failedAt: second
        )
        let checkpoint = await store.checkpoint(for: file)
        #expect(checkpoint?.manualRecovery?.dismissedAt == nil)
        #expect(checkpoint?.manualRecovery?.failedAt == second)
    }

    @Test func retryClearsDismissal() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)
        let failedAt = Date(timeIntervalSince1970: 100)

        await store.saveTranscription(AnalysisFixtures.basicTranscription, for: file)
        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription, failedAt: failedAt
        )
        _ = await store.dismiss(fileID: file.id, expectingFailedAt: failedAt)

        await store.saveQueued(file)          // this is what a retry does
        let checkpoint = await store.checkpoint(for: file)
        #expect(checkpoint?.manualRecovery == nil)
        // Retry resumes from the saved transcript rather than transcribing again.
        #expect(checkpoint?.transcription != nil)
    }

    @Test func removeDeletesTheCheckpointEntirely() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)
        let failedAt = Date(timeIntervalSince1970: 100)

        await store.saveTranscription(AnalysisFixtures.basicTranscription, for: file)
        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription, failedAt: failedAt
        )
        let removed = await store.remove(fileID: file.id, expectingFailedAt: failedAt)
        #expect(removed)

        let reloaded = AnalysisProgressStore(storeURL: url)
        #expect(await reloaded.checkpoint(for: file) == nil)
        #expect(await reloaded.manualRecoveryCheckpoints().isEmpty)
    }

    @Test func dismissReturnsFalseWhenNoRecoveryExists() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)
        let dismissed = await store.dismiss(
            fileID: file.id, expectingFailedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(dismissed == false)
    }
}
