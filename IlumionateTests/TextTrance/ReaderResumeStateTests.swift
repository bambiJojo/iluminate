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
                binauralEnabled: false, lightEnabled: true, beatFrequency: 10,
                attentionGateEnabled: true),
            phase: .reading,
            scriptContentHash: "hash123",
            savedAt: Date(timeIntervalSince1970: 1_000_000))
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReaderResumeState.self, from: data)
        #expect(decoded.wordIndex == 42)
        #expect(decoded.settings.speedMultiplier == 1.25)
        #expect(decoded.settings.attentionGateEnabled)
        #expect(decoded.settings.speedTraining == .standard)
        #expect(decoded.settings.displayPreferences == .standard)
        #expect(decoded.phase == .reading)
    }

    @Test func missingOptionalSettingsDecodeWithDefaults() throws {
        let json = """
        {
          "arc": "fullText",
          "speedMultiplier": 1,
          "subliminalEnabled": true,
          "subliminalSpeed": "medium",
          "binauralEnabled": false,
          "lightEnabled": false,
          "beatFrequency": 10
        }
        """
        let settings = try JSONDecoder().decode(PersistedReaderSettings.self, from: Data(json.utf8))
        #expect(!settings.attentionGateEnabled)
        #expect(settings.speedTraining == .standard)
        #expect(settings.displayPreferences == .standard)
    }

    @Test func contentHashIsStableForSameText() {
        let a = ReaderResumeState.contentHash(for: "drift down now")
        let b = ReaderResumeState.contentHash(for: "drift down now")
        let c = ReaderResumeState.contentHash(for: "drift down NOW")
        #expect(a == b)
        #expect(a != c)
    }

    @Test func usabilityRequiresMatchingHashAndInRangeIndex() {
        let state = ReaderResumeState(
            scriptId: "abc",
            wordIndex: 2,
            settings: PersistedReaderSettings(
                arc: .fullText, speedMultiplier: 1,
                subliminalEnabled: true, subliminalSpeed: .medium,
                binauralEnabled: false, lightEnabled: false, beatFrequency: 10),
            phase: .reading,
            scriptContentHash: "hash123",
            savedAt: .now)
        let firstWordState = ReaderResumeState(
            scriptId: "abc",
            wordIndex: 0,
            settings: state.settings,
            phase: .reading,
            scriptContentHash: "hash123",
            savedAt: .now)
        let beforeStartState = ReaderResumeState(
            scriptId: "abc",
            wordIndex: -1,
            settings: state.settings,
            phase: .reading,
            scriptContentHash: "hash123",
            savedAt: .now)

        #expect(state.isUsable(contentHash: "hash123", scheduleCount: 3))
        #expect(firstWordState.isUsable(contentHash: "hash123", scheduleCount: 3))
        #expect(!beforeStartState.isUsable(contentHash: "hash123", scheduleCount: 3))
        #expect(!state.isUsable(contentHash: "changed", scheduleCount: 3))
        #expect(!state.isUsable(contentHash: "hash123", scheduleCount: 2))
        #expect(!state.isUsable(contentHash: "hash123", scheduleCount: 0))
    }
}
