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
                    await MainActor.run {
                        // Update file with results
                        var updatedFile = file
                        updatedFile.analysisResult = completed.analysis
                        updatedFile.transcription = completed.transcription.fullText

                        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
                            audioFiles[index] = updatedFile
                            saveAudioFiles()
                        }
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
            saveAudioFiles()
        }
        showingExpandedProgress = false
    }

    // MARK: - File Management

    func loadAudioFiles() {
        if let data = UserDefaults.standard.data(forKey: AnalysisStateManager.audioFilesUserDefaultsKey),
           let files = try? JSONDecoder().decode([AudioFile].self, from: data) {
            audioFiles = files
            Log.audio.info("📦 Loaded \(files.count) audio files")
        }
    }

    func saveAudioFiles() {
        if let data = try? JSONEncoder().encode(audioFiles) {
            UserDefaults.standard.set(data, forKey: AnalysisStateManager.audioFilesUserDefaultsKey)
            Log.audio.info("💾 Saved \(audioFiles.count) audio files")
        }
    }

    func addAudioFile(_ file: AudioFile) {
        audioFiles.insert(file, at: 0)
        saveAudioFiles()
        Log.audio.info("✅ Added audio file: \(file.filename)")
    }

    func deleteFile(_ file: AudioFile) {
        // Delete the audio file
        try? FileManager.default.removeItem(at: file.url)

        // Delete the generated session if it exists
        GeneratedSessionStore.shared.delete(for: file)

        // Remove from list
        audioFiles.removeAll { $0.id == file.id }
        saveAudioFiles()
        Log.audio.info("🗑 Deleted: \(file.filename)")
    }

    func renameFile(_ file: AudioFile, newName: String) {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
            // Keep the original extension
            let urlExtension = file.url.pathExtension
            let finalName = cleanName.hasSuffix("." + urlExtension) || urlExtension.isEmpty
                ? cleanName
                : cleanName + "." + urlExtension

            audioFiles[index].filename = finalName
            saveAudioFiles()
            Log.audio.info("✏️ Renamed to: \(finalName)")
        }
    }

    // MARK: - Rating & Liking Management

    func toggleFavorite(for file: AudioFile) {
        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
            audioFiles[index].isFavorite = !(audioFiles[index].isFavorite ?? false)
            saveAudioFiles()
            TranceHaptics.shared.light()
        }
    }

    func updateRating(for file: AudioFile, rating: Int) {
        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
            audioFiles[index].rating = rating
            saveAudioFiles()
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

    func deleteSelectedFiles() {
        let filesToDelete = audioFiles.filter { selectedFiles.contains($0.id) }
        for file in filesToDelete {
            deleteFile(file)
        }

        // Exit selection mode
        selectedFiles.removeAll()
        isSelectionMode = false
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
                        await MainActor.run {
                            addAudioFile(file)
                        }
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
                    await MainActor.run {
                        addAudioFile(file)
                        showingURLDownloader = false
                        audioURLInput = ""
                        isDownloadingURL = false
                    }

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
