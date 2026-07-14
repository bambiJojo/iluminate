# Library Full Shelf-First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Library tab fully shelf-first: add Artists, Analyzed, and All Files carousels plus a New Playlist create card, and move the inline vertical list to a pushed screen.

**Architecture:** Extend the shipped shelf stack — `LibraryShelfContent` (pure derivation + tests), `LibraryShelves.swift` (cards), `LibraryView` (composition) — plus a new `LibraryAllFilesView` that inherits the existing `LibrarySessionsList`. `LibrarySortOption` moves next to the derivation code so sorting is testable.

**Tech Stack:** SwiftUI (iOS 26, `@Observable`), Swift Testing, xcodebuild.

**Spec:** `docs/superpowers/specs/2026-07-13-library-full-shelf-design.md`

**Repo facts:**
- Synchronized groups: new files under `Ilumionate/` are picked up automatically.
- Build/test destination: `platform=iOS Simulator,name=iPhone 17`.
- `AudioFile.creator` and `.analysisResult` are mutable vars — tests set them post-init; `AnalysisFixtures.hypnosisAnalysis` is a ready-made `AnalysisResult`.
- `CreatorDetailView(creatorName:audioFiles:engine:)` and `LibraryCreatorsView(audioFiles:engine:)` exist in `Ilumionate/LibraryCreatorsView.swift`.
- `PlaylistEditorView(playlist:isNew:onSave:)` exists in `PlaylistEditorView.swift` (repo root).
- Pre-existing analyzer test failures exist on this branch; only `LibraryShelfContentTests` must be green.

---

### Task 1: Derivation additions to `LibraryShelfContent` (TDD)

**Files:**
- Modify: `IlumionateTests/LibraryShelfContentTests.swift`
- Modify: `Ilumionate/LibraryShelfContent.swift`
- Modify: `Ilumionate/LibraryView.swift` (delete `LibrarySortOption` — it moves)

- [ ] **Step 1: Extend the test helper and add failing tests**

In `IlumionateTests/LibraryShelfContentTests.swift`, replace the existing `makeFile` helper with:

```swift
    private func makeFile(
        filename: String,
        createdDate: Date = Date(),
        lastPlayed: Date? = nil,
        favorite: Bool = false,
        creator: String? = nil,
        analyzed: Bool = false
    ) -> AudioFile {
        var file = AudioFile(
            filename: filename,
            duration: 300,
            fileSize: 1_024,
            createdDate: createdDate,
            isFavorite: favorite,
            lastPlayedDate: lastPlayed
        )
        file.creator = creator
        if analyzed { file.analysisResult = AnalysisFixtures.hypnosisAnalysis }
        return file
    }
```

Then append these tests inside `LibraryShelfContentTests` (before the closing brace):

