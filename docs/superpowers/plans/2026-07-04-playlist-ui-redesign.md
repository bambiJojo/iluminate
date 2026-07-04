# Playlist UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the three playlist surfaces (Playlists tab, editor, streaming featured cards) on the void/aurora design system, fixing overlapping card content and black artwork tiles.

**Architecture:** Extract a shared, testable `PlaylistArtwork` mosaic + a pure `distinctTypes` helper; reuse the existing `ContentTypeStyle`/`SessionGlowDot` components. Rebuild the Playlists tab as a bento hero + 2-up grid, re-theme the editor and streaming cards to design tokens, and replace the streaming `AsyncImage` with an explicit phase-based tile that never renders black.

**Tech Stack:** SwiftUI (iOS 26), Swift 6.2, Swift Testing. Design tokens in `TranceDesignSystem.swift`; content-type styling in `Ilumionate/DesignSystem/ContentTypeStyle.swift`.

**Reference spec:** `docs/superpowers/specs/2026-07-04-playlist-ui-redesign-design.md`

---

## Key facts (verified in codebase)

- `AnalysisResult.ContentType` is `typealias ContentType = AudioContentType` (`Ilumionate/AudioFile.swift:152`). The existing `ContentTypeStyle.color(for: AudioContentType?)` / `.icon(for:)` and `SessionGlowDot` are directly reusable.
- `Playlist` (`Playlist.swift`): `id: UUID`, `name`, `items: [PlaylistItem]`, `smartTransitions`, `totalDurationFormatted`, `itemCount`, `isEmpty`. `PlaylistItem` has `audioFileId: UUID`, `displayName`, `durationFormatted`, `duration`.
- Audio files persist in `UserDefaults` under key `"audioFiles"` as `[AudioFile]` (see `PlaylistEditorView.loadAvailableFiles`).
- `StreamingPlaylist` (`Ilumionate/StreamingService.swift:45`): `id: String`, `name`, `trackCount: Int`, `artworkURL: URL?`, `service: StreamingServiceType`. `StreamingServiceType.color`/`.displayName`/`.icon` exist.
- Design tokens: `Color.bgPrimary`, `.bgCard`, `.glassBorder`, `.textPrimary/.textSecondary/.textLight`, `.roseGold`(teal), `.roseDeep`(blue), `.blush`, `.lavender`; `TranceSpacing.*`, `TranceRadius.*`. Reusable `GlassCard`.

## File structure

- **Create** `PlaylistArtwork.swift` — pure `distinctTypes(from:)` helper + `PlaylistArtwork` mosaic view (0/1/2–4 gradients, no `GeometryReader`/`.position`).
- **Create** `PlaylistHeroCard.swift` — large featured playlist card.
- **Create** `PlaylistGridTile.swift` — compact grid tile.
- **Create** `StreamingArtworkTile.swift` — phase-based streaming artwork (the black-tile fix).
- **Create** `IlumionateTests/PlaylistArtworkTests.swift` — Swift Testing for `distinctTypes`.
- **Modify** `PlaylistLibraryView.swift` — bento hero + grid; load audio files; re-theme stats/empty state.
- **Modify** `PlaylistEditorView.swift` — de-`GeometryReader` artwork via `PlaylistArtwork`; glass rows; reuse `SessionGlowDot`; re-theme `SessionPickerView`.
- **Modify** `Ilumionate/StreamingBrowserView.swift` — `PlaylistRow` uses `StreamingArtworkTile`; re-theme `CategoryCard`/rows to tokens.

All new files must be added to the **Ilumionate** target (synchronized group — verify membership after creating).

---

## Task 1: Shared artwork helper + mosaic view

**Files:**
- Create: `PlaylistArtwork.swift`
- Test: `IlumionateTests/PlaylistArtworkTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/PlaylistArtworkTests.swift`:

