# Library Shelf Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the main Library tab as a shelf-first vertical scroll of horizontal card carousels, matching the reader tab's Apple Music-style redesign.

**Architecture:** Reuse the reader's shelf mechanics (`CarouselRow`, `LiminalCard`, section-header pattern) but build Library-specific cards in a new `LibraryShelves.swift`. Shelf-content derivation lives in a pure `LibraryShelfContent` helper (unit-tested). `LibraryView` composes header + shelves + the unchanged Audio Files list.

**Tech Stack:** SwiftUI (iOS 26, `@Observable`), Swift Testing (`import Testing`), xcodebuild.

**Spec:** `docs/superpowers/specs/2026-07-12-library-shelf-redesign-design.md`

**Repo facts the engineer needs:**
- Xcode project uses synchronized groups — new files under `Ilumionate/` and `IlumionateTests/` are picked up automatically; no pbxproj edits.
- Build: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' build` (if "iPhone 17" is missing, list simulators with `xcrun simctl list devices available` and use an available iPhone).
- Tests are Swift Testing style (`@Test`, `#expect`), see `IlumionateTests/AppSettingsManagerTests.swift`.
- Some analyzer-related test failures pre-exist on this branch; only the new test suite must be green, plus no *new* failures elsewhere.
- Design tokens: `TranceSpacing`/`TranceRadius`/`TranceTypography` in `Ilumionate/TranceDesignSystem.swift`; glass surfaces in `Ilumionate/DesignSystem/LiminalSurface.swift`; `SessionGlowDot` in `Ilumionate/DesignSystem/ContentTypeStyle.swift`.

---

### Task 1: `LibraryShelfContent` derivation helper (TDD)

**Files:**
- Create: `IlumionateTests/LibraryShelfContentTests.swift`
- Create: `Ilumionate/LibraryShelfContent.swift`

- [ ] **Step 1: Write the failing tests**

Create `IlumionateTests/LibraryShelfContentTests.swift`:

