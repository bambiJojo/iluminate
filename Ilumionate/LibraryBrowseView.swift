//
//  LibraryBrowseView.swift
//  Ilumionate
//
//  The single pushed browse screen for any scoped set of audio files —
//  All Files, Favorites, and a creator's sessions all route here. Search,
//  quick filters, and sort stay pinned above the list so a large library
//  stays navigable without scrolling back to the top.
//

import SwiftUI

struct LibraryBrowseView: View {

    let title: String
    let audioFiles: [AudioFile]
    @Bindable var engine: LightEngine

    /// Pre-applied narrowing for scoped entry points (e.g. Favorites).
    var initialFilter: LibraryQuickFilter = .all

    /// Handed down by whoever owns `audioFiles` — this screen only displays a
    /// scoped copy, so it cannot remove a file itself.
    var onDelete: ((AudioFile) -> Void)?

    @State private var searchText = ""
    @State private var quickFilter: LibraryQuickFilter = .all
    @State private var sortOption: LibrarySortOption = .newest
    @State private var didApplyInitialFilter = false
    @State private var playerFile: AudioFile?
    @State private var fileForPlaylist: AudioFile?
    @State private var navigatingFile: AudioFile?

    private var chips: [LibraryFilterChip] {
        LibraryBrowseFilter.chips(for: audioFiles)
    }

    private var results: [AudioFile] {
        LibraryBrowseFilter.apply(
            to: audioFiles,
            query: searchText,
            filter: quickFilter,
            sort: sortOption
        )
    }

    var body: some View {
        // Compute the filtered and sorted snapshot once per view update. The
        // previous computed property was read by the empty check, controls,
        // `ForEach`, and once per separator.
        let visibleResults = results

        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                controls(resultCount: visibleResults.count)

                if visibleResults.isEmpty {
                    ScrollView {
                        LibraryNoResultsView(query: searchText, onClear: clearNarrowing)
                            .padding(.top, TranceSpacing.statusBar)
                    }
                } else {
                    resultsList(visibleResults)
                }
            }
        }
        .navigationTitle(title)
        .navigationDestination(item: $navigatingFile) { file in
            SessionDetailView(audioFile: file, engine: engine)
        }
        .platformFullScreenCover(item: $playerFile) { file in
            UnifiedPlayerView(mode: .audioLight(audioFile: file), engine: engine)
        }
        .sheet(item: $fileForPlaylist) { file in
            AddToPlaylistSheet(itemTitle: file.displayName) { playlist in
                addFile(file, to: playlist)
            }
        }
        .onAppear {
            // Applied once so returning from a detail push does not wipe the
            // narrowing the listener set by hand.
            guard didApplyInitialFilter == false else { return }
            quickFilter = initialFilter
            didApplyInitialFilter = true
        }
    }

    // MARK: - Controls

    private func controls(resultCount: Int) -> some View {
        VStack(spacing: TranceSpacing.inner) {
            LibrarySearchField(text: $searchText)
                .padding(.horizontal, TranceSpacing.screen)

            if chips.isEmpty == false {
                LibraryFilterChipRow(chips: chips, selection: $quickFilter)
            }

            HStack {
                LibraryResultSummary(shown: resultCount, total: audioFiles.count)
                Spacer()
                LibrarySortMenu(selection: $sortOption)
            }
            .padding(.horizontal, TranceSpacing.screen)
        }
        .padding(.top, TranceSpacing.inner)
        .padding(.bottom, TranceSpacing.list)
    }

    // MARK: - Results

    private func resultsList(_ visibleResults: [AudioFile]) -> some View {
        let lastFileID = visibleResults.last?.id

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visibleResults) { file in
                    LibraryFileResultRow(
                        file: file,
                        onPlay: { play(file) },
                        onOpenInfo: { navigatingFile = file },
                        onAddToPlaylist: { fileForPlaylist = file },
                        onAnalyze: { analyze(file) },
                        onDelete: onDelete.map { delete in { delete(file) } }
                    )
                    // Delete remains in the context menu. A second drag
                    // recognizer on every row made the parent ScrollView's
                    // vertical gesture unreliable in large filtered lists.
                    if file.id != lastFileID {
                        LibraryRowSeparator()
                    }
                }
            }
            .padding(.horizontal, TranceSpacing.card)
            .padding(.vertical, TranceSpacing.inner)
            .liminalSurface()
            .padding(.horizontal, TranceSpacing.screen)

            Color.clear.frame(height: TranceSpacing.tabBarClearance + TranceSpacing.content)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Actions

    private func clearNarrowing() {
        searchText = ""
        quickFilter = .all
    }

    private func play(_ file: AudioFile) {
        TranceHaptics.shared.medium()
        playerFile = file
    }

    private func analyze(_ file: AudioFile) {
        Task {
            await AnalysisStateManager.shared.evictCachedResult(for: file)
            await AnalysisStateManager.shared.queueForAnalysis(file)
        }
    }

    private func addFile(_ file: AudioFile, to playlist: Playlist) {
        var playlists = PlaylistStore.load()
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        let item = PlaylistItem(audioFileId: file.id, filename: file.filename, duration: file.duration)
        playlists[index].items.append(item)
        PlaylistStore.save(playlists)
    }
}
