//  ReaderProgressStoreTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct ReaderProgressStoreTests {
    private func tempDir() -> URL {
        URL.temporaryDirectory.appending(path: "reader-store-\(UUID().uuidString)")
    }

    private func makeState(id: String, savedAt: Date = .now) -> ReaderResumeState {
        ReaderResumeState(
            scriptId: id, wordIndex: 5,
            settings: PersistedReaderSettings(
                arc: .fullText, speedMultiplier: 1.0,
                subliminalEnabled: true, subliminalSpeed: .medium,
                binauralEnabled: false, lightEnabled: false, beatFrequency: 10),
            phase: .reading, scriptContentHash: "h", savedAt: savedAt)
    }

    @Test func savesAndLoadsByScriptId() {
        let store = ReaderProgressStore(directory: tempDir())
        store.save(makeState(id: "alpha"))
        #expect(store.resumeState(forScriptId: "alpha")?.wordIndex == 5)
        #expect(store.resumeState(forScriptId: "missing") == nil)
    }

    @Test func persistsAcrossInstances() {
        let dir = tempDir()
        let a = ReaderProgressStore(directory: dir)
        a.save(makeState(id: "beta"))
        let b = ReaderProgressStore(directory: dir)
        #expect(b.resumeState(forScriptId: "beta")?.wordIndex == 5)
    }

    @Test func clearRemovesEntry() {
        let store = ReaderProgressStore(directory: tempDir())
        store.save(makeState(id: "gamma"))
        store.clear(scriptId: "gamma")
        #expect(store.resumeState(forScriptId: "gamma") == nil)
    }

    @Test func recentStatesAreNewestFirst() {
        let store = ReaderProgressStore(directory: tempDir())
        store.save(makeState(id: "older", savedAt: Date(timeIntervalSince1970: 100)))
        store.save(makeState(id: "newer", savedAt: Date(timeIntervalSince1970: 200)))

        #expect(store.recentStates.map(\.scriptId) == ["newer", "older"])
    }

    @Test func expiredEntriesArePrunedOnLoad() {
        let dir = tempDir()
        let old = Date.now.addingTimeInterval(-31 * 24 * 60 * 60)
        let a = ReaderProgressStore(directory: dir)
        a.save(makeState(id: "stale", savedAt: old))
        let b = ReaderProgressStore(directory: dir)   // prunes on load
        #expect(b.resumeState(forScriptId: "stale") == nil)
    }
}
