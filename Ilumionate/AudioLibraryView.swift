//
//  AudioLibraryView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// Bundles AudioFile + LightSession for atomic `fullScreenCover(item:)` presentation.
/// Using `item:` instead of `isPresented:` guarantees SwiftUI only renders the sheet
/// when both values are non-nil — eliminating the blank-black-screen race condition.
struct SyncPlayerItem: Identifiable {
    let id = UUID()
    let audioFile: AudioFile
    let lightSession: LightSession
}

/// Displays and manages the user's audio file library with Trance design
struct AudioLibraryView: View {

    enum SortOption: String, CaseIterable {
        case newest = "Newest"
        case name = "Name"
        case rating = "Highest Rated"
        case duration = "Duration"
        case analyzed = "Analysis Complete"
        case tranceDepth = "Trance Depth"
        case confidence = "AI Confidence"
        case lastPlayed = "Recently Played"
    }

    enum ContentFilter: String, CaseIterable {
        case all = "All"
        case hypnosis = "Hypnosis"
        case meditation = "Meditation"
        case music = "Music"
        case guided = "Guided"
        case affirmations = "Affirmations"
        case analyzed = "Analyzed"
        case unanalyzed = "Needs Analysis"
    }

    enum DurationFilter: String, CaseIterable {
        case all = "Any Length"
        case short = "5-15 min"
        case medium = "15-30 min"
        case long = "30-60 min"
        case extended = "60+ min"
    }

    enum TranceDepthFilter: String, CaseIterable {
        case all = "All Depths"
        case light = "Light Trance"
        case medium = "Medium Trance"
        case deep = "Deep Trance"
        case somnambulism = "Somnambulism"
    }

    @Bindable var engine: LightEngine
    @State var audioFiles: [AudioFile] = []
    @State var showingImporter = false
    @State var selectedFile: AudioFile?
    @State var selectedFiles = Set<AudioFile.ID>()
    @State var showingAnalysis = false
    @State var audioManager = AudioManager()
    var analysisManager: AnalysisStateManager {
        AnalysisStateManager.shared
    }
    @State var showingExpandedProgress = false
    @State var playerFile: AudioFile?
    @State var isSelectionMode = false
    @State var showingQueueManagement = false
    @State var searchText = ""
    @State var sortOption: SortOption = .newest
    @State var showFavoritesOnly = false
    @State var contentFilter: ContentFilter = .all
    @State var durationFilter: DurationFilter = .all
    @State var tranceDepthFilter: TranceDepthFilter = .all
    @State var searchTranscription = false
    @State var showingRenameAlert = false
    @State var newFilename = ""
    @State var fileToRename: AudioFile?
    @State var showingURLDownloader = false
    @State var audioURLInput = ""
    @State var isDownloadingURL = false
    @State var downloadError: String?
    @State var showingBrowser = false
    @State var showingAddSheet = false
 // TODO: Replace with actual playlist model
    @State var showingDeleteSelectedAlert = false
    @Environment(\.dismiss) var dismiss

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

                                Button {
                                    TranceHaptics.shared.medium()
                                    showingDeleteSelectedAlert = true
                                } label: {
                                    Image(systemName: "trash.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                        .font(.system(size: 32))
                                        .foregroundStyle(Color.roseGold)
                                }
                                .padding(.trailing, 8)
                                .disabled(selectedFiles.isEmpty)

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
                        .padding(.bottom, TranceSpacing.tabBarClearance)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

            }
            .navigationTitle("Sessions")
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
                        // Queue badge
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

                        // Add button — triggers action sheet
                        Button {
                            TranceHaptics.shared.light()
                            showingAddSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    LinearGradient(colors: [.roseGold, .blush],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
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
            .alert("Delete \(selectedFiles.count) Files?", isPresented: $showingDeleteSelectedAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteSelectedFiles()
                }
            } message: {
                Text("Are you sure you want to delete these audio files? This action cannot be undone.")
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
            .alert("Download Audio URL", isPresented: $showingURLDownloader) {
                TextField("https://...", text: $audioURLInput)
                Button("Cancel", role: .cancel) {
                    audioURLInput = ""
                    isDownloadingURL = false
                }
                Button("Download") {
                    handleURLDownload()
                }
                .disabled(audioURLInput.isEmpty || isDownloadingURL)
            } message: {
                if isDownloadingURL {
                    Text("Downloading... Please wait.")
                } else {
                    Text("Enter a stable URL pointing directly to an MP3, M4A, or WAV file.")
                }
            }
            .alert("Download Failed", isPresented: Binding(
                get: { downloadError != nil },
                set: { if !$0 { downloadError = nil } }
            )) {
                Button("OK", role: .cancel) { downloadError = nil }
            } message: {
                if let err = downloadError { Text(err) }
            }
            .onAppear {
                loadAudioFiles()
            }
            .confirmationDialog("Add to Sessions", isPresented: $showingAddSheet, titleVisibility: .visible) {
                Button("Import from Files") {
                    TranceHaptics.shared.light()
                    showingImporter = true
                }
                Button("Import from URL") {
                    TranceHaptics.shared.light()
                    showingURLDownloader = true
                }
                Button("Browse the Web") {
                    TranceHaptics.shared.light()
                    showingBrowser = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingBrowser) {
                InAppBrowserView { file in
                    addAudioFile(file)
                    if AnalysisPreferences.shared.autoAnalyzeOnImport {
                        Task { await analysisManager.queueForAnalysis([file]) }
                    }
                }
            }
            .onChange(of: isSelectionMode) { _, newValue in
                if !newValue {
                    selectedFiles.removeAll()
                }
            }
            .onAppear {
                loadAudioFiles()
            }
        }
    }
}

#Preview {
    @Previewable @State var engine = LightEngine()
    AudioLibraryView(engine: engine)
}
