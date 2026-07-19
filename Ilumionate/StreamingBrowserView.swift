//
//  StreamingBrowserView.swift
//  Ilumionate
//
//  UI for browsing and selecting streaming content
//

import SwiftUI
import os

struct StreamingBrowserView: View {
    @Bindable var engine: LightEngine
    @Environment(\.dismiss) private var dismiss

    @State private var streamingManager = StreamingManager()
    @State private var searchText = ""
    @State private var selectedCategory: ContentCategory = .meditation
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if streamingManager.availableServices.isEmpty {
                    StreamingSetupView { showingSettings = true }
                } else if !streamingManager.availableServices.allSatisfy(\.isAuthenticated) {
                    StreamingConnectingView(errorMessage: streamingManager.errorMessage)
                } else {
                    StreamingContentView(
                        manager: streamingManager,
                        searchText: searchText,
                        selectedCategory: selectedCategory,
                        onSelectCategory: { category in
                            selectedCategory = category
                            Task { await searchCategory(category) }
                        },
                        onSelectTrack: selectTrack
                    )
                }

                // Analysis overlay
                if streamingManager.isAnalyzing {
                    StreamingAnalysisOverlay(manager: streamingManager)
                }
            }
            .navigationTitle("Streaming")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .searchable(text: $searchText, prompt: "Search for meditation, ambient, therapy...")
            .onSubmit(of: .search) {
                Task { await streamingManager.search(searchText) }
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty {
                    streamingManager.searchResults = []
                }
            }
            .onAppear {
                setupStreaming()
                UsageAnalytics.shared.screen(.streamingBrowser)
            }
            .sheet(isPresented: $showingSettings) {
                StreamingSettingsView(manager: streamingManager)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 18))
            }
        }
    }

    // MARK: - Actions

    private func setupStreaming() {
        // Load stored credentials
        let scClientId = UserDefaults.standard.string(forKey: "SoundCloud_ClientId")
        let scSecret = UserDefaults.standard.string(forKey: "SoundCloud_Secret")

        streamingManager.configure(
            soundCloudClientId: scClientId,
            soundCloudSecret: scSecret
        )

        if !streamingManager.availableServices.isEmpty {
            Task {
                await streamingManager.authenticateAll()
                await streamingManager.loadFeaturedContent()
                await searchCategory(.meditation) // Default category
            }
        }
    }

    private func searchCategory(_ category: ContentCategory) async {
        switch category {
        case .meditation:
            await streamingManager.searchWellnessContent()
        case .hypnosis:
            await streamingManager.searchHypnosisContent()
        case .focus:
            await streamingManager.searchFocusContent()
        case .ambient:
            await streamingManager.search("ambient nature sounds white noise")
        }
    }

    private func selectTrack(_ track: StreamingTrack) {
        Task {
            do {
                // Enhanced analysis and session generation
                let (audioFile, lightSession) = try await streamingManager.analyzeAndCreateSession(for: track)

                // Add to library and start playback with the custom session.
                await addToLibraryAndPlay(audioFile, lightSession: lightSession)
                dismiss()
            } catch {
                Log.streaming.info("Failed to analyze track: \(error)")
                // Fallback to basic creation
                let audioFile = streamingManager.createAudioFileFromTrack(track)
                await addToLibraryAndPlay(audioFile)
                dismiss()
            }
        }
    }

    private func addToLibraryAndPlay(_ audioFile: AudioFile, lightSession: LightSession? = nil) async {
        // Add to user's library
        var audioFiles = await loadAudioFiles()
        audioFiles.append(audioFile)
        await saveAudioFiles(audioFiles)

        // Save the generated light session if provided
        if let session = lightSession {
            saveGeneratedSession(session, for: audioFile)
        }

        // Start playback with light synchronization
        Log.streaming.info("🎵 Playing streaming track: \(audioFile.displayName)")
        if let session = lightSession {
            Log.streaming.info("✨ Using custom generated session with \(session.light_score.count) light moments")
        }
    }

    private func saveGeneratedSession(_ session: LightSession, for audioFile: AudioFile) {
        do {
            try GeneratedSessionStore.shared.save(session, for: audioFile)
        } catch {
            Log.streaming.info("❌ Failed to save session: \(error)")
        }
    }

    // MARK: - Helpers


    private func loadAudioFiles() async -> [AudioFile] {
        await AudioLibraryStore.loadRepairingStoredFiles()
    }

    private func saveAudioFiles(_ files: [AudioFile]) async {
        await AudioLibraryStore.save(files)
    }
}

