//
//  LibraryView.swift
//  Ilumionate
//
//  Unified library hub: shelf-first vertical scroll of carousel shelves
//  (Recently Played, Favorites, Playlists, Built-in Sessions) over an
//  inline Audio Files list.
//

import SwiftUI
import os

// MARK: - Library Navigation Destination

enum LibraryDestination: Hashable {
    case favorites
    case builtInSessions
    case artists
    case artist(String)
    case allFiles
}

// MARK: - LibraryView

struct LibraryView: View {

    @Bindable var engine: LightEngine
    /// Decoded once by `ContentView` and handed down. Library used to re-run
    /// `LightScoreReader` for all twelve bundled sessions in its own `.task`,
    /// which meant a synchronous JSON decode on the main actor every single
    /// time the Library tab was tapped.
    let builtInSessions: [LightSession]
    let isCheckingIncomingFiles: Bool
    let onCheckIncomingFiles: () -> Void

    @State private var audioFiles: [AudioFile] = []
    @State private var audioLibraryCache = AudioLibraryCache.shared
    /// Seeded at construction, not in `.task`. `.task` runs after the first
    /// paint, so loading there left the playlist shelf empty for a frame.
    /// `PlaylistStore.load()` is cached, so this is free on re-entry.
    @State private var playlists: [Playlist] = PlaylistStore.load()
    // Cached derived collections — recomputed only when audioFiles change
    @State private var cachedRecentFiles: [AudioFile] = []
    @State private var cachedFavoriteFiles: [AudioFile] = []
    @State private var cachedArtists: [LibraryArtist] = []
    @State private var cachedAnalyzedFiles: [AudioFile] = []
    @State private var cachedAllFiles: [AudioFile] = []
    @State private var cachedRecommendedFiles: [AudioFile] = []
    @State private var cachedGeneratedSessions: [GeneratedSessionItem] = []
    @State private var cachedFilterChips: [LibraryFilterChip] = []
    @State private var searchText = ""
    @State private var quickFilter: LibraryQuickFilter = .all
    @State private var savedSessionStore = SavedSessionStore.shared
    @State private var analysisManager = AnalysisStateManager.shared
    /// Injected by the app root. Library filters the shared snapshot rather than
    /// rebuilding analysis state of its own.
    @Environment(AnalysisCenterModel.self) private var analysisCenter
    @State private var navPath = NavigationPath()
    @State private var showingPlaylists = false
    @State private var showingSessionsManager = false
    @State private var showingAnalysisQueue = false
    @State private var playerFile: AudioFile?
    @State private var playingPlaylist: Playlist?
    @State private var playingSession: LightSession?
    @State private var fileForPlaylist: AudioFile?
    @State private var editingPlaylist: Playlist?
    @State private var pendingDeletion = PendingAudioDeletion.shared
    /// Library adds audio itself now rather than sending the user through the
    /// Audio manager first, so it hosts the three import sources.
    @State private var acquisition = AudioAcquisition()
    @State private var playlistImportRequest: PlaylistImportRequest?
    @State private var showingPlaylistLinkBrowser = false
    @State private var pendingPlaylistLink: String?

