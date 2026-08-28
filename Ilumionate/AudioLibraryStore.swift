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
        documentsURL: URL = .documentsDirectory,
        managedAudioURL: URL = AppStoragePaths.managedAudio
    ) async -> [AudioFile] {
        let trace = PerformanceTrace.begin("Library Refresh")
        defer { PerformanceTrace.end(trace) }

        let files = load(storage: storage)
        let repair = await discoverUnregisteredDocumentFiles(
            existingFiles: files,
            documentsURL: documentsURL,
            managedAudioURL: managedAudioURL
        )
        _ = await persistence.reconcileRepair(
            repair,
            storage: storage
        )
        if !repair.addedFiles.isEmpty {
            Log.audio.info("📦 Registered \(repair.addedFiles.count) audio file(s) discovered in Documents")
        }
        return await persistence.migrateLegacyAudio(
            storage: storage,
            documentsURL: documentsURL,
            managedAudioURL: managedAudioURL
        )
    }

    static func load(storage: AudioLibraryStorage = .standard) -> [AudioFile] {
        let trace = PerformanceTrace.begin("Library Decode")
        defer { PerformanceTrace.end(trace) }

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
    /// normalises a title per file. Both callers in `AudioIntake` are
    /// `@MainActor`, so without this the whole cost lands on the main thread
    /// on every single import.
    @concurrent
    nonisolated static func duplicateIndex(
        storage: AudioLibraryStorage = .standard
    ) async -> DuplicateAudioIndex {
        DuplicateAudioIndex(load(storage: storage))
    }

    /// The whole library, decoded off the caller's actor.
    ///
    /// `@concurrent` is load-bearing for the same reason it is on
    /// `duplicateIndex`. Unlike `loadRepairingStoredFiles` this neither walks
    /// `Documents` nor writes anything back, which is what a reader that only
    /// needs to resolve known identifiers — `PlaylistPlayerController` — wants.
    @concurrent
    nonisolated static func allFiles(
        storage: AudioLibraryStorage = .standard
    ) async -> [AudioFile] {
        load(storage: storage)
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
        PerformanceTrace.event("Library Replace")
        return await persistence.save(files, storage: storage)
    }

    /// Inserts one file without exposing a read-modify-write snapshot to the
    /// caller. The returned library is the exact state that reached disk.
    @discardableResult
    static func add(
        _ file: AudioFile,
        storage: AudioLibraryStorage = .standard
    ) async -> [AudioFile]? {
        PerformanceTrace.event("Library Add")
        return await persistence.add(file, storage: storage)
    }

    /// Removes entries by identity while preserving unrelated mutations that
    /// may have reached the persistence actor first.
    @discardableResult
    static func remove(
        audioFileIDs: Set<AudioFile.ID>,
        storage: AudioLibraryStorage = .standard
    ) async -> [AudioFile]? {
        PerformanceTrace.event("Library Remove")
        return await persistence.remove(audioFileIDs: audioFileIDs, storage: storage)
    }

    /// Re-inserts a recovered deletion batch at its original positions.
    @discardableResult
    static func restore(
        _ entries: [StagedAudioFile],
        storage: AudioLibraryStorage = .standard
    ) async -> [AudioFile]? {
        PerformanceTrace.event("Library Restore")
        return await persistence.restore(entries, storage: storage)
    }

    /// Recomputes duplicate keepers from the latest stored entries, then
    /// removes only the identifiers whose files were successfully staged.
    @discardableResult
    static func mergeDuplicates(
        remapping: [AudioFile.ID: AudioFile.ID],
        storage: AudioLibraryStorage = .standard
    ) async -> [AudioFile]? {
        PerformanceTrace.event("Library Merge Duplicates")
        return await persistence.mergeDuplicates(remapping: remapping, storage: storage)
    }

    /// Removes the file-backed library without exposing its location to callers.
    /// Serialized with every other library mutation so a reset cannot race a
    /// write and leave the library behind again.
    static func deleteLibrary(
        storage: AudioLibraryStorage = .standard
    ) async throws {
        PerformanceTrace.event("Library Delete")
        try await persistence.deleteLibrary(storage: storage)
    }

    @discardableResult
    static func recordPlayback(
        audioFileID: UUID,
        at date: Date = .now,
        storage: AudioLibraryStorage = .standard
    ) async -> Bool {
        PerformanceTrace.event("Library Record Playback")
        return await persistence.recordPlayback(
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
        PerformanceTrace.event("Library Set Favorite")
        return await persistence.setFavorite(
            isFavorite,
            audioFileID: audioFileID,
            storage: storage
        )
    }

    @discardableResult
    static func setUserTitle(
        _ title: String?,
        audioFileID: UUID,
        storage: AudioLibraryStorage = .standard
    ) async -> Bool {
        PerformanceTrace.event("Library Set Title")
        return await persistence.setUserTitle(
            title,
            audioFileID: audioFileID,
            storage: storage
        )
    }

    @discardableResult
    static func setRating(
        _ rating: Int?,
        audioFileID: UUID,
        storage: AudioLibraryStorage = .standard
    ) async -> Bool {
        PerformanceTrace.event("Library Set Rating")
        return await persistence.setRating(
            rating,
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
        PerformanceTrace.event("Library Save Transcript")
        return await persistence.savePartialTranscription(
            transcription,
            audioFileID: audioFileID,
            storage: storage
        )
    }

    /// Caches a measured dead-time profile against its library entry.
    ///
    /// Playlist crossfades are sized from this, and measuring it costs a scan
    /// of both ends of the file, so it is worth keeping. Routed through the
    /// persistence actor like every other library write.
    @discardableResult
    static func saveDeadTimeProfile(
        _ profile: DeadTimeProfile,
        audioFileID: UUID,
        storage: AudioLibraryStorage = .standard
    ) async -> Bool {
        PerformanceTrace.event("Library Save Dead Time")
        return await persistence.saveDeadTimeProfile(
            profile,
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
        PerformanceTrace.event("Library Save Analysis")
        return await persistence.saveAnalysis(
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

    fileprivate static func needsCatalogHydration(_ audioFile: AudioFile) -> Bool {
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
        documentsURL: URL,
        managedAudioURL: URL
    ) async -> LibraryRepair {
        var repairedExistingFiles = existingFiles
        for index in repairedExistingFiles.indices where repairedExistingFiles[index].contentFingerprint == nil {
            guard !Task.isCancelled else { break }
            let storedURL: URL
            if repairedExistingFiles[index].filename.hasPrefix("/") {
                storedURL = repairedExistingFiles[index].url
            } else if repairedExistingFiles[index].storageLocation == .managed {
                storedURL = managedAudioURL.appending(
                    path: repairedExistingFiles[index].filename
                )
            } else {
                storedURL = documentsURL.appending(
                    path: repairedExistingFiles[index].filename
                )
            }
            if let fingerprint = AudioFingerprintService.computeFingerprint(for: storedURL) {
                repairedExistingFiles[index].contentFingerprint = fingerprint
            }
        }

        // Discovery of unregistered Documents-root audio was retired when the
        // cable inbox landed. Both scanned the same directory, so whichever ran
        // first won — and this one had no stability check, so it could register
        // a file Finder was still copying. `CableFileImportService` now owns
        // root intake and routes it through the full import pipeline.
        //
        // The fingerprint repair above is unrelated and still required.
        return LibraryRepair(
            existingFiles: repairedExistingFiles,
            addedFiles: []
        )
    }

    fileprivate struct LibraryRepair: Sendable {
        let existingFiles: [AudioFile]
        let addedFiles: [AudioFile]
    }
}

/// Serializes library writes away from the main actor. Keeping one persistence
/// actor also prevents two rapid UI edits from writing snapshots concurrently.
private actor AudioLibraryPersistence {
    /// Moves each legacy library file behind Application Support, persisting
    /// its new location before proceeding to the next file. A failed library
    /// write rolls that file back, while a crash after the move is recovered by
    /// the deterministic per-ID destination on the next launch.
    func migrateLegacyAudio(
        storage: AudioLibraryStorage,
        documentsURL: URL,
        managedAudioURL: URL
    ) -> [AudioFile] {
        var files = decode(storage) ?? []
        let fileManager = FileManager.default

        for index in files.indices {
            let current = files[index]
            guard current.filename.hasPrefix("/") == false,
                  current.storageLocation != .managed else {
                continue
            }

            let sourceURL = documentsURL.appending(path: current.filename)
            let relativePath = "\(current.id.uuidString)/\(sourceURL.lastPathComponent)"
            let destinationURL = managedAudioURL.appending(path: relativePath)
            let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
            let sourceExists = fileManager.fileExists(atPath: sourceURL.path)
            guard destinationExists || sourceExists else {
                continue
            }

            // A destination left by a completed move is valid crash recovery,
            // but an unrelated file at the deterministic path must never
            // replace the library's legacy bytes. Keep using Documents until a
            // human can resolve the collision.
            if destinationExists, sourceExists {
                let sourceFingerprint = AudioFingerprintService.computeFingerprint(for: sourceURL)
                let destinationFingerprint = AudioFingerprintService.computeFingerprint(
                    for: destinationURL
                )
                guard sourceFingerprint != nil,
                      sourceFingerprint == destinationFingerprint else {
                    Log.audio.error(
                        "Could not privatize \(sourceURL.lastPathComponent, privacy: .public): the private destination contains different audio"
                    )
                    continue
                }
            }

            do {
                if destinationExists == false {
                    try fileManager.createDirectory(
                        at: destinationURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                }

                var migrated = current
                migrated.filename = relativePath
                migrated.storageLocation = .managed
                var candidate = files
                candidate[index] = migrated

                guard save(candidate, storage: storage) else {
                    if destinationExists == false {
                        try? fileManager.moveItem(at: destinationURL, to: sourceURL)
                    }
                    continue
                }

                files = candidate
                if destinationExists,
                   fileManager.fileExists(atPath: sourceURL.path),
                   AudioFingerprintService.computeFingerprint(for: sourceURL)
                    == AudioFingerprintService.computeFingerprint(for: destinationURL) {
                    try? fileManager.removeItem(at: sourceURL)
                }
            } catch {
                Log.audio.error(
                    "Could not privatize \(sourceURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return files
    }

    func deleteLibrary(storage: AudioLibraryStorage) throws {
        let trace = PerformanceTrace.begin("Library Delete Files")
        defer { PerformanceTrace.end(trace) }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: storage.fileURL.path()) {
            try fileManager.removeItem(at: storage.fileURL)
        }
        storage.legacyDefaults?.removeObject(
            forKey: AnalysisStateManager.audioFilesUserDefaultsKey
        )
    }

    @discardableResult
    func save(_ files: [AudioFile], storage: AudioLibraryStorage) -> Bool {
        let trace = PerformanceTrace.begin("Library Persist")
        defer { PerformanceTrace.end(trace) }

        guard let data = try? JSONEncoder().encode(files) else {
            Log.audio.error("❌ Failed to encode \(files.count) audio file(s)")
            return false
        }

        return AudioLibraryStore.write(data, to: storage.fileURL)
    }

    /// Merges slow filesystem discovery into the latest stored library instead
    /// of writing the snapshot that discovery started from. This closes the
    /// remaining stale-snapshot window during a library refresh.
    func reconcileRepair(
        _ repair: AudioLibraryStore.LibraryRepair,
        storage: AudioLibraryStorage
    ) -> [AudioFile] {
        var files = decode(storage) ?? []
        let repairedByID = Dictionary(
            uniqueKeysWithValues: repair.existingFiles.map { ($0.id, $0) }
        )
        var didChange = false

        for index in files.indices where files[index].contentFingerprint == nil {
            guard let fingerprint = repairedByID[files[index].id]?.contentFingerprint else {
                continue
            }
            files[index].contentFingerprint = fingerprint
            didChange = true
        }

        let registeredFilenames = Set(files.map { $0.url.lastPathComponent })
        let additions = repair.addedFiles.filter { added in
            files.contains(where: { $0.id == added.id }) == false
                && registeredFilenames.contains(added.url.lastPathComponent) == false
        }
        if additions.isEmpty == false {
            files.insert(contentsOf: additions, at: 0)
            didChange = true
        }

        for index in files.indices where AudioLibraryStore.needsCatalogHydration(files[index]) {
            guard let reviewed = KnownAudioCatalog.shared.applyingReviewedAnalysis(
                to: files[index]
            ) else {
                continue
            }
            files[index] = reviewed
            didChange = true
        }

        if didChange {
            _ = save(files, storage: storage)
        }
        return files
    }

    func add(_ file: AudioFile, storage: AudioLibraryStorage) -> [AudioFile]? {
        var files = decode(storage) ?? []
        guard files.contains(where: { $0.id == file.id }) == false else {
            return files
        }
        files.insert(file, at: 0)
        return save(files, storage: storage) ? files : nil
    }

    func remove(
        audioFileIDs: Set<AudioFile.ID>,
        storage: AudioLibraryStorage
    ) -> [AudioFile]? {
        guard var files = decode(storage) else { return nil }
        files.removeAll { audioFileIDs.contains($0.id) }
        return save(files, storage: storage) ? files : nil
    }

    func restore(
        _ entries: [StagedAudioFile],
        storage: AudioLibraryStorage
    ) -> [AudioFile]? {
        var files = decode(storage) ?? []
        for entry in entries.sorted(by: { $0.originalIndex < $1.originalIndex }) {
            guard files.contains(where: { $0.id == entry.file.id }) == false else { continue }
            files.insert(entry.file, at: min(max(entry.originalIndex, 0), files.count))
        }
        return save(files, storage: storage) ? files : nil
    }

    func mergeDuplicates(
        remapping: [AudioFile.ID: AudioFile.ID],
        storage: AudioLibraryStorage
    ) -> [AudioFile]? {
        guard var files = decode(storage) else { return nil }

        let redundantIDs = Set(remapping.keys)
        for keeperID in Set(remapping.values) {
            guard let keeper = files.first(where: { $0.id == keeperID }) else { continue }
            let redundant = files.filter {
                remapping[$0.id] == keeperID
            }
            guard redundant.isEmpty == false else { continue }

            let merged = DuplicateAudioGroup(keeper: keeper, redundant: redundant).merged()
            if let keeperIndex = files.firstIndex(where: { $0.id == keeperID }) {
                files[keeperIndex] = merged
            }
        }
        files.removeAll { redundantIDs.contains($0.id) }
        return save(files, storage: storage) ? files : nil
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

    func setUserTitle(_ title: String?, audioFileID: UUID, storage: AudioLibraryStorage) -> Bool {
        guard var files = decode(storage),
              let index = files.firstIndex(where: { $0.id == audioFileID }) else { return false }
        files[index].userTitle = title
        return save(files, storage: storage)
    }

    func setRating(_ rating: Int?, audioFileID: UUID, storage: AudioLibraryStorage) -> Bool {
        guard var files = decode(storage),
              let index = files.firstIndex(where: { $0.id == audioFileID }) else { return false }
        files[index].rating = rating
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

    func saveDeadTimeProfile(
        _ profile: DeadTimeProfile,
        audioFileID: UUID,
        storage: AudioLibraryStorage
    ) -> Bool {
        guard var files = decode(storage),
              let index = files.firstIndex(where: { $0.id == audioFileID }) else { return false }
        files[index].deadTimeProfile = profile
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
        let trace = PerformanceTrace.begin("Library Mutation Decode")
        defer { PerformanceTrace.end(trace) }

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