// MARK: - Streaming Browser Components

private struct StreamingSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(TranceTypography.sectionTitle)
            .foregroundStyle(.textPrimary)
            .fontWeight(.bold)
            .padding(.leading, TranceSpacing.screen)
    }
}

private struct StreamingSetupView: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: TranceSpacing.content) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.roseGold, .blush],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Connect to SoundCloud")
                .font(TranceTypography.screenTitle)
                .foregroundStyle(.textPrimary)

            Text("Add your SoundCloud credentials to access thousands of full-length meditation, hypnosis, and therapy tracks.")
                .font(TranceTypography.body)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TranceSpacing.content)

            Button("Get Started") {
                onGetStarted()
            }
            .buttonStyle(TranceButtonStyle())
        }
    }
}

private struct StreamingConnectingView: View {
    let errorMessage: String?

    var body: some View {
        VStack(spacing: TranceSpacing.content) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.roseGold)

            Text("Connecting to services...")
                .font(TranceTypography.body)
                .foregroundStyle(.textSecondary)

            if let error = errorMessage {
                Text(error)
                    .font(TranceTypography.caption)
                    .foregroundStyle(.red)
                    .padding(.top)
            }
        }
    }
}

private struct StreamingAnalysisOverlay: View {
    let manager: StreamingManager

    var body: some View {
        ZStack {
            Color.bgPrimary.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: TranceSpacing.content) {
                ZStack {
                    Circle()
                        .stroke(Color.glassBorder, lineWidth: 3)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: manager.analysisProgress)
                        .stroke(
                            LinearGradient(
                                colors: [.roseGold, .blush],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(manager.analysisProgress * 100))%")
                        .font(TranceTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.roseGold)
                }

                VStack(spacing: TranceSpacing.inner) {
                    Text("Analyzing Content")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(.textPrimary)

                    Text(manager.analysisStatus)
                        .font(TranceTypography.body)
                        .foregroundStyle(.textSecondary)
                        .multilineTextAlignment(.center)

                    Text("Creating personalized light therapy session...")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textLight)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

private struct StreamingContentView: View {
    let manager: StreamingManager
    let searchText: String
    let selectedCategory: ContentCategory
    let onSelectCategory: (ContentCategory) -> Void
    let onSelectTrack: (StreamingTrack) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !searchText.isEmpty {
                    StreamingSearchResults(manager: manager, onSelectTrack: onSelectTrack)
                } else {
                    StreamingCategoriesSection(
                        manager: manager,
                        selectedCategory: selectedCategory,
                        onSelectCategory: onSelectCategory,
                        onSelectTrack: onSelectTrack
                    )
                    StreamingFeaturedSection(manager: manager)
                }
            }
        }
    }
}

private struct StreamingCategoriesSection: View {
    let manager: StreamingManager
    let selectedCategory: ContentCategory
    let onSelectCategory: (ContentCategory) -> Void
    let onSelectTrack: (StreamingTrack) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.card) {
            StreamingSectionHeader(title: "Browse Categories")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TranceSpacing.card) {
                    ForEach(ContentCategory.allCases, id: \.self) { category in
                        CategoryCard(category: category, isSelected: selectedCategory == category) {
                            onSelectCategory(category)
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
            }

            if !manager.searchResults.isEmpty {
                StreamingTracksList(tracks: manager.searchResults, onSelect: onSelectTrack)
            }
        }
        .padding(.top, TranceSpacing.content)
    }
}