    var body: some View {
        // The banner sits outside the NavigationStack so it stays visible over
        // pushed screens — Audio Files, Favorites, a creator's sessions — all
        // of which can now delete.
        ZStack {
            libraryStack

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
        .animation(.snappy(duration: 0.25), value: pendingDeletion.staged.count)
        #if os(macOS) || targetEnvironment(macCatalyst)
        // Only offered while the Library is on screen, which is what greys out
        // ⌘F everywhere else rather than letting it fire into nothing.
        .focusedSceneValue(\.focusLibrarySearch) { searchFocusRequest += 1 }
        #endif
        .task(id: pendingDeletion.staged.map(\.id)) {
            guard !pendingDeletion.staged.isEmpty else { return }
            try? await Task.sleep(for: PendingAudioDeletion.undoWindow)
            guard !Task.isCancelled else { return }
            pendingDeletion.commit()
        }
        .onDisappear {
            // Leaving the Library tab finalizes the delete.
            pendingDeletion.commit()
        }
    }

    private var undoBannerMessage: String {
        let staged = pendingDeletion.staged
        guard staged.count == 1, let only = staged.first else {
            return "\(staged.count) files deleted"
        }
        return "Deleted “\(only.file.displayName)”"
    }

    private var libraryStack: some View {
        NavigationStack(path: $navPath) {
            ZStack(alignment: .bottom) {
                AuroraBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: TranceSpacing.cardMargin) {
                        LibraryHubHeader { addMenu }
                        .padding(.horizontal, TranceSpacing.screen)

                        if audioFiles.isEmpty == false {
                            LibrarySearchField(text: $searchText, focusRequest: searchFocusRequest)
                                .padding(.horizontal, TranceSpacing.screen)

                            if cachedFilterChips.isEmpty == false {
                                LibraryFilterChipRow(chips: cachedFilterChips, selection: $quickFilter)
                            }
                        }

                        if isNarrowed {
                            searchResultsSection
                        } else {
                            browseShelves
                        }

                        bottomSpacer
                    }
                    .padding(.top, TranceSpacing.screen)
                }
                .scrollIndicators(.hidden)
            }
            .platformNavigationBarHidden()
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .favorites:
                    LibraryBrowseView(
                        title: "Favorites",
                        audioFiles: audioFiles,
                        engine: engine,
                        initialFilter: .favorites,
                        onDelete: { deleteFile($0) }
                    )
                case .builtInSessions:
                    SessionLibraryView(engine: engine)
                case .artists:
                    LibraryCreatorsView(
                        audioFiles: audioFiles,
                        engine: engine,
                        onDelete: { deleteFile($0) }
                    )
                case .artist(let name):
                    LibraryBrowseView(
                        title: name,
                        audioFiles: audioFiles.filter { $0.creatorDisplayName == name },
                        engine: engine,
                        onDelete: { deleteFile($0) }
                    )
                case .allFiles:
                    LibraryBrowseView(
                        title: "Audio Files",
                        audioFiles: audioFiles,
                        engine: engine,
                        onDelete: { deleteFile($0) }
                    )
                }
            }
            .navigationDestination(for: AudioFile.self) { file in
                SessionDetailView(audioFile: file, engine: engine)
            }
            .sheet(isPresented: $showingPlaylists) {
                PlaylistLibraryView(engine: engine)
            }
            .sheet(isPresented: $showingSessionsManager) {
                AudioLibraryView(engine: engine)
            }
            .sheet(isPresented: $showingAnalysisQueue) {
                NavigationStack {
                    AnalysisCenterView(engine: engine)
                }
            }
            .platformFullScreenCover(item: $playerFile, onDismiss: {
                // Playback updates last-played metadata in persistent storage.
                Task { await loadAudioFiles(forceRefresh: true) }
            }) { file in
                UnifiedPlayerView(mode: .audioLight(audioFile: file), engine: engine)
            }
            .platformFullScreenCover(item: $playingPlaylist) { playlist in
                UnifiedPlayerView(mode: .playlist(playlist: playlist), engine: engine)
            }
            .platformFullScreenCover(item: $playingSession) { session in
                UnifiedPlayerView(mode: .session(session: session, audioFile: nil), engine: engine)
            }
            .sheet(item: $fileForPlaylist) { file in
                AddToPlaylistSheet(itemTitle: file.displayName) { playlist in
                    addFile(file, to: playlist)
                }
            }
            .sheet(item: $editingPlaylist) { playlist in
                PlaylistEditorView(
                    playlist: playlist,
                    isNew: !playlists.contains(where: { $0.id == playlist.id }),
                    onSave: { saved in upsertPlaylist(saved) }
                )
            }
            .audioAcquisition(acquisition)
            .sheet(item: $playlistImportRequest) { request in
                BambiCloudPlaylistImportView(
                    audioFiles: request.audioFiles,
                    initialLink: request.initialLink,
                    onImport: { imported in upsertPlaylist(imported) }
                )
            }
            .platformFullScreenCover(
                isPresented: $showingPlaylistLinkBrowser,
                onDismiss: startPendingPlaylistImport
            ) {
                PlaylistLinkBrowserView { pendingPlaylistLink = $0 }
            }
            .task {
                // Refreshing here rather than inside the model keeps the
                // acquisition flow ignorant of who is hosting it.
                acquisition.onImported = { _ in
                    Task { await loadAudioFiles(forceRefresh: true) }
                }
                loadPlaylists()
                recomputeDerivedCollections()
                await loadAudioFiles()
            }
            .onChange(of: audioFiles) { _, _ in recomputeDerivedCollections() }
            .onChange(of: audioLibraryCache.files) { _, files in
                audioFiles = files
            }
            .onChange(of: analysisManager.partialResultsRevision) {
                Task { await loadAudioFiles(forceRefresh: true) }
            }
        }
    }

    // MARK: - Browse Shelves

    /// The default shelf stack. "Analyzed" is deliberately absent — it duplicated
    /// All Files card-for-card, and every card now carries its own analyzed seal.
    /// "Continue" is absent too: it lives on home, next to the Current section,
    /// so resuming does not require a tab hop first.
    /// Incremented by the Mac ⌘F command to move focus into the search field.
    @State private var searchFocusRequest = 0

    /// The one way to add anything to the Library. Shared by the header's "+" and
    /// by the empty-state card, so an empty library offers it where it is described.
    @ViewBuilder
    private var addMenu: some View {
        LibraryAddMenu(
            acquisition: acquisition,
            onNewPlaylist: { editingPlaylist = Playlist(name: "") },
            onImportPlaylistLink: { playlistImportRequest = PlaylistImportRequest(audioFiles: audioFiles) },
            onBrowseForPlaylist: { showingPlaylistLinkBrowser = true },
            isCheckingIncomingFiles: isCheckingIncomingFiles,
            onCheckIncomingFiles: onCheckIncomingFiles,
            onManageAudio: { showingSessionsManager = true }
        )
    }

    @ViewBuilder
    private var browseShelves: some View {
        LibraryAnalysisEntryRow(
            activeTask: analysisCenter.activeTask,
            queuedCount: analysisCenter.queuedCount,
            attentionCount: analysisCenter.attentionCount,
            onOpen: openAnalysisQueue
        )
        .padding(.horizontal, TranceSpacing.screen)

        if audioFiles.isEmpty {
            LibraryEmptyCard { addMenu }
                .padding(.horizontal, TranceSpacing.screen)
        }

        if !recentFiles.isEmpty {
            LibraryShelfSectionHeader(title: "Recently Played")
                .padding(.horizontal, TranceSpacing.screen)
            LibraryAudioShelf(files: recentFiles, onPlay: playWithLights, onOpenInfo: openFileInfo)
        }

        if !recommendedFiles.isEmpty {
            LibraryShelfSectionHeader(title: "Recommended Next")
                .padding(.horizontal, TranceSpacing.screen)
            LibraryAudioShelf(files: recommendedFiles, onPlay: playWithLights, onOpenInfo: openFileInfo)
        }

        if !favoriteFiles.isEmpty {
            LibraryShelfSectionHeader(title: "Favorites") {
                navPath.append(LibraryDestination.favorites)
            }
            .padding(.horizontal, TranceSpacing.screen)
            LibraryAudioShelf(files: favoriteFiles, showsHeart: true, onPlay: playWithLights, onOpenInfo: openFileInfo)
        }

        LibraryShelfSectionHeader(title: "Playlists") {
            TranceHaptics.shared.light()
            showingPlaylists = true
        }
        .padding(.horizontal, TranceSpacing.screen)
        LibraryPlaylistShelf(
            playlists: shelfPlaylists,
            onPlay: { playPlaylist($0) },
            onCreate: { editingPlaylist = Playlist(name: "") },
            onOpenLibrary: { showingPlaylists = true },
            onOpenInfo: { openPlaylistInfo($0) }
        )

        if !artists.isEmpty {
            LibraryShelfSectionHeader(title: "Artists") {
                navPath.append(LibraryDestination.artists)
            }
            .padding(.horizontal, TranceSpacing.screen)
            LibraryArtistShelf(artists: artists) { artist in
                navPath.append(LibraryDestination.artist(artist.name))
            }
        }

        if !allFilesShelf.isEmpty {
            LibraryShelfSectionHeader(title: "All Files") {
                navPath.append(LibraryDestination.allFiles)
            }
            .padding(.horizontal, TranceSpacing.screen)
            LibraryAudioShelf(files: allFilesShelf, onPlay: playWithLights, onOpenInfo: openFileInfo)
        }

        if !generatedSessions.isEmpty {
            LibraryShelfSectionHeader(title: "Your Sessions")
                .padding(.horizontal, TranceSpacing.screen)
            LibraryGeneratedSessionShelf(items: generatedSessions, onPlay: playWithLights)
        }

        if !shelfSessions.isEmpty {
            LibraryShelfSectionHeader(title: "Built-in Sessions") {
                navPath.append(LibraryDestination.builtInSessions)
            }
            .padding(.horizontal, TranceSpacing.screen)
            LibraryBuiltInSessionShelf(sessions: shelfSessions) {
                playSession($0)
            }
        }

        if !savedSessions.isEmpty {
            LibraryShelfSectionHeader(title: "Saved Sessions")
                .padding(.horizontal, TranceSpacing.screen)
            LibraryBuiltInSessionShelf(sessions: savedSessions, onPlay: playSession)
        }
    }

    // MARK: - Search Results

    /// Replaces the shelves the moment the listener types or taps a chip — a
    /// flat, dense answer rather than ten carousels to swipe through.
    @ViewBuilder
    private var searchResultsSection: some View {
        // Filtering and sorting are linearithmic in the library size. Capture
        // each result once for this update instead of recomputing it for the
        // empty check, count, `ForEach`, and every row's separator.
        let matchedFiles = searchResults
        let matchedPlaylists = playlistResults
        let lastFileID = matchedFiles.last?.id
        let lastPlaylistID = matchedPlaylists.last?.id

        if matchedFiles.isEmpty && matchedPlaylists.isEmpty {
            LibraryNoResultsView(query: searchText, onClear: clearNarrowing)
        } else {
            if matchedPlaylists.isEmpty == false {
                LibraryShelfSectionHeader(title: "Playlists")
                    .padding(.horizontal, TranceSpacing.screen)

                LazyVStack(spacing: 0) {
                    ForEach(matchedPlaylists) { playlist in
                        LibraryPlaylistResultRow(
                            playlist: playlist,
                            onPlay: { playPlaylist(playlist) },
                            onOpenInfo: { openPlaylistInfo(playlist) }
                        )
                        if playlist.id != lastPlaylistID {
                            LibraryRowSeparator()
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.card)
                .padding(.vertical, TranceSpacing.inner)
                .liminalSurface()
                .padding(.horizontal, TranceSpacing.screen)
            }

            if matchedFiles.isEmpty == false {
                HStack {
                    Text("Sessions")
                        .font(TranceTypography.sectionTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    LibraryResultSummary(shown: matchedFiles.count, total: audioFiles.count)
                }
                .padding(.horizontal, TranceSpacing.screen)

                LazyVStack(spacing: 0) {
                    ForEach(matchedFiles) { file in
                        LibraryFileResultRow(
                            file: file,
                            onPlay: { playWithLights(file) },
                            onOpenInfo: { openFileInfo(file) },
                            onAddToPlaylist: { fileForPlaylist = file },
                            onDelete: { deleteFile(file) }
                        )
                        // The row's context menu still exposes Delete. Omitting
                        // the custom drag recognizer here keeps vertical list
                        // scrolling under a single gesture owner.
                        if file.id != lastFileID {
                            LibraryRowSeparator()
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.card)
                .padding(.vertical, TranceSpacing.inner)
                .liminalSurface()
                .padding(.horizontal, TranceSpacing.screen)
            }
        }
    }

    // MARK: - Helpers

    private var isNarrowed: Bool {
        LibraryBrowseFilter.isSearching(query: searchText, filter: quickFilter)
    }

    private var searchResults: [AudioFile] {
        LibraryBrowseFilter.apply(to: audioFiles, query: searchText, filter: quickFilter)
    }

    /// Playlists only join the results for a typed query — a content-type chip
    /// says nothing about a playlist.
    private var playlistResults: [Playlist] {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return []
        }
        return LibraryBrowseFilter.apply(to: playlists, query: searchText)
    }

    private func clearNarrowing() {
        searchText = ""
        quickFilter = .all
    }

    private var recentFiles: [AudioFile] { cachedRecentFiles }
    private var favoriteFiles: [AudioFile] { cachedFavoriteFiles }
    private var artists: [LibraryArtist] { cachedArtists }
    private var analyzedFiles: [AudioFile] { cachedAnalyzedFiles }
    private var allFilesShelf: [AudioFile] { cachedAllFiles }
    private var recommendedFiles: [AudioFile] { cachedRecommendedFiles }
    private var generatedSessions: [GeneratedSessionItem] { cachedGeneratedSessions }
    private var shelfPlaylists: [Playlist] { LibraryShelfContent.shelfPlaylists(from: playlists) }
    private var shelfSessions: [LightSession] {
        Array(builtInSessions.prefix(LibraryShelfContent.shelfCap))
    }
    private var savedSessions: [LightSession] {
        builtInSessions.filter { savedSessionStore.contains($0.id.uuidString) }
    }
    private var partialAnalysisFiles: [AudioFile] {
        audioFiles.filter { $0.hasTranscription && $0.isAnalyzed == false }
    }
    private func recomputeDerivedCollections() {
        cachedRecentFiles = LibraryShelfContent.recents(from: audioFiles)
        cachedFavoriteFiles = LibraryShelfContent.favorites(from: audioFiles)
        cachedArtists = LibraryShelfContent.artists(from: audioFiles)
        cachedAnalyzedFiles = LibraryShelfContent.analyzed(from: audioFiles)
        cachedAllFiles = LibraryShelfContent.allFiles(from: audioFiles)
        cachedRecommendedFiles = LibraryShelfContent.recommendedNext(from: audioFiles)
        cachedGeneratedSessions = LibraryShelfContent.generatedSessions(
            from: audioFiles,
            hasSession: { GeneratedSessionStore.shared.hasGeneratedScoreOnDisk(for: $0) },
            sessionLookup: { GeneratedSessionStore.shared.load(for: $0) }
        )
        cachedFilterChips = LibraryBrowseFilter.chips(for: audioFiles)
        if cachedFilterChips.contains(where: { $0.filter == quickFilter }) == false {
            quickFilter = .all
        }
    }

    private func upsertPlaylist(_ playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
        } else {
            playlists.append(playlist)
        }
        PlaylistStore.save(playlists)
    }

    /// Paints the last known library immediately. ContentView primes this cache
    /// at launch, so a normal Library entry must not decode the same multi-MB
    /// analysis payload again. Callers that follow a persistent mutation opt
    /// into a refresh explicitly.
    private func loadAudioFiles(forceRefresh: Bool = false) async {
        let cache = AudioLibraryCache.shared
        if cache.hasLoaded, forceRefresh == false {
            audioFiles = cache.files
            recomputeDerivedCollections()
            return
        }

        await cache.refresh()
        audioFiles = cache.files
    }

    // MARK: - Delete

    /// Removes the row and stages the file for undo. Nothing is destroyed until
    /// `PendingAudioDeletion.commit()` runs.
    private func deleteFile(_ file: AudioFile) {
        guard let index = audioFiles.firstIndex(where: { $0.id == file.id }) else { return }

        let staged = pendingDeletion.stage([
            StagedAudioFile(file: file, originalURL: file.url, originalIndex: index)
        ])

        // The move failed, so the file is still in Documents. Keep the row —
        // dropping it would let the next library scan re-register it.
        guard !staged.isEmpty else { return }

        audioFiles.remove(at: index)
        Task {
            if let persisted = await AudioLibraryStore.remove(audioFileIDs: [file.id]) {
                AudioLibraryCache.shared.store(persisted)
                audioFiles = persisted
            }
        }
        TranceHaptics.shared.medium()
    }

    private func undoDelete() {
        let recovered = pendingDeletion.restore()
        for entry in recovered {
            audioFiles.insert(entry.file, at: min(entry.originalIndex, audioFiles.count))
        }
        Task {
            if let persisted = await AudioLibraryStore.restore(recovered) {
                AudioLibraryCache.shared.store(persisted)
                audioFiles = persisted
            }
        }
        TranceHaptics.shared.light()
        Log.audio.info("↩️ Restored \(recovered.count) deleted file(s)")
    }

    private func loadPlaylists() {
        playlists = PlaylistStore.load()
    }

    /// Opens the importer on the link the browser landed on. Deferred to the
    /// browser's dismissal because presenting a sheet from inside a full screen
    /// cover that is still on its way out drops the presentation.
    private func startPendingPlaylistImport() {
        guard let link = pendingPlaylistLink else { return }
        pendingPlaylistLink = nil
        playlistImportRequest = PlaylistImportRequest(
            audioFiles: audioFiles,
            initialLink: link
        )
    }

    private func playPlaylist(_ playlist: Playlist) {
        TranceHaptics.shared.medium()
        playingPlaylist = playlist
    }

    private func playSession(_ session: LightSession) {
        TranceHaptics.shared.medium()
        playingSession = session
    }

    private func playWithLights(_ file: AudioFile) {
        TranceHaptics.shared.medium()
        playerFile = file
    }

    /// Pushes the file's detail screen (metadata, phases, transcript).
    private func openFileInfo(_ file: AudioFile) {
        navPath.append(file)
    }

    /// Opens the playlist's detail screen (tracks, transitions, artwork) —
    /// the playlist counterpart to `openFileInfo`.
    private func openPlaylistInfo(_ playlist: Playlist) {
        TranceHaptics.shared.light()
        editingPlaylist = playlist
    }

    private func openAnalysisQueue() {
        TranceHaptics.shared.light()
        showingAnalysisQueue = true
    }

    private func analyze(_ file: AudioFile) {
        Task {
            await analysisManager.evictCachedResult(for: file)
            await analysisManager.queueForAnalysis(file)
        }
    }

    private func addFile(_ file: AudioFile, to playlist: Playlist) {
        var playlists = PlaylistStore.load()
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        let item = PlaylistItem(audioFileId: file.id, filename: file.filename, duration: file.duration)
        playlists[index].items.append(item)
        PlaylistStore.save(playlists)
    }

    // MARK: - Layout Spacers

    private var bottomSpacer: some View {
        Color.clear.frame(height: TranceSpacing.tabBarClearance + TranceSpacing.content)
    }
}
