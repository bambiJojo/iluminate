// AudioLibraryView+Actions.swift
// Ilumionate
//

import SwiftUI

extension AudioLibraryView {

    // MARK: - Playback Handlers

    func openPlayer(for file: AudioFile) {
        playerFile = file
    }

    // MARK: - Analysis Handler

    func startAnalysis(for file: AudioFile) {
        print("🔬 Queuing file for analysis: \(file.filename)")
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
        // Load audio files from UserDefaults or a data store
        if let data = UserDefaults.standard.data(forKey: "audioFiles"),
           let files = try? JSONDecoder().decode([AudioFile].self, from: data) {
            audioFiles = files
            print("📦 Loaded \(files.count) audio files")
        }
    }

    func saveAudioFiles() {
        if let data = try? JSONEncoder().encode(audioFiles) {
            UserDefaults.standard.set(data, forKey: "audioFiles")
            print("💾 Saved \(audioFiles.count) audio files")
        }
    }

    func addAudioFile(_ file: AudioFile) {
        audioFiles.insert(file, at: 0)
        saveAudioFiles()
        print("✅ Added audio file: \(file.filename)")
    }

    func deleteFile(_ file: AudioFile) {
        // Delete the audio file
        try? FileManager.default.removeItem(at: file.url)

        // Delete the generated session if it exists
        let documentsURL = URL.documentsDirectory
        let sessionsURL = documentsURL.appendingPathComponent("GeneratedSessions", isDirectory: true)
        let baseName = file.filename
            .replacing(".mp3", with: "")
            .replacing(".m4a", with: "")
            .replacing(".wav", with: "")
        let sessionFile = sessionsURL.appendingPathComponent("\(baseName)_session.json")
        try? FileManager.default.removeItem(at: sessionFile)

        // Remove from list
        audioFiles.removeAll { $0.id == file.id }
        saveAudioFiles()
        print("🗑 Deleted: \(file.filename)")
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
            print("✏️ Renamed to: \(finalName)")
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
        print("📝 Show detailed rating for: \(file.filename)")
        TranceHaptics.shared.light()
    }

    // MARK: - Selection Management

    func toggleSelection(for file: AudioFile) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
            print("📋 Deselected: \(file.filename)")
        } else {
            selectedFiles.insert(file.id)
            print("📋 Selected: \(file.filename)")
        }
        print("📋 Total selected: \(selectedFiles.count)")
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
        print("🔬 Queuing \(filesToAnalyze.count) files for analysis: \(filesToAnalyze.map { $0.filename })")

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

                print("📥 Starting import of \(totalFiles) audio files...")

                for (index, url) in urls.enumerated() {
                    guard url.startAccessingSecurityScopedResource() else {
                        print("❌ Failed to access file: \(url.lastPathComponent)")
                        continue
                    }

                    print("📥 Processing file \(index + 1)/\(totalFiles): \(url.lastPathComponent)")

                    // Import with timeout handling
                    if let file = await audioManager.importAudio(from: url) {
                        await MainActor.run {
                            addAudioFile(file)
                        }
                        importedFiles.append(file)
                        print("✅ Imported (\(index + 1)/\(totalFiles)): \(file.filename)")
                    } else {
                        print("⚠️ Skipped (\(index + 1)/\(totalFiles)): \(url.lastPathComponent) - Import failed")
                    }

                    url.stopAccessingSecurityScopedResource()
                }

                // Automatically queue all imported files for analysis
                if !importedFiles.isEmpty {
                    if AnalysisPreferences.shared.autoAnalyzeOnImport {
                        print("🔬 Auto-queuing \(importedFiles.count) files for analysis...")
                        await analysisManager.queueForAnalysis(importedFiles)
                    }
                    print("✅ Import complete: \(importedFiles.count)/\(totalFiles) files processed")
                } else {
                    print("⚠️ No files were successfully imported")
                }
            }

        case .failure(let error):
            print("❌ Import failed: \(error)")
        }
    }

    func handleURLDownload() {
        guard let url = URL(string: audioURLInput.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" || url.scheme == "https" else {
            downloadError = "Please enter a valid http:// or https:// URL."
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
                        print("🔬 Auto-queuing downloaded file for analysis...")
                        await analysisManager.queueForAnalysis([file])
                    }
                } else {
                    await MainActor.run {
                        isDownloadingURL = false
                        downloadError = "Download completed but the file could not be saved. Please try again."
                    }
                }
            } catch let urlError as URLError where urlError.code == .badServerResponse {
                await MainActor.run {
                    isDownloadingURL = false
                    downloadError = "The server returned an error. Please check the URL and try again."
                }
            } catch {
                await MainActor.run {
                    isDownloadingURL = false
                    downloadError = "Download failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
