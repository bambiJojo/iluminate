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
    let onContinueReading: () -> Void

    @State private var audioFiles: [AudioFile] = []
    @State private var playlists: [Playlist] = []
    @State private var builtInSessions: [LightSession] = []
    // Cached derived collections — recomputed only when audioFiles change
    @State private var cachedRecentFiles: [AudioFile] = []
    @State private var cachedFavoriteFiles: [AudioFile] = []
    @State private var cachedArtists: [LibraryArtist] = []
    @State private var cachedAnalyzedFiles: [AudioFile] = []
    @State private var cachedAllFiles: [AudioFile] = []
    @State private var cachedRecommendedFiles: [AudioFile] = []
    @State private var readingContinuation: LibraryReadingContinuation?
    @State private var playbackProgressStore = PlaybackProgressStore.shared
    @State private var savedSessionStore = SavedSessionStore.shared
    @State private var analysisManager = AnalysisStateManager.shared
    @State private var navPath = NavigationPath()
    @State private var showingPlaylists = false
    @State private var showingSessionsManager = false
    @State private var showingAnalysisQueue = false
    @State private var playerFile: AudioFile?
    @State private var playingPlaylist: Playlist?
    @State private var playingSession: LightSession?
    @State private var fileForPlaylist: AudioFile?
    @State private var editingPlaylist: Playlist?

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack(alignment: .bottom) {
                AuroraBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: TranceSpacing.cardMargin) {
                        LibraryHubHeader {
                            TranceHaptics.shared.light()
                            showingSessionsManager = true
                        }
                        .padding(.horizontal, TranceSpacing.screen)

                        LibraryContinuationSection(
                            listening: listeningContinuations,
                            reading: readingContinuation,
                            onContinueListening: continueListening,
                            onContinueReading: onContinueReading
                        )
                        .padding(.horizontal, TranceSpacing.screen)

                        LibraryAnalysisStatusSection(
                            manager: analysisManager,
                            partialFiles: partialAnalysisFiles,
                            onOpen: openAnalysisQueue
                        )
                        .padding(.horizontal, TranceSpacing.screen)

                        if audioFiles.isEmpty {
                            LibraryEmptyCard()
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
                            onOpenLibrary: { showingPlaylists = true }
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

                        if !analyzedFiles.isEmpty {
                            LibraryShelfSectionHeader(title: "Analyzed")
                                .padding(.horizontal, TranceSpacing.screen)
                            LibraryAudioShelf(files: analyzedFiles, showsAnalyzedSeal: true, onPlay: playWithLights, onOpenInfo: openFileInfo)
                        }

                        if !allFilesShelf.isEmpty {
                            LibraryShelfSectionHeader(title: "All Files") {
                                navPath.append(LibraryDestination.allFiles)
                            }
                            .padding(.horizontal, TranceSpacing.screen)
                            LibraryAudioShelf(files: allFilesShelf, onPlay: playWithLights, onOpenInfo: openFileInfo)
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

                        bottomSpacer
                    }
                    .padding(.top, TranceSpacing.screen)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .favorites:
                    LibraryFavoritesView(audioFiles: audioFiles, engine: engine)
                case .builtInSessions:
                    SessionLibraryView(engine: engine)
                case .artists:
                    LibraryCreatorsView(audioFiles: audioFiles, engine: engine)
                case .artist(let name):
                    CreatorDetailView(
                        creatorName: name,
                        audioFiles: audioFiles.filter { $0.creatorDisplayName == name },
                        engine: engine
                    )
                case .allFiles:
                    LibraryAllFilesView(audioFiles: audioFiles, engine: engine)
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
                    AnalyzerView(engine: engine)
                }
            }
            .fullScreenCover(item: $playerFile, onDismiss: {
                Task { await loadAudioFiles() }
            }) { file in
                UnifiedPlayerView(mode: .audioLight(audioFile: file), engine: engine)
            }
            .fullScreenCover(item: $playingPlaylist) { playlist in
                UnifiedPlayerView(mode: .playlist(playlist: playlist), engine: engine)
            }
            .fullScreenCover(item: $playingSession) { session in
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
            .task {
                await loadAudioFiles()
                loadPlaylists()
                loadBuiltInSessions()
                recomputeDerivedCollections()
                loadReadingContinuation()
            }
            .onChange(of: audioFiles) { _, _ in recomputeDerivedCollections() }
            .onChange(of: analysisManager.partialResultsRevision) {
                Task { await loadAudioFiles() }
            }
        }
    }

    // MARK: - Helpers

    private var recentFiles: [AudioFile] { cachedRecentFiles }
    private var favoriteFiles: [AudioFile] { cachedFavoriteFiles }
    private var artists: [LibraryArtist] { cachedArtists }
    private var analyzedFiles: [AudioFile] { cachedAnalyzedFiles }
    private var allFilesShelf: [AudioFile] { cachedAllFiles }
    private var recommendedFiles: [AudioFile] { cachedRecommendedFiles }
    private var shelfPlaylists: [Playlist] { LibraryShelfContent.shelfPlaylists(from: playlists) }
    private var shelfSessions: [LightSession] {
        Array(builtInSessions.prefix(LibraryShelfContent.shelfCap))
    }
    private var savedSessions: [LightSession] {
        builtInSessions.filter { savedSessionStore.contains($0.id.uuidString) }
    }
    private var listeningContinuations: [PlaybackProgressSnapshot] {
        playbackProgressStore.snapshots.filter { snapshot in
            switch snapshot.kind {
            case .audio: audioFiles.contains { $0.id.uuidString == snapshot.contentID }
            case .session: builtInSessions.contains { $0.id.uuidString == snapshot.contentID }
            }
        }
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
    }

    private func upsertPlaylist(_ playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
        } else {
            playlists.append(playlist)
        }
        PlaylistStore.save(playlists)
    }

    private func loadAudioFiles() async {
        audioFiles = await AudioLibraryStore.loadRepairingStoredFiles()
    }

    private func loadPlaylists() {
        playlists = PlaylistStore.load()
    }

    private func loadBuiltInSessions() {
        var sessions: [LightSession] = []
        for name in LightScoreReader.discoverBundledSessions() {
            do {
                sessions.append(try LightScoreReader.loadSession(named: name))
            } catch {
                Log.ui.info("Library: failed to load bundled session '\(name)': \(error)")
            }
        }
        builtInSessions = sessions
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

    private func continueListening(_ snapshot: PlaybackProgressSnapshot) {
        switch snapshot.kind {
        case .audio:
            guard let file = audioFiles.first(where: { $0.id.uuidString == snapshot.contentID }) else { return }
            playWithLights(file)
        case .session:
            guard let session = builtInSessions.first(where: { $0.id.uuidString == snapshot.contentID }) else { return }
            playSession(session)
        }
    }

    private func openAnalysisQueue() {
        TranceHaptics.shared.light()
        showingAnalysisQueue = true
    }

    private func loadReadingContinuation() {
        guard let state = ReaderProgressStore.shared.recentStates.first else {
            readingContinuation = nil
            return
        }
        let imported = ImportedTranceScriptStore.shared.importedScripts
        let scripts = imported + TranceScriptLibrary.bundled().filter { candidate in
            imported.contains { $0.id == candidate.id } == false
        }
        if let script = scripts.first(where: { $0.id == state.scriptId }) {
            readingContinuation = LibraryReadingContinuation(
                title: script.title,
                wordIndex: state.wordIndex
            )
            return
        }
        if let document = ReadingDocumentStore.shared.documents.first(where: { $0.scriptID == state.scriptId }) {
            readingContinuation = LibraryReadingContinuation(
                title: document.title,
                wordIndex: state.wordIndex
            )
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

// MARK: - LibrarySessionRow

struct LibrarySessionRow: View {
    let file: AudioFile
    let onPlay: () -> Void
    var onAddToPlaylist: (() -> Void)?

    var body: some View {
        Button(action: {
            Log.ui.info("🎯 LibrarySessionRow: button tapped for \(file.displayName)")
            onPlay()
        }) {
            HStack(spacing: TranceSpacing.list) {
                // Content type icon badge
                SessionGlowDot(contentType: file.analysisResult?.contentType, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.displayName)
                        .font(TranceTypography.body)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let creator = file.creatorDisplayName {
                            Text(creator)
                                .font(TranceTypography.caption)
                                .foregroundStyle(.roseGold)
                        }
                        Text(file.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.textLight)
                    }
                }

                Spacer()

                if file.favorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "E85D75"))
                }

                if let onAddToPlaylist {
                    Button {
                        onAddToPlaylist()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.roseGold)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, TranceSpacing.card)
        }
        .buttonStyle(PlainButtonStyle())
    }

}

