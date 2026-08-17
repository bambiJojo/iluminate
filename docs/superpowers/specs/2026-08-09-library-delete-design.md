# Easier Deletion in the Audio Library — Design

**Date:** 2026-08-09
**Status:** Approved, ready for planning
**Surface:** `AudioLibraryView` (the Audio tab / library screen)

## Problem

Deleting one audio file from the library is simultaneously hard to find and unsafe once found.

There are two paths today:

1. **Long-press the row** → context menu with six items → *Delete* at the very bottom
   ([`AudioFileRow.swift:232`](../../../Ilumionate/AudioFileRow.swift)). It fires **immediately, with no
   confirmation and no undo**.
2. **Selection mode** → toolbar "Select" → tap the row's 52pt thumbnail → tap the trash in the bottom
   bar → confirm alert ([`AudioLibraryView.swift:238`](../../../Ilumionate/AudioLibraryView.swift)).

Bulk deletion is worse than it looks. In selection mode every row is still wrapped in a
`NavigationLink` ([`AudioLibraryView+Filtering.swift:20`](../../../Ilumionate/AudioLibraryView+Filtering.swift)),
so tapping anywhere except the thumbnail **navigates to the detail screen** instead of toggling
selection. There is no Select All, so clearing twenty files means twenty precise thumbnail taps.

## Two constraints from the existing code

These are not incidental — they determine the shape of the solution.

### The library re-discovers orphaned files

`AudioLibraryStore.loadRepairingStoredFiles` calls `discoverUnregisteredDocumentFiles`
([`AudioLibraryStore.swift:121`](../../../Ilumionate/AudioLibraryStore.swift)), which scans
`Documents` and auto-registers any supported audio file that isn't already in the library.

So an undo window **cannot** work by dropping the row and leaving the file on disk: a library reload
during those seconds resurrects it. Reloads are not rare — they fire from `.task` on appear and from
`onChange(of: analysisManager.completedAnalyses.count)`.

The deleted file must move somewhere the scan cannot see it. The scan is non-recursive
(`contentsOfDirectory`, not an enumerator) and filters on `.isRegularFile`, so any subdirectory is
already invisible to it — but staging outside `Documents` entirely is the durable choice, since it
survives a future change to the scan.

### The generated light session must outlive the undo window

`deleteFile` currently calls `GeneratedSessionStore.shared.delete(for:)` at delete time
([`AudioLibraryView+Actions.swift:80`](../../../Ilumionate/AudioLibraryView+Actions.swift)). If that
stays where it is, Undo restores the audio but silently loses the light session generated for it.
The call has to move to commit time.

## Approach

Three options were weighed:

| Approach | Verdict |
|---|---|
| **A. Custom swipe on the existing `LazyVStack`** | **Chosen.** Keeps `GlassCard`, dividers, and all Trance styling untouched. Costs a hand-rolled gesture. |
| **B. Convert the list to a real `List`** | Rejected. Native `.swipeActions` and `.onDelete`, matching `LibraryFoldersView` — but it discards the `GlassCard` container and its results header, and rebuilding that look via `listRowBackground`/`listRowSeparator` is a visual refactor of the app's most bespoke screen. |
| **C. Always-visible trash button per row** | Rejected. Cheapest, but a permanent destructive control invites mistaps and clutters a row already carrying a waveform, title, creator, duration, badge, and chevron. Not the iOS idiom. |

The library screen's appearance is the most custom thing in the app. B trades a lot of design
surface for a gesture obtainable without touching it.

## Behavior

### Single-row delete

Swipe left on a row to reveal a red trash action. Tapping it animates the row out. *Delete* also
moves to the **top** of the context menu — still available for discoverability and for pointer-based
platforms, no longer buried under six other items.

### Bulk delete

- In selection mode, the row is **not** wrapped in a `NavigationLink`; tapping anywhere toggles
  selection.
- **Select All / Deselect All** in the toolbar, operating on `filteredAudioFiles` (the visible set),
  not the whole library — deleting things you cannot see would be a trap.
- The selection bar's trash deletes the whole set with no confirmation alert.

### Undo

A banner slides up above the tab bar: *"Deleted 'Name' — Undo"*, or *"3 files deleted — Undo"* for a
batch. It auto-dismisses after **6 seconds**. Undo restores every file in the batch to its original
index in `audioFiles`.

No confirmation alert on either path. The undo banner replaces the existing bulk-delete alert
entirely.

### When the delete becomes permanent

The staged delete commits on the **first** of:

- the 6-second timer firing,
- the banner being dismissed by the user,
- the library view disappearing,
- another delete starting (the previous batch commits immediately; only one batch is ever pending).

Committing on view disappear is deliberate: navigating away from the library finalizes the delete
rather than leaving it recoverable indefinitely.

## Architecture

Three new pieces, each with one job and testable on its own.

### `PendingAudioDeletion`

A `@MainActor @Observable` model owning the staging directory. **No SwiftUI** — pure file and state
logic, so it unit-tests directly.

```
Application Support/PendingAudioDeletion/<audioFile.id>/<originalLastPathComponent>
```

Staging per file ID avoids collisions when two files share a last path component.

