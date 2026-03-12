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
    @State private var playerFile: AudioFile?
    @State private var isSelectionMode = false
    @State private var showingQueueManagement = false
    @State private var searchText = ""
    @State private var sortOption: SortOption = .newest
    @State private var showFavoritesOnly = false
    @State private var contentFilter: ContentFilter = .all
    @State private var durationFilter: DurationFilter = .all
    @State private var tranceDepthFilter: TranceDepthFilter = .all
    @State private var searchTranscription = false
    @State private var showingRenameAlert = false
    @State private var newFilename = ""
    @State private var fileToRename: AudioFile?
    @State private var showingURLDownloader = false
    @State private var audioURLInput = ""
    @State private var isDownloadingURL = false
    @State private var downloadError: String?
    @State private var showingBrowser = false
    @State private var showingAddSheet = false
 // TODO: Replace with actual playlist model
    @State private var showingDeleteSelectedAlert = false
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TranceSpacing.content) {
            Spacer()

            VStack(spacing: TranceSpacing.card) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.roseGold, .roseDeep],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.roseGold.opacity(0.25), radius: 16, x: 0, y: 8)

                VStack(spacing: TranceSpacing.inner) {
                    Text("No Audio Yet")
                        .font(TranceTypography.greeting)
                        .foregroundColor(.textPrimary)

                    Text("Tap  +  in the top right to add\naudio files to your library")
                        .font(TranceTypography.body)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }

            Spacer()

            // Subtle AI hint at the bottom
            HStack(spacing: TranceSpacing.icon) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.roseGold)
                Text("AI will analyze your audio to create custom light sessions")
                    .font(TranceTypography.caption)
                    .foregroundColor(.textLight)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.bottom, TranceSpacing.statusBar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Audio Library Content

    private var audioLibraryContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Search bar
                searchSection
                
                // Filter and Sort controls
                filterSortSection
                
                // Audio files list
                audioFilesGrid

                // Bottom spacing for selection toolbar or tab bar clearance
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: isSelectionMode ? TranceSpacing.tabBarClearance + 80 : TranceSpacing.tabBarClearance)
            }
        }
        .fullScreenCover(item: $playerFile) { file in
            AudioLightPlayerView(audioFile: file, engine: engine)
        }
    }

    // MARK: - Search Section

    private var searchSection: some View {
        GlassCard {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "magnifyingglass")
                    .font(TranceTypography.body)
                    .foregroundColor(.textLight)

                TextField(searchTranscription ? "Search content & transcriptions..." : "Search audio files...", text: $searchText)
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

    // MARK: - Filter & Sort Section

    private var filterSortSection: some View {
        VStack(spacing: TranceSpacing.inner) {
            // Quick Filters Row 1 - Content & Favorites
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TranceSpacing.inner) {
                    // Content Type Filter
                    Menu {
                        Picker("Content Type", selection: $contentFilter) {
                            ForEach(ContentFilter.allCases, id: \.self) { filter in
                                HStack {
                                    Text(filter.rawValue)
                                    if filter != .all {
                                        Text("(\(filteredCount(for: filter)))")
                                            .foregroundColor(.secondary)
                                    }
                                }.tag(filter)
                            }
                        }
                    } label: {
                        filterChipView(
                            icon: contentFilterIcon(contentFilter),
                            title: contentFilter.rawValue,
                            isActive: contentFilter != .all
                        )
                    }

                    // Duration Filter
                    Menu {
                        Picker("Duration", selection: $durationFilter) {
                            ForEach(DurationFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                    } label: {
                        filterChipView(
                            icon: "clock",
                            title: durationFilter.rawValue,
                            isActive: durationFilter != .all
                        )
                    }

                    // Trance Depth Filter (only show if we have analyzed files)
                    if audioFiles.contains(where: { $0.isAnalyzed && $0.analysisResult?.contentType == .hypnosis }) {
                        Menu {
                            Picker("Trance Depth", selection: $tranceDepthFilter) {
                                ForEach(TranceDepthFilter.allCases, id: \.self) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                        } label: {
                            filterChipView(
                                icon: "brain.head.profile",
                                title: tranceDepthFilter == .all ? "Depth" : tranceDepthFilter.rawValue,
                                isActive: tranceDepthFilter != .all
                            )
                        }
                    }

                    // Favorites Toggle
                    Button {
                        TranceHaptics.shared.light()
                        withAnimation(.spring(response: 0.3)) {
                            showFavoritesOnly.toggle()
                        }
                    } label: {
                        filterChipView(
                            icon: showFavoritesOnly ? "heart.fill" : "heart",
                            title: "Favorites",
                            isActive: showFavoritesOnly
                        )
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
            }

            // Sort & Search Options Row 2
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TranceSpacing.inner) {
                    // Sort Menu
                    Menu {
                        Picker("Sort By", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortOption.rawValue)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(TranceTypography.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.glassBorder.opacity(0.1))
                        .foregroundColor(.textSecondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(Color.glassBorder.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // Search in Transcription Toggle
                    if audioFiles.contains(where: { $0.hasTranscription }) {
                        Button {
                            TranceHaptics.shared.light()
                            withAnimation(.spring(response: 0.3)) {
                                searchTranscription.toggle()
                            }
                        } label: {
                            filterChipView(
                                icon: "doc.text.magnifyingglass",
                                title: "Search Content",
                                isActive: searchTranscription
                            )
                        }
                    }

                    // Clear All Filters (only show if any filters are active)
                    if contentFilter != .all || durationFilter != .all || tranceDepthFilter != .all || showFavoritesOnly {
                        Button {
                            TranceHaptics.shared.light()
                            withAnimation(.spring(response: 0.3)) {
                                contentFilter = .all
                                durationFilter = .all
                                tranceDepthFilter = .all
                                showFavoritesOnly = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Clear")
                            }
                            .font(TranceTypography.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
            }
        }
        .padding(.top, TranceSpacing.inner)
    }

    // MARK: - Filter Chip Helper

    private func filterChipView(icon: String, title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(isActive ? .roseGold : .textSecondary)
            Text(title)
        }
        .font(TranceTypography.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isActive ? Color.roseGold.opacity(0.15) : Color.glassBorder.opacity(0.1))
        .foregroundColor(isActive ? .roseGold : .textSecondary)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(isActive ? Color.roseGold.opacity(0.5) : Color.glassBorder.opacity(0.3), lineWidth: 1)
        )
    }

    private func contentFilterIcon(_ filter: ContentFilter) -> String {
        switch filter {
        case .all: return "list.bullet"
        case .hypnosis: return "brain.head.profile"
        case .meditation: return "leaf"
        case .music: return "music.note"
        case .guided: return "figure.mind.and.body"
        case .affirmations: return "quote.bubble"
        case .analyzed: return "sparkles"
        case .unanalyzed: return "questionmark.circle"
        }
    }

    private func filteredCount(for filter: ContentFilter) -> Int {
        audioFiles.filter { file in
            switch filter {
            case .all: return true
            case .hypnosis: return file.analysisResult?.contentType == .hypnosis
            case .meditation: return file.analysisResult?.contentType == .meditation
            case .music: return file.analysisResult?.contentType == .music
            case .guided: return file.analysisResult?.contentType == .guidedImagery
            case .affirmations: return file.analysisResult?.contentType == .affirmations
            case .analyzed: return file.isAnalyzed
            case .unanalyzed: return !file.isAnalyzed
            }
        }.count
    }

    // MARK: - Import Options Section

    private var importOptionsSection: some View {
        GlassCard(label: "Add Audio") {
            VStack(spacing: TranceSpacing.inner) {
                // --- Import from File (Primary) ---
                Button {
                    TranceHaptics.shared.light()
                    showingImporter = true
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                            .frame(width: 28)
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import from File")
                                .font(TranceTypography.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            Text("Choose MP3, M4A, or WAV files")
                                .font(TranceTypography.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, TranceSpacing.card)
                    .padding(.vertical, TranceSpacing.card)
                    .background(
                        LinearGradient(
                            colors: [.roseGold, .roseDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                    .shadow(color: Color.roseGold.opacity(0.30), radius: 8, x: 0, y: 4)
                }

                // --- Import from Web (Secondary) ---
                Button {
                    TranceHaptics.shared.light()
                    showingURLDownloader = true
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Group {
                            if isDownloadingURL {
                                ProgressView()
                                    .tint(.roseGold)
                            } else {
                                Image(systemName: "link.icloud.fill")
                                    .font(.title2)
                            }
                        }
                        .frame(width: 28)
                        .foregroundColor(.roseGold)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isDownloadingURL ? "Downloading..." : "Import from Web")
                                .font(TranceTypography.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.textPrimary)

                            Text(isDownloadingURL ? "Saving to your library..." : "Paste a link to an audio file")
                                .font(TranceTypography.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textLight)
                    }
                    .padding(.horizontal, TranceSpacing.card)
                    .padding(.vertical, TranceSpacing.card)
                    .background(
                        RoundedRectangle(cornerRadius: TranceRadius.button)
                            .fill(Color.roseGold.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: TranceRadius.button)
                                    .strokeBorder(Color.roseGold.opacity(0.35), lineWidth: 1)
                            )
                    )
                }
                .disabled(isDownloadingURL)

                // --- Browse the Web (Tertiary) ---
                Button {
                    TranceHaptics.shared.light()
                    showingBrowser = true
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Image(systemName: "safari.fill")
                            .font(.title2)
                            .frame(width: 28)
                            .foregroundColor(.textSecondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Browse the Web")
                                .font(TranceTypography.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.textPrimary)

                            Text("Find & download audio in-app")
                                .font(TranceTypography.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textLight)
                    }
                    .padding(.horizontal, TranceSpacing.card)
                    .padding(.vertical, TranceSpacing.card)
                    .background(
                        RoundedRectangle(cornerRadius: TranceRadius.button)
                            .fill(Color.glassBorder.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: TranceRadius.button)
                                    .strokeBorder(Color.glassBorder.opacity(0.35), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.cardMargin)
    }

    // MARK: - Audio Files Grid

    private var audioFilesGrid: some View {
        LazyVStack(spacing: TranceSpacing.cardMargin) {
            if !filteredAudioFiles.isEmpty {
                GlassCard(label: resultsHeaderText) {
                    LazyVStack(spacing: TranceSpacing.card) {
                        ForEach(filteredAudioFiles) { file in
                            AudioFileRow(
                                file: file,
                                audioManager: audioManager,
                                analysisManager: analysisManager,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedFiles.contains(file.id),
                                onPlay: { openPlayer(for: file) },
                                onRename: {
                                    fileToRename = file
                                    newFilename = file.displayName
                                    showingRenameAlert = true
                                },
                                onDelete: { deleteFile(file) },
                                onToggleSelection: { toggleSelection(for: file) },
                                onToggleFavorite: {
                                    toggleFavorite(for: file)
                                },
                                onUpdateRating: { newRating in
                                    updateRating(for: file, rating: newRating)
                                },
                                onDetailedRating: {
                                    showDetailedRatingSheet(for: file)
                                },
                                onAddToPlaylist: {
                                    print("🎵 Add \(file.filename) to playlist")
                                    TranceHaptics.shared.light()
                                }
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
        let baseFilter = audioFiles.filter { file in
            // Search filter
            let matchesSearch: Bool = {
                if searchText.isEmpty { return true }

                let searchInFilename = file.filename.localizedCaseInsensitiveContains(searchText)
                let searchInTranscription = searchTranscription && (file.transcription?.localizedCaseInsensitiveContains(searchText) == true)

                // Also search in analysis results if available
                let searchInAnalysis = file.analysisResult?.aiSummary.localizedCaseInsensitiveContains(searchText) == true ||
                                     file.analysisResult?.recommendedPreset.localizedCaseInsensitiveContains(searchText) == true

                return searchInFilename || searchInTranscription || searchInAnalysis
            }()

            // Content type filter
            let matchesContentType: Bool = {
                switch contentFilter {
                case .all: return true
                case .hypnosis: return file.analysisResult?.contentType == .hypnosis
                case .meditation: return file.analysisResult?.contentType == .meditation
                case .music: return file.analysisResult?.contentType == .music
                case .guided: return file.analysisResult?.contentType == .guidedImagery
                case .affirmations: return file.analysisResult?.contentType == .affirmations
                case .analyzed: return file.isAnalyzed
                case .unanalyzed: return !file.isAnalyzed
                }
            }()

            // Duration filter
            let matchesDuration: Bool = {
                switch durationFilter {
                case .all: return true
                case .short: return file.duration >= 300 && file.duration < 900 // 5-15 min
                case .medium: return file.duration >= 900 && file.duration < 1800 // 15-30 min
                case .long: return file.duration >= 1800 && file.duration < 3600 // 30-60 min
                case .extended: return file.duration >= 3600 // 60+ min
                }
            }()

            // Trance depth filter (only applicable to analyzed hypnosis files)
            let matchesTranceDeph: Bool = {
                switch tranceDepthFilter {
                case .all: return true
                case .light: return file.analysisResult?.hypnosisMetadata?.estimatedTranceDeph == .light
                case .medium: return file.analysisResult?.hypnosisMetadata?.estimatedTranceDeph == .medium
                case .deep: return file.analysisResult?.hypnosisMetadata?.estimatedTranceDeph == .deep
                case .somnambulism: return file.analysisResult?.hypnosisMetadata?.estimatedTranceDeph == .somnambulism
                }
            }()

            let matchesFavorite = !showFavoritesOnly || file.favorite

            return matchesSearch && matchesContentType && matchesDuration && matchesTranceDeph && matchesFavorite
        }

        return baseFilter.sorted { file1, file2 in
            switch sortOption {
            case .newest:
                return file1.createdDate > file2.createdDate
            case .name:
                return file1.filename.localizedStandardCompare(file2.filename) == .orderedAscending
            case .rating:
                return file1.userRating > file2.userRating
            case .duration:
                return file1.duration < file2.duration
            case .analyzed:
                if file1.isAnalyzed != file2.isAnalyzed {
                    return file1.isAnalyzed
                }
                return file1.createdDate > file2.createdDate
            case .tranceDepth:
                let depth1 = file1.analysisResult?.hypnosisMetadata?.estimatedTranceDeph.rawValue ?? "unknown"
                let depth2 = file2.analysisResult?.hypnosisMetadata?.estimatedTranceDeph.rawValue ?? "unknown"
                let depthOrder = ["deep", "somnambulism", "medium", "light", "unknown"]
                let index1 = depthOrder.firstIndex(of: depth1) ?? depthOrder.count
                let index2 = depthOrder.firstIndex(of: depth2) ?? depthOrder.count
                return index1 < index2
            case .confidence:
                let conf1 = file1.analysisResult?.classificationConfidence?.overallConfidence ?? 0
                let conf2 = file2.analysisResult?.classificationConfidence?.overallConfidence ?? 0
                return conf1 > conf2
            case .lastPlayed:
                let played1 = file1.lastPlayedDate ?? Date.distantPast
                let played2 = file2.lastPlayedDate ?? Date.distantPast
                return played1 > played2
            }
        }
    }

    // MARK: - Results Header

    private var resultsHeaderText: String {
        var components: [String] = []

        // Count with smart description
        let count = filteredAudioFiles.count
        let totalCount = audioFiles.count

        if count == totalCount {
            components.append("All Files (\(count))")
        } else {
            components.append("\(count) of \(totalCount) Files")
        }

        // Add active filter descriptions
        var filters: [String] = []

        if contentFilter != .all {
            filters.append(contentFilter.rawValue)
        }

        if durationFilter != .all {
            filters.append(durationFilter.rawValue)
        }

        if tranceDepthFilter != .all {
            filters.append(tranceDepthFilter.rawValue)
        }

        if showFavoritesOnly {
            filters.append("Favorites")
        }

        if !filters.isEmpty {
            components.append("• " + filters.joined(separator: ", "))
        }

        return components.joined(separator: " ")
    }

    // MARK: - Playback Handlers

    private func openPlayer(for file: AudioFile) {
        playerFile = file
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
    
    // MARK: - Rating & Liking Management

    private func toggleFavorite(for file: AudioFile) {
        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
            audioFiles[index].isFavorite = !(audioFiles[index].isFavorite ?? false)
            saveAudioFiles()
            TranceHaptics.shared.light()
        }
    }

    private func updateRating(for file: AudioFile, rating: Int) {
        if let index = audioFiles.firstIndex(where: { $0.id == file.id }) {
            audioFiles[index].rating = rating
            saveAudioFiles()
            TranceHaptics.shared.light()
        }
    }

    private func showDetailedRatingSheet(for file: AudioFile) {
        // For now, just show a quick rating action sheet
        // TODO: Implement full detailed rating sheet in future update
        print("📝 Show detailed rating for: \(file.filename)")
        TranceHaptics.shared.light()
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

    private func deleteSelectedFiles() {
        let filesToDelete = audioFiles.filter { selectedFiles.contains($0.id) }
        for file in filesToDelete {
            deleteFile(file)
        }
        
        // Exit selection mode
        selectedFiles.removeAll()
        isSelectionMode = false
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

    private func handleURLDownload() {
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

// MARK: - Audio File Row Component

struct AudioFileRow: View {
    let file: AudioFile
    let audioManager: AudioManager
    let analysisManager: AnalysisStateManager
    let isSelectionMode: Bool
    let isSelected: Bool
    let onPlay: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onToggleSelection: () -> Void
    let onToggleFavorite: () -> Void
    let onUpdateRating: (Int) -> Void
    let onDetailedRating: () -> Void
    let onAddToPlaylist: () -> Void

    @State private var hasGeneratedSession = false

    private var isAnalyzing: Bool {
        analysisManager.currentAnalysis?.audioFile.id == file.id
    }

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            // Selection/Play button
            Button {
                TranceHaptics.shared.medium()
                if isSelectionMode {
                    onToggleSelection()
                } else {
                    onPlay()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            isSelectionMode && isSelected ? Color.roseGold :
                            Color.roseGold.opacity(0.12)
                        )
                        .frame(width: 44, height: 44)

                    if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark" : "")
                            .font(.body.weight(.medium))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.body.weight(.medium))
                            .foregroundColor(.roseGold)
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

                    // Rating Stars
                    if !isSelectionMode && file.isAnalyzed {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= file.userRating ? "star.fill" : "star")
                                    .font(.caption2)
                                    .foregroundColor(star <= file.userRating ? .roseGold : .textLight)
                                    .onTapGesture {
                                        onUpdateRating(star == file.userRating ? 0 : star)
                                    }
                            }
                        }
                    }

                    // Playlist Add Button
                    if !isSelectionMode {
                        Button {
                            TranceHaptics.shared.light()
                            onAddToPlaylist()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.roseGold)
                        }
                    }
                }

                // Metadata row with heart, duration, and badges
                HStack(spacing: TranceSpacing.list) {
                    // Heart icon next to duration
                    if !isSelectionMode {
                        Image(systemName: file.favorite ? "heart.fill" : "heart")
                            .font(.caption)
                            .foregroundColor(file.favorite ? .roseGold : .textLight)
                    }

                    Text(file.durationFormatted)
                        .font(TranceTypography.caption)
                        .foregroundColor(.textSecondary)

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

                // Enhanced Content Badges (without file size)
                if let result = file.analysisResult {
                    HStack(spacing: TranceSpacing.inner) {
                        // Content Type Badge
                        HStack(spacing: 4) {
                            Image(systemName: contentTypeIcon(result.contentType))
                                .font(.system(size: 10))
                            Text(result.contentType.rawValue.capitalized)
                        }
                        .font(TranceTypography.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(contentTypeColor(result.contentType).opacity(0.15))
                        .foregroundColor(contentTypeColor(result.contentType))
                        .clipShape(Capsule())

                        // Trance Depth Badge (for hypnosis)
                        if result.contentType == .hypnosis,
                           let depth = result.hypnosisMetadata?.estimatedTranceDeph {
                            HStack(spacing: 2) {
                                Image(systemName: tranceDepthIcon(depth))
                                    .font(.system(size: 10))
                                Text(depth.rawValue.capitalized)
                            }
                            .font(TranceTypography.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tranceDepthColor(depth).opacity(0.15))
                            .foregroundColor(tranceDepthColor(depth))
                            .clipShape(Capsule())
                        }

                        // AI Confidence Indicator
                        if let confidence = result.classificationConfidence?.overallConfidence {
                            HStack(spacing: 2) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("\(Int(confidence * 100))%")
                            }
                            .font(TranceTypography.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(confidenceColor(confidence).opacity(0.15))
                            .foregroundColor(confidenceColor(confidence))
                            .clipShape(Capsule())
                        }

                        Spacer()
                    }
                }

            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .leading) {
            if !isSelectionMode {
                // Delete action (swipe from left)
                Button(role: .destructive) {
                    TranceHaptics.shared.medium()
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .trailing) {
            if !isSelectionMode {
                // Favorite action (swipe from right)
                Button {
                    TranceHaptics.shared.light()
                    onToggleFavorite()
                } label: {
                    Label(file.favorite ? "Unfavorite" : "Favorite",
                          systemImage: file.favorite ? "heart.slash.fill" : "heart.fill")
                }
                .tint(file.favorite ? .gray : .roseGold)

                // Rename action (swipe from right)
                Button {
                    TranceHaptics.shared.light()
                    onRename()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
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

    // MARK: - Helper Functions for Enhanced Display

    private func contentTypeIcon(_ type: AnalysisResult.ContentType) -> String {
        switch type {
        case .hypnosis: return "brain.head.profile"
        case .meditation: return "leaf"
        case .music: return "music.note"
        case .guidedImagery: return "figure.mind.and.body"
        case .affirmations: return "quote.bubble"
        case .unknown: return "questionmark.circle"
        }
    }

    private func contentTypeColor(_ type: AnalysisResult.ContentType) -> Color {
        switch type {
        case .hypnosis: return .roseGold
        case .meditation: return .green
        case .music: return .purple
        case .guidedImagery: return .blue
        case .affirmations: return .orange
        case .unknown: return .gray
        }
    }

    private func tranceDepthIcon(_ depth: HypnosisMetadata.TranceDeph) -> String {
        switch depth {
        case .light: return "circle"
        case .medium: return "circle.fill"
        case .deep: return "circles.hexagongrid.fill"
        case .somnambulism: return "brain"
        }
    }

    private func tranceDepthColor(_ depth: HypnosisMetadata.TranceDeph) -> Color {
        switch depth {
        case .light: return .cyan
        case .medium: return .blue
        case .deep: return .indigo
        case .somnambulism: return .purple
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .yellow
        default: return .orange
        }
    }

    private func ratingIndicator(_ icon: String, value: Int, color: Color) -> some View {
        HStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(color)
            Text("\(value)")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(color)
        }
    }
}

#Preview {
    @Previewable @State var engine = LightEngine()
    AudioLibraryView(engine: engine)
}
