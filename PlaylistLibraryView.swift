//
//  PlaylistLibraryView.swift
//  Ilumionate
//
//  Browse, manage, and launch playlists — bento layout on the void:
//  featured hero card + 2-up glass grid, artwork derived from content types.
//

import SwiftUI

struct PlaylistLibraryView: View {

    let engine: LightEngine
    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [Playlist] = []
    @State private var searchText = ""
    @State private var sortOption: PlaylistSortOption = .newest
    @State private var availableAudioFiles: [AudioFile] = []
    @State private var editingPlaylist: Playlist?
    @State private var playingPlaylist: Playlist?
    @State private var importRequest: PlaylistImportRequest?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                Group {
                    if playlists.isEmpty {
                        emptyState
                    } else {
                        bentoLayout
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // A bare glyph: the toolbar already supplies the capsule, so
                    // a filled circle on top of it reads as a control inside a
                    // control. Matches the Audio manager's toolbar.
                    Menu("Add", systemImage: "plus") {
                        Button("New Playlist", systemImage: "plus") {
                            TranceHaptics.shared.light()
                            createNewPlaylist()
                        }

                        Button("Import from Link", systemImage: "link") {
                            showPlaylistImporter()
                        }
                    }
                    .tint(.roseGold)
                }
            }
            .onAppear {
                playlists = PlaylistStore.load()
                loadAudioFiles()
            }
            .sheet(item: $editingPlaylist) { item in
                // item-based presentation can never present blank; the editor
                // owns its draft, so nothing writes back mid-presentation.
                PlaylistEditorView(
                    playlist: item,
                    isNew: !playlists.contains(where: { $0.id == item.id }),
                    onSave: { saved in
                        savePlaylist(saved)
                    }
                )
            }
            .sheet(item: $importRequest) { request in
                // The request carries its own library snapshot; an isPresented
                // sheet would build the importer from the pre-update body and
                // hand it an empty library.
                PlaylistImportView(
                    audioFiles: request.audioFiles,
                    onImport: savePlaylist
                )
            }
            .platformFullScreenCover(item: $playingPlaylist) { playlist in
                UnifiedPlayerView(mode: .playlist(playlist: playlist), engine: engine)
            }
        }
    }

    // MARK: - Actions

    private func createNewPlaylist() {
        editingPlaylist = Playlist(name: "")
    }

    private func showPlaylistImporter() {
        let files = AudioLibraryStore.load()
        availableAudioFiles = files
        TranceHaptics.shared.light()
        importRequest = PlaylistImportRequest(audioFiles: files)
    }

    private func editPlaylist(_ playlist: Playlist) {
        editingPlaylist = playlist
    }

    private func savePlaylist(_ playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
        } else {
            playlists.append(playlist)
        }
        PlaylistStore.save(playlists)
    }

    private func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        PlaylistStore.save(playlists)
    }

    private func playPlaylist(_ playlist: Playlist) {
        guard !playlist.isEmpty else { return }
        playingPlaylist = playlist
    }

    private func loadAudioFiles() {
        availableAudioFiles = AudioLibraryStore.load()
    }

    /// Content types driving a playlist's generated artwork. Falls back to the
    /// whole-session analysis type when item lookups come up empty.
    private func artworkTypes(for playlist: Playlist) -> [AudioContentType] {
        let itemTypes = playlist.items.map { item in
            availableAudioFiles.first { $0.id == item.audioFileId }?.analysisResult?.contentType
        }
        let types = PlaylistArtwork.distinctTypes(from: itemTypes)
        if types.isEmpty, let analyzed = playlist.wholeSessionAnalysis?.contentType, analyzed != .unknown {
            return [analyzed]
        }
        return types
    }

    // MARK: - Bento Layout

    /// Playlists after search + sort — everything below derives from this so the
    /// hero and the grid always agree with what the listener asked for.
    private var visiblePlaylists: [Playlist] {
        sortOption.sorted(LibraryBrowseFilter.apply(to: playlists, query: searchText))
    }

    private var isSearching: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// The hero is a browsing flourish, not a search result — while searching,
    /// every match earns an equal-sized tile instead.
    private var heroPlaylist: Playlist? {
        guard isSearching == false else { return nil }
        return visiblePlaylists.first { !$0.isEmpty } ?? visiblePlaylists.first
    }

    private var gridPlaylists: [Playlist] {
        visiblePlaylists.filter { $0.id != heroPlaylist?.id }
    }

    private var bentoLayout: some View {
        ScrollView {
            LazyVStack(spacing: TranceSpacing.card) {
                statsHeader

                LibrarySearchField(text: $searchText, prompt: "Search playlists and tracks")

                HStack {
                    LibraryResultSummary(
                        shown: visiblePlaylists.count,
                        total: playlists.count,
                        noun: "playlists"
                    )
                    Spacer()
                    playlistSortMenu
                }

                if visiblePlaylists.isEmpty {
                    LibraryNoResultsView(query: searchText) { searchText = "" }
                }

                if let hero = heroPlaylist {
                    PlaylistHeroCard(
                        playlist: hero,
                        types: artworkTypes(for: hero),
                        onPlay: {
                            TranceHaptics.shared.medium()
                            playPlaylist(hero)
                        },
                        onEdit: {
                            TranceHaptics.shared.light()
                            editPlaylist(hero)
                        }
                    )
                    .contextMenu { contextActions(for: hero) }
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: TranceSpacing.list),
                              GridItem(.flexible(), spacing: TranceSpacing.list)],
                    spacing: TranceSpacing.list
                ) {
                    ForEach(gridPlaylists) { playlist in
                        PlaylistGridTile(
                            playlist: playlist,
                            types: artworkTypes(for: playlist),
                            onPlay: {
                                TranceHaptics.shared.medium()
                                playPlaylist(playlist)
                            },
                            onEdit: {
                                TranceHaptics.shared.light()
                                editPlaylist(playlist)
                            }
                        )
                        .contextMenu { contextActions(for: playlist) }
                    }
                }

                Spacer(minLength: TranceSpacing.tabBarClearance)
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.vertical, TranceSpacing.list)
        }
        .scrollContentBackground(.hidden)
    }

    private var playlistSortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortOption) {
                ForEach(PlaylistSortOption.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            HStack(spacing: TranceSpacing.micro) {
                Image(systemName: "arrow.up.arrow.down")
                Text(sortOption.label)
            }
            .font(TranceTypography.caption)
            .fontWeight(.medium)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, TranceSpacing.list)
            .padding(.vertical, TranceSpacing.inner)
            .liminalGlass(.capsule, glow: false)
        }
        .accessibilityLabel("Sort playlists by \(sortOption.label)")
    }

    @ViewBuilder
    private func contextActions(for playlist: Playlist) -> some View {
        if !playlist.isEmpty {
            Button("Play", systemImage: "play.fill") { playPlaylist(playlist) }
        }
        Button("Edit", systemImage: "pencil") { editPlaylist(playlist) }
        Button("Delete", systemImage: "trash", role: .destructive) {
            TranceHaptics.shared.medium()
            deletePlaylist(playlist)
        }
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Playlists")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.textPrimary)

                let totalTracks = playlists.reduce(0) { $0 + $1.itemCount }
                Text("\(playlists.count) playlists · \(totalTracks) tracks")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                let totalDuration = playlists.reduce(0.0) { $0 + $1.totalDuration }
                let hours = Int(totalDuration) / 3600
                let minutes = Int(totalDuration) % 3600 / 60

                Text("\(hours)h \(minutes)m")
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(.roseGold)

                Text("Total time")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textLight)
            }
        }
        .padding(.vertical, TranceSpacing.inner)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TranceSpacing.screen) {
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.lavender.opacity(0.6),
                                Color.roseDeep.opacity(0.8),
                                Color.warmAccent.opacity(0.4),
                                Color.lavender.opacity(0.6)
                            ],
                            center: .center
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.roseGold.opacity(0.4),
                                Color.lavender.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 70
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "music.note.list")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(
                        LinearGradient(colors: [.roseGold, .roseDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            VStack(spacing: TranceSpacing.list) {
                Text("Your Playlist Library")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.textPrimary)

                Text("Sequence sessions and light experiences into curated journeys")
                    .font(TranceTypography.body)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TranceSpacing.screen)
            }

            Button {
                TranceHaptics.shared.medium()
                createNewPlaylist()
            } label: {
                Label("Create Your First Playlist", systemImage: "plus.circle.fill")
                    .font(TranceTypography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voidPrimary)
                    .padding(.horizontal, TranceSpacing.content)
                    .padding(.vertical, TranceSpacing.card)
                    .background(
                        LinearGradient(colors: [.roseGold, .roseDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
            }
            .buttonStyle(.plain)

            Button(
                "Import Playlist Link",
                systemImage: "link",
                action: showPlaylistImporter
            )
            .buttonStyle(.bordered)
            .tint(.roseGold)

            HStack(spacing: TranceSpacing.inner) {
                Image(systemName: "lightbulb.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.roseGold)
                    .font(.caption)

                Text("Playlists can crossfade between sessions for seamless experiences")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textLight)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TranceSpacing.screen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Add To Playlist Sheet

struct AddToPlaylistSheet: View {
    let itemTitle: String
    let onAdd: (Playlist) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [Playlist] = []
    @State private var addedPlaylistId: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if playlists.isEmpty {
                    VStack(spacing: TranceSpacing.card) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundStyle(Color.roseGold)
                        Text("No Playlists Yet")
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(.textPrimary)
                        Text("Create a playlist first from the Playlists tab")
                            .font(TranceTypography.body)
                            .foregroundStyle(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(TranceSpacing.screen)
                } else {
                    List {
                        Section {
                            ForEach(playlists) { playlist in
                                Button {
                                    onAdd(playlist)
                                    addedPlaylistId = playlist.id
                                    TranceHaptics.shared.medium()
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(800))
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: TranceSpacing.list) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.roseGold.opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "music.note.list")
                                                .font(.system(size: 16))
                                                .foregroundStyle(Color.roseGold)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(playlist.name)
                                                .font(TranceTypography.body)
                                                .foregroundStyle(.textPrimary)
                                            Text("\(playlist.itemCount) tracks")
                                                .font(TranceTypography.caption)
                                                .foregroundStyle(.textSecondary)
                                        }

                                        Spacer()

                                        if addedPlaylistId == playlist.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Color.roseGold)
                                        } else {
                                            Image(systemName: "plus")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(Color.roseGold)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.bgCard)
                            }
                        } header: {
                            Text("Add \"\(itemTitle)\" to")
                                .font(TranceTypography.caption)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    .platformInsetGroupedListStyle()
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Add to Playlist")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                playlists = PlaylistStore.load()
            }
        }
    }
}
