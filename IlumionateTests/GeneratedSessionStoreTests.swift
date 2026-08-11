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

    @Test func recognizedAudioAutomaticallyLoadsGoldSessionWithoutDiskState() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioFile = makeAudioFile(filename: "recognized.mp3")
        let goldSession = makeSession(name: "Catalog Gold")
        let store = GeneratedSessionStore(
            directoryURL: directory,
            goldSessionProvider: { file in
                file.id == audioFile.id ? goldSession : nil
            }
        )

        #expect(store.load(for: audioFile)?.session_name == "Catalog Gold")
        #expect(store.exists(for: audioFile))
        #expect(
            FileManager.default.fileExists(
                atPath: store.sessionURL(forAudioFileID: audioFile.id).path
            ) == false
        )
    }

    @Test func generatedSessionCannotShadowRecognizedGoldSession() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioFile = makeAudioFile(filename: "recognized.mp3")
        let goldSession = makeSession(name: "Catalog Gold")
        var savedCount = 0
        let store = GeneratedSessionStore(
            directoryURL: directory,
            onSessionSaved: { savedCount += 1 },
            goldSessionProvider: { file in
                file.id == audioFile.id ? goldSession : nil
            }
        )

        try store.save(
            makeSession(name: "Generic Generated"),
            for: audioFile
        )

        #expect(store.load(for: audioFile)?.session_name == "Catalog Gold")
        #expect(savedCount == 0)
        #expect(
            FileManager.default.fileExists(
                atPath: store.sessionURL(forAudioFileID: audioFile.id).path
            ) == false
        )
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

    /// `exists(for:)` stopped decoding in `86e37db` so the Library shelves would
    /// not read a session per row, and it now reports a present-but-corrupt file
    /// as ready — deliberately, per the note on the method: badging a row
    /// optimistically beats stalling the list. `load(for:)` is what must not
    /// hand back a broken session.
    ///
    /// This test asserted the pre-`86e37db` behaviour and had been failing ever
    /// since, in isolation as well as under load.
    @Test func corruptSessionIsBadgedButNeverLoaded() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = GeneratedSessionStore(directoryURL: directory)
        let audioFile = makeAudioFile(filename: "corrupt.mp3")
        try Data("not-json".utf8).write(to: store.sessionURL(forAudioFileID: audioFile.id))

        #expect(store.exists(for: audioFile))
        #expect(store.hasGeneratedScoreOnDisk(for: audioFile))
        // The one that matters: nothing broken reaches playback.
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
