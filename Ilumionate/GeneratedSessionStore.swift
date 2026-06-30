//  GeneratedSessionStore.swift
//  Ilumionate
//
//  Canonical persistence for audio-generated light sessions.

import Foundation
import os

@MainActor
final class GeneratedSessionStore {
    static let shared = GeneratedSessionStore()

    private let directoryURL: URL

    init(directoryURL: URL = URL.documentsDirectory.appending(path: "GeneratedSessions", directoryHint: .isDirectory)) {
        self.directoryURL = directoryURL
    }

    func sessionURL(forAudioFileID id: UUID) -> URL {
        directoryURL.appending(path: "\(id.uuidString).json")
    }

    func legacySessionURL(for audioFile: AudioFile) -> URL {
        directoryURL.appending(path: "\(audioFile.displayName)_session.json")
    }

    func save(_ session: LightSession, for audioFile: AudioFile) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        let url = sessionURL(forAudioFileID: audioFile.id)
        try data.write(to: url, options: .atomic)

        Log.analysis.info("💾 Saved generated session: \(url.lastPathComponent)")
    }

    func load(for audioFile: AudioFile) -> LightSession? {
        let url = sessionURL(forAudioFileID: audioFile.id)
        if let session = decodeSession(at: url) {
            return session
        }

        try? migrateLegacySessionIfNeeded(for: audioFile)
        return decodeSession(at: url)
    }

    func exists(for audioFile: AudioFile) -> Bool {
        load(for: audioFile) != nil
    }

    func delete(for audioFile: AudioFile) {
        let urls = [sessionURL(forAudioFileID: audioFile.id)] + legacySessionURLs(for: audioFile)
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func readyCount(for files: [AudioFile]) -> Int {
        files.count { exists(for: $0) }
    }

    private func migrateLegacySessionIfNeeded(for audioFile: AudioFile) throws {
        let canonicalURL = sessionURL(forAudioFileID: audioFile.id)
        if FileManager.default.fileExists(atPath: canonicalURL.path) {
            try FileManager.default.removeItem(at: canonicalURL)
        }

        guard let legacyURL = legacySessionURLs(for: audioFile).first(where: { decodeSession(at: $0) != nil }) else {
            return
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: legacyURL, to: canonicalURL)
        Log.analysis.info("📦 Migrated generated session to \(canonicalURL.lastPathComponent)")
    }

    private func legacySessionURLs(for audioFile: AudioFile) -> [URL] {
        let originalName = URL(filePath: audioFile.filename).lastPathComponent
        let oldWriterBaseName = originalName
            .replacing(".mp3", with: "")
            .replacing(".m4a", with: "")
            .replacing(".wav", with: "")
        let filenames = [
            "\(audioFile.displayName)_session.json",
            "\(oldWriterBaseName)_session.json",
            "\(originalName)_session.json"
        ]

        return filenames.reduce(into: []) { urls, filename in
            let url = directoryURL.appending(path: filename)
            if urls.contains(url) == false {
                urls.append(url)
            }
        }
    }

    private func decodeSession(at url: URL) -> LightSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LightSession.self, from: data)
    }
}