```swift
    // MARK: - Artists

    @Test
    func artists_groupsByCreatorSortedByNameAndExcludesUnknown() {
        let files = [
            makeFile(filename: "b1.m4a", creator: "Bella"),
            makeFile(filename: "a1.m4a", creator: "Anders"),
            makeFile(filename: "b2.m4a", creator: "Bella"),
            makeFile(filename: "none.m4a")
        ]

        let artists = LibraryShelfContent.artists(from: files)

        #expect(artists == [
            LibraryArtist(name: "Anders", fileCount: 1),
            LibraryArtist(name: "Bella", fileCount: 2)
        ])
    }

    @Test
    func artists_capsAtShelfCap() {
        let files = (0..<14).map { index in
            makeFile(filename: "f\(index).m4a", creator: String(format: "Artist %02d", index))
        }

        #expect(LibraryShelfContent.artists(from: files).count == LibraryShelfContent.shelfCap)
    }

    // MARK: - Analyzed

    @Test
    func analyzed_filtersToAnalyzedNewestFirst() {
        let now = Date()
        let files = [
            makeFile(filename: "old.m4a", createdDate: now.addingTimeInterval(-100), analyzed: true),
            makeFile(filename: "raw.m4a", createdDate: now),
            makeFile(filename: "new.m4a", createdDate: now, analyzed: true)
        ]

        let analyzed = LibraryShelfContent.analyzed(from: files)

        #expect(analyzed.map(\.filename) == ["new.m4a", "old.m4a"])
    }

    // MARK: - All Files

    @Test
    func allFiles_ordersNewestFirstAndCaps() {
        let now = Date()
        let files = (0..<12).map { index in
            makeFile(filename: "f\(index).m4a", createdDate: now.addingTimeInterval(-Double(index)))
        }

        let shelf = LibraryShelfContent.allFiles(from: files)

        #expect(shelf.count == LibraryShelfContent.shelfCap)
        #expect(shelf.first?.filename == "f0.m4a")
        #expect(shelf.last?.filename == "f9.m4a")
    }

    // MARK: - Sorted Files

    @Test
    func sortedFiles_sortsByEachOption() {
        let now = Date()
        let files = [
            makeFile(filename: "beta.m4a", createdDate: now.addingTimeInterval(-10),
                     lastPlayed: now, favorite: false),
            makeFile(filename: "alpha.m4a", createdDate: now,
                     lastPlayed: now.addingTimeInterval(-50), favorite: true)
        ]

        #expect(LibraryShelfContent.sortedFiles(from: files, by: .newest).map(\.filename)
                == ["alpha.m4a", "beta.m4a"])
        #expect(LibraryShelfContent.sortedFiles(from: files, by: .name).map(\.filename)
                == ["alpha.m4a", "beta.m4a"])
        #expect(LibraryShelfContent.sortedFiles(from: files, by: .lastPlayed).map(\.filename)
                == ["beta.m4a", "alpha.m4a"])
        #expect(LibraryShelfContent.sortedFiles(from: files, by: .favorites).map(\.filename)
                == ["alpha.m4a", "beta.m4a"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/LibraryShelfContentTests 2>&1 | tail -15
```
Expected: **BUILD FAILS** — `cannot find 'LibraryArtist' in scope` etc. (RED).

- [ ] **Step 3: Implement**

In `Ilumionate/LibraryShelfContent.swift`, append inside the `LibraryShelfContent` enum:

```swift
    /// Creators with at least one file, name-sorted; unknown/empty creators excluded.
    static func artists(from files: [AudioFile]) -> [LibraryArtist] {
        let named = files.compactMap { file -> String? in
            guard let name = file.creatorDisplayName, !name.isEmpty else { return nil }
            return name
        }
        let grouped = Dictionary(grouping: named) { $0 }
        return Array(
            grouped
                .map { LibraryArtist(name: $0.key, fileCount: $0.value.count) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .prefix(shelfCap)
        )
    }

    /// Analyzed files, newest first.
    static func analyzed(from files: [AudioFile]) -> [AudioFile] {
        Array(
            files
                .filter(\.isAnalyzed)
                .sorted { $0.createdDate > $1.createdDate }
                .prefix(shelfCap)
        )
    }

    /// Every file, newest first, capped for the shelf.
    static func allFiles(from files: [AudioFile]) -> [AudioFile] {
        Array(files.sorted { $0.createdDate > $1.createdDate }.prefix(shelfCap))
    }

    /// Full-list sorting for the Audio Files screen (uncapped).
    static func sortedFiles(from files: [AudioFile], by option: LibrarySortOption) -> [AudioFile] {
        files.sorted { lhs, rhs in
            switch option {
            case .newest:     return lhs.createdDate > rhs.createdDate
            case .name:       return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            case .lastPlayed: return (lhs.lastPlayedDate ?? .distantPast) > (rhs.lastPlayedDate ?? .distantPast)
            case .favorites:  return lhs.favorite && !rhs.favorite
            }
        }
    }
```

And after the enum's closing brace, add:

```swift
/// A creator/narrator group shown on the Artists shelf.
nonisolated struct LibraryArtist: Identifiable, Equatable {
    let name: String
    let fileCount: Int
    var id: String { name }
}
```

