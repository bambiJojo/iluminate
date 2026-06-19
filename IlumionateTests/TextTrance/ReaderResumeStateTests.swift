//  ReaderResumeStateTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct ReaderResumeStateTests {
    @Test func roundTripsThroughJSON() throws {
        let state = ReaderResumeState(
            scriptId: "abc",
            wordIndex: 42,
            settings: PersistedReaderSettings(
                arc: .handoff, speedMultiplier: 1.25,
                subliminalEnabled: true, subliminalSpeed: .deep,
                binauralEnabled: false, lightEnabled: true, beatFrequency: 10),
            phase: .reading,
            scriptContentHash: "hash123",
            savedAt: Date(timeIntervalSince1970: 1_000_000))
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReaderResumeState.self, from: data)
        #expect(decoded.wordIndex == 42)
        #expect(decoded.settings.speedMultiplier == 1.25)
        #expect(decoded.phase == .reading)
    }

    @Test func contentHashIsStableForSameText() {
        let a = ReaderResumeState.contentHash(for: "drift down now")
        let b = ReaderResumeState.contentHash(for: "drift down now")
        let c = ReaderResumeState.contentHash(for: "drift down NOW")
        #expect(a == b)
        #expect(a != c)
    }
}