It exchanges a single value type rather than parallel arrays:

```swift
struct StagedAudioFile: Sendable {
    let file: AudioFile
    let originalURL: URL   // recorded, never recomputed — see below
    let originalIndex: Int
}
```

| Method | Behavior |
|---|---|
| `stage(_ entries: [StagedAudioFile])` | Commits any existing batch, then moves each file to staging. Returns the entries it actually staged. |
| `restore() -> [StagedAudioFile]` | Moves every staged file back to its `originalURL` and returns the entries that came back, for re-insertion at `originalIndex`. |
| `commit()` | Deletes the staged copies and calls `GeneratedSessionStore.delete(for:)` for each. |
| `sweepOrphans()` | Deletes anything left in the staging directory. Called once at app launch. |

Recording the original URL rather than recomputing it matters: `AudioFile.url` derives from
`filename`, and files imported by training or migration flows carry an absolute path
(`filename.hasPrefix("/")`) that points outside `Documents`
([`AudioFile.swift:58`](../../../Ilumionate/AudioFile.swift)). The `AudioFile` value itself is never
mutated — `filename` is untouched, so a restored file is byte-identical to what was deleted.

`sweepOrphans()` runs from `IlumionateApp` at launch. Without it, a batch pending when the app is
killed leaves files staged forever.

### `UndoDeleteBanner`

Presentation only: a message, an Undo button, a dismiss action. Styled after
[`PlayerInterruptionBanner`](../../../Ilumionate/PlayerInterruptionBanner.swift) — `.ultraThinMaterial`,
`TranceRadius.thumbnail`, Trance spacing tokens.

### `SwipeToDeleteRow`

A `ViewModifier` holding the drag gesture, so the same swipe can be reused on other custom lists
later.

The gesture engages only when horizontal translation exceeds vertical, so it does not fight the
enclosing `ScrollView`. It must also coexist with the wrapping `NavigationLink`, which will try to
consume the drag — this is the one genuinely fiddly part of the implementation and needs testing on
both a touch device and a trackpad.

### Changes to existing files

- `AudioLibraryView+Actions.swift` — `deleteFile` and `deleteSelectedFiles` become thin calls into
  `PendingAudioDeletion` plus an array removal and save. They no longer touch `FileManager` or
  `GeneratedSessionStore` directly.
- `AudioLibraryView+Filtering.swift` — `audioFilesGrid` conditionally wraps in `NavigationLink`; the
  row gains `.swipeToDelete`.
- `AudioLibraryView.swift` — hosts the banner, drops `showingDeleteSelectedAlert` and its alert, adds
  the Select All toolbar item. The banner sits in the outer `ZStack`, above **both** `emptyState` and
  `audioLibraryContent` — deleting the last file swaps the screen to the empty state, and Undo has to
  remain reachable from there.
- `AudioFileRow.swift` — *Delete* moves to the top of `rowMenu`.

## Data flow

```
swipe / bulk trash
  → PendingAudioDeletion.stage(files, indices)      (files moved out of Documents)
  → audioFiles.removeAll { staged }  +  saveAudioFiles()
  → banner appears, 6s timer starts

Undo    → restore()  → re-insert at original indices → saveAudioFiles() → banner hides
Commit  → commit()   → staged copies + generated sessions deleted → banner hides
```

## Error handling

- **A move to staging fails** (permissions, disk full). That file is skipped and stays in the
  library; the rest of the batch proceeds. Logged via `Log.audio.error`. Silently dropping the row
  while the file survives on disk would resurrect it on the next scan — the worst outcome — so the
  row must stay.
- **A restore move fails.** The file is left staged and *not* re-inserted, and the failure is logged.
  Re-inserting a row whose file is missing would produce a library entry that cannot play.
- **`commit()` fails to remove a staged file.** Logged; `sweepOrphans()` catches it at next launch.
- **App killed mid-window.** Files stay staged and are already out of `audioFiles`, so the library is
  consistent. `sweepOrphans()` reclaims the space at launch. The delete is effectively permanent —
  correct, since the user did ask to delete.

## Testing

Unit tests (Swift Testing, per the suite convention) against `PendingAudioDeletion` with a temporary
staging directory injected:

- stage then restore returns the file to its exact original URL, including an absolute-path file
- stage then commit removes the staged file and the generated session
- staging two files sharing a last path component keeps both recoverable
- restore returns indices that reproduce the original ordering
- `sweepOrphans` empties a populated staging directory
- staging a new batch commits the previous one
- a failed move leaves the file reported as not staged

The gesture and the banner are verified by hand on device and in the simulator — a unit test on a
drag gesture would assert little of value. Manual checks: swipe does not trigger while scrolling
vertically; swipe does not navigate; Undo restores position, not just presence; deleting the last
visible file transitions to the empty state correctly.

## Out of scope

- A user-visible Trash / Recently Deleted screen. The staging folder is an implementation detail of
  undo, not a feature.
- Swipe-to-delete on the other library surfaces (`SessionLibraryView`, `PlaylistLibraryView`,
  `TextTranceLibraryView`). `SwipeToDeleteRow` is built reusable so they can adopt it later.
- Changes to `LibraryFoldersView`, which already has native swipe actions.