Then MOVE `LibrarySortOption` (the whole `enum LibrarySortOption` block under `// MARK: - Sort Options`) out of `Ilumionate/LibraryView.swift` and into `Ilumionate/LibraryShelfContent.swift` (below `LibraryArtist`), adding `nonisolated`:

```swift
// MARK: - Sort Options

nonisolated enum LibrarySortOption: String, CaseIterable {
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
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: `** TEST SUCCEEDED **` (12 tests).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/LibraryShelfContent.swift Ilumionate/LibraryView.swift IlumionateTests/LibraryShelfContentTests.swift
git commit -m "feat(library): artists/analyzed/allFiles/sortedFiles derivations with tests"
```

---

### Task 2: New shelf components in `LibraryShelves.swift`

**Files:**
- Modify: `Ilumionate/LibraryShelves.swift`

- [ ] **Step 1: Add the analyzed seal to the audio shelf/card**

In `LibraryAudioShelf`, add a pass-through flag and forward it:

```swift
struct LibraryAudioShelf: View {
    let files: [AudioFile]
    var showsHeart = false
    var showsAnalyzedSeal = false
    let onPlay: (AudioFile) -> Void

    var body: some View {
        CarouselRow(items: files) { file in
            Button {
                onPlay(file)
            } label: {
                AudioShelfCard(file: file, showsHeart: showsHeart, showsAnalyzedSeal: showsAnalyzedSeal)
            }
            .buttonStyle(.plain)
        }
    }
}
```

In `AudioShelfCard`, add `var showsAnalyzedSeal = false` below `showsHeart`, and inside the `HStack` after the `showsHeart` block add:

```swift
                    if showsAnalyzedSeal {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.roseGold)
                    }
```

- [ ] **Step 2: Add the Artists shelf**

Append to `LibraryShelves.swift`:

```swift
// MARK: - Artists Shelf

/// Horizontal shelf of creator cards; tapping opens that artist's sessions.
struct LibraryArtistShelf: View {
    let artists: [LibraryArtist]
    let onOpen: (LibraryArtist) -> Void

    var body: some View {
        CarouselRow(items: artists) { artist in
            Button {
                TranceHaptics.shared.light()
                onOpen(artist)
            } label: {
                ArtistShelfCard(artist: artist)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ArtistShelfCard: View {
    let artist: LibraryArtist

    var body: some View {
        LiminalCard {
            HStack(spacing: TranceSpacing.list) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.auroraBlue.opacity(0.18))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "music.mic")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.auroraBlue)
                    }

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(artist.name)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(artist.fileCount) sessions")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 88)
    }
}
```

- [ ] **Step 3: Add the New Playlist create card and rework the playlists shelf**

Replace `LibraryPlaylistShelf` with:

```swift
/// Horizontal shelf of playlist cards, led by a create card; tapping a
/// playlist plays it, tapping the create card opens the new-playlist editor.
struct LibraryPlaylistShelf: View {
    let playlists: [Playlist]
    let onPlay: (Playlist) -> Void
    let onCreate: () -> Void
    let onOpenLibrary: () -> Void

    private var items: [PlaylistShelfItem] {
        [.create] + playlists.map(PlaylistShelfItem.playlist)
    }

    var body: some View {
        CarouselRow(items: items) { item in
            switch item {
            case .create:
                Button {
                    TranceHaptics.shared.light()
                    onCreate()
                } label: {
                    NewPlaylistCard()
                }
                .buttonStyle(.plain)
            case .playlist(let playlist):
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
}

private enum PlaylistShelfItem: Identifiable {
    case create
    case playlist(Playlist)

    var id: String {
        switch self {
        case .create: return "create-playlist"
        case .playlist(let playlist): return playlist.id.uuidString
        }
    }
}

/// Dashed "New Playlist" affordance leading the playlists shelf.
private struct NewPlaylistCard: View {
    var body: some View {
        VStack(spacing: TranceSpacing.list) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.auroraTeal)
            Text("New Playlist")
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 128)
        .background(Color.glassBorder.opacity(0.10),
                    in: .rect(cornerRadius: TranceRadius.glassCard))
        .overlay {
            RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                .strokeBorder(Color.auroraTeal.opacity(0.5),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
    }
}
```

