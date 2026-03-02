//
//  AudioLibraryView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// Displays and manages the user's audio file library
struct AudioLibraryView: View {

    @Bindable var engine: LightEngine
    @State private var audioFiles: [AudioFile] = []
    @State private var showingImporter = false
    @State private var selectedFile: AudioFile?
    @State private var selectedFiles = Set<AudioFile.ID>()
    @State private var showingAnalysis = false
    @State private var audioManager = AudioManager()
    @State private var analysisManager = AnalysisStateManager()
    @State private var showingExpandedProgress = false
    @State private var showingSyncPlayer = false
    @State private var selectedLightSession: LightSession?
    @State private var isSelectionMode = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Main content
                Group {
                    if audioFiles.isEmpty {
                        emptyState
                    } else {
                        audioList
                    }
                }

                // Selection toolbar
                if isSelectionMode && !selectedFiles.isEmpty {
                    VStack(spacing: 0) {
                        Divider()
                        HStack {
                            Text("\(selectedFiles.count) selected")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Analyze All") {
                                analyzeSelectedFiles()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedFiles.isEmpty)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(.regularMaterial)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !audioFiles.isEmpty {
                        Button(isSelectionMode ? "Done" : "Select") {
                            if isSelectionMode {
                                selectedFiles.removeAll()
                            }
                            isSelectionMode.toggle()
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
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

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Audio Files", systemImage: "waveform.circle")
        } description: {
            Text("Import audio to create custom light therapy sessions")
        } actions: {
            Button {
                showingImporter = true
            } label: {
                Label("Import Audio", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Audio List

    private var audioList: some View {
        List {
            ForEach(audioFiles) { file in
                AudioFileRow(
                    file: file,
                    audioManager: audioManager,
                    analysisManager: analysisManager,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedFiles.contains(file.id),
                    onAnalyze: {
                        startAnalysis(for: file)
                    },
                    onPlayWithLights: {
                        playWithLights(file)
                    },
                    onDelete: {
                        deleteFile(file)
                    },
                    onToggleSelection: {
                        toggleSelection(for: file)
                    }
                )
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

    // MARK: - Playback Handlers

    private func playWithLights(_ file: AudioFile) {
        Task {
            // Load the generated session
            if let session = await loadGeneratedSession(for: file) {
                selectedFile = file
                selectedLightSession = session
                showingSyncPlayer = true
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
        selectedFile = file

        Task {
            await analysisManager.startAnalysis(for: file)

            // Poll for completion
            while analysisManager.currentAnalysis != nil {
                if let completed = analysisManager.getCompletedAnalysis(for: file) {
                    // Update file with results
                    var updatedFile = file
                    updatedFile.analysisResult = completed.analysis
                    updatedFile.transcription = completed.transcription.fullText

                    if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
                        audioFiles[index] = updatedFile
                        saveAudioFiles()
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

    // MARK: - Selection Management

    private func toggleSelection(for file: AudioFile) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
        } else {
            selectedFiles.insert(file.id)
        }
    }

    private func analyzeSelectedFiles() {
        let filesToAnalyze = audioFiles.filter { selectedFiles.contains($0.id) }

        Task {
            await analysisManager.startAnalysis(for: filesToAnalyze)
        }

        // Exit selection mode
        selectedFiles.removeAll()
        isSelectionMode = false
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // Import multiple files
            Task {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else {
                        print("❌ Failed to access file: \(url)")
                        continue
                    }

                    if let file = await audioManager.importAudio(from: url) {
                        addAudioFile(file)
                    }

                    url.stopAccessingSecurityScopedResource()
                }
            }

        case .failure(let error):
            print("❌ Import failed: \(error)")
        }
    }
}

// MARK: - Audio File Row

struct AudioFileRow: View {

    let file: AudioFile
    var audioManager: AudioManager
    var analysisManager: AnalysisStateManager
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onAnalyze: (() -> Void)?
    var onPlayWithLights: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleSelection: (() -> Void)?

    @State private var isPlaying = false
    @State private var hasGeneratedSession = false
    @State private var showingDeleteConfirmation = false

    /// Whether this file is currently being analyzed
    private var isAnalyzing: Bool {
        analysisManager.currentAnalysis?.audioFile.id == file.id
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Selection circle or play button
                if isSelectionMode {
                    Button {
                        onToggleSelection?()
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title)
                            .foregroundStyle(isSelected ? .blue : .gray)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Play button
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }

                // File info
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.filename)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        Label(file.durationFormatted, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(file.fileSizeFormatted, systemImage: "doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if file.isAnalyzed {
                            Label("Analyzed", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer()
            }

            // Action buttons (hidden in selection mode)
            if !isSelectionMode {
                HStack(spacing: 10) {
                // Analyze / Re-analyze button
                Button {
                    onAnalyze?()
                } label: {
                    if isAnalyzing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Analyzing...")
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label(
                            hasGeneratedSession ? "Re-analyze" : "Analyze",
                            systemImage: "waveform.badge.magnifyingglass"
                        )
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isAnalyzing)

                // Play with Lights button (if session available)
                if hasGeneratedSession {
                    Button {
                        onPlayWithLights?()
                    } label: {
                        Label("Play with Lights", systemImage: "lightbulb.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                // Delete button
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                }
            }
        }
        .padding(.vertical, 8)
        .confirmationDialog(
            "Delete \(file.filename)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("This will remove the audio file and its generated light session.")
        }
        .task {
            await checkForGeneratedSession()
        }
        .onChange(of: analysisManager.currentAnalysis?.stage) {
            // Re-check when analysis stage changes (especially when it completes)
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
        // Check if generated session exists
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