private struct StreamingFeaturedSection: View {
    let manager: StreamingManager

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.card) {
            StreamingSectionHeader(title: "Featured Playlists")

            if manager.featuredPlaylists.isEmpty {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TranceSpacing.content)
            } else {
                LazyVStack(spacing: TranceSpacing.card) {
                    ForEach(manager.featuredPlaylists) { playlist in
                        PlaylistRow(playlist: playlist) {
                            // Handle playlist selection
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
            }
        }
        .padding(.top, TranceSpacing.content)
    }
}

private struct StreamingSearchResults: View {
    let manager: StreamingManager
    let onSelectTrack: (StreamingTrack) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.card) {
            StreamingSectionHeader(title: "Search Results")

            if manager.isLoading {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TranceSpacing.content)
            } else {
                StreamingTracksList(tracks: manager.searchResults, onSelect: onSelectTrack)
            }
        }
        .padding(.top, TranceSpacing.content)
    }
}

private struct StreamingTracksList: View {
    let tracks: [StreamingTrack]
    let onSelect: (StreamingTrack) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(tracks) { track in
                StreamingTrackRow(track: track) {
                    onSelect(track)
                }

                if track.id != tracks.last?.id {
                    Divider()
                        .padding(.leading, 56)
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
        .overlay(
            RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                .strokeBorder(Color.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, TranceSpacing.screen)
    }
}

// MARK: - Content Categories

enum ContentCategory: String, CaseIterable {
    case meditation = "meditation"
    case hypnosis = "hypnosis"
    case focus = "focus"
    case ambient = "ambient"

    var displayName: String {
        switch self {
        case .meditation: return "Meditation"
        case .hypnosis: return "Hypnosis"
        case .focus: return "Focus"
        case .ambient: return "Ambient"
        }
    }

    var icon: String {
        switch self {
        case .meditation: return "leaf.fill"
        case .hypnosis: return "brain.head.profile"
        case .focus: return "target"
        case .ambient: return "waveform.path.ecg"
        }
    }

    var color: Color {
        switch self {
        case .meditation: return .bwAlpha
        case .hypnosis: return .bwDelta
        case .focus: return .bwBeta
        case .ambient: return .bwTheta
        }
    }
}

// MARK: - Supporting Views

struct CategoryCard: View {
    let category: ContentCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: TranceSpacing.inner) {
                ZStack {
                    RoundedRectangle(cornerRadius: TranceRadius.button)
                        .fill(category.color.opacity(isSelected ? 0.3 : 0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: category.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(category.color)
                }

                Text(category.displayName)
                    .font(TranceTypography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .textPrimary : .textSecondary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct StreamingTrackRow: View {
    let track: StreamingTrack
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: TranceSpacing.list) {
                // Service icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(track.service.color.opacity(0.18))
                        .frame(width: 40, height: 40)

                    Image(systemName: track.service.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(track.service.color)
                }

                // Track info
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(TranceTypography.body)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(track.artist)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.textSecondary)

                        Text("•")
                            .foregroundStyle(.textLight)

                        Text(track.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.textLight)

                        Text("•")
                            .foregroundStyle(.textLight)

                        Text(track.service.displayName)
                            .font(TranceTypography.caption)
                            .foregroundStyle(track.service.color)
                    }
                }

                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.roseGold)
            }
            .padding(.vertical, TranceSpacing.card)
        }
        .buttonStyle(.plain)
    }
}

struct PlaylistRow: View {
    let playlist: StreamingPlaylist
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: TranceSpacing.list) {
                StreamingArtworkTile(url: playlist.artworkURL,
                                     accentColor: playlist.service.color)

                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(TranceTypography.body)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text("\(playlist.trackCount) tracks")
                            .font(TranceTypography.caption)
                            .foregroundStyle(.textSecondary)

                        Text("•")
                            .foregroundStyle(.textLight)

                        Text(playlist.service.displayName)
                            .font(TranceTypography.caption)
                            .foregroundStyle(playlist.service.color)
                    }
                }

                Spacer()
            }
            .padding(TranceSpacing.list)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
            .overlay(
                RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                    .strokeBorder(Color.glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
