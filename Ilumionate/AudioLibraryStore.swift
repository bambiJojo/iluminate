//
//  AudioLibraryStore.swift
//  Ilumionate
//

import AVFoundation
import Foundation
import os

nonisolated enum AudioLibraryStore {
    private nonisolated static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac"]
    private static let persistence = AudioLibraryPersistence()

    /// Runs off the main actor. `@concurrent` is load-bearing — do not drop it.
    ///
    /// This decodes the whole stored library (every `AudioFile`, and with it every
    /// `AnalysisResult` and `TranscriptAnalysis`), walks `Documents`, SHA-256
    /// hashes any file missing a fingerprint, and decodes the 830 KB known-audio
    /// catalog. An Instruments trace on device measured it at ~2.1s per call with
    /// a 75-file library, blocking the main thread every time Library appeared.
    ///
    /// Marking it merely `nonisolated` is not enough: this target builds with
    /// `SWIFT_APPROACHABLE_CONCURRENCY = YES`, so a plain `nonisolated async`
    /// function *inherits the caller's isolation*. Called from a `@MainActor`
    /// `.task`, it therefore ran on the main actor regardless. `@concurrent`
    /// forces the global executor.
    ///
    /// `AudioFile` and `LibraryRepair` are `Sendable` and every caller already
    /// awaits, so results cross back on assignment.
    @concurrent
    nonisolated static func loadRepairingStoredFiles(
        storage: AudioLibraryStorage = .standard,
        documentsURL: URL = .documentsDirectory
    ) async -> [AudioFile] {
        var files = load(storage: storage)
        let repair = await discoverUnregisteredDocumentFiles(
            existingFiles: files,
            documentsURL: documentsURL
        )
        files = repair.existingFiles
        files.insert(contentsOf: repair.addedFiles, at: 0)

        var didChange = repair.didChange
        for index in files.indices where needsCatalogHydration(files[index]) {
            guard let reviewed = KnownAudioCatalog.shared.applyingReviewedAnalysis(
                to: files[index]
            ) else {
                continue
            }
            files[index] = reviewed
            didChange = true
        }

        guard didChange else { return files }

        await save(files, storage: storage)
        if !repair.addedFiles.isEmpty {
            Log.audio.info("📦 Registered \(repair.addedFiles.count) audio file(s) discovered in Documents")
        }
        return files
    }

    static func load(storage: AudioLibraryStorage = .standard) -> [AudioFile] {
        migrateFromUserDefaultsIfNeeded(storage)

        if let data = try? Data(contentsOf: storage.fileURL) {
            return decoded(data)
        }

        // The file could not be read and migration did not manage to create it,
        // so the old store is still the library. Reporting an empty library here
        // would be far worse than reading stale data: `loadRepairingStoredFiles`
        // would find every file in Documents unregistered and re-register it
        // under a fresh identifier, discarding the analysis, rating and play
        // count attached to the old one, and orphaning every playlist.
        if let defaults = storage.legacyDefaults,
           let legacy = defaults.data(forKey: AnalysisStateManager.audioFilesUserDefaultsKey) {
            Log.audio.error(
                "Falling back to the legacy audio library — the stored file could not be read"
            )
            return decoded(legacy)
        }

        return []
    }

    /// The library's duplicate index, built off the main actor.
    ///
    /// `@concurrent` is load-bearing for the same reason it is on
    /// `loadRepairingStoredFiles`: this decodes the entire library — every
    /// `AudioFile`, and with it every transcript and `AnalysisResult` — then
    /// normalises a title per file. Both callers in `AudioManager` are
    /// `@MainActor`, so without this the whole cost lands on the main thread
    /// on every single import.
    @concurrent
    nonisolated static func duplicateIndex(
        storage: AudioLibraryStorage = .standard
    ) async -> DuplicateAudioIndex {
        DuplicateAudioIndex(load(storage: storage))
    }

    /// One entry by identifier, without decoding the library on the caller's
    /// actor. Used after an import resolves to a file already on the shelf.
    @concurrent
    nonisolated static func file(
        withID id: AudioFile.ID,
        storage: AudioLibraryStorage = .standard
    ) async -> AudioFile? {
        load(storage: storage).first { $0.id == id }
    }

    /// Per-element. Decoding the array whole meant one unreadable audio file
    /// silently emptied the user's entire library.
    private static func decoded(_ data: Data) -> [AudioFile] {
        let (files, dropped) = ResilientDecoding.array(AudioFile.self, from: data)
        if dropped > 0 {
            Log.audio.error("Dropped \(dropped) unreadable audio file(s) while loading the library")
        }
        return files
    }

    /// - Returns: whether the library reached disk. Unlike `UserDefaults.set`,
    ///   a file write can fail loudly, and callers that care may check.
    @discardableResult
    static func save(
        _ files: [AudioFile],
        storage: AudioLibraryStorage = .standard
    ) async -> Bool {
        await persistence.save(files, storage: storage)
    }

    @discardableResult
    static func recordPlayback(
        audioFileID: UUID,
        at date: Date = .now,
        storage: AudioLibraryStorage = .standard
    ) async -> Bool {
        await persistence.recordPlayback(
            audioFileID: audioFileID,
            at: date,
            storage: storage
        )
    }

    @discardableResult
    static func setFavorite(
        _ isFavorite: Bool,
        audioFileID: UUID,
        storage: AudioLibraryStorage = .standard
    ) async -> Bool {
        await persistence.setFavorite(
            isFavorite,
            audioFileID: audioFileID,
            storage: storage
        )
    }

    @discardableResult
    static func savePartialTranscription(
        _ transcription: String,
        audioFileID: UUID,
        storage: AudioLibraryStorage = .standard
    ) async -> Bool {
        await persistence.savePartialTranscription(
            transcription,
            audioFileID: audioFileID,
            storage: storage
        )
    }

    /// Records a finished analysis against its library entry.
    ///
    /// Lives here rather than in `AnalysisStateManager` so every library write
    /// goes through one serialized actor and one store. The analyzer used to
    /// read and write `UserDefaults` directly, which is how a rejected write
    /// could be logged as `💾 Persisted analysis result`.
    ///
    /// - Returns: `false` when the file is absent from the library or the write
    ///   failed — the caller should say so rather than claim success.
    @discardableResult
    static func saveAnalysis(
        _ analysis: AnalysisResult,
        transcription: String,
        trackMetadata: AudioTrackMetadata?,
        audioFileID: UUID,
        storage: AudioLibraryStorage = .standard
    ) async -> Bool {
        await persistence.saveAnalysis(
            analysis,
            transcription: transcription,
            trackMetadata: trackMetadata,
            audioFileID: audioFileID,
            storage: storage
        )
    }

    /// Moves a library written by an older build out of `UserDefaults`.
    ///
    /// The raw bytes are copied rather than decoded and re-encoded, so nothing
    /// `ResilientDecoding` would have dropped is lost in the move. The old key
    /// is cleared **only** once the file is on disk: clearing first would
    /// destroy the library outright if the write failed.
    private static func migrateFromUserDefaultsIfNeeded(_ storage: AudioLibraryStorage) {
        guard !FileManager.default.fileExists(atPath: storage.fileURL.path),
              let defaults = storage.legacyDefaults,
              let legacy = defaults.data(
                  forKey: AnalysisStateManager.audioFilesUserDefaultsKey
              )
        else {
            return
        }

        guard write(legacy, to: storage.fileURL) else {
            Log.audio.error(
                "Could not migrate the audio library out of UserDefaults — leaving the old copy in place"
            )
            return
        }

        defaults.removeObject(forKey: AnalysisStateManager.audioFilesUserDefaultsKey)
        Log.audio.info("📦 Migrated the audio library out of UserDefaults (\(legacy.count) bytes)")
    }

    /// Atomic, so a crash mid-write cannot leave a half-written library.
    fileprivate static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            Log.audio.error(
                "Failed to write the audio library: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private static func needsCatalogHydration(_ audioFile: AudioFile) -> Bool {
        guard let entry = KnownAudioCatalog.shared.match(audioFile: audioFile)?.entry else {
            return false
        }

        let expectedPreset = "\(entry.title) — Gold Light Score"
        let expectedVersion = "version \(entry.goldLightScore.scoreVersion)"
        let expectedReview = "Catalog review \(KnownAudioCatalog.reviewedAnalysisVersion)"
        let hasCurrentReview = audioFile.analysisResult?.recommendedPreset == expectedPreset
            && audioFile.analysisResult?.expertAnalysis?.summary.contains(expectedVersion) == true
            && audioFile.analysisResult?.expertAnalysis?.summary.contains(expectedReview) == true
        let hasVerifiedMetadata = audioFile.trackMetadata?.verificationSource != nil
        let needsTranscript = entry.transcript.isEmpty == false
            && AudioTranscriptionResult.sanitizedTranscriptText(
                audioFile.transcription ?? ""
            ).isEmpty

        return hasCurrentReview == false || hasVerifiedMetadata == false || needsTranscript
    }

    @concurrent
    private static func discoverUnregisteredDocumentFiles(
        existingFiles: [AudioFile],
        documentsURL: URL
    ) async -> LibraryRepair {
        let fileManager = FileManager.default
        var repairedExistingFiles = existingFiles
        var repairedFingerprint = false
        for index in repairedExistingFiles.indices where repairedExistingFiles[index].contentFingerprint == nil {
            guard !Task.isCancelled else { break }
            let storedURL = repairedExistingFiles[index].filename.hasPrefix("/")
                ? repairedExistingFiles[index].url
                : documentsURL.appending(path: repairedExistingFiles[index].filename)
            if let fingerprint = AudioFingerprintService.computeFingerprint(for: storedURL) {
                repairedExistingFiles[index].contentFingerprint = fingerprint
                repairedFingerprint = true
            }
        }

        let existingFilenames = Set(repairedExistingFiles.map { $0.url.lastPathComponent })

        let urls = (try? fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let discoveredURLs = urls
            .filter { url in
                supportedExtensions.contains(url.pathExtension.lowercased())
            }
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .filter { url in
                !existingFilenames.contains(url.lastPathComponent)
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }

        var addedFiles: [AudioFile] = []
        addedFiles.reserveCapacity(discoveredURLs.count)
        for url in discoveredURLs {
            guard !Task.isCancelled else { break }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
            addedFiles.append(AudioFile(
                filename: url.lastPathComponent,
                duration: duration.isFinite ? duration : 0,
                fileSize: Int64(values?.fileSize ?? 0),
                createdDate: values?.creationDate ?? Date(),
                contentFingerprint: AudioFingerprintService.computeFingerprint(for: url)
            ))
        }
        return LibraryRepair(
            existingFiles: repairedExistingFiles,
            addedFiles: addedFiles,
            didChange: repairedFingerprint || !addedFiles.isEmpty
        )
    }

    private struct LibraryRepair: Sendable {
        let existingFiles: [AudioFile]
        let addedFiles: [AudioFile]
        let didChange: Bool
    }
}

/// Serializes library writes away from the main actor. Keeping one persistence
/// actor also prevents two rapid UI edits from writing snapshots concurrently.
private actor AudioLibraryPersistence {
    @discardableResult
    func save(_ files: [AudioFile], storage: AudioLibraryStorage) -> Bool {
        guard let data = try? JSONEncoder().encode(files) else {
            Log.audio.error("❌ Failed to encode \(files.count) audio file(s)")
            return false
        }

        return AudioLibraryStore.write(data, to: storage.fileURL)
    }

    func recordPlayback(audioFileID: UUID, at date: Date, storage: AudioLibraryStorage) -> Bool {
        guard var files = decode(storage),
              let index = files.firstIndex(where: { $0.id == audioFileID }) else { return false }
        files[index].lastPlayedDate = date
        files[index].playCount = (files[index].playCount ?? 0) + 1
        return save(files, storage: storage)
    }

    func setFavorite(_ isFavorite: Bool, audioFileID: UUID, storage: AudioLibraryStorage) -> Bool {
        guard var files = decode(storage),
              let index = files.firstIndex(where: { $0.id == audioFileID }) else { return false }
        files[index].isFavorite = isFavorite
        return save(files, storage: storage)
    }

    func savePartialTranscription(
        _ transcription: String,
        audioFileID: UUID,
        storage: AudioLibraryStorage
    ) -> Bool {
        guard transcription.isEmpty == false,
              var files = decode(storage),
              let index = files.firstIndex(where: { $0.id == audioFileID }) else { return false }
        files[index].transcription = transcription
        return save(files, storage: storage)
    }

    func saveAnalysis(
        _ analysis: AnalysisResult,
        transcription: String,
        trackMetadata: AudioTrackMetadata?,
        audioFileID: UUID,
        storage: AudioLibraryStorage
    ) -> Bool {
        guard var files = decode(storage) else {
            Log.analysis.error("⚠️ Could not read the audio library to persist analysis")
            return false
        }
        guard let index = files.firstIndex(where: { $0.id == audioFileID }) else {
            Log.analysis.error("⚠️ AudioFile \(audioFileID) not found in the stored library")
            return false
        }

        files[index].analysisResult = analysis
        files[index].transcription = transcription
        files[index].trackMetadata = trackMetadata
        return save(files, storage: storage)
    }

    /// Element-wise, matching `AudioLibraryStore.load`. Whole-array decoding let
    /// one unreadable entry turn every edit below — favourite, play count,
    /// partial transcript — into a silent no-op.
    private func decode(_ storage: AudioLibraryStorage) -> [AudioFile]? {
        guard let data = try? Data(contentsOf: storage.fileURL) else {
            return nil
        }
        let (files, dropped) = ResilientDecoding.array(AudioFile.self, from: data)
        if dropped > 0 {
            Log.audio.error("Dropped \(dropped) unreadable audio file(s) while updating the library")
        }
        return files.isEmpty ? nil : files
    }
}
