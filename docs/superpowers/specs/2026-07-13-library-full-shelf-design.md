# Library Full Shelf-First — Design

**Date:** 2026-07-13
**Branch:** red-team-reader
**Status:** Approved by user
**Builds on:** `2026-07-12-library-shelf-redesign-design.md` (shipped: commits 8e6d484 / 1cd74ca / 4d27a49)

## Goal

Complete the Library tab's shelf-first conversion: add Artists, Analyzed, and All
Files carousels, and move the inline vertical Audio Files list to its own pushed
screen. The Library root becomes pure shelves top to bottom, like the reader tab.

## Decisions (user-confirmed)

1. **Fully shelf-first.** The vertical Audio Files list leaves the Library root.
   "All Files" is a carousel; its "See all" pushes the full sortable list as its
   own screen.
2. **Shelf set and order:** Recently Played, Favorites, Playlists, Artists,
   Analyzed, All Files, Built-in Sessions. Empty shelves stay hidden.

## Shelves

| # | Shelf | Card | Tap | See all |
|---|-------|------|-----|---------|
| 1 | Recently Played | existing audio card | play with lights | — |
| 2 | Favorites | existing audio card + heart | play with lights | push Favorites (existing) |
| 3 | Playlists | existing playlist card | play playlist | playlists sheet (existing) |
| 4 | **Artists** (new) | `music.mic` icon tile, artist name, "N sessions" | push `CreatorDetailView(creatorName:audioFiles:engine:)` for that artist | push `LibraryCreatorsView` |
| 5 | **Analyzed** (new) | audio card with `checkmark.seal` accent | play with lights | — (full set lives in All Files) |
| 6 | **All Files** (new) | existing audio card | play with lights | push new `LibraryAllFilesView` |
| 7 | Built-in Sessions | existing session card | play session | push Session Library (existing) |

- Artists shelf excludes files with empty/unknown creator (`creatorDisplayName`
  nil or empty); those files remain reachable via All Files. Artist cards sort by
  name (localized standard compare).
- Analyzed and All Files order newest first (`createdDate` descending).
- All shelves cap at `LibraryShelfContent.shelfCap` (10).

## New screen: `LibraryAllFilesView`

Pushed via `LibraryDestination.allFiles`. Hosts the existing `LibrarySessionsList`
(sort menu, swipe actions, context menus, `SessionDetailView` navigation links)
over `AuroraBackground`, with native `navigationTitle("Audio Files")`. The view
owns its `@State sortOption` and derives its sorted files via
`LibraryShelfContent.sortedFiles(from:by:)`. `LibrarySessionsList` moves out of
`LibraryView.swift` into this new file; `LibraryView` drops `sortOption` and
`cachedSortedFiles`.

## Empty library

When `audioFiles` is empty, a single glass card under the header reads
"Tap + to add your first session" (`plus` icon, teal accent) — replaces the old
inline hint that lived in `LibrarySessionsList`. `LibrarySessionsList` keeps its
own empty hint for edge cases on the pushed screen.

## Data & derivation (`LibraryShelfContent`, unit-tested)

```swift
struct LibraryArtist: Identifiable, Equatable {
    let name: String          // id == name
    let fileCount: Int
    var id: String { name }
}

static func artists(from files: [AudioFile]) -> [LibraryArtist]
    // group by creatorDisplayName, exclude nil/empty, sort by name
    // (localizedStandardCompare), cap at shelfCap
static func analyzed(from files: [AudioFile]) -> [AudioFile]
    // isAnalyzed only, createdDate desc, cap
static func allFiles(from files: [AudioFile]) -> [AudioFile]
    // createdDate desc, cap
static func sortedFiles(from files: [AudioFile], by option: LibrarySortOption) -> [AudioFile]
    // existing LibraryView sort-switch moves here (newest / name /
    // lastPlayed / favorites-first), uncapped
```

`LibraryView.recomputeDerivedCollections()` caches artists/analyzed/allFiles
alongside recents/favorites.

## Navigation

`LibraryDestination` gains:

```swift
case artists                 // → LibraryCreatorsView(audioFiles:engine:)
case artist(String)          // → CreatorDetailView(creatorName:audioFiles:engine:)
                             //   (audioFiles filtered to that creator)
case allFiles                // → LibraryAllFilesView(audioFiles:engine:)
```

All pushed via the existing `NavigationPath`; pushed screens keep native nav bars.

## Files

- `Ilumionate/LibraryShelfContent.swift` — add `LibraryArtist`, four new statics.
- `Ilumionate/LibraryShelves.swift` — add `LibraryArtistShelf` + `ArtistShelfCard`;
  extend the audio card with an optional analyzed accent; add `LibraryEmptyCard`.
- `Ilumionate/LibraryView.swift` — new shelf composition + destinations; remove
  inline list, `sortOption`, `cachedSortedFiles`.
- `Ilumionate/LibraryAllFilesView.swift` (new) — pushed full-list screen;
  `LibrarySessionsList` moves here.
- `IlumionateTests/LibraryShelfContentTests.swift` — tests for the four new
  derivations.

## Error & empty handling

- Empty shelves render nothing (unchanged pattern).
- Artists shelf renders nothing when every file lacks a creator.
- Empty library shows the `LibraryEmptyCard` under the header.

## Testing & verification

1. Unit tests: artists grouping/exclusion/order/cap, analyzed filter+order,
   allFiles order+cap, sortedFiles all four sort options.
2. Build + run `LibraryShelfContentTests`.
3. Simulator: new shelves render (Built-in device has no audio, so verify empty
   card + Built-in shelf; data shelves need device check), All Files "See all"
   pushes the sortable list, artist tap pushes detail.

## Out of scope

- No changes to `CreatorDetailView`, `LibraryCreatorsView` internals,
  `LibraryFoldersView` (Folders shelf not requested), playback, or reader tab.
