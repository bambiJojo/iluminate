//
//  AudioLibraryView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// Displays and manages the user's audio file library with Trance design
struct AudioLibraryView: View {

    @Bindable var engine: LightEngine
    @State private var audioFiles: [AudioFile] = []
    @State private var showingImporter = false
    @State private var selectedFile: AudioFile?
    @State private var selectedFiles = Set<AudioFile.ID>()
    @State private var showingAnalysis = false
    @State private var audioManager = AudioManager()
    private var analysisManager: AnalysisStateManager {
        AnalysisStateManager.shared
    }
    @State private var showingExpandedProgress = false
    @State private var showingSyncPlayer = false
    @State private var selectedLightSession: LightSession?
    @State private var isSelectionMode = false
    @State private var showingQueueManagement = false
    @State private var searchText = ""
    @State private var showingRenameAlert = false
    @State private var newFilename = ""
    @State private var fileToRename: AudioFile?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // Trance background
                Color.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Main content
                    if audioFiles.isEmpty {
                        emptyState
                    } else {
                        audioLibraryContent
                    }

                    // Selection toolbar with Trance design
                    if isSelectionMode && !selectedFiles.isEmpty {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.glassBorder.opacity(0.3))
                                .frame(height: 1)

                            HStack(spacing: TranceSpacing.card) {
                                Text("\(selectedFiles.count) selected")
                                    .font(TranceTypography.caption)
                                    .foregroundColor(.textSecondary)

                                Spacer()

                                Button("Analyze All") {
                                    TranceHaptics.shared.medium()
                                    analyzeSelectedFiles()
                                }
                                .padding(.horizontal, TranceSpacing.card)
                                .padding(.vertical, TranceSpacing.inner)
                                .background(
                                    LinearGradient(
                                        colors: [.roseGold, .roseDeep],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.white)
                                .font(TranceTypography.body)
                                .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                                .disabled(selectedFiles.isEmpty)
                            }
                            .padding(TranceSpacing.content)
                            .background(.ultraThinMaterial)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                // Status bar overlay
                if let analysis = analysisManager.currentAnalysis {
                    AnalysisStatusBar(
                        stage: analysis.stage,
                        progress: analysisManager.overallProgress,
                        fileName: analysis.audioFile.filename,
                        queueCount: analysisManager.analysisQueue.count,
                        onCancel: {
                            analysisManager.cancelCurrentAnalysis()
                        },
                        onCancelAll: analysisManager.analysisQueue.isEmpty ? nil : {
                            analysisManager.cancelAllAnalyses()
                        },
                        onTap: {
                            showingExpandedProgress = true
                        }
                    )
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: analysisManager.currentAnalysis != nil)
                }
            }
            .navigationTitle("Audio Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !audioFiles.isEmpty {
                        Button(isSelectionMode ? "Done" : "Select") {
                            TranceHaptics.shared.light()
                            if isSelectionMode {
                                selectedFiles.removeAll()
                            }
                            isSelectionMode.toggle()
                        }
                        .font(TranceTypography.body)
                        .foregroundColor(.roseGold)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: TranceSpacing.small) {
                        // Queue management button
                        if analysisManager.currentAnalysis != nil || !analysisManager.analysisQueue.isEmpty {
                            Button {
                                showingQueueManagement = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "list.bullet.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                    if !analysisManager.analysisQueue.isEmpty {
                                        Text("\(analysisManager.analysisQueue.count)")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.roseGold, in: Capsule())
                                    }
                                }
                                .foregroundColor(.roseGold)
                            }
                        }

                        // Import button with Trance styling
                        Button {
                            TranceHaptics.shared.light()
                            showingImporter = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.title2)
                                .foregroundColor(.roseGold)
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showingExpandedProgress) {
                if let file = analysisManager.currentAnalysis?.audioFile {
                    AnalysisProgressView(audioFile: file) { analyzedFile, result in
                        handleAnalysisComplete(analyzedFile: analyzedFile, result: result)
                    }
                }
            }
            .sheet(isPresented: $showingQueueManagement) {
                QueueManagementView(analysisManager: AnalysisStateManager.shared)
            }
            .alert("Rename File", isPresented: $showingRenameAlert) {
                TextField("New name", text: $newFilename)
                Button("Cancel", role: .cancel) {
                    newFilename = ""
                    fileToRename = nil
                }
                Button("Save") {
                    if let file = fileToRename {
                        renameFile(file, newName: newFilename)
                    }
                    newFilename = ""
                    fileToRename = nil
                }
            } message: {
                Text("Enter a new name for this audio file.")
            }
            .onAppear {
                loadAudioFiles()
            }
            .onChange(of: isSelectionMode) { _, newValue in
                if !newValue {
                    selectedFiles.removeAll()
                }
            }
        }
    }

    // MARK: - Empty State with Trance Design

    private var emptyState: some View {
        VStack(spacing: TranceSpacing.statusBar) {
            Spacer()

            // Elegant centered icon
            VStack(spacing: TranceSpacing.card) {
                // Simple icon with rose gold styling
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.roseGold, .roseDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: Color.roseGold.opacity(0.3),
                        radius: 20,
                        x: 0,
                        y: 10
                    )

                VStack(spacing: TranceSpacing.inner) {
                    Text("Your Audio Library")
                        .font(TranceTypography.greeting)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Transform your audio into personalized\nlight therapy experiences")
                        .font(TranceTypography.body)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }

            Spacer()

            // Import button with Trance styling
            VStack(spacing: TranceSpacing.card) {
                Button {
                    TranceHaptics.shared.medium()
                    showingImporter = true
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import Audio Files")
                                .font(TranceTypography.body)
                                .fontWeight(.semibold)

                            Text("MP3, M4A & more formats")
                                .font(TranceTypography.caption)
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .opacity(0.7)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, TranceSpacing.content)
                    .padding(.vertical, TranceSpacing.card)
                }
                .background(
                    LinearGradient(
                        colors: [.roseGold, .roseDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                .shadow(
                    color: TranceShadow.button.color,
                    radius: TranceShadow.button.radius,
                    x: TranceShadow.button.x,
                    y: TranceShadow.button.y
                )
                .padding(.horizontal, TranceSpacing.screen)

                // Helpful tip
                HStack(spacing: TranceSpacing.icon) {
                    Image(systemName: "sparkles")
                        .font(TranceTypography.caption)
                        .foregroundColor(.roseGold)

                    Text("AI will analyze your audio to create custom light sessions")
                        .font(TranceTypography.caption)
                        .foregroundColor(.textLight)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, TranceSpacing.screen)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Audio Library Content with Trance Design

    private var audioLibraryContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Search bar
                searchSection

                // Import options section
                importOptionsSection

                // Audio files grid
                audioFilesGrid

                // Bottom spacing for selection toolbar
                if isSelectionMode {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 100)
                }
            }
        }
        .fullScreenCover(isPresented: $showingSyncPlayer) {
            if let file = selectedFile, let session = selectedLightSession {
                AudioLightPlayerView(
                    audioFile: file,
                    lightSession: session,
                    engine: engine
                )
            }
        }
    }

    // MARK: - Search Section

    private var searchSection: some View {
        GlassCard {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "magnifyingglass")
                    .font(TranceTypography.body)
                    .foregroundColor(.textLight)

                TextField("Search audio files...", text: $searchText)
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(TranceTypography.body)
                            .foregroundColor(.textLight)
                    }
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.card)
    }

    // MARK: - Import Options Section

    private var importOptionsSection: some View {
        GlassCard(label: "Add Audio") {
            VStack(spacing: TranceSpacing.card) {
                // Import from Files
                Button {
                    TranceHaptics.shared.light()
                    showingImporter = true
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                            .foregroundColor(.roseGold)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import from Files")
                                .font(TranceTypography.body)
                                .fontWeight(.medium)
                                .foregroundColor(.textPrimary)

                            Text("Choose MP3, M4A, or WAV files")
                                .font(TranceTypography.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.textLight)
                    }
                    .padding(.vertical, TranceSpacing.inner)
                }

                Rectangle()
                    .fill(Color.glassBorder.opacity(0.3))
                    .frame(height: 1)

                // Record Audio (placeholder for now)
                Button {
                    TranceHaptics.shared.light()
                    // TODO: Implement audio recording
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Image(systemName: "mic.fill")
                            .font(.title2)
                            .foregroundColor(.warmAccent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Record Audio")
                                .font(TranceTypography.body)
                                .fontWeight(.medium)
                                .foregroundColor(.textPrimary)

                            Text("Record directly in the app")
                                .font(TranceTypography.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Text("Coming Soon")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textLight)
                            .padding(.horizontal, TranceSpacing.inner)
                            .padding(.vertical, TranceSpacing.micro)
                            .background(Color.glassBorder.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.pill))
                    }
                    .padding(.vertical, TranceSpacing.inner)
                }
                .disabled(true)
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.cardMargin)
    }

    // MARK: - Audio Files Grid

    private var audioFilesGrid: some View {
        LazyVStack(spacing: TranceSpacing.cardMargin) {
            if !filteredAudioFiles.isEmpty {
                GlassCard(label: "Your Files (\(filteredAudioFiles.count))") {
                    LazyVStack(spacing: TranceSpacing.card) {
                        ForEach(filteredAudioFiles) { file in
                            AudioFileRow(
                                file: file,
                                audioManager: audioManager,
                                analysisManager: analysisManager,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedFiles.contains(file.id),
                                onAnalyze: { startAnalysis(for: file) },
                                onPlayWithLights: { playWithLights(file) },
                                onRename: {
                                    fileToRename = file
                                    newFilename = file.displayName
                                    showingRenameAlert = true
                                },
                                onDelete: { deleteFile(file) },
                                onToggleSelection: { toggleSelection(for: file) }
                            )

                            if file.id != filteredAudioFiles.last?.id {
                                Rectangle()
                                    .fill(Color.glassBorder.opacity(0.3))
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.cardMargin)
            }
        }
    }

    // MARK: - Filtered Audio Files

    private var filteredAudioFiles: [AudioFile] {
        if searchText.isEmpty {
            return audioFiles
        }
        return audioFiles.filter { file in
            file.filename.localizedCaseInsensitiveContains(searchText) ||
            file.transcription?.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    // MARK: - Playback Handlers

    private func playWithLights(_ file: AudioFile) {
        Task {
            // Load the generated session
            if let session = await loadGeneratedSession(for: file) {
                await MainActor.run {
                    selectedFile = file
                    selectedLightSession = session
                    showingSyncPlayer = true
                }
            }
        }
    }

    private func loadGeneratedSession(for file: AudioFile) async -> LightSession? {
        let fileManager = FileManager.default
        let documentsURL = URL.documentsDirectory
        let sessionsURL = documentsURL.appendingPathComponent("GeneratedSessions", isDirectory: true)

        let baseName = file.filename
            .replacing(".mp3", with: "")
            .replacing(".m4a", with: "")
            .replacing(".wav", with: "")
        let filename = "\(baseName)_session.json"
        let fileURL = sessionsURL.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("❌ No generated session found at: \(fileURL.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let session = try decoder.decode(LightSession.self, from: data)
            print("✅ Loaded generated session: \(session.session_name)")
            return session
        } catch {
            print("❌ Failed to load session: \(error)")
            return nil
        }
    }

    // MARK: - Analysis Handler

    private func startAnalysis(for file: AudioFile) {
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

    private func handleAnalysisComplete(analyzedFile: AudioFile, result: AnalysisResult) {
        // Update the file with analysis results
        if let index = audioFiles.firstIndex(where: { $0.id == analyzedFile.id }) {
            audioFiles[index] = analyzedFile
            saveAudioFiles()
        }
        showingExpandedProgress = false
    }

    // MARK: - File Management

    private func loadAudioFiles() {
        // Load audio files from UserDefaults or a data store
        if let data = UserDefaults.standard.data(forKey: "audioFiles"),
           let files = try? JSONDecoder().decode([AudioFile].self, from: data) {
            audioFiles = files
            print("📦 Loaded \(files.count) audio files")
        }
    }

    private func saveAudioFiles() {
        if let data = try? JSONEncoder().encode(audioFiles) {
            UserDefaults.standard.set(data, forKey: "audioFiles")
            print("💾 Saved \(audioFiles.count) audio files")
        }
    }

    private func addAudioFile(_ file: AudioFile) {
        audioFiles.insert(file, at: 0)
        saveAudioFiles()
        print("✅ Added audio file: \(file.filename)")
    }

    private func deleteFile(_ file: AudioFile) {
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

    private func renameFile(_ file: AudioFile, newName: String) {
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

    // MARK: - Selection Management

    private func toggleSelection(for file: AudioFile) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
            print("📋 Deselected: \(file.filename)")
        } else {
            selectedFiles.insert(file.id)
            print("📋 Selected: \(file.filename)")
        }
        print("📋 Total selected: \(selectedFiles.count)")
    }

    private func analyzeSelectedFiles() {
        let filesToAnalyze = audioFiles.filter { selectedFiles.contains($0.id) }
        print("🔬 Queuing \(filesToAnalyze.count) files for analysis: \(filesToAnalyze.map { $0.filename })")

        Task {
            await analysisManager.queueForAnalysis(filesToAnalyze)
        }

        // Exit selection mode
        selectedFiles.removeAll()
        isSelectionMode = false
    }

    private func handleImport(_ result: Result<[URL], Error>) {
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
                    print("🔬 Auto-queuing \(importedFiles.count) files for analysis...")
                    await analysisManager.queueForAnalysis(importedFiles)
                    print("✅ Import complete: \(importedFiles.count)/\(totalFiles) files processed and queued")
                } else {
                    print("⚠️ No files were successfully imported")
                }
            }

        case .failure(let error):
            print("❌ Import failed: \(error)")
        }
    }
}

// MARK: - Audio File Row Component

struct AudioFileRow: View {
    let file: AudioFile
    let audioManager: AudioManager
    let analysisManager: AnalysisStateManager
    let isSelectionMode: Bool
    let isSelected: Bool
    let onAnalyze: () -> Void
    let onPlayWithLights: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onToggleSelection: () -> Void

    @State private var isPlaying = false
    @State private var hasGeneratedSession = false

    private var isAnalyzing: Bool {
        analysisManager.currentAnalysis?.audioFile.id == file.id
    }

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            // Selection/Play button
            Button {
                TranceHaptics.shared.light()
                if isSelectionMode {
                    onToggleSelection()
                } else {
                    togglePlayback()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            isSelectionMode && isSelected ? Color.roseGold :
                            Color.glassBorder.opacity(0.3)
                        )
                        .frame(width: 44, height: 44)

                    if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark" : "")
                            .font(.body.weight(.medium))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.body.weight(.medium))
                            .foregroundColor(isPlaying ? .white : .roseGold)
                    }
                }
            }

            // File info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(file.displayName)
                        .font(TranceTypography.body)
                        .fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    Spacer()

                    // Analysis status badges
                    HStack(spacing: TranceSpacing.icon) {
                        if file.isAnalyzed {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundColor(.phaseInduction)
                        }

                        if hasGeneratedSession {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundColor(.roseGold)
                        }

                        if isAnalyzing {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.roseGold)
                        }
                    }
                }

                // Metadata
                HStack(spacing: TranceSpacing.list) {
                    Text(file.durationFormatted)
                        .font(TranceTypography.caption)
                        .foregroundColor(.textSecondary)

                    Text("•")
                        .font(TranceTypography.caption)
                        .foregroundColor(.textLight)

                    Text(file.fileSizeFormatted)
                        .font(TranceTypography.caption)
                        .foregroundColor(.textSecondary)

                    if let result = file.analysisResult {
                        Text("•")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textLight)

                        Text(result.contentType.rawValue.capitalized)
                            .font(TranceTypography.caption)
                            .foregroundColor(.textLight)
                    }
                }

                // Action button for session playback
                if hasGeneratedSession && !isSelectionMode {
                    Button {
                        TranceHaptics.shared.medium()
                        onPlayWithLights()
                    } label: {
                        HStack(spacing: TranceSpacing.icon) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                            Text("Play with Lights")
                                .font(TranceTypography.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.roseGold)
                        .padding(.horizontal, TranceSpacing.inner)
                        .padding(.vertical, TranceSpacing.micro)
                        .background(Color.roseGold.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: TranceRadius.pill))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if !isSelectionMode {
                Button {
                    onRename()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .overlay(alignment: .trailing) {
            if !isSelectionMode {
                Menu {
                    Button {
                        onRename()
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(.textLight)
                        .padding(.vertical, TranceSpacing.list)
                        .padding(.leading, TranceSpacing.list)
                }
            }
        }
        .task {
            await checkForGeneratedSession()
        }
        .onChange(of: analysisManager.currentAnalysis?.stage) {
            Task {
                await checkForGeneratedSession()
            }
        }
        .onChange(of: audioManager.isPlaying) { _, playing in
            if !playing && isPlaying {
                isPlaying = false
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            audioManager.stopPlayback()
            isPlaying = false
        } else {
            audioManager.startPlayback(url: file.url)
            isPlaying = true
        }
    }

    private func checkForGeneratedSession() async {
        let fileManager = FileManager.default
        let documentsURL = URL.documentsDirectory
        let sessionsURL = documentsURL.appendingPathComponent("GeneratedSessions", isDirectory: true)

        let baseName = file.filename
            .replacing(".mp3", with: "")
            .replacing(".m4a", with: "")
            .replacing(".wav", with: "")
        let filename = "\(baseName)_session.json"
        let fileURL = sessionsURL.appendingPathComponent(filename)

        hasGeneratedSession = fileManager.fileExists(atPath: fileURL.path)
    }
}

#Preview {
    @Previewable @State var engine = LightEngine()
    AudioLibraryView(engine: engine)
}
