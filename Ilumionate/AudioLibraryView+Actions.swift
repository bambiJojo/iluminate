// AudioLibraryView+Actions.swift
// Ilumionate
//

import SwiftUI
import os

extension AudioLibraryView {

    // MARK: - Playback Handlers

    func openPlayer(for file: AudioFile) {
        playerFile = file
    }

    // MARK: - Analysis Handler

    func startAnalysis(for file: AudioFile) {
        Log.audio.info("🔬 Queuing file for analysis: \(file.filename)")
        selectedFile = file

        Task {
            await analysisManager.queueForAnalysis(file)

            // Poll for completion
            while analysisManager.currentAnalysis != nil {
                if let completed = analysisManager.getCompletedAnalysis(for: file) {
                    var updatedFile = file
                    updatedFile.analysisResult = completed.analysis
                    updatedFile.transcription = completed.transcription.fullText
                    updatedFile.trackMetadata = completed.audioFile.trackMetadata

                    if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
                        audioFiles[index] = updatedFile
                    }
                    break
                }

                // Wait a bit before checking again
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: - File Management

    func loadAudioFiles() async {
        let files = await AudioLibraryStore.loadRepairingStoredFiles()
        audioFiles = files
        Log.audio.info("📦 Loaded \(files.count) audio files")
    }

    /// Removes the row and stages the file for undo. Nothing is destroyed here —
    /// `PendingAudioDeletion.commit()` does that once the undo window closes.
    func deleteFile(_ file: AudioFile) {
        guard let index = audioFiles.firstIndex(where: { $0.id == file.id }) else { return }

        let staged = pendingDeletion.stage([
            StagedAudioFile(file: file, originalURL: file.url, originalIndex: index)
        ])

        // The move failed, so the file is still sitting in Documents. Keep the
        // row: dropping it would let the next library scan re-register the file
        // as a duplicate.
        guard !staged.isEmpty else { return }

        audioFiles.remove(at: index)
        Task {
            if let persisted = await AudioLibraryStore.remove(audioFileIDs: [file.id]) {
                audioFiles = persisted
            }
        }
        TranceHaptics.shared.medium()
    }

    func renameFile(_ file: AudioFile, newName: String) {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
            audioFiles[index].userTitle = cleanName
            Task {
                await AudioLibraryStore.setUserTitle(cleanName, audioFileID: file.id)
            }
            Log.audio.info("✏️ Updated library title to: \(cleanName)")
        }
    }

    // MARK: - Rating & Liking Management

    func toggleFavorite(for file: AudioFile) {
        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
            let isFavorite = !(audioFiles[index].isFavorite ?? false)
            audioFiles[index].isFavorite = isFavorite
            Task {
                await AudioLibraryStore.setFavorite(isFavorite, audioFileID: file.id)
            }
            TranceHaptics.shared.light()
        }
    }