```swift
import Testing
@testable import Ilumionate

@Suite("PlaylistArtwork.distinctTypes")
struct PlaylistArtworkTests {

    @Test("Deduplicates preserving first-seen order")
    func deduplicates() {
        let input: [AudioContentType?] = [.hypnosis, .hypnosis, .music, .hypnosis]
        #expect(PlaylistArtwork.distinctTypes(from: input) == [.hypnosis, .music])
    }

    @Test("Drops nil and .unknown")
    func dropsNilAndUnknown() {
        let input: [AudioContentType?] = [nil, .unknown, .meditation, nil]
        #expect(PlaylistArtwork.distinctTypes(from: input) == [.meditation])
    }

    @Test("Caps at 4 types")
    func capsAtFour() {
        let input: [AudioContentType?] = [.hypnosis, .meditation, .music, .guidedImagery, .affirmations]
        #expect(PlaylistArtwork.distinctTypes(from: input) == [.hypnosis, .meditation, .music, .guidedImagery])
    }

    @Test("Empty input yields empty")
    func emptyYieldsEmpty() {
        #expect(PlaylistArtwork.distinctTypes(from: []) == [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/PlaylistArtworkTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PlaylistArtwork' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `PlaylistArtwork.swift`:

```swift
//
//  PlaylistArtwork.swift
//  Ilumionate
//
//  Generated gradient artwork for playlists — a content-type gradient mosaic.
//  Shared by the Playlists tab (hero + grid) and the editor header.
//

import SwiftUI

enum PlaylistArtwork {
    /// Distinct, non-nil, non-`.unknown` content types in first-seen order, capped at 4.
    static func distinctTypes(from types: [AudioContentType?]) -> [AudioContentType] {
        var seen = Set<AudioContentType>()
        var result: [AudioContentType] = []
        for case let type? in types where type != .unknown {
            if seen.insert(type).inserted { result.append(type) }
            if result.count == 4 { break }
        }
        return result
    }
}

/// Gradient mosaic view. 0 types → aurora placeholder; 1 → single gradient; 2–4 → 2×2 grid.
/// Uses a plain `Grid` (no `GeometryReader`/`.position`) so quadrants never overlap.
struct PlaylistArtworkView: View {
    let types: [AudioContentType]
    var cornerRadius: CGFloat = TranceRadius.thumbnail
    var showsIcon: Bool = true

