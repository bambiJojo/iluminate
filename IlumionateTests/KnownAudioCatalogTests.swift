//  KnownAudioCatalogTests.swift
//  IlumionateTests

import Testing
@testable import Ilumionate

struct KnownAudioCatalogTests {
    @Test func appStoreBuildShipsWithoutBundledThirdPartyCatalog() {
        #expect(KnownAudioCatalog.shared.entries.isEmpty)
    }

    @Test func missingCatalogFallsBackToNormalAnalysis() {
        let file = AudioFile(
            filename: "personal-recording.m4a",
            duration: 60,
            fileSize: 1_024
        )

        #expect(KnownAudioCatalog.shared.match(audioFile: file) == nil)
        #expect(KnownAudioCatalog.shared.transcription(for: file) == nil)
        #expect(KnownAudioCatalog.shared.verifiedMetadata(for: file) == nil)
        #expect(KnownAudioCatalog.shared.goldLightSession(for: file) == nil)
    }
}
