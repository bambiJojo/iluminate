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
        case eroticHypnosis = "Erotic Hypnosis"
        case sleepHypnosis = "Sleep Hypnosis"
        case meditation = "Meditation"
        case brainwave = "Brainwave"
        case asmr = "ASMR"
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
    @State var audioManager = AudioManager.shared
    @State var analysisManager = AnalysisStateManager.shared
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
    @State var showingDownloadError = false
    @State var showingBrowser = false
    @State var showingAddSheet = false
    @State var showingDuplicateReview = false
    @State var showingFilters = false
    // TODO: Replace with actual playlist model
    @State var pendingDeletion = PendingAudioDeletion.shared
    /// Which row currently has its swipe action revealed. Only one at a time.
    @State var openSwipeRowID: AudioFile.ID?
    @Environment(\.dismiss) private var dismiss

    private var analysisAttentionCount: Int {
        analysisManager.analysisQueue.count + analysisManager.failedAnalyses.count
    }

    private var undoBannerMessage: String {
        let staged = pendingDeletion.staged
        guard staged.count == 1, let only = staged.first else {
            return "\(staged.count) files deleted"
        }
        return "Deleted “\(only.file.displayName)”"
    }

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
                                    .foregroundStyle(.textSecondary)

                                Spacer()

                                Button {
                                    deleteSelectedFiles()
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
                                .foregroundStyle(.white)
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

                // Above both emptyState and audioLibraryContent on purpose:
                // deleting the last file flips the screen to the empty state,
                // and Undo has to stay reachable from there.
                if !pendingDeletion.staged.isEmpty {
                    VStack {
                        Spacer()
                        UndoDeleteBanner(
                            message: undoBannerMessage,
                            onUndo: { undoDelete() },
                            onDismiss: { pendingDeletion.commit() }
                        )
                        .padding(.bottom, TranceSpacing.tabBarClearance)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Audio")
            .navigationDestination(for: AudioFile.self) { file in
                SessionDetailView(audioFile: file, engine: engine)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !audioFiles.isEmpty {
                        HStack(spacing: TranceSpacing.list) {
                            Button(isSelectionMode ? "Done" : "Select") {
                                TranceHaptics.shared.light()
                                if isSelectionMode {
                                    selectedFiles.removeAll()
                                }
                                isSelectionMode.toggle()
                            }

                            if isSelectionMode {
                                Button(allVisibleSelected ? "Deselect All" : "Select All") {
                                    toggleSelectAll()
                                }
                            }
                        }
                        .font(TranceTypography.body)
                        .foregroundStyle(.roseGold)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: TranceSpacing.small) {
                        // Queue badge
                        if analysisManager.currentAnalysis != nil || analysisAttentionCount > 0 {
                            Button {
                                showingQueueManagement = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "list.bullet.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                    if analysisAttentionCount > 0 {
                                        Text("\(analysisAttentionCount)")
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.roseGold, in: Capsule())
                                    }
                                }
                                .foregroundStyle(.roseGold)
                            }
                        }

                        // Needs at least two files before a duplicate is even
                        // possible.
                        if audioFiles.count > 1 {
                            Button("Find Duplicates", systemImage: "doc.on.doc") {
                                TranceHaptics.shared.light()
                                showingDuplicateReview = true
                            }
                            .labelStyle(.iconOnly)
                            .tint(.roseGold)
                        }

                        // Add button — triggers action sheet.
                        // Hidden while empty, where the inline import cards already
                        // present the same options.
                        if !audioFiles.isEmpty {
                            Button("Add", systemImage: "plus") {
                                TranceHaptics.shared.light()
                                showingAddSheet = true
                            }
                            .tint(.roseGold)
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
                NavigationStack {
                    AnalyzerView(engine: engine)
                }
            }
            .sheet(isPresented: $showingFilters) {
                filtersSheet
            }
            .sheet(isPresented: $showingDuplicateReview) {
                DuplicateAudioReviewView(audioFiles: audioFiles) { resolution in
                    Task { await mergeDuplicates(resolution) }
                }
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
            .alert("Download Failed", isPresented: $showingDownloadError) {
                Button("OK", role: .cancel) { downloadError = nil }
            } message: {
                if let err = downloadError { Text(err) }
            }
            .onChange(of: downloadError) { _, newValue in
                showingDownloadError = newValue != nil
            }
            .task {
                await loadAudioFiles()
                UsageAnalytics.shared.screen(.audioLibrary)
            }
            .animation(.snappy(duration: 0.25), value: pendingDeletion.staged.count)
            .task(id: pendingDeletion.staged.map(\.id)) {
                guard !pendingDeletion.staged.isEmpty else { return }
                // Re-runs whenever the batch changes, cancelling the previous
                // wait — so a second delete restarts the window rather than
                // inheriting the remains of the first.
                try? await Task.sleep(for: PendingAudioDeletion.undoWindow)
                guard !Task.isCancelled else { return }
                pendingDeletion.commit()
            }
            .onDisappear {
                // Leaving the library finalizes the delete. Attached to the
                // NavigationStack, so pushing a detail screen keeps Undo alive
                // and only leaving the tab commits.
                pendingDeletion.commit()
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
                    Task {
                        await addAudioFile(file)
                        if AnalysisPreferences.shared.autoAnalyzeOnImport {
                            await analysisManager.queueForAnalysis([file])
                        }
                    }
                }
            }
            .onChange(of: isSelectionMode) { _, newValue in
                if !newValue {
                    selectedFiles.removeAll()
                }
            }
            .onChange(of: analysisManager.completedAnalyses.count) {
                // Reload from UserDefaults when analysis completes —
                // AnalysisStateManager persists results there directly.
                Task { await loadAudioFiles() }
            }
        }
    }
}

#Preview {
    @Previewable @State var engine = LightEngine()
    AudioLibraryView(engine: engine)
}