```swift
//
//  LibraryShelfContentTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct LibraryShelfContentTests {

    private func makeFile(
        filename: String,
        lastPlayed: Date? = nil,
        favorite: Bool = false
    ) -> AudioFile {
        AudioFile(
            filename: filename,
            duration: 300,
            fileSize: 1_024,
            isFavorite: favorite,
            lastPlayedDate: lastPlayed
        )
    }

    // MARK: - Recents

    @Test
    func recents_ordersByLastPlayedDescendingAndExcludesNeverPlayed() {
        let now = Date()
        let files = [
            makeFile(filename: "old.m4a", lastPlayed: now.addingTimeInterval(-3_600)),
            makeFile(filename: "never.m4a"),
            makeFile(filename: "new.m4a", lastPlayed: now)
        ]

        let recents = LibraryShelfContent.recents(from: files)

        #expect(recents.map(\.filename) == ["new.m4a", "old.m4a"])
    }

    @Test
    func recents_capsAtShelfCap() {
        let now = Date()
        let files = (0..<25).map { index in
            makeFile(filename: "file\(index).m4a",
                     lastPlayed: now.addingTimeInterval(-Double(index)))
        }

        let recents = LibraryShelfContent.recents(from: files)

        #expect(recents.count == LibraryShelfContent.shelfCap)
        #expect(recents.first?.filename == "file0.m4a")
    }

    @Test
    func recents_emptyInputReturnsEmpty() {
        #expect(LibraryShelfContent.recents(from: []).isEmpty)
    }

    // MARK: - Favorites

    @Test
    func favorites_filtersToFavoritesInFilenameOrder() {
        let files = [
            makeFile(filename: "b.m4a", favorite: true),
            makeFile(filename: "plain.m4a"),
            makeFile(filename: "a.m4a", favorite: true)
        ]

        let favorites = LibraryShelfContent.favorites(from: files)

        #expect(favorites.map(\.filename) == ["a.m4a", "b.m4a"])
    }

    @Test
    func favorites_capsAtShelfCap() {
        let files = (0..<15).map { index in
            makeFile(filename: String(format: "fav%02d.m4a", index), favorite: true)
        }

        let favorites = LibraryShelfContent.favorites(from: files)

        #expect(favorites.count == LibraryShelfContent.shelfCap)
    }

    // MARK: - Playlists

    @Test
    func shelfPlaylists_preservesStoredOrderAndCaps() {
        let playlists = (0..<12).map { Playlist(name: "List \($0)") }

        let shelf = LibraryShelfContent.shelfPlaylists(from: playlists)

        #expect(shelf.count == LibraryShelfContent.shelfCap)
        #expect(shelf.first?.name == "List 0")
        #expect(shelf.last?.name == "List 9")
    }

    @Test
    func shelfPlaylists_emptyInputReturnsEmpty() {
        #expect(LibraryShelfContent.shelfPlaylists(from: []).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/LibraryShelfContentTests 2>&1 | tail -20
```
Expected: **BUILD FAILS** with `cannot find 'LibraryShelfContent' in scope` — that compile failure is the RED state (the type doesn't exist yet).

- [ ] **Step 3: Write the implementation**

Create `Ilumionate/LibraryShelfContent.swift`:

```swift
//
//  LibraryShelfContent.swift
//  Ilumionate
//
//  Pure derivation of the Library tab's shelf contents from stored data.
//  Kept UI-free so shelf ordering, filtering, and caps stay unit-testable.
//

import Foundation

nonisolated enum LibraryShelfContent {

    /// Maximum cards a shelf shows; the full set lives behind "See all"
    /// or the Audio Files list.
    static let shelfCap = 10

    /// Played files, most recently played first.
    static func recents(from files: [AudioFile]) -> [AudioFile] {
        Array(
            files
                .filter { $0.lastPlayedDate != nil }
                .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
                .prefix(shelfCap)
        )
    }

    /// Favorited files in filename order (matches the Favorites screen sort).
    static func favorites(from files: [AudioFile]) -> [AudioFile] {
        Array(
            files
                .filter(\.favorite)
                .sorted { $0.filename < $1.filename }
                .prefix(shelfCap)
        )
    }

    /// Stored playlists capped for the shelf, in stored order.
    static func shelfPlaylists(from playlists: [Playlist]) -> [Playlist] {
        Array(playlists.prefix(shelfCap))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same command as Step 2.
Expected: `Test Suite 'LibraryShelfContentTests' passed` / `** TEST SUCCEEDED **` (7 tests pass).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/LibraryShelfContent.swift IlumionateTests/LibraryShelfContentTests.swift
git commit -m "feat(library): shelf-content derivation helper with tests"
```

---

### Task 2: Shelf UI components (`LibraryShelves.swift`) + shared `CarouselRow` comment

**Files:**
- Create: `Ilumionate/LibraryShelves.swift`
- Modify: `Ilumionate/TextTrance/CarouselRow.swift:1-5` (comment only)

- [ ] **Step 1: Update the `CarouselRow` header comment**

In `Ilumionate/TextTrance/CarouselRow.swift`, replace:

```swift
//  CarouselRow.swift
//  Ilumionate
//
//  Shared horizontal shelf for the Reader tab: view-aligned paging with a
//  peek of the next card, matching the Apple Music shelf pattern.
```

with:

```swift
//  CarouselRow.swift
//  Ilumionate
//
//  Shared horizontal shelf used by the Reader and Library tabs: view-aligned
//  paging with a peek of the next card, matching the Apple Music shelf pattern.
```

- [ ] **Step 2: Create the shelf components**

Create `Ilumionate/LibraryShelves.swift`:

```swift
//
//  LibraryShelves.swift
//  Ilumionate
//
//  Shelf-first components for the Library tab: reader-style header, shelf
//  section headers, carousel shelves for recents/favorites/playlists/built-in
//  sessions, and the analysis-queue status card. Pure presentation — all
//  state and actions stay in LibraryView.
//

import SwiftUI

// MARK: - Header

/// "Library" title with a circular + button, matching the reader's header.
struct LibraryHubHeader: View {
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Text("Library")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.auroraTeal)
                    .frame(width: 36, height: 36)
                    .background(Color.glassBorder.opacity(0.14), in: .circle)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.glassBorder.opacity(0.35), lineWidth: 1)
                    }
            }
            .accessibilityLabel("Add sessions")
        }
    }
}

// MARK: - Section Header

/// Shelf title with an optional trailing "See all" action.
struct LibraryShelfSectionHeader: View {
    let title: String
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TranceTypography.sectionTitle)
                .fontWeight(.bold)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            if let onSeeAll {
                Button("See all", action: onSeeAll)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.auroraTeal)
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, TranceSpacing.micro)
    }
}

// MARK: - Analysis Queue Status

/// Compact status row shown only while analyses are queued or running.
struct AnalysisQueueStatusCard: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GlassCard {
                HStack(spacing: TranceSpacing.list) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.roseGold.opacity(0.18))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "waveform")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.roseGold)
                        }

                    Text("Analysis Queue")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)

                    Spacer()

                    Text("\(count)")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textLight)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textLight)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Audio Shelf (Recently Played / Favorites)

/// Horizontal shelf of audio-file cards; tapping a card plays it with lights.
struct LibraryAudioShelf: View {
    let files: [AudioFile]
    var showsHeart = false
    let onPlay: (AudioFile) -> Void

    var body: some View {
        CarouselRow(items: files) { file in
            Button {
                onPlay(file)
            } label: {
                AudioShelfCard(file: file, showsHeart: showsHeart)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AudioShelfCard: View {
    let file: AudioFile
    var showsHeart = false

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.list) {
                    SessionGlowDot(contentType: file.analysisResult?.contentType, size: 40)

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(file.displayName)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(file.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if showsHeart {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "E85D75"))
                    }
                }

                ShelfPlayPill()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 128)
    }
}

// MARK: - Playlists Shelf

/// Horizontal shelf of playlist cards; tapping plays the playlist.
struct LibraryPlaylistShelf: View {
    let playlists: [Playlist]
    let onPlay: (Playlist) -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        CarouselRow(items: playlists) { playlist in
            Button {
                onPlay(playlist)
            } label: {
                PlaylistShelfCard(playlist: playlist)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Play", systemImage: "play.fill") {
                    onPlay(playlist)
                }
                Button("Open Playlists", systemImage: "music.note.list") {
                    onOpenLibrary()
                }
            }
        }
    }
}

private struct PlaylistShelfCard: View {
    let playlist: Playlist

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.list) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.roseGold.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.roseGold)
                        }

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(playlist.name)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text("\(playlist.itemCount) tracks · \(playlist.totalDurationFormatted)")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                ShelfPlayPill()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 128)
    }
}

// MARK: - Built-in Sessions Shelf

/// Horizontal shelf of bundled light-session cards; tapping plays the session.
struct LibraryBuiltInSessionShelf: View {
    let sessions: [LightSession]
    let onPlay: (LightSession) -> Void

    var body: some View {
        CarouselRow(items: sessions) { session in
            Button {
                onPlay(session)
            } label: {
                BuiltInSessionShelfCard(session: session)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct BuiltInSessionShelfCard: View {
    let session: LightSession

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.list) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.bwGamma.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.bwGamma)
                        }

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(session.displayName)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(session.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                ShelfPlayPill()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 128)
    }
}

// MARK: - Shared Pill

/// Gradient "Play" pill shared by all shelf cards (mirrors the reader's
/// Resume pill on Continue Reading cards).
private struct ShelfPlayPill: View {
    var body: some View {
        Label("Play", systemImage: "play.fill")
            .font(TranceTypography.caption.weight(.semibold))
            .foregroundStyle(Color.voidDeep)
            .padding(.horizontal, TranceSpacing.list)
            .padding(.vertical, TranceSpacing.icon)
            .background(
                LinearGradient(colors: [.auroraTeal, .auroraBlue],
                               startPoint: .leading, endPoint: .trailing),
                in: .capsule
            )
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/LibraryShelves.swift Ilumionate/TextTrance/CarouselRow.swift
git commit -m "feat(library): shelf UI components (header, carousels, status card)"
```

---

### Task 3: Restructure `LibraryView` to compose the shelves

**Files:**
- Modify: `Ilumionate/LibraryView.swift`

- [ ] **Step 1: Replace state, body, and helpers**

In `Ilumionate/LibraryView.swift`, inside `struct LibraryView`:

**1a.** Replace the `@State` block (currently `audioFiles` through `fileForPlaylist`) with:

```swift
    @State private var audioFiles: [AudioFile] = []
    @State private var playlists: [Playlist] = []
    @State private var builtInSessions: [LightSession] = []
    @State private var sortOption: LibrarySortOption = .newest
    // Cached derived collections — recomputed only when audioFiles or sortOption change
    @State private var cachedSortedFiles: [AudioFile] = []
    @State private var cachedRecentFiles: [AudioFile] = []
    @State private var cachedFavoriteFiles: [AudioFile] = []
    @State private var navPath = NavigationPath()
    @State private var showingPlaylists = false
    @State private var showingSessionsManager = false
    @State private var showingAnalysisQueue = false
    @State private var playerFile: AudioFile?
    @State private var playingPlaylist: Playlist?
    @State private var playingSession: LightSession?
    @State private var fileForPlaylist: AudioFile?
```

**1b.** Replace the whole `var body` (the `NavigationStack { ... }` block, currently lines ~37-106) with:

```swift
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

                        if analysisQueueCount > 0 {
                            AnalysisQueueStatusCard(count: analysisQueueCount) {
                                TranceHaptics.shared.light()
                                showingAnalysisQueue = true
                            }
                            .padding(.horizontal, TranceSpacing.screen)
                        }

                        if !recentFiles.isEmpty {
                            LibraryShelfSectionHeader(title: "Recently Played")
                                .padding(.horizontal, TranceSpacing.screen)
                            LibraryAudioShelf(files: recentFiles, onPlay: playWithLights)
                        }

                        if !favoriteFiles.isEmpty {
                            LibraryShelfSectionHeader(title: "Favorites") {
                                navPath.append(LibraryDestination.favorites)
                            }
                            .padding(.horizontal, TranceSpacing.screen)
                            LibraryAudioShelf(files: favoriteFiles, showsHeart: true, onPlay: playWithLights)
                        }

                        if !shelfPlaylists.isEmpty {
                            LibraryShelfSectionHeader(title: "Playlists") {
                                TranceHaptics.shared.light()
                                showingPlaylists = true
                            }
                            .padding(.horizontal, TranceSpacing.screen)
                            LibraryPlaylistShelf(
                                playlists: shelfPlaylists,
                                onPlay: { playPlaylist($0) },
                                onOpenLibrary: { showingPlaylists = true }
                            )
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

                        LibrarySessionsList(
                            files: sortedAudioFiles,
                            engine: engine,
                            sortOption: $sortOption,
                            onPlay: playWithLights,
                            onAddToPlaylist: { fileForPlaylist = $0 }
                        )
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
                }
            }
            .sheet(isPresented: $showingPlaylists) {
                PlaylistLibraryView(engine: engine)
            }
            .sheet(isPresented: $showingSessionsManager) {
                AudioLibraryView(engine: engine)
            }
            .sheet(isPresented: $showingAnalysisQueue) {
                NavigationStack {
                    AnalyzerView()
                }
            }
            .fullScreenCover(item: $playerFile) { file in
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
            .onAppear {
                loadAudioFiles()
                loadPlaylists()
                loadBuiltInSessions()
                recomputeDerivedCollections()
            }
            .onChange(of: audioFiles) { _, _ in recomputeDerivedCollections() }
            .onChange(of: sortOption) { _, _ in recomputeDerivedCollections() }
        }
    }
```

**1c.** Delete the `// MARK: - Toolbar` section (`toolbarContent` property) entirely.

**1d.** Replace the `// MARK: - Helpers` computed properties and `recomputeDerivedCollections()`/`loadAudioFiles()` with:

```swift
    // MARK: - Helpers

    private var analysisQueueCount: Int {
        let manager = AnalysisStateManager.shared
        let active = manager.currentAnalysis != nil ? 1 : 0
        return active + manager.analysisQueue.count
    }
    private var recentFiles: [AudioFile] { cachedRecentFiles }
    private var favoriteFiles: [AudioFile] { cachedFavoriteFiles }
    private var sortedAudioFiles: [AudioFile] { cachedSortedFiles }
    private var shelfPlaylists: [Playlist] { LibraryShelfContent.shelfPlaylists(from: playlists) }
    private var shelfSessions: [LightSession] {
        Array(builtInSessions.prefix(LibraryShelfContent.shelfCap))
    }

    private func recomputeDerivedCollections() {
        cachedRecentFiles = LibraryShelfContent.recents(from: audioFiles)
        cachedFavoriteFiles = LibraryShelfContent.favorites(from: audioFiles)
        cachedSortedFiles = audioFiles.sorted { lhs, rhs in
            switch sortOption {
            case .newest:     return lhs.createdDate > rhs.createdDate
            case .name:       return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            case .lastPlayed: return (lhs.lastPlayedDate ?? .distantPast) > (rhs.lastPlayedDate ?? .distantPast)
            case .favorites:  return lhs.favorite && !rhs.favorite
            }
        }
    }

    private func loadAudioFiles() {
        audioFiles = AudioLibraryStore.loadRepairingStoredFiles()
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
```

(`playWithLights` and `addFile` stay as they are; the `divider` layout helper is now unused — delete it, keep `bottomSpacer`.)

**1e.** Delete these now-unused private structs from the bottom half of the file:
- `LibrarySectionHeader`
- `LibraryCategoryRows`
- `RecentsStrip`
- `LibraryCategoryRow`
- `LibraryCategoryRowLabel` (verified unused outside this file)
- `SessionMiniCard`

Keep: `LibraryRowDivider` (still used by `LibrarySessionsList`), `LibrarySessionsList`, `LibrarySortOption`, `LibrarySessionRow` (used by `LibraryCreatorsView`/`LibraryFoldersView`), `LibrarySessionRowLabel`, `LibraryFavoritesView`, and the `LibraryDestination` enum.

**1f.** In `LibrarySessionsList`'s header `HStack`, replace `LibrarySectionHeader(title: "Audio Files")` (the struct is deleted) with:

```swift
                Text("Audio Files")
                    .font(TranceTypography.sectionTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.textPrimary)
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. If it fails on unused-symbol or misnamed references, fix the exact error — do not restructure further.

- [ ] **Step 3: Run the new test suite again (regression)**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/LibraryShelfContentTests 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/LibraryView.swift
git commit -m "feat(library): shelf-first redesign of the Library tab"
```

---

### Task 4: Simulator visual verification

**Files:** none (verification only)

- [ ] **Step 1: Launch the app in the simulator**

Build and run on the iPhone 17 simulator (via Xcode MCP tools if available, otherwise `xcodebuild` + `xcrun simctl launch`). Navigate to the Library tab.

- [ ] **Step 2: Verify against this checklist**

- Header shows bold "Library" + circular `+`; `+` opens the Add Sessions sheet.
- No system nav bar on the Library root; pushing Favorites / Built-in Sessions shows their native titles and a working back button.
- Shelves appear only when they have content; each shelf pages with the next-card peek; a single-item shelf renders one full-width card.
- Recently Played card tap starts audio+light playback; Favorites cards show the heart; Favorites "See all" pushes the Favorites screen.
- Playlist card tap starts playlist playback; long-press shows Play / Open Playlists; "See all" opens the playlists sheet.
- Built-in Sessions card tap starts session playback; "See all" pushes the Session Library.
- Audio Files list below the shelves: sort menu, swipe actions, context menu, and empty-state hint all still work.
- Last content clears the floating tab bar (bottom spacer intact).
- Analysis Queue card appears only while something is queued/analyzing (trigger via a file's "Analyze" context action).

- [ ] **Step 3: Fix anything that fails, rebuild, re-verify, commit fixes**

```bash
git add -A Ilumionate
git commit -m "fix(library): shelf redesign polish from simulator verification"
```
(Only if fixes were needed.)

---

## Self-Review Notes

- Spec coverage: header (T3-1b), status card (T2+T3), four shelves (T2+T3), unchanged list (T3-1e/1f keep `LibrarySessionsList`), caps (T1), CarouselRow comment (T2-1), error/empty handling (`loadBuiltInSessions` logs and degrades; empty shelves render nothing via `if !….isEmpty`), tests (T1), sim verification (T4). No gaps found.
- Type consistency: `LibraryShelfContent.shelfCap/recents/favorites/shelfPlaylists` used identically in T1 and T3; shelf view names (`LibraryAudioShelf`, `LibraryPlaylistShelf`, `LibraryBuiltInSessionShelf`, `LibraryHubHeader`, `LibraryShelfSectionHeader`, `AnalysisQueueStatusCard`) match between T2 definitions and T3 call sites.
