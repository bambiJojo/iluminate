# Library Shelf Redesign — Design

**Date:** 2026-07-12
**Branch:** red-team-reader
**Status:** Approved by user

## Goal

Apply the reader tab's shelf-first carousel style (from the `feat(reader): shelf-first
library redesign with carousel shelves` work, commit 4325c1e) to the main Library tab
(`Ilumionate/LibraryView.swift`), so both tabs share the same Apple Music-style visual
language: a vertical scroll of horizontal card shelves.

## Decisions (user-confirmed)

1. **Shelves + full list below.** Curated groups become carousel shelves; the complete
   Audio Files list stays as a vertical list at the bottom with its sort menu.
2. **Category rows become content shelves.** Playlists, Favorites, and Built-in Sessions
   each become a carousel of actual item cards with "See all" links. The Analysis Queue
   stays a compact status surface, not a shelf.
3. **Reader-style header.** Custom in-scroll bold "Library" title with a circular `+`
   button, replacing `navigationTitle("Library")` and the toolbar `+`.

## Approach

Reuse the shelf *mechanics* — `CarouselRow` (view-aligned paging, 86%-width cards with
next-card peek, scale/fade scroll transition, full-width single card) plus `LiminalCard`
and the section-header pattern — but build Library-specific card views. The reader's
private card components (`MetricPill`, `TagChip`, `HistoryCard`, …) are not extracted;
they stay private to the reader.

## Layout (top → bottom, one vertical `ScrollView` over `AuroraBackground`)

1. **Header** — bold "Library" (28pt, matching the reader's `LibraryHeader`) + circular
   `+` button on the right. `+` opens the existing Add Sessions sheet (`AudioLibraryView`),
   exactly what the toolbar button does today. The navigation bar is hidden on this root
   screen only (`.toolbar(.hidden, for: .navigationBar)` scoped to the root); pushed
   screens (Favorites, Built-in Sessions) keep their native titles.
2. **Analysis Queue status card** — rendered only when the queue count > 0. Compact
   glass row: waveform icon, "Analysis Queue", count. Tap opens the existing queue sheet
   (`AnalyzerView`).
3. **"Recently Played" shelf** — `CarouselRow` of cards: `SessionGlowDot` (40pt tile) +
   title + duration + gradient "Play" pill (mirrors the reader's Continue Reading /
   `HistoryCard`). Tap plays with lights (`UnifiedPlayerView(mode: .audioLight)`).
   Hidden when there are no recents.
4. **"Favorites" shelf** — same card grammar with the heart accent color
   (`Color(hex: "E85D75")`). "See all" pushes the existing
   `LibraryDestination.favorites`. Hidden when no favorites.
5. **"Playlists" shelf** — cards: rose-gold icon tile, playlist name, item count +
   total duration captions. Tap plays the playlist
   (`UnifiedPlayerView(mode: .playlist(playlist:))`). "See all" opens the existing
   playlists sheet (`PlaylistLibraryView`). Context menu: Play, Open Playlists.
   Hidden when no playlists exist.
6. **"Built-in Sessions" shelf** — cards from `LightScoreReader` bundled sessions:
   sparkles icon tile, session display name, duration. Tap plays
   (`UnifiedPlayerView(mode: .session(session:audioFile: nil))`). "See all" pushes
   `LibraryDestination.builtInSessions`.
7. **"Audio Files" list** — unchanged vertical `LibrarySessionsList` (sort menu, swipe
   actions, context menu, empty-state hint).
8. **Tab-bar clearance spacer** (existing `TranceSpacing.tabBarClearance` pattern).

Shelves cap at 10 items each; full sets live behind "See all" / the bottom list.

## Files

- **`Ilumionate/LibraryShelves.swift` (new)** — `LibraryHubHeader`, shelf section views
  (recents, favorites, playlists, built-in sessions), their card views, the section
  header with optional "See all", and the analysis-queue status card. Components private
  where possible.
- **`Ilumionate/LibraryView.swift` (restructured)** — body composes header + shelves +
  list. `LibraryCategoryRows`, `LibraryCategoryRow(Label)`, `RecentsStrip`, and
  `SessionMiniCard` are removed. Adds `@State` for `playlists: [Playlist]`
  (from `PlaylistStore.load()`) and `builtInSessions: [LightSession]`
  (from `LightScoreReader`), loaded in `onAppear` alongside audio files. The cached
  favorites *count* becomes a cached favorites *array*.
- **`Ilumionate/TextTrance/CarouselRow.swift`** — stays in place (same target); only
  the header comment changes from "for the Reader tab" to a shared-shelf description.
  Not moved, to avoid pbxproj churn with the synchronized-groups setup.
- **`IlumionateTests/LibraryShelfContentTests.swift` (new)** — see Testing.

## Data & derivation

Shelf-content derivation moves into a small pure helper so it is unit-testable:

```swift
struct LibraryShelfContent {
    static let shelfCap = 10
    static func recents(from files: [AudioFile]) -> [AudioFile]     // lastPlayed desc, cap
    static func favorites(from files: [AudioFile]) -> [AudioFile]   // favorite only, cap
    static func shelfPlaylists(from playlists: [Playlist]) -> [Playlist] // cap
}
```

`LibraryView.recomputeDerivedCollections()` delegates to these. Sorting of the bottom
Audio Files list is unchanged.

## Error & empty handling

- Empty shelves render nothing (reader pattern) — no placeholder cards.
- Playlist / built-in-session load failures degrade to hidden shelves; no alerts.
- Audio-file loading keeps the existing repairing loader
  (`AudioLibraryStore.loadRepairingStoredFiles()`).
- Empty audio list keeps the existing "Tap + to add your first session" hint.

## Testing & verification

1. Unit tests for `LibraryShelfContent` (recents ordering, favorites filter, caps,
   empty inputs) in `IlumionateTests/LibraryShelfContentTests.swift`.
2. Build via `xcodebuild`; run existing test suite (note: some analyzer test failures
   pre-exist on this branch).
3. Simulator run to visually verify: shelf paging + peek, single-item full-width card,
   See all navigation, tap-to-play for each shelf type, hidden nav bar on root but
   visible titles on pushed screens, tab-bar clearance.

## Out of scope

- No changes to the reader tab beyond the `CarouselRow` comment.
- No changes to `AudioLibraryView`, `PlaylistLibraryView`, `SessionLibraryView`,
  favorites view internals, or playback.
- No extraction of the reader's private card components.