(The `onPlay` haptic stays in `LibraryView.playPlaylist`, unchanged.)

- [ ] **Step 4: Add the empty-library card**

Append:

```swift
// MARK: - Empty Library

/// Shown under the header when no audio files exist at all.
struct LibraryEmptyCard: View {
    var body: some View {
        GlassCard {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(Color.auroraTeal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No sessions yet")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Tap  +  to add your first session")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected failure at this point: `LibraryView.swift` still calls the old `LibraryPlaylistShelf(playlists:onPlay:onOpenLibrary:)` signature — that's fixed in Task 4. If that is the ONLY error, proceed; commit happens after Task 4 builds green. Otherwise fix errors in `LibraryShelves.swift` now.

---

### Task 3: `LibraryAllFilesView` (list moves out of the root)

**Files:**
- Create: `Ilumionate/LibraryAllFilesView.swift`
- Modify: `Ilumionate/LibraryView.swift` (delete `LibrarySessionsList`, `LibraryRowDivider`, and the `// MARK: - Library Section Components` header they lived under)

- [ ] **Step 1: Create the new screen file**

Create `Ilumionate/LibraryAllFilesView.swift`. MOVE the existing `LibrarySessionsList` and `LibraryRowDivider` structs verbatim out of `LibraryView.swift` into this file (below `LibraryAllFilesView`), and add the host screen:

```swift
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
```

The moved `LibrarySessionsList` keeps its current body exactly (sort menu, `Text("Audio Files")` bold header, swipe actions, context menus, `emptySessionsHint`), and `LibraryRowDivider` comes with it because the list is its only consumer.

- [ ] **Step 2: Verify `LibraryView.swift` no longer contains them**

Run: `grep -n "LibrarySessionsList\|LibraryRowDivider" Ilumionate/LibraryView.swift`
Expected after Task 4 wiring: no struct definitions remain in `LibraryView.swift` (a call-site match is also gone because the root no longer renders the list). Build happens in Task 4.

---

### Task 4: Recompose `LibraryView`

**Files:**
- Modify: `Ilumionate/LibraryView.swift`

- [ ] **Step 1: Extend `LibraryDestination`**

```swift
enum LibraryDestination: Hashable {
    case favorites
    case builtInSessions
    case artists
    case artist(String)
    case allFiles
}
```

- [ ] **Step 2: Update state**

Remove `@State private var sortOption` and `@State private var cachedSortedFiles`. Add:

```swift
    @State private var cachedArtists: [LibraryArtist] = []
    @State private var cachedAnalyzedFiles: [AudioFile] = []
    @State private var cachedAllFiles: [AudioFile] = []
    @State private var editingPlaylist: Playlist?
```

- [ ] **Step 3: Replace the shelf composition in `body`**

Inside the `LazyVStack`, after the header/status-card blocks, replace everything from the `if !recentFiles.isEmpty` block through the `LibrarySessionsList(...)` call with:

```swift
                        if audioFiles.isEmpty {
                            LibraryEmptyCard()
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
                            LibraryAudioShelf(files: analyzedFiles, showsAnalyzedSeal: true, onPlay: playWithLights)
                        }

                        if !allFilesShelf.isEmpty {
                            LibraryShelfSectionHeader(title: "All Files") {
                                navPath.append(LibraryDestination.allFiles)
                            }
                            .padding(.horizontal, TranceSpacing.screen)
                            LibraryAudioShelf(files: allFilesShelf, onPlay: playWithLights)
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
```

(`bottomSpacer` stays after this block.)

- [ ] **Step 4: Extend `navigationDestination` and sheets**

