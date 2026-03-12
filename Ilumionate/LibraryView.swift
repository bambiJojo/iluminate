//
//  LibraryView.swift
//  Ilumionate
//
//  Unified library hub: Playlists, Creators, Folders, Favorites,
//  a Recents strip, and an inline Sessions list.
//

import SwiftUI

// MARK: - Library Navigation Destination

enum LibraryDestination: Hashable {
    case creators
    case folders
    case favorites
}

// MARK: - LibraryView

struct LibraryView: View {

    @Bindable var engine: LightEngine

    @State private var audioFiles: [AudioFile] = []
    @State private var sortOption: LibrarySortOption = .newest
    @State private var showingPlaylists = false
    @State private var showingSessionsManager = false
    @State private var syncPlayerItem: SyncPlayerItem?

    @Environment(FolderStore.self) private var folderStore

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        categoryRowsSection
                        divider
                        recentsSection
                        divider
                        sessionsSection
                        bottomSpacer
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar { toolbarContent }
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .creators:
                    LibraryCreatorsView(audioFiles: audioFiles, engine: engine)
                case .folders:
                    LibraryFoldersView(audioFiles: audioFiles, engine: engine)
                case .favorites:
                    LibraryFavoritesView(audioFiles: audioFiles, engine: engine)
                }
            }
            .sheet(isPresented: $showingPlaylists) {
                PlaylistLibraryView(engine: engine)
            }
            .sheet(isPresented: $showingSessionsManager) {
                AudioLibraryView(engine: engine)
            }
            .fullScreenCover(item: $syncPlayerItem) { item in
                AudioLightPlayerView(audioFile: item.audioFile, engine: engine)
            }
            .onAppear { loadAudioFiles() }
        }
    }

    // MARK: - Category Rows

    private var categoryRowsSection: some View {
        VStack(spacing: 0) {
            LibraryCategoryRow(icon: "music.note.list", iconColor: .roseGold, title: "Playlists", count: nil) {
                TranceHaptics.shared.light()
                showingPlaylists = true
            }
            rowDivider
            NavigationLink(value: LibraryDestination.creators) {
                LibraryCategoryRowLabel(icon: "person.wave.2.fill", iconColor: .bwTheta, title: "Creators", count: creatorCount)
            }
            .buttonStyle(PlainButtonStyle())
            rowDivider
            NavigationLink(value: LibraryDestination.folders) {
                LibraryCategoryRowLabel(icon: "folder.fill", iconColor: .warmAccent, title: "Folders", count: folderCount)
            }
            .buttonStyle(PlainButtonStyle())
            rowDivider
            NavigationLink(value: LibraryDestination.favorites) {
                LibraryCategoryRowLabel(icon: "heart.fill", iconColor: Color(hex: "E85D75"), title: "Favorites", count: favoritesCount)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.card)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
        .overlay(
            RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                .strokeBorder(Color.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.content)
    }

    // MARK: - Recents Strip

    @ViewBuilder
    private var recentsSection: some View {
        if !recentFiles.isEmpty {
            VStack(alignment: .leading, spacing: TranceSpacing.card) {
                sectionHeader("Recently Played")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TranceSpacing.card) {
                        ForEach(recentFiles) { file in
                            SessionMiniCard(file: file) {
                                playWithLights(file)
                            }
                        }
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.bottom, TranceSpacing.inner)
                }
            }
            .padding(.top, TranceSpacing.content)
        }
    }

    // MARK: - Sessions List

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionHeader("Sessions")
                Spacer()
                Menu {
                    Picker("Sort By", selection: $sortOption) {
                        ForEach(LibrarySortOption.allCases, id: \.self) { opt in
                            Text(opt.label).tag(opt)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortOption.label)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(TranceTypography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.glassBorder.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.glassBorder.opacity(0.3), lineWidth: 1))
                }
                .padding(.trailing, TranceSpacing.screen)
            }
            .padding(.leading, TranceSpacing.screen)
            .padding(.top, TranceSpacing.content)

            if sortedAudioFiles.isEmpty {
                emptySessionsHint
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(sortedAudioFiles) { file in
                        LibrarySessionRow(file: file, onPlay: { playWithLights(file) })
                        if file.id != sortedAudioFiles.last?.id {
                            rowDivider
                                .padding(.leading, 56)
                                .padding(.horizontal, TranceSpacing.screen)
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.inner)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
                .overlay(
                    RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                        .strokeBorder(Color.glassBorder, lineWidth: 1)
                )
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.inner)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                TranceHaptics.shared.light()
                showingSessionsManager = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(colors: [.roseGold, .blush],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
        }
    }

    // MARK: - Helpers

    private var creatorCount: Int {
        Set(audioFiles.compactMap { $0.creator?.isEmpty == false ? $0.creator : nil }).count
    }

    private var folderCount: Int { folderStore.folders.count }

    private var favoritesCount: Int { audioFiles.filter { $0.favorite }.count }

    private var recentFiles: [AudioFile] {
        audioFiles
            .filter { $0.lastPlayedDate != nil }
            .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
            .prefix(10)
            .map { $0 }
    }

    private var sortedAudioFiles: [AudioFile] {
        audioFiles.sorted { lhs, rhs in
            switch sortOption {
            case .newest:     return lhs.createdDate > rhs.createdDate
            case .name:       return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            case .lastPlayed: return (lhs.lastPlayedDate ?? .distantPast) > (rhs.lastPlayedDate ?? .distantPast)
            case .favorites:  return lhs.favorite && !rhs.favorite
            }
        }
    }

    private func loadAudioFiles() {
        guard let data = UserDefaults.standard.data(forKey: "audioFiles"),
              let files = try? JSONDecoder().decode([AudioFile].self, from: data) else { return }
        audioFiles = files
    }

    private func playWithLights(_ file: AudioFile) {
        Task {
            if let session = await loadGeneratedSession(for: file) {
                await MainActor.run {
                    syncPlayerItem = SyncPlayerItem(audioFile: file, lightSession: session)
                }
            }
        }
    }

    private func loadGeneratedSession(for file: AudioFile) async -> LightSession? {
        let sessionsDir = URL.documentsDirectory.appending(path: "GeneratedSessions")
        let sessionURL = sessionsDir.appending(path: "\(file.id).json")
        return try? LightScoreReader.loadSession(from: sessionURL)
    }

    // MARK: - Reusable Sub-views

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(TranceTypography.sectionTitle)
            .foregroundColor(.textPrimary)
            .fontWeight(.bold)
    }

    private var divider: some View {
        Color.bgPrimary.frame(height: TranceSpacing.inner)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.glassBorder.opacity(0.3))
            .frame(height: 1)
    }

    private var bottomSpacer: some View {
        Color.clear.frame(height: TranceSpacing.tabBarClearance + TranceSpacing.content)
    }

    private var emptySessionsHint: some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: "plus.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.title2)
                .foregroundStyle(Color.roseGold)
            Text("Tap  +  to add your first session")
                .font(TranceTypography.body)
                .foregroundColor(.textSecondary)
        }
        .padding(TranceSpacing.content)
    }
}