    private func gradient(for type: AudioContentType) -> LinearGradient {
        let c = ContentTypeStyle.color(for: type)
        return LinearGradient(colors: [c, c.opacity(0.6)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var placeholder: LinearGradient {
        LinearGradient(colors: [.roseGold, .roseDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            switch types.count {
            case 0:
                placeholder
                if showsIcon {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.7))
                }
            case 1:
                gradient(for: types[0])
                if showsIcon {
                    Image(systemName: ContentTypeStyle.icon(for: types[0]))
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.75))
                }
            default:
                // Pad to 4 by cycling so the 2×2 grid is always full.
                let padded = (0..<4).map { types[$0 % types.count] }
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow { gradient(for: padded[0]); gradient(for: padded[1]) }
                    GridRow { gradient(for: padded[2]); gradient(for: padded[3]) }
                }
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
    }
}
```

- [ ] **Step 4: Add `PlaylistArtwork.swift` and the test to the Ilumionate targets, then run tests**

Add `PlaylistArtwork.swift` to the app target and `PlaylistArtworkTests.swift` to the test target (synchronized group — confirm both appear).
Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/PlaylistArtworkTests 2>&1 | tail -20`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add PlaylistArtwork.swift IlumionateTests/PlaylistArtworkTests.swift Ilumionate.xcodeproj
git commit -m "feat(playlist): shared content-type gradient artwork + distinctTypes helper"
```

---

## Task 2: Streaming artwork tile — the black-card fix

**Files:**
- Create: `StreamingArtworkTile.swift`
- Modify: `Ilumionate/StreamingBrowserView.swift` (`PlaylistRow` body ~lines 564–607; `CategoryCard` ~472–500)

- [ ] **Step 1: Create the phase-based tile**

Create `StreamingArtworkTile.swift`:

```swift
//
//  StreamingArtworkTile.swift
//  Ilumionate
//
//  Remote artwork tile for streaming rows. Renders an aurora gradient fallback
//  while loading, on a nil URL, and on failure — so a tile never renders black.
//

import SwiftUI

struct StreamingArtworkTile: View {
    let url: URL?
    let tint: Color
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 12

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [tint, .roseDeep],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note.list")
                .font(.system(size: size * 0.34, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
    }
}
```

- [ ] **Step 2: Use the tile in `PlaylistRow`**

In `Ilumionate/StreamingBrowserView.swift`, replace the `AsyncImage(url: playlist.artworkURL) { … } placeholder: { … } .frame(width: 60, height: 60).clipShape(…)` block inside `PlaylistRow.body` with:

```swift
StreamingArtworkTile(url: playlist.artworkURL,
                     tint: playlist.service.color,
                     size: 56)
```

Wrap the row content in a glass background: after the outer `HStack { … }.padding(.vertical, TranceSpacing.inner)`, add:

```swift
.padding(.horizontal, TranceSpacing.card)
.background(Color.bgCard)
.clipShape(.rect(cornerRadius: TranceRadius.glassCard))
.overlay(.rect(cornerRadius: TranceRadius.glassCard).stroke(Color.glassBorder, lineWidth: 1))
```

(Keep `Text(playlist.name)` `.foregroundStyle(.textPrimary)`, meta `.textSecondary`, service tag `.foregroundStyle(playlist.service.color)`.)

- [ ] **Step 3: Re-theme `CategoryCard`**

In `CategoryCard.body`, the tile already uses `category.color.opacity(...)` and `.textPrimary/.textSecondary` — confirm no hardcoded `Color.white`/`.primary`. No change needed if already token-based; otherwise swap to tokens.

- [ ] **Step 4: Build**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -15`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add StreamingArtworkTile.swift Ilumionate/StreamingBrowserView.swift Ilumionate.xcodeproj
git commit -m "fix(streaming): phase-based artwork tile so cards never render black"
```

---

## Task 3: Playlists tab — bento hero + grid

**Files:**
- Create: `PlaylistHeroCard.swift`, `PlaylistGridTile.swift`
- Modify: `PlaylistLibraryView.swift` (`enhancedPlaylistsView` ~245–281, `playlistStatsHeader` ~285–335, `EnhancedPlaylistCard` ~439–512)

- [ ] **Step 1: Create `PlaylistGridTile.swift`**

```swift
//
//  PlaylistGridTile.swift
//  Ilumionate
//

import SwiftUI

struct PlaylistGridTile: View {
    let playlist: Playlist
    let types: [AudioContentType]
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                PlaylistArtworkView(types: types, cornerRadius: TranceRadius.thumbnail)
                    .aspectRatio(1, contentMode: .fit)
                Text(playlist.name)
                    .font(TranceTypography.body)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Text("\(playlist.itemCount) tracks · \(playlist.totalDurationFormatted)")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
            .padding(TranceSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgCard)
            .clipShape(.rect(cornerRadius: TranceRadius.glassCard))
            .overlay(.rect(cornerRadius: TranceRadius.glassCard).stroke(Color.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Create `PlaylistHeroCard.swift`**

```swift
//
//  PlaylistHeroCard.swift
//  Ilumionate
//

import SwiftUI

struct PlaylistHeroCard: View {
    let playlist: Playlist
    let types: [AudioContentType]
    var onPlay: () -> Void
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomLeading) {
                PlaylistArtworkView(types: types, cornerRadius: TranceRadius.glassCard, showsIcon: false)
                    .frame(height: 180)
                    .overlay(
                        LinearGradient(colors: [.black.opacity(0.75), .clear],
                                       startPoint: .bottom, endPoint: .center)
                    )
                    .clipShape(.rect(cornerRadius: TranceRadius.glassCard))

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MOST PLAYED")
                            .font(TranceTypography.cardLabel)
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(playlist.name)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(playlist.itemCount) tracks · \(playlist.totalDurationFormatted)")
                            .font(TranceTypography.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.bgPrimary)
                            .frame(width: 46, height: 46)
                            .background(
                                LinearGradient(colors: [.roseGold, .roseDeep],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: .circle
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(TranceSpacing.card)
            }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Rewrite `enhancedPlaylistsView` and wire audio-file loading**

In `PlaylistLibraryView`, add state and a loader, and derive per-playlist types. Add near the other `@State`:

```swift
@State private var audioFiles: [AudioFile] = []
```

Add these helpers to `PlaylistLibraryView`:

```swift
private func loadAudioFiles() {
    guard let data = UserDefaults.standard.data(forKey: "audioFiles"),
          let files = try? JSONDecoder().decode([AudioFile].self, from: data) else { return }
    audioFiles = files
}

private func types(for playlist: Playlist) -> [AudioContentType] {
    let mapped = playlist.items.map { item -> AudioContentType? in
        audioFiles.first { $0.id == item.audioFileId }?.analysisResult?.contentType
    }
    return PlaylistArtwork.distinctTypes(from: mapped)
}
```

In `.onAppear` (currently just `playlists = PlaylistStore.load()`) add `loadAudioFiles()`.

Replace `enhancedPlaylistsView` body with the hero + grid:

```swift
private var enhancedPlaylistsView: some View {
    ScrollView {
        LazyVStack(spacing: TranceSpacing.card) {
            playlistStatsHeader
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.list)

            if let hero = playlists.first(where: { !$0.isEmpty }) ?? playlists.first {
                PlaylistHeroCard(
                    playlist: hero,
                    types: types(for: hero),
                    onPlay: { TranceHaptics.shared.medium(); playPlaylist(hero) },
                    onOpen: { TranceHaptics.shared.light(); editPlaylist(hero) }
                )
                .padding(.horizontal, TranceSpacing.screen)

                let rest = playlists.filter { $0.id != hero.id }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: TranceSpacing.card),
                                    GridItem(.flexible(), spacing: TranceSpacing.card)],
                          spacing: TranceSpacing.card) {
                    ForEach(rest) { playlist in
                        PlaylistGridTile(playlist: playlist, types: types(for: playlist)) {
                            TranceHaptics.shared.light(); editPlaylist(playlist)
                        }
                        .contextMenu {
                            if !playlist.isEmpty {
                                Button("Play", systemImage: "play.fill") { playPlaylist(playlist) }
                            }
                            Button("Edit", systemImage: "pencil") { editPlaylist(playlist) }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                if let i = playlists.firstIndex(where: { $0.id == playlist.id }) {
                                    deletePlaylists(at: IndexSet(integer: i))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
            }

            Spacer(minLength: TranceSpacing.tabBarClearance)
        }
        .padding(.vertical, TranceSpacing.list)
    }
    .scrollContentBackground(.hidden)
}
```

- [ ] **Step 4: Re-theme `playlistStatsHeader`**

In `playlistStatsHeader`, replace the background `RoundedRectangle(...).fill(Color.white.opacity(0.8))...` with:

```swift
.background(Color.bgCard)
.clipShape(.rect(cornerRadius: TranceRadius.thumbnail))
.overlay(.rect(cornerRadius: TranceRadius.thumbnail).stroke(Color.glassBorder, lineWidth: 1))
```

Ensure text uses `.textPrimary`/`.textSecondary`/`.textLight` (replace any `.foregroundStyle(.primary)`/`.tertiary`). Keep the aurora accent on the total-time value (`.foregroundStyle(.roseGold)`).

- [ ] **Step 5: Delete the obsolete `EnhancedPlaylistCard`**

Remove the `EnhancedPlaylistCard` struct (~439–512) — it is replaced by hero + grid. Confirm no other file references it: `grep -rn "EnhancedPlaylistCard" --include=*.swift .` returns nothing.

- [ ] **Step 6: Build**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -15`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add PlaylistHeroCard.swift PlaylistGridTile.swift PlaylistLibraryView.swift Ilumionate.xcodeproj
git commit -m "feat(playlist): bento hero + grid Playlists tab on void/aurora"
```

---

## Task 4: Editor — de-GeometryReader artwork + glass rows

**Files:**
- Modify: `PlaylistEditorView.swift` (`artworkView` ~144–180, `TrackRow` ~384–463)

- [ ] **Step 1: Replace `artworkView` with the shared mosaic**

In `PlaylistEditorView`, replace the entire `artworkView` computed property (the `GeometryReader { … .position(…) … }` block) with:

```swift
private var artworkView: some View {
    PlaylistArtworkView(types: PlaylistArtwork.distinctTypes(from: dominantContentTypeOptionals),
                        cornerRadius: TranceRadius.pattern)
}
```

Replace `dominantContentTypes` with an optionals accessor feeding the shared helper:

```swift
private var dominantContentTypeOptionals: [AudioContentType?] {
    playlist.items.map { item in
        availableAudioFiles.first { $0.id == item.audioFileId }?.analysisResult?.contentType
    }
}
```

Update `artworkTopColor` to use the helper:

```swift
private var artworkTopColor: Color {
    guard let first = PlaylistArtwork.distinctTypes(from: dominantContentTypeOptionals).first
    else { return .roseGold }
    return ContentTypeStyle.color(for: first)
}
```

Delete the now-unused `contentTypeColor(for:)`, `contentTypeGradient(for:)`, and `contentTypeIcon(for:)` methods in `PlaylistEditorView` (the mosaic view and `ContentTypeStyle` cover these). Keep `.frame(width: 200, height: 200)` and `.shadow(...)` on `artworkView` where it is used in `artworkHeader`.

- [ ] **Step 2: Reuse `SessionGlowDot` in `TrackRow`**

In `TrackRow.body`, replace the `ZStack { RoundedRectangle... ; Image(systemName: contentTypeIcon)... }` badge with:

```swift
SessionGlowDot(contentType: contentType, size: 44)
```

Delete `TrackRow`'s private `contentTypeColor` and `contentTypeIcon` (now covered by `ContentTypeStyle`/`SessionGlowDot`). Keep `contentType` (it feeds `SessionGlowDot`). Ensure title/meta use `.textPrimary`/`.textLight`/`.roseGold` (already do).

- [ ] **Step 3: Confirm editor list surfaces use tokens**

The list already uses `.listRowBackground(Color.bgCard)` and `.background(Color.bgPrimary...)`. No hardcoded `Color.white`/`.primary` should remain: `grep -n "Color.white\|\.primary\b\|foregroundColor(\.primary)" PlaylistEditorView.swift` → none (swap any stragglers to tokens).

- [ ] **Step 4: Build**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -15`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add PlaylistEditorView.swift
git commit -m "refactor(playlist): editor artwork via shared mosaic + SessionGlowDot rows"
```

---

## Task 5: SessionPickerView + AddToPlaylistSheet token pass

**Files:**
- Modify: `PlaylistEditorView.swift` (`SessionPickerView`, `PickerSessionRow`, `FilterChip`)
- Modify: `PlaylistLibraryView.swift` (`AddToPlaylistSheet` ~340–435)

- [ ] **Step 1: Reuse `SessionGlowDot` in `PickerSessionRow`**

Replace the `ZStack { RoundedRectangle...; Image(systemName: contentTypeIcon)... }` badge in `PickerSessionRow.body` with `SessionGlowDot(contentType: file.analysisResult?.contentType, size: 44)`. Delete `PickerSessionRow`'s private `contentTypeColor`/`contentTypeIcon`.

- [ ] **Step 2: Token pass on `AddToPlaylistSheet`**

In `AddToPlaylistSheet`, the thumbnail uses `Color.roseGold.opacity(0.15)` and text uses `.primary`/`.secondary`. Swap `.foregroundStyle(.primary)` → `.textPrimary`, `.secondary` → `.textSecondary`. The `Color.roseGold` accents already resolve to aurora teal — keep them.

- [ ] **Step 3: Build**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -15`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add PlaylistEditorView.swift PlaylistLibraryView.swift
git commit -m "style(playlist): token pass on session picker + add-to-playlist sheet"
```

---

## Task 6: Full test + simulator verification

**Files:** none (verification only)

- [ ] **Step 1: Run the focused test suite**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/PlaylistArtworkTests 2>&1 | tail -20`
Expected: PASS (4 tests). (Note: some pre-existing analyzer tests fail independently of this work — do not treat those as regressions.)

- [ ] **Step 2: Launch in the simulator and verify the three screens**

Build & run the app on `iPhone 17`. Verify:
- **Playlists tab:** hero card renders with a gradient wash + readable white text; grid tiles below show mosaics; no text/tag overlap. Create/edit/play still work.
- **Editor:** 200×200 mosaic artwork (no clipped/overlapping quadrants); glass Smart Transitions row + toggle; glow-dot track rows; drag-reorder and swipe-delete work; Add Sessions opens the picker.
- **Streaming → Featured Playlists:** artwork tiles show the aurora gradient while loading and on failure — **never black**. Force a failure by temporarily setting an invalid `artworkURL` in a debug build if needed, then revert.

- [ ] **Step 3: Verify Dynamic Type + narrow width**

In the simulator, raise Dynamic Type (Settings → Accessibility → larger text) and confirm meta rows wrap/truncate rather than overlap on the hero, grid tiles, and track rows.

- [ ] **Step 4: Final commit (if any verification fixes were needed)**

```bash
git add -A
git commit -m "test(playlist): verify redesign on device + fix verification findings"
```

---

## Self-review notes

- **Spec coverage:** Bento hero (Task 3), editor re-theme + de-GeometryReader (Task 4), streaming phase-based artwork/black-tile fix (Task 2), shared `ContentTypeStyle`/mosaic reuse (Tasks 1/4/5), non-goals respected (no model/persistence/playback/networking changes), verification plan (Task 6). ✅
- **Overlap bug:** eliminated structurally — the editor's `GeometryReader`+`.position` mosaic is replaced by a `Grid`; card meta uses single-line truncation instead of overflowing `HStack`s of `Label`s.
- **Black-tile bug:** fixed by `StreamingArtworkTile`'s explicit `.empty`/`.failure`/nil-URL fallbacks.
- **Type consistency:** `distinctTypes(from: [AudioContentType?]) -> [AudioContentType]` used identically in Tasks 1, 3, 4; `PlaylistArtworkView(types:cornerRadius:showsIcon:)` signature consistent across call sites; `ContentTypeStyle`/`SessionGlowDot` reused, not redefined.
- **Target membership:** every new `.swift` file has an explicit "add to target" step (synchronized group).
```
