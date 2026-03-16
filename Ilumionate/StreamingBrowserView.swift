//
//  StreamingBrowserView.swift
//  Ilumionate
//
//  UI for browsing and selecting streaming content
//

import SwiftUI

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
                    setupView
                } else if !streamingManager.availableServices.allSatisfy(\.isAuthenticated) {
                    connectingView
                } else {
                    contentView
                }

                // Analysis overlay
                if streamingManager.isAnalyzing {
                    analysisOverlay
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
            .onAppear { setupStreaming() }
            .sheet(isPresented: $showingSettings) {
                StreamingSettingsView(manager: streamingManager)
            }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
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
                .foregroundColor(.textPrimary)

            Text("Add your SoundCloud credentials to access thousands of full-length meditation, hypnosis, and therapy tracks.")
                .font(TranceTypography.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TranceSpacing.content)

            Button("Get Started") {
                showingSettings = true
            }
            .buttonStyle(TranceButtonStyle())
        }
    }

    // MARK: - Connecting View

    private var connectingView: some View {
        VStack(spacing: TranceSpacing.content) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.roseGold)

            Text("Connecting to services...")
                .font(TranceTypography.body)
                .foregroundColor(.textSecondary)

            if let error = streamingManager.errorMessage {
                Text(error)
                    .font(TranceTypography.caption)
                    .foregroundColor(.red)
                    .padding(.top)
            }
        }
    }

    // MARK: - Analysis Overlay

    private var analysisOverlay: some View {
        ZStack {
            Color.bgPrimary.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: TranceSpacing.content) {
                // Analysis progress circle
                ZStack {
                    Circle()
                        .stroke(Color.glassBorder, lineWidth: 3)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: streamingManager.analysisProgress)
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

                    Text("\(Int(streamingManager.analysisProgress * 100))%")
                        .font(TranceTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.roseGold)
                }

                VStack(spacing: TranceSpacing.inner) {
                    Text("Analyzing Content")
                        .font(TranceTypography.sectionTitle)
                        .foregroundColor(.textPrimary)

                    Text(streamingManager.analysisStatus)
                        .font(TranceTypography.body)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)

                    Text("Creating personalized light therapy session...")
                        .font(TranceTypography.caption)
                        .foregroundColor(.textLight)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !searchText.isEmpty {
                    searchResultsSection
                } else {
                    categoriesSection
                    featuredSection
                }
            }
        }
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.card) {
            sectionHeader("Browse Categories")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TranceSpacing.card) {
                    ForEach(ContentCategory.allCases, id: \.self) { category in
                        CategoryCard(category: category, isSelected: selectedCategory == category) {
                            selectedCategory = category
                            Task { await searchCategory(category) }
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
            }

            if !streamingManager.searchResults.isEmpty {
                tracksList
            }
        }
        .padding(.top, TranceSpacing.content)
    }

    // MARK: - Featured Section

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.card) {
            sectionHeader("Featured Playlists")

            if streamingManager.featuredPlaylists.isEmpty {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TranceSpacing.content)
            } else {
                LazyVStack(spacing: TranceSpacing.card) {
                    ForEach(streamingManager.featuredPlaylists) { playlist in
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

    // MARK: - Search Results

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.card) {
            sectionHeader("Search Results")

            if streamingManager.isLoading {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TranceSpacing.content)
            } else {
                tracksList
            }
        }
        .padding(.top, TranceSpacing.content)
    }

    // MARK: - Tracks List

    private var tracksList: some View {
        LazyVStack(spacing: 0) {
            ForEach(streamingManager.searchResults) { track in
                StreamingTrackRow(track: track) {
                    selectTrack(track)
                }

                if track.id != streamingManager.searchResults.last?.id {
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
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

                await MainActor.run {
                    // Add to library and start playbook with custom session
                    addToLibraryAndPlay(audioFile, lightSession: lightSession)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    print("Failed to analyze track: \(error)")
                    // Fallback to basic creation
                    let audioFile = streamingManager.createAudioFileFromTrack(track)
                    addToLibraryAndPlay(audioFile)
                    dismiss()
                }
            }
        }
    }

    private func addToLibraryAndPlay(_ audioFile: AudioFile, lightSession: LightSession? = nil) {
        // Add to user's library
        var audioFiles = loadAudioFiles()
        audioFiles.append(audioFile)
        saveAudioFiles(audioFiles)

        // Save the generated light session if provided
        if let session = lightSession {
            saveGeneratedSession(session, for: audioFile)
        }

        // Start playback with light synchronization
        print("🎵 Playing streaming track: \(audioFile.displayName)")
        if let session = lightSession {
            print("✨ Using custom generated session with \(session.light_score.count) light moments")
        }
    }

    private func saveGeneratedSession(_ session: LightSession, for audioFile: AudioFile) {
        let sessionsDir = URL.documentsDirectory.appending(path: "GeneratedSessions")
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let sessionURL = sessionsDir.appending(path: "\(audioFile.id).json")
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: sessionURL)
            print("💾 Saved generated session: \(sessionURL.lastPathComponent)")
        } catch {
            print("❌ Failed to save session: \(error)")
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(TranceTypography.sectionTitle)
            .foregroundColor(.textPrimary)
            .fontWeight(.bold)
            .padding(.leading, TranceSpacing.screen)
    }

    private func loadAudioFiles() -> [AudioFile] {
        guard let data = UserDefaults.standard.data(forKey: "audioFiles"),
              let files = try? JSONDecoder().decode([AudioFile].self, from: data) else { return [] }
        return files
    }

    private func saveAudioFiles(_ files: [AudioFile]) {
        let data = try? JSONEncoder().encode(files)
        UserDefaults.standard.set(data, forKey: "audioFiles")
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
                        .foregroundColor(category.color)
                }

                Text(category.displayName)
                    .font(TranceTypography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .textPrimary : .textSecondary)
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
                        .foregroundColor(track.service.color)
                }

                // Track info
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(TranceTypography.body)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(track.artist)
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)

                        Text("•")
                            .foregroundColor(.textLight)

                        Text(track.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundColor(.textLight)

                        Text("•")
                            .foregroundColor(.textLight)

                        Text(track.service.displayName)
                            .font(TranceTypography.caption)
                            .foregroundColor(track.service.color)
                    }
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.roseGold)
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
                AsyncImage(url: playlist.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(playlist.service.color.opacity(0.3))
                        .overlay(
                            Image(systemName: "music.note.list")
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(TranceTypography.body)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text("\(playlist.trackCount) tracks")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)

                        Text("•")
                            .foregroundColor(.textLight)

                        Text(playlist.service.displayName)
                            .font(TranceTypography.caption)
                            .foregroundColor(playlist.service.color)
                    }
                }

                Spacer()
            }
            .padding(.vertical, TranceSpacing.inner)
        }
        .buttonStyle(.plain)
    }
}