// MARK: - Sort Options

enum LibrarySortOption: String, CaseIterable {
    case newest     = "newest"
    case name       = "name"
    case lastPlayed = "lastPlayed"
    case favorites  = "favorites"

    var label: String {
        switch self {
        case .newest:     "Newest"
        case .name:       "Name"
        case .lastPlayed: "Recently Played"
        case .favorites:  "Favorites First"
        }
    }
}

// MARK: - LibraryCategoryRow

private struct LibraryCategoryRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LibraryCategoryRowLabel(icon: icon, iconColor: iconColor, title: title, count: count)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - LibraryCategoryRowLabel

struct LibraryCategoryRowLabel: View {
    let icon: String
    let iconColor: Color
    let title: String
    let count: Int?

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            Text(title)
                .font(TranceTypography.body)
                .foregroundColor(.textPrimary)

            Spacer()

            if let count, count > 0 {
                Text("\(count)")
                    .font(TranceTypography.caption)
                    .foregroundColor(.textLight)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textLight)
        }
        .padding(.vertical, TranceSpacing.card)
    }
}

// MARK: - SessionMiniCard (Recents strip)

private struct SessionMiniCard: View {
    let file: AudioFile
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                ZStack {
                    RoundedRectangle(cornerRadius: TranceRadius.button)
                        .fill(contentTypeGradient)
                        .frame(width: 110, height: 110)
                    Image(systemName: contentTypeIcon)
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.85))
                }
                .shadow(color: contentTypeColor.opacity(0.3), radius: 8, x: 0, y: 4)

                Text(file.displayName)
                    .font(TranceTypography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                    .frame(width: 110, alignment: .leading)

                Text(file.durationFormatted)
                    .font(.caption2)
                    .foregroundColor(.textLight)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var contentTypeColor: Color {
        switch file.analysisResult?.contentType {
        case .hypnosis:     return .bwDelta
        case .meditation:   return .bwAlpha
        case .music:        return .bwBeta
        case .guidedImagery: return .bwTheta
        case .affirmations: return .warmAccent
        default:            return .roseGold
        }
    }

    private var contentTypeGradient: LinearGradient {
        LinearGradient(
            colors: [contentTypeColor, contentTypeColor.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var contentTypeIcon: String {
        switch file.analysisResult?.contentType {
        case .hypnosis:     return "brain.head.profile"
        case .meditation:   return "leaf"
        case .music:        return "music.note"
        case .guidedImagery: return "figure.mind.and.body"
        case .affirmations: return "quote.bubble"
        default:            return "waveform"
        }
    }
}

// MARK: - LibrarySessionRow

struct LibrarySessionRow: View {
    let file: AudioFile
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: TranceSpacing.list) {
                // Content type icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(contentTypeColor.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: contentTypeIcon)
                        .font(.system(size: 17))
                        .foregroundColor(contentTypeColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.displayName)
                        .font(TranceTypography.body)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let creator = file.creator, !creator.isEmpty {
                            Text(creator)
                                .font(TranceTypography.caption)
                                .foregroundColor(.roseGold)
                        }
                        Text(file.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundColor(.textLight)
                    }
                }

                Spacer()

                if file.favorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "E85D75"))
                }

                Image(systemName: "play.circle")
                    .font(.system(size: 22))
                    .foregroundColor(.roseGold)
            }
            .padding(.vertical, TranceSpacing.card)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var contentTypeColor: Color {
        switch file.analysisResult?.contentType {
        case .hypnosis:      return .bwDelta
        case .meditation:    return .bwAlpha
        case .music:         return .bwBeta
        case .guidedImagery: return .bwTheta
        case .affirmations:  return .warmAccent
        default:             return .roseGold
        }
    }

    private var contentTypeIcon: String {
        switch file.analysisResult?.contentType {
        case .hypnosis:      return "brain.head.profile"
        case .meditation:    return "leaf"
        case .music:         return "music.note"
        case .guidedImagery: return "figure.mind.and.body"
        case .affirmations:  return "quote.bubble"
        default:             return "waveform"
        }
    }
}

