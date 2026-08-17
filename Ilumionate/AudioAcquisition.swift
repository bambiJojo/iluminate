//
//  AudioAcquisition.swift
//  Ilumionate
//
//  The three ways audio enters the library — the Files picker, a direct URL,
//  and the in-app browser — as one model any screen can host.
//
//  These used to live inside `AudioLibraryView` as view state plus a pair of
//  extension methods, which is why Library could not offer them without opening
//  the Audio manager first. Owning the flow here lets both screens present the
//  same three sources, and means a fourth source only has to be added once.
//

import SwiftUI
import UniformTypeIdentifiers
import os

@Observable
@MainActor
final class AudioAcquisition {

    /// Called after a batch lands in the store, with only the files that were
    /// actually added. Hosts use it to refresh their own list; the model never
    /// reaches into host state itself.
    var onImported: (([AudioFile]) -> Void)?

    var showingFileImporter = false
    var showingURLPrompt = false
    var showingBrowser = false

    var urlInput = ""
    var isDownloading = false
    var errorMessage: String?

    private let intake = AudioIntake.shared

    init(onImported: (([AudioFile]) -> Void)? = nil) {
        self.onImported = onImported
    }

    // MARK: - Opening a source

    func importFromFiles() {
        TranceHaptics.shared.light()
        showingFileImporter = true
    }

    func importFromURL() {
        TranceHaptics.shared.light()
        showingURLPrompt = true
    }

    func browseTheWeb() {
        TranceHaptics.shared.light()
        showingBrowser = true
    }

    // MARK: - Files

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { await importFiles(at: urls) }
        case .failure(let error):
            Log.audio.info("❌ Import failed: \(error)")
        }
    }

    private func importFiles(at urls: [URL]) async {
        var imported: [AudioFile] = []
        let total = urls.count

        Log.audio.info("📥 Starting import of \(total) audio files...")

        for (index, url) in urls.enumerated() {
            guard url.startAccessingSecurityScopedResource() else {
                Log.audio.info("❌ Failed to access file: \(url.lastPathComponent)")
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }

            Log.audio.info("📥 Processing file \(index + 1)/\(total): \(url.lastPathComponent)")

            if let file = await intake.importAudio(from: url), await store(file) {
                imported.append(file)
                Log.audio.info("✅ Imported (\(index + 1)/\(total)): \(file.filename)")
            } else {
                Log.audio.info("⚠️ Skipped (\(index + 1)/\(total)): \(url.lastPathComponent) - Import failed")
            }
        }

        if imported.isEmpty {
            Log.audio.info("⚠️ No files were successfully imported")
        } else {
            Log.audio.info("✅ Import complete: \(imported.count)/\(total) files processed")
        }
        await finish(imported)
    }

    // MARK: - Direct URL

    func downloadFromURL() {
        guard let url = URL(string: urlInput.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" || url.scheme == "https" else {
            errorMessage = "Please enter a valid http:// or https:// URL."
            UsageAnalytics.shared.errorOccurred(.audioURLInvalid)
            return
        }

        isDownloading = true

        Task {
            do {
                guard let file = try await intake.downloadAudio(from: url) else {
                    isDownloading = false
                    errorMessage = "Download completed but the file could not be saved. Please try again."
                    return
                }
                let added = await store(file)
                isDownloading = false
                urlInput = ""
                showingURLPrompt = false
                await finish(added ? [file] : [])
            } catch let rejection as AudioDownloadValidation.Rejection {
                // Already counted as .audioURLServerRejected at the point of
                // rejection, where the Content-Type is still in scope.
                isDownloading = false
                errorMessage = rejection.userFacingMessage
            } catch let urlError as URLError where urlError.code == .badServerResponse {
                UsageAnalytics.shared.errorOccurred(.audioURLServerRejected)
                isDownloading = false
                errorMessage = "The server returned an error. Please check the URL and try again."
            } catch {
                UsageAnalytics.shared.errorOccurred(.audioURLDownloadFailed)
                isDownloading = false
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    func cancelURLPrompt() {
        urlInput = ""
        isDownloading = false
    }

    // MARK: - In-app browser

    /// The browser hands back a file it has already written to Documents.
    func adopt(_ file: AudioFile) {
        Task {
            let added = await store(file)
            await finish(added ? [file] : [])
        }
    }

    // MARK: - Shared tail

    /// Persists one file. The persistence actor already refuses a second entry
    /// with the same id, so this is safe to call for a file the library may
    /// have resolved to something already on the shelf.
    private func store(_ file: AudioFile) async -> Bool {
        let reviewed = KnownAudioCatalog.shared.applyingReviewedAnalysis(to: file) ?? file
        guard await AudioLibraryStore.add(reviewed) != nil else {
            Log.audio.error("❌ Could not add \(reviewed.filename) to the audio library")
            return false
        }
        Log.audio.info("✅ Added audio file: \(reviewed.filename)")
        return true
    }

    private func finish(_ files: [AudioFile]) async {
        guard !files.isEmpty else { return }
        if AnalysisPreferences.shared.autoAnalyzeOnImport {
            Log.audio.info("🔬 Auto-queuing \(files.count) file(s) for analysis...")
            await AnalysisStateManager.shared.queueForAnalysis(files)
        }
        onImported?(files)
    }
}

// MARK: - Hosting

private struct AudioAcquisitionModifier: ViewModifier {
    @Bindable var acquisition: AudioAcquisition

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $acquisition.showingFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                acquisition.handleFileImport(result)
            }
            .alert("Download Audio URL", isPresented: $acquisition.showingURLPrompt) {
                TextField("https://...", text: $acquisition.urlInput)
                Button("Cancel", role: .cancel) { acquisition.cancelURLPrompt() }
                Button("Download") { acquisition.downloadFromURL() }
                    .disabled(acquisition.urlInput.isEmpty || acquisition.isDownloading)
            } message: {
                if acquisition.isDownloading {
                    Text("Downloading... Please wait.")
                } else {
                    Text("Enter a stable URL pointing directly to an MP3, M4A, or WAV file.")
                }
            }
            .alert(
                "Download Failed",
                isPresented: Binding(
                    get: { acquisition.errorMessage != nil },
                    set: { if !$0 { acquisition.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { acquisition.errorMessage = nil }
            } message: {
                if let message = acquisition.errorMessage { Text(message) }
            }
            .sheet(isPresented: $acquisition.showingBrowser) {
                InAppBrowserView { file in
                    acquisition.adopt(file)
                }
            }
    }
}

extension View {
    /// Hosts the Files picker, the URL prompt and the in-app browser for an
    /// `AudioAcquisition`. Attach once per screen that offers audio import.
    func audioAcquisition(_ acquisition: AudioAcquisition) -> some View {
        modifier(AudioAcquisitionModifier(acquisition: acquisition))
    }
}
