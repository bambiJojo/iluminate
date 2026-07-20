//  GeneratedSessionStoreTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct GeneratedSessionStoreTests {

    @Test func successfulSaveReportsGeneratedSession() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var savedCount = 0
        let store = GeneratedSessionStore(
            directoryURL: directory,
            onSessionSaved: { savedCount += 1 }
        )

        try store.save(
            makeSession(name: "Measured Session"),
            for: makeAudioFile(filename: "measured.mp3")
        )

        #expect(savedCount == 1)
    }

    @Test func saveWritesCanonicalIDBasedSessionFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = GeneratedSessionStore(directoryURL: directory)
        let audioFile = makeAudioFile(filename: "sessions/deep-drift.m4a")
        let session = makeSession(name: "Deep Drift Lights")

        try store.save(session, for: audioFile)

        let canonicalURL = store.sessionURL(forAudioFileID: audioFile.id)
        #expect(FileManager.default.fileExists(atPath: canonicalURL.path))
        #expect(store.load(for: audioFile)?.session_name == "Deep Drift Lights")
        #expect(store.exists(for: audioFile))
    }

    @Test func loadMigratesLegacyDisplayNameSessionFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = GeneratedSessionStore(directoryURL: directory)
        let audioFile = makeAudioFile(filename: "legacy-name.wav")
        let session = makeSession(name: "Legacy Lights")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(session)
        try data.write(to: store.legacySessionURL(for: audioFile))

        #expect(FileManager.default.fileExists(atPath: store.sessionURL(forAudioFileID: audioFile.id).path) == false)
        #expect(store.load(for: audioFile)?.session_name == "Legacy Lights")
        #expect(FileManager.default.fileExists(atPath: store.sessionURL(forAudioFileID: audioFile.id).path))
    }

    @Test func loadMigratesLegacyFilenameThatRetainedExtension() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = GeneratedSessionStore(directoryURL: directory)
        let audioFile = makeAudioFile(filename: "legacy-aac.aac")
        let session = makeSession(name: "Legacy AAC Lights")
        let legacyURL = directory.appending(path: "legacy-aac.aac_session.json")

        try JSONEncoder().encode(session).write(to: legacyURL)

        #expect(store.load(for: audioFile)?.session_name == "Legacy AAC Lights")
        #expect(FileManager.default.fileExists(atPath: store.sessionURL(forAudioFileID: audioFile.id).path))
    }

    @Test func corruptSessionIsNotReportedAsReady() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = GeneratedSessionStore(directoryURL: directory)
        let audioFile = makeAudioFile(filename: "corrupt.mp3")
        try Data("not-json".utf8).write(to: store.sessionURL(forAudioFileID: audioFile.id))

        #expect(store.exists(for: audioFile) == false)
        #expect(store.load(for: audioFile) == nil)
    }

    @Test func deleteRemovesCanonicalAndLegacySessionFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = GeneratedSessionStore(directoryURL: directory)
        let audioFile = makeAudioFile(filename: "delete-me.mp3")
        let session = makeSession(name: "Delete Me")
        let data = try JSONEncoder().encode(session)

        try store.save(session, for: audioFile)
        try data.write(to: store.legacySessionURL(for: audioFile))

        store.delete(for: audioFile)

        #expect(FileManager.default.fileExists(atPath: store.sessionURL(forAudioFileID: audioFile.id).path) == false)
        #expect(FileManager.default.fileExists(atPath: store.legacySessionURL(for: audioFile).path) == false)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "generated-session-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeAudioFile(filename: String) -> AudioFile {
        AudioFile(
            id: UUID(),
            filename: filename,
            duration: 120,
            fileSize: 2048,
            createdDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func makeSession(name: String) -> LightSession {
        LightSession(
            session_name: name,
            duration_sec: 120,
            light_score: [
                LightMoment(
                    time: 0,
                    frequency: 8,
                    intensity: 0.35,
                    waveform: .sine
                ),
                LightMoment(
                    time: 60,
                    frequency: 6,
                    intensity: 0.5,
                    waveform: .softPulse,
                    ramp_duration: 8
                )
            ]
        )
    }
}