// MARK: - Favorites Sub-View

struct LibraryFavoritesView: View {
    let audioFiles: [AudioFile]
    @Bindable var engine: LightEngine
    @State private var syncPlayerItem: SyncPlayerItem?

    private var favorites: [AudioFile] {
        audioFiles.filter { $0.favorite }.sorted { $0.filename < $1.filename }
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            if favorites.isEmpty {
                VStack(spacing: TranceSpacing.card) {
                    Image(systemName: "heart")
                        .font(.system(size: 56, weight: .ultraLight))
                        .foregroundStyle(LinearGradient(colors: [.roseGold, .roseDeep], startPoint: .top, endPoint: .bottom))
                    Text("No Favorites Yet")
                        .font(TranceTypography.greeting)
                        .foregroundColor(.textPrimary)
                    Text("Heart a session to find it here")
                        .font(TranceTypography.body)
                        .foregroundColor(.textSecondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(favorites) { file in
                            LibrarySessionRow(file: file) { playWithLights(file) }
                            if file.id != favorites.last?.id {
                                Rectangle().fill(Color.glassBorder.opacity(0.3)).frame(height: 1)
                                    .padding(.leading, 56)
                            }
                        }
                        Color.clear.frame(height: TranceSpacing.tabBarClearance)
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                }
            }
        }
        .navigationTitle("Favorites")
        .fullScreenCover(item: $syncPlayerItem) { item in
            AudioLightPlayerView(audioFile: item.audioFile, engine: engine)
        }
    }

    private func playWithLights(_ file: AudioFile) {
        Task {
            let sessionsDir = URL.documentsDirectory.appending(path: "GeneratedSessions")
            let sessionURL = sessionsDir.appending(path: "\(file.id).json")
            if let session = try? LightScoreReader.loadSession(from: sessionURL) {
                await MainActor.run { syncPlayerItem = SyncPlayerItem(audioFile: file, lightSession: session) }
            }
        }
    }
}
