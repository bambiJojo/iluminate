//
//  DeferredAIRetryStoreTests.swift
//  IlumionateTests
//
//  A transient AI failure must leave something to resume from — but a retained
//  checkpoint is picked up by `allPending()` and re-queued at launch, in the
//  foreground, where the device recorded 0/16. That would spend the whole retry
//  budget on attempts that cannot succeed.
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
    URL.temporaryDirectory.appending(path: "DeferredAIRetry-\(UUID().uuidString).json")
}

struct DeferredAIRetryStoreTests {

    @Test("Deferring keeps the saved transcript so only the AI stage re-runs")
    func deferringRetainsTheTranscript() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)

        await store.saveTranscription(AnalysisFixtures.basicTranscription, for: file)
        let deferred = await store.markAwaitingAIRetry(for: file, kind: .systemBusy)
        #expect(deferred)

        let checkpoint = await store.checkpoint(for: file)
        #expect(checkpoint?.transcription != nil)
        #expect(checkpoint?.deferredAIRetry?.kind == .systemBusy)
        #expect(checkpoint?.deferredAIRetry?.attempts == 0)
    }

    /// The load-bearing exclusion. Without it the file is re-queued on the next
    /// launch, in the foreground, and fails three times in a row.
    @Test("A deferred file is not treated as interrupted work")
    func deferredFileIsNotAutoResumed() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)

        await store.saveTranscription(AnalysisFixtures.basicTranscription, for: file)
        _ = await store.markAwaitingAIRetry(for: file, kind: .systemBusy)

        #expect(await store.allPending().isEmpty)
        #expect(await store.deferredAIRetryCheckpoints().count == 1)
    }

    @Test("Deferral survives a relaunch")
    func deferralRoundTripsThroughANewStore() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()

        let store = AnalysisProgressStore(storeURL: url)
        await store.saveTranscription(AnalysisFixtures.basicTranscription, for: file)
        _ = await store.markAwaitingAIRetry(for: file, kind: .rateLimited)

        let reloaded = AnalysisProgressStore(storeURL: url)
        let restored = await reloaded.deferredAIRetryCheckpoints()
        #expect(restored.count == 1)
        #expect(restored.first?.deferredAIRetry?.kind == .rateLimited)
        #expect(await reloaded.allPending().isEmpty)
    }

    @Test("Each attempt is counted so the ceiling can be enforced")
    func attemptsAccumulate() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)

        await store.saveTranscription(AnalysisFixtures.basicTranscription, for: file)
        _ = await store.markAwaitingAIRetry(for: file, kind: .systemBusy)
        _ = await store.recordAIRetryAttempt(for: file.id)
        _ = await store.recordAIRetryAttempt(for: file.id)

        let checkpoint = await store.checkpoint(for: file)
        #expect(checkpoint?.deferredAIRetry?.attempts == 2)
    }

    @Test("Requeueing the file clears the deferral rather than stacking one")
    func queueingClearsTheDeferral() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)

        await store.saveTranscription(AnalysisFixtures.basicTranscription, for: file)
        _ = await store.markAwaitingAIRetry(for: file, kind: .systemBusy)

        await store.saveQueued(file)

        let checkpoint = await store.checkpoint(for: file)
        #expect(checkpoint?.deferredAIRetry == nil)
        // The transcript is the whole point of deferring — it must survive.
        #expect(checkpoint?.transcription != nil)
        #expect(await store.allPending().count == 1)
    }

    @Test("Deferring a file with no checkpoint does nothing")
    func deferringWithoutACheckpointIsRejected() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AnalysisProgressStore(storeURL: url)

        #expect(await store.markAwaitingAIRetry(for: makeAudioFile(), kind: .systemBusy) == false)
    }
}

// MARK: - Selecting a window's worth of work

struct DeferredAIRetrySelectionTests {

    private func checkpoint(
        kind: AIGenerationDiagnosis.Kind,
        attempts: Int,
        lastAttemptAt: Date? = nil
    ) -> AnalysisCheckpoint {
        var checkpoint = AnalysisCheckpoint(
            audioFile: makeAudioFile(),
            transcription: nil,
            analysis: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 0)
        )
        checkpoint.deferredAIRetry = DeferredAIRetry(
            kind: kind,
            attempts: attempts,
            deferredAt: Date(timeIntervalSince1970: 0),
            lastAttemptAt: lastAttemptAt
        )
        return checkpoint
    }

    @Test("Only transient kinds under the ceiling are offered")
    func selectionAppliesThePolicy() {
        let eligible = checkpoint(kind: .systemBusy, attempts: 0)
        let exhausted = checkpoint(
            kind: .systemBusy,
            attempts: DeferredAIAnalysisPolicy.maximumRetryAttempts
        )
        // Should never have been deferred, but must not be retried if it was.
        let settled = checkpoint(kind: .guardrail, attempts: 0)

        let selected = DeferredAIAnalysisPolicy.candidates(
            from: [eligible, exhausted, settled]
        )

        #expect(selected.map(\.audioFileID) == [eligible.audioFile.id])
    }

    @Test("A checkpoint with no deferral is not a candidate")
    func nonDeferredCheckpointIsIgnored() {
        let plain = AnalysisCheckpoint(
            audioFile: makeAudioFile(),
            transcription: nil,
            analysis: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 0)
        )

        #expect(DeferredAIAnalysisPolicy.candidates(from: [plain]).isEmpty)
    }
}
