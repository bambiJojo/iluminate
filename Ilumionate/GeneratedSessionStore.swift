//  GeneratedSessionStore.swift
//  Ilumionate
//
//  Canonical persistence for audio-generated light sessions.

import Foundation
import os

@MainActor
final class GeneratedSessionStore {
    static let shared = GeneratedSessionStore()

    /// `nonisolated` so the Analysis Task Center can build session URLs and
    /// decode scores off the main actor. It is an immutable `Sendable` value;
    /// everything that mutates state (the gold-match cache) stays isolated.
    private nonisolated let directoryURL: URL
    private let onSessionSaved: () -> Void
    private let goldSessionProvider: (AudioFile) -> LightSession?

    /// Whether each file matched the bundled catalog, remembered per file.
    ///
    /// The default provider runs `KnownAudioCatalog`'s fuzzy match, which folds
    /// and tokenises strings for every alias of all 54 entries on each call.
    /// `exists(for:)` reaches it for every file that has no score on disk — the
    /// common case — and Library asks once per file plus once per visible row,
    /// on every appear.
    ///
    /// Never needs invalidating: a gold match is derived from the file's own
    /// identity against a bundled catalog that cannot change at runtime, and
    /// `exists(for:)` consults the disk before it consults this, so a score
    /// saved later is still seen.
    /// `nil` inner value means "matched nothing"; an absent key means "not yet
    /// asked". Caching the score itself rather than a flag means `load(for:)`
    /// benefits too — it was still running the match on every call.
    private var goldMatchCache: [UUID: LightSession?] = [:]

    init(
        directoryURL: URL? = nil,
        onSessionSaved: @escaping () -> Void = {
            UsageAnalytics.shared.sessionGenerated()
        },
        goldSessionProvider: @escaping (AudioFile) -> LightSession? = {
            KnownAudioCatalog.shared.goldLightSession(for: $0)
        }
    ) {
        self.directoryURL = directoryURL ?? PrivateStorageMigration.migrateItemIfNeeded(
            from: URL.documentsDirectory.appending(
                path: "GeneratedSessions",
                directoryHint: .isDirectory
            ),
            to: AppStoragePaths.generatedSessions
        )
        self.onSessionSaved = onSessionSaved
        self.goldSessionProvider = goldSessionProvider
    }

    nonisolated func sessionURL(forAudioFileID id: UUID) -> URL {
        directoryURL.appending(path: "\(id.uuidString).json")
    }

    func legacySessionURL(for audioFile: AudioFile) -> URL {
        directoryURL.appending(path: "\(audioFile.displayName)_session.json")
    }

    func save(_ session: LightSession, for audioFile: AudioFile) throws {
        guard hasGoldSession(audioFile) == false else {
            Log.analysis.info("🏅 Preserved bundled gold light score for \(audioFile.filename)")
            return
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        let url = sessionURL(forAudioFileID: audioFile.id)
        try data.write(to: url, options: .atomic)
        onSessionSaved()

        Log.analysis.info("💾 Saved generated session: \(url.lastPathComponent)")
    }

    func load(for audioFile: AudioFile) -> LightSession? {
        if let goldSession = goldSession(for: audioFile) {
            return goldSession
        }

        let url = sessionURL(forAudioFileID: audioFile.id)
        if let session = decodeSession(at: url) {
            return session
        }

        try? migrateLegacySessionIfNeeded(for: audioFile)
        return decodeSession(at: url)
    }

    /// Whether a generated score exists, without paying to decode it.
    ///
    /// This used to be `load(for:) != nil`, which read the file, JSON-decoded it,
    /// and on a miss attempted a legacy migration and decoded again — then
    /// consulted the 830 KB known-audio catalog. Callers hit it once per row
    /// (`AudioFileRow`) and once per file (`readyCount`), so a library of any
    /// size spent that on the main actor on every appear.
    ///
    /// The cheap checks come first and answer for anything already on disk. Only
    /// a file with no score anywhere falls through to the catalog.
    ///
    /// Trade-off: a present-but-corrupt score now reports `true` here while
    /// `load(for:)` still returns nil. Badging a row optimistically is the
    /// better failure than stalling the list.
    func exists(for audioFile: AudioFile) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: sessionURL(forAudioFileID: audioFile.id).path) {
            return true
        }
        if legacySessionURLs(for: audioFile).contains(where: {
            fileManager.fileExists(atPath: $0.path)
        }) {
            return true
        }
        return hasGoldSession(audioFile)
    }

    /// Disk only — deliberately no catalog fallback.
    ///
    /// The "Your Sessions" shelf is about scores generated from the listener's
    /// own audio, so a bundled gold score does not belong in it. Keeping the
    /// catalog out also keeps a fuzzy match per file off the main actor during
    /// Library's derivation, which is what made a 75-file library slow to open.
    func hasGeneratedScoreOnDisk(for audioFile: AudioFile) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: sessionURL(forAudioFileID: audioFile.id).path) {
            return true
        }
        return legacySessionURLs(for: audioFile).contains {
            fileManager.fileExists(atPath: $0.path)
        }
    }

    /// The bundled catalog score for a file, if one matches.
    ///
    /// Exposed for the Analysis Task Center, whose ready enumeration runs the
    /// disk half off the main actor and cannot reach `load(for:)`. This half is
    /// an in-memory catalog match backed by `goldMatchCache`, so calling it per
    /// library file costs nothing after the first pass.
    func goldSessionIfAny(for audioFile: AudioFile) -> LightSession? {
        goldSession(for: audioFile)
    }

    private func goldSession(for audioFile: AudioFile) -> LightSession? {
        if let cached = goldMatchCache[audioFile.id] { return cached }
        let matched = goldSessionProvider(audioFile)
        goldMatchCache[audioFile.id] = matched
        return matched
    }

    private func hasGoldSession(_ audioFile: AudioFile) -> Bool {
        goldSession(for: audioFile) != nil
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