Add the new destination cases to the existing `switch`:

```swift
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
```

Add the editor sheet after the existing `.sheet(item: $fileForPlaylist)`:

```swift
            .sheet(item: $editingPlaylist) { playlist in
                PlaylistEditorView(
                    playlist: playlist,
                    isNew: !playlists.contains(where: { $0.id == playlist.id }),
                    onSave: { saved in upsertPlaylist(saved) }
                )
            }
```

Remove the now-dead `.onChange(of: sortOption)` modifier.

- [ ] **Step 5: Update helpers**

Remove the `sortedAudioFiles` computed property. Add/replace:

```swift
    private var artists: [LibraryArtist] { cachedArtists }
    private var analyzedFiles: [AudioFile] { cachedAnalyzedFiles }
    private var allFilesShelf: [AudioFile] { cachedAllFiles }

    private func recomputeDerivedCollections() {
        cachedRecentFiles = LibraryShelfContent.recents(from: audioFiles)
        cachedFavoriteFiles = LibraryShelfContent.favorites(from: audioFiles)
        cachedArtists = LibraryShelfContent.artists(from: audioFiles)
        cachedAnalyzedFiles = LibraryShelfContent.analyzed(from: audioFiles)
        cachedAllFiles = LibraryShelfContent.allFiles(from: audioFiles)
    }

    private func upsertPlaylist(_ playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
        } else {
            playlists.append(playlist)
        }
        PlaylistStore.save(playlists)
    }
```

(The old `recomputeDerivedCollections` sorting switch is gone — it lives in `LibraryShelfContent.sortedFiles` now.)

- [ ] **Step 6: Build**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Run the test suite**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/LibraryShelfContentTests 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add Ilumionate/LibraryShelves.swift Ilumionate/LibraryView.swift Ilumionate/LibraryAllFilesView.swift
git commit -m "feat(library): full shelf-first Library with artists/analyzed/all-files shelves and New Playlist card"
```

---

### Task 5: Simulator verification

**Files:** none

- [ ] **Step 1: Install and launch on the booted iPhone 17 simulator; open the Library tab**

- [ ] **Step 2: Checklist**

- Playlists shelf always shows; with no playlists it is a single full-width dashed "New Playlist" card.
- Tapping New Playlist opens the playlist editor sheet; saving a named playlist makes it appear on the shelf immediately.
- All Files shelf shows audio cards (device-dependent); "See all" pushes the "Audio Files" screen with sort menu, swipe actions, and detail navigation.
- Artists shelf hidden with no creators (sim default); Analyzed shelf hidden with no analyzed files.
- Built-in Sessions shelf unchanged; Recently Played/Favorites unchanged.
- Empty library (no audio) shows the "No sessions yet" card under the header.
- No inline vertical list on the Library root anymore.

- [ ] **Step 3: Fix + commit any issues found**

```bash
git add -A Ilumionate
git commit -m "fix(library): full-shelf polish from simulator verification"
```

---

## Self-Review Notes

- Spec coverage: shelves table (T2+T4), New Playlist card incl. always-visible shelf + upsert (T2-3, T4-3/4/5), LibraryAllFilesView + list move (T3), derivations + LibraryArtist + LibrarySortOption move (T1), destinations (T4-1/4), empty card (T2-4, T4-3), tests (T1), sim pass (T5). No gaps.
- Type consistency: `LibraryShelfContent.artists/analyzed/allFiles/sortedFiles`, `LibraryArtist(name:fileCount:)`, `LibraryPlaylistShelf(playlists:onPlay:onCreate:onOpenLibrary:)`, `LibraryAudioShelf(files:showsHeart:showsAnalyzedSeal:onPlay:)`, `LibraryAllFilesView(audioFiles:engine:)` match across tasks.
- Known cross-task dependency: Task 2's build intentionally red until Task 4 rewires the playlist shelf call site; commits are sequenced accordingly (T1 commit, then T2–T4 commit together after green).