// MARK: - LibrarySessionRowLabel (for NavigationLink usage)

struct LibrarySessionRowLabel: View {
    let file: AudioFile

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            SessionGlowDot(contentType: file.analysisResult?.contentType, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.displayName)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let creator = file.creatorDisplayName {
                        Text(creator)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.roseGold)
                    }
                    Text(file.durationFormatted)
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textLight)
                    if file.isAnalyzed {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.roseGold)
                    }
                }
            }

            Spacer()

            if file.favorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "E85D75"))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textLight)
        }
        .padding(.vertical, TranceSpacing.card)
    }

}

// MARK: - Favorites Sub-View

struct LibraryFavoritesView: View {
    let audioFiles: [AudioFile]
    @Bindable var engine: LightEngine
    @State private var syncPlayerItem: SyncPlayerItem?
    @State private var fileForPlaylist: AudioFile?
    @State private var favorites: [AudioFile] = []

    var body: some View {
        ZStack {
            AuroraBackground()
            if favorites.isEmpty {
                VStack(spacing: TranceSpacing.card) {
                    Image(systemName: "heart")
                        .font(.system(size: 56, weight: .ultraLight))
                        .foregroundStyle(LinearGradient(colors: [.roseGold, .roseDeep], startPoint: .top, endPoint: .bottom))
                    Text("No Favorites Yet")
                        .font(TranceTypography.greeting)
                        .foregroundStyle(.textPrimary)
                    Text("Heart a session to find it here")
                        .font(TranceTypography.body)
                        .foregroundStyle(.textSecondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(favorites) { file in
                            LibrarySessionRow(file: file, onPlay: { playWithLights(file) }, onAddToPlaylist: { fileForPlaylist = file })
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
        .onAppear {
            favorites = audioFiles.filter { $0.favorite }.sorted { $0.filename < $1.filename }
        }
        .onChange(of: audioFiles) { _, new in
            favorites = new.filter { $0.favorite }.sorted { $0.filename < $1.filename }
        }
        .fullScreenCover(item: $syncPlayerItem) { item in
            UnifiedPlayerView(
                mode: .audioLight(audioFile: item.audioFile),
                engine: engine,
                initialLightSession: item.lightSession
            )
        }
        .sheet(item: $fileForPlaylist) { file in
            AddToPlaylistSheet(itemTitle: file.displayName) { playlist in
                addFile(file, to: playlist)
            }
        }
    }

    private func playWithLights(_ file: AudioFile) {
        syncPlayerItem = SyncPlayerItem(
            audioFile: file,
            lightSession: GeneratedSessionStore.shared.load(for: file)
        )
    }

    private func addFile(_ file: AudioFile, to playlist: Playlist) {
        var playlists = PlaylistStore.load()
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        let item = PlaylistItem(audioFileId: file.id, filename: file.filename, duration: file.duration)
        playlists[index].items.append(item)
        PlaylistStore.save(playlists)
    }
}
