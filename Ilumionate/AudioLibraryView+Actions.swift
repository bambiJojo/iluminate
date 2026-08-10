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
                        await saveAudioFiles()
                    }
                    break
                }

                // Wait a bit before checking again
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func handleAnalysisComplete(analyzedFile: AudioFile, result: AnalysisResult) {
        // Update the file with analysis results
        if let index = audioFiles.firstIndex(where: { $0.id == analyzedFile.id }) {
            audioFiles[index] = analyzedFile
            Task { await saveAudioFiles() }
        }
        showingExpandedProgress = false
    }

    // MARK: - File Management

    func loadAudioFiles() async {
        let files = await AudioLibraryStore.loadRepairingStoredFiles()
        audioFiles = files
        Log.audio.info("📦 Loaded \(files.count) audio files")
    }

    func saveAudioFiles() async {
        await AudioLibraryStore.save(audioFiles)
        Log.audio.info("💾 Saved \(audioFiles.count) audio files")
    }

    func addAudioFile(_ file: AudioFile) async {
        // The import may have resolved to a file already on the shelf, in which
        // case there is nothing to add — inserting would put the same entry in
        // the list twice.
        guard !audioFiles.contains(where: { $0.id == file.id }) else {
            Log.audio.info("↩️ Already in the library, not added again: \(file.filename)")
            return
        }
        let reviewedFile = KnownAudioCatalog.shared.applyingReviewedAnalysis(to: file) ?? file
        audioFiles.insert(reviewedFile, at: 0)
        await saveAudioFiles()
        Log.audio.info("✅ Added audio file: \(reviewedFile.filename)")
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
        Task { await saveAudioFiles() }
        TranceHaptics.shared.medium()
    }

    func renameFile(_ file: AudioFile, newName: String) {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
            audioFiles[index].userTitle = cleanName
            Task { await saveAudioFiles() }
            Log.audio.info("✏️ Updated library title to: \(cleanName)")
        }
    }

    // MARK: - Rating & Liking Management

    func toggleFavorite(for file: AudioFile) {
        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
            audioFiles[index].isFavorite = !(audioFiles[index].isFavorite ?? false)
            Task { await saveAudioFiles() }
            TranceHaptics.shared.light()
        }
    }

    func updateRating(for file: AudioFile, rating: Int) {
        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
            audioFiles[index].rating = rating
            Task { await saveAudioFiles() }
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
        Task { await saveAudioFiles() }
        TranceHaptics.shared.medium()

        selectedFiles.removeAll()
        isSelectionMode = false
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
        Task { await saveAudioFiles() }
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

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // Import multiple files with progress tracking
            Task {
                var importedFiles: [AudioFile] = []
                let totalFiles = urls.count

                Log.audio.info("📥 Starting import of \(totalFiles) audio files...")

                for (index, url) in urls.enumerated() {
                    guard url.startAccessingSecurityScopedResource() else {
                        Log.audio.info("❌ Failed to access file: \(url.lastPathComponent)")
                        continue
                    }

                    Log.audio.info("📥 Processing file \(index + 1)/\(totalFiles): \(url.lastPathComponent)")

                    // Import with timeout handling
                    if let file = await audioManager.importAudio(from: url) {
                        await addAudioFile(file)
                        importedFiles.append(file)
                        Log.audio.info("✅ Imported (\(index + 1)/\(totalFiles)): \(file.filename)")
                    } else {
                        Log.audio.info("⚠️ Skipped (\(index + 1)/\(totalFiles)): \(url.lastPathComponent) - Import failed")
                    }

                    url.stopAccessingSecurityScopedResource()
                }

                // Automatically queue all imported files for analysis
                if !importedFiles.isEmpty {
                    if AnalysisPreferences.shared.autoAnalyzeOnImport {
                        Log.audio.info("🔬 Auto-queuing \(importedFiles.count) files for analysis...")
                        await analysisManager.queueForAnalysis(importedFiles)
                    }
                    Log.audio.info("✅ Import complete: \(importedFiles.count)/\(totalFiles) files processed")
                } else {
                    Log.audio.info("⚠️ No files were successfully imported")
                }
            }

        case .failure(let error):
            Log.audio.info("❌ Import failed: \(error)")
        }
    }

    func handleURLDownload() {
        guard let url = URL(string: audioURLInput.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" || url.scheme == "https" else {
            downloadError = "Please enter a valid http:// or https:// URL."
            UsageAnalytics.shared.errorOccurred(.audioURLInvalid)
            return
        }

        isDownloadingURL = true

        Task {
            do {
                if let file = try await audioManager.downloadAudio(from: url) {
                    await addAudioFile(file)
                    showingURLDownloader = false
                    audioURLInput = ""
                    isDownloadingURL = false

                    // Auto queue for analysis
                    if AnalysisPreferences.shared.autoAnalyzeOnImport {
                        Log.audio.info("🔬 Auto-queuing downloaded file for analysis...")
                        await analysisManager.queueForAnalysis([file])
                    }
                } else {
                    await MainActor.run {
                        isDownloadingURL = false
                        downloadError = "Download completed but the file could not be saved. Please try again."
                    }
                }
            } catch let rejection as AudioDownloadValidation.Rejection {
                // Already counted as .audioURLServerRejected at the point of
                // rejection, where the Content-Type is still in scope.
                await MainActor.run {
                    isDownloadingURL = false
                    downloadError = rejection.userFacingMessage
                }
            } catch let urlError as URLError where urlError.code == .badServerResponse {
                UsageAnalytics.shared.errorOccurred(.audioURLServerRejected)
                await MainActor.run {
                    isDownloadingURL = false
                    downloadError = "The server returned an error. Please check the URL and try again."
                }
            } catch {
                UsageAnalytics.shared.errorOccurred(.audioURLDownloadFailed)
                await MainActor.run {
                    isDownloadingURL = false
                    downloadError = "Download failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