    func updateRating(for file: AudioFile, rating: Int) {
        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
            audioFiles[index].rating = rating
            Task {
                await AudioLibraryStore.setRating(rating, audioFileID: file.id)
            }
            TranceHaptics.shared.light()
        }
    }

    func showDetailedRatingSheet(for file: AudioFile) {
        // For now, just show a quick rating action sheet
        // TODO: Implement full detailed rating sheet in future update
        Log.audio.info("📝 Show detailed rating for: \(file.filename)")
        TranceHaptics.shared.light()
    }

    // MARK: - Selection Management

    func toggleSelection(for file: AudioFile) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
            Log.audio.info("📋 Deselected: \(file.filename)")
        } else {
            selectedFiles.insert(file.id)
            Log.audio.info("📋 Selected: \(file.filename)")
        }
        Log.audio.info("📋 Total selected: \(selectedFiles.count)")
    }

    /// Stages the whole selection as one batch, so a single Undo brings all of
    /// it back. Calling `deleteFile` in a loop would not — each `stage(_:)`
    /// commits the batch before it.
    /// True when every *visible* file is selected. Scoped to the filtered set —
    /// "Select All" must never reach files the current filter is hiding.
    var allVisibleSelected: Bool {
        !filteredAudioFiles.isEmpty && filteredAudioFiles.allSatisfy { selectedFiles.contains($0.id) }
    }

    func toggleSelectAll() {
        TranceHaptics.shared.light()
        if allVisibleSelected {
            for file in filteredAudioFiles {
                selectedFiles.remove(file.id)
            }
        } else {
            for file in filteredAudioFiles {
                selectedFiles.insert(file.id)
            }
        }
    }

    func deleteSelectedFiles() {
        let entries = audioFiles.enumerated()
            .filter { selectedFiles.contains($0.element.id) }
            .map { index, file in
                StagedAudioFile(file: file, originalURL: file.url, originalIndex: index)
            }
        guard !entries.isEmpty else { return }

        let staged = pendingDeletion.stage(entries)
        let stagedIDs = Set(staged.map(\.file.id))
        audioFiles.removeAll { stagedIDs.contains($0.id) }
        Task {
            if let persisted = await AudioLibraryStore.remove(audioFileIDs: stagedIDs) {
                audioFiles = persisted
            }
        }
        TranceHaptics.shared.medium()

        selectedFiles.removeAll()
        isSelectionMode = false
    }

    /// Collapses each selected duplicate group to one entry.
    ///
    /// The redundant files must actually leave `Documents`. Dropping only the
    /// row would leave the file in place for `discoverUnregisteredDocumentFiles`
    /// to re-register under a fresh identifier on the next load, recreating the
    /// duplicate this just removed.
    ///
    /// Everything is staged as one batch so a single Undo reverses the whole
    /// merge — `PendingAudioDeletion` holds exactly one batch, and staging in a
    /// loop would commit each group before the next.
    func mergeDuplicates(_ resolution: DuplicateAudioReviewViewModel.Resolution) async {
        guard !resolution.removed.isEmpty else { return }

        let entries = resolution.removed.map { file in
            StagedAudioFile(
                file: file,
                originalURL: file.url,
                originalIndex: audioFiles.firstIndex { $0.id == file.id } ?? 0
            )
        }
        let staged = pendingDeletion.stage(entries)
        let stagedIDs = Set(staged.map(\.file.id))
        guard !stagedIDs.isEmpty else { return }

        let successfulRemap = resolution.remap.filter { stagedIDs.contains($0.key) }
        guard let persisted = await AudioLibraryStore.mergeDuplicates(
            remapping: successfulRemap
        ) else {
            _ = pendingDeletion.restore()
            Log.audio.error("Could not persist duplicate merge; restored staged audio files")
            return
        }
        audioFiles = persisted

        PlaylistStore.rebindAll(to: audioFiles, remapping: successfulRemap)

        TranceHaptics.shared.medium()
        Log.audio.info(
            "🧹 Merged \(Set(successfulRemap.values).count) duplicate group(s), removed \(stagedIDs.count) file(s)"
        )
    }

    /// Puts the staged batch back where it came from.
    func undoDelete() {
        let recovered = pendingDeletion.restore()
        // Ascending by original index, so inserting in order reproduces the
        // original arrangement. Clamped because filters or a concurrent reload
        // may have changed the array's length in the meantime.
        for entry in recovered {
            audioFiles.insert(entry.file, at: min(entry.originalIndex, audioFiles.count))
        }
        Task {
            if let persisted = await AudioLibraryStore.restore(recovered) {
                audioFiles = persisted
            }
        }
        TranceHaptics.shared.light()
        Log.audio.info("↩️ Restored \(recovered.count) deleted file(s)")
    }

    func analyzeSelectedFiles() {
        let filesToAnalyze = audioFiles.filter { selectedFiles.contains($0.id) }
        Log.audio.info("🔬 Queuing \(filesToAnalyze.count) files for analysis: \(filesToAnalyze.map { $0.filename })")

        Task {
            await analysisManager.queueForAnalysis(filesToAnalyze)
        }

        // Exit selection mode
        selectedFiles.removeAll()
        isSelectionMode = false
    }
}
