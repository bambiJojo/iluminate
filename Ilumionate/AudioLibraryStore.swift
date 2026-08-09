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
        defaults: UserDefaults = .standard,
        documentsURL: URL = .documentsDirectory
    ) async -> [AudioFile] {
        var files = load(defaults: defaults)
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

        await save(files, defaults: defaults)
        if !repair.addedFiles.isEmpty {
            Log.audio.info("📦 Registered \(repair.addedFiles.count) audio file(s) discovered in Documents")
        }
        return files
    }

    static func load(defaults: UserDefaults = .standard) -> [AudioFile] {
        guard let data = defaults.data(forKey: AnalysisStateManager.audioFilesUserDefaultsKey) else {
            return []
        }
        // Per-element. Decoding the array whole meant one unreadable audio file
        // silently emptied the user's entire library.
        let (files, dropped) = ResilientDecoding.array(AudioFile.self, from: data)
        if dropped > 0 {
            Log.audio.error("Dropped \(dropped) unreadable audio file(s) while loading the library")
        }
        return files
    }

    static func save(_ files: [AudioFile], defaults: UserDefaults = .standard) async {
        await persistence.save(files, defaults: ThreadSafeUserDefaults(defaults))
    }

    static func recordPlayback(
        audioFileID: UUID,
        at date: Date = .now,
        defaults: UserDefaults = .standard
    ) async {
        await persistence.recordPlayback(
            audioFileID: audioFileID,
            at: date,
            defaults: ThreadSafeUserDefaults(defaults)
        )
    }

    static func setFavorite(
        _ isFavorite: Bool,
        audioFileID: UUID,
        defaults: UserDefaults = .standard
    ) async {
        await persistence.setFavorite(
            isFavorite,
            audioFileID: audioFileID,
            defaults: ThreadSafeUserDefaults(defaults)
        )
    }

    static func savePartialTranscription(
        _ transcription: String,
        audioFileID: UUID,
        defaults: UserDefaults = .standard
    ) async {
        await persistence.savePartialTranscription(
            transcription,
            audioFileID: audioFileID,
            defaults: ThreadSafeUserDefaults(defaults)
        )
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
    func save(_ files: [AudioFile], defaults: ThreadSafeUserDefaults) {
        guard let data = try? JSONEncoder().encode(files) else {
            Log.audio.info("❌ Failed to encode \(files.count) audio file(s)")
            return
        }

        defaults.value.set(data, forKey: AnalysisStateManager.audioFilesUserDefaultsKey)
    }

    func recordPlayback(audioFileID: UUID, at date: Date, defaults: ThreadSafeUserDefaults) {
        guard var files = decode(defaults),
              let index = files.firstIndex(where: { $0.id == audioFileID }) else { return }
        files[index].lastPlayedDate = date
        files[index].playCount = (files[index].playCount ?? 0) + 1
        save(files, defaults: defaults)
    }

    func setFavorite(_ isFavorite: Bool, audioFileID: UUID, defaults: ThreadSafeUserDefaults) {
        guard var files = decode(defaults),
              let index = files.firstIndex(where: { $0.id == audioFileID }) else { return }
        files[index].isFavorite = isFavorite
        save(files, defaults: defaults)
    }

    func savePartialTranscription(
        _ transcription: String,
        audioFileID: UUID,
        defaults: ThreadSafeUserDefaults
    ) {
        guard transcription.isEmpty == false,
              var files = decode(defaults),
              let index = files.firstIndex(where: { $0.id == audioFileID }) else { return }
        files[index].transcription = transcription
        save(files, defaults: defaults)
    }

    private func decode(_ defaults: ThreadSafeUserDefaults) -> [AudioFile]? {
        guard let data = defaults.value.data(forKey: AnalysisStateManager.audioFilesUserDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode([AudioFile].self, from: data)
    }
}

/// `UserDefaults` supports concurrent access, but Foundation does not yet mark
/// the reference type Sendable. This wrapper is confined to the persistence
/// actor and is never mutated outside the documented thread-safe API.
private nonisolated struct ThreadSafeUserDefaults: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}
