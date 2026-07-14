//
//  LibraryAllFilesView.swift
//  Ilumionate
//
//  Pushed "Audio Files" screen: the full sortable list with swipe actions,
//  context menus, and detail navigation. Reached from the Library's
//  All Files shelf via "See all".
//

import SwiftUI

struct LibraryAllFilesView: View {
    let audioFiles: [AudioFile]
    @Bindable var engine: LightEngine

    @State private var sortOption: LibrarySortOption = .newest
    @State private var playerFile: AudioFile?
    @State private var fileForPlaylist: AudioFile?

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    LibrarySessionsList(
                        files: LibraryShelfContent.sortedFiles(from: audioFiles, by: sortOption),
                        engine: engine,
                        sortOption: $sortOption,
                        onPlay: playWithLights,
                        onAddToPlaylist: { fileForPlaylist = $0 }
                    )
                    Color.clear.frame(height: TranceSpacing.tabBarClearance + TranceSpacing.content)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Audio Files")
        .fullScreenCover(item: $playerFile) { file in
            UnifiedPlayerView(mode: .audioLight(audioFile: file), engine: engine)
        }
        .sheet(item: $fileForPlaylist) { file in
            AddToPlaylistSheet(itemTitle: file.displayName) { playlist in
                addFile(file, to: playlist)
            }
        }
    }

    private func playWithLights(_ file: AudioFile) {
        TranceHaptics.shared.medium()
        playerFile = file
    }

    private func addFile(_ file: AudioFile, to playlist: Playlist) {
        var playlists = PlaylistStore.load()
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        let item = PlaylistItem(audioFileId: file.id, filename: file.filename, duration: file.duration)
        playlists[index].items.append(item)
        PlaylistStore.save(playlists)
    }
}

// MARK: - Sessions List

/// Thin hairline divider between rows.
private struct LibraryRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.glassBorder.opacity(0.3))
            .frame(height: 1)
    }
}

/// The audio-files list with sort menu and per-row actions.
private struct LibrarySessionsList: View {
    let files: [AudioFile]
    let engine: LightEngine
    @Binding var sortOption: LibrarySortOption
    let onPlay: (AudioFile) -> Void
    let onAddToPlaylist: (AudioFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Audio Files")
                    .font(TranceTypography.sectionTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.textPrimary)
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
                    .foregroundStyle(.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .liminalGlass(.capsule, glow: false)
                }
                .padding(.trailing, TranceSpacing.screen)
            }
            .padding(.leading, TranceSpacing.screen)
            .padding(.top, TranceSpacing.content)

            if files.isEmpty {
                emptySessionsHint
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(files) { file in
                        NavigationLink {
                            SessionDetailView(audioFile: file, engine: engine)
                        } label: {
                            LibrarySessionRowLabel(file: file)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Play", systemImage: "play.fill") {
                                onPlay(file)
                            }
                            Button("Analyze", systemImage: "waveform") {
                                Task {
                                    AnalysisStateManager.shared.evictCachedResult(for: file)
                                    await AnalysisStateManager.shared.queueForAnalysis(file)
                                }
                            }
                            Button("Add to Playlist", systemImage: "plus") {
                                onAddToPlaylist(file)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                onPlay(file)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .tint(.auroraTeal)

                            Button {
                                onAddToPlaylist(file)
                            } label: {
                                Label("Add to Playlist", systemImage: "plus")
                            }
                            .tint(.bwTheta)
                        }
                        if file.id != files.last?.id {
                            LibraryRowDivider()
                                .padding(.leading, 56)
                                .padding(.horizontal, TranceSpacing.screen)
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.inner)
                .liminalSurface()
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.inner)
            }
        }
    }

    private var emptySessionsHint: some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: "plus")
                .font(.title2)
                .foregroundStyle(Color.auroraTeal)
            Text("Tap  +  to add your first session")
                .font(TranceTypography.body)
                .foregroundStyle(.textSecondary)
        }
        .padding(TranceSpacing.content)
    }
}
