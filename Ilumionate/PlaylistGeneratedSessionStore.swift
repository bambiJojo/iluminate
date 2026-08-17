//
//  PlaylistGeneratedSessionStore.swift
//  Ilumionate
//
//  Persistence for playlist-level generated light sessions.
//

import Foundation
import os

@MainActor
final class PlaylistGeneratedSessionStore {
    static let shared = PlaylistGeneratedSessionStore()

    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
            return
        }
        let generatedSessionsRoot = PrivateStorageMigration.migrateItemIfNeeded(
            from: URL.documentsDirectory.appending(
                path: "GeneratedSessions",
                directoryHint: .isDirectory
            ),
            to: AppStoragePaths.generatedSessions
        )
        self.directoryURL = generatedSessionsRoot.appending(
            path: "Playlists",
            directoryHint: .isDirectory
        )
    }

    func sessionURL(forPlaylistID id: UUID) -> URL {
        directoryURL.appending(path: "\(id.uuidString).json")
    }

    func save(_ session: LightSession, for playlist: Playlist) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        let url = sessionURL(forPlaylistID: playlist.id)
        try data.write(to: url, options: .atomic)

        Log.analysis.info("Saved playlist generated session: \(url.lastPathComponent)")
    }

    func load(for playlist: Playlist) -> LightSession? {
        let url = sessionURL(forPlaylistID: playlist.id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LightSession.self, from: data)
    }

    func delete(for playlist: Playlist) {
        let url = sessionURL(forPlaylistID: playlist.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
