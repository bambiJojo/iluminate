# Duplicate Detection on Audio Import — Design

**Date:** 2026-08-10
**Status:** Approved, ready for planning
**Surfaces:** BambiCloud playlist import, Files-picker import, URL download, Audio Library

## Problem

Importing a BambiCloud playlist that shares tracks with a playlist already imported produces a
second copy of every shared track on disk, named `Track (1).mp3`, carrying a fresh `UUID`, no
analysis, no rating, and no play count. Repeat it across a few playlists and the library fills with
near-identical rows.

The reported symptom is precise: the duplicate is *noticed too late*. The app re-downloads the file
and renames it rather than recognising, before spending the bytes, that it already has it.

## Root causes

Five independent defects compound. All are in current `main` behaviour.

### 1. The content fingerprint is computed and never read

`AudioFile.contentFingerprint` is a SHA-256 of the file's bytes. It is computed on import
([`AudioImportWorker.swift:64`](../../../Ilumionate/AudioImportWorker.swift)) and backfilled for
older entries by the repairing library load
([`AudioLibraryStore.swift:149`](../../../Ilumionate/AudioLibraryStore.swift)).

Its only readers are `KnownAudioCatalog` matching and the analysis cache. **No import path compares
a fingerprint against the library.** The identity needed to detect duplicates already exists and is
simply never consulted.

### 2. Both "unique destination" helpers manufacture duplicates

[`AudioImportWorker.swift:77`](../../../Ilumionate/AudioImportWorker.swift) and
[`PlaylistTrackDownloader.swift:148`](../../../Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift)
each run `while fileExists { … "Name (1).ext", "Name (2).ext" … }`.

A filename collision is the cheapest available signal that this file may already be present. Both
call sites treat it as a naming inconvenience and resolve it by guaranteeing a second copy.

### 3. The downloader sets no fingerprint at all

[`PlaylistTrackDownloader.swift:106`](../../../Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift)
returns `AudioFile(filename:duration:fileSize:)`. A downloaded track therefore has no content
identity until some later library scan backfills it — so it cannot participate in dedupe even if
dedupe existed.

### 4. Nothing remembers where a track came from

`BambiCloudPlaylist.Track` carries a stable publisher `uuid` and an `audioURL`
([`BambiCloudPlaylist.swift:11`](../../../Ilumionate/PlaylistImport/BambiCloudPlaylist.swift)). Both
are discarded once the download completes.

`BambiCloudPlaylistImporter.matchScore`
([`BambiCloudPlaylistImporter.swift:96`](../../../Ilumionate/PlaylistImport/BambiCloudPlaylistImporter.swift))
therefore matches on **title text alone**, requiring a score of 0.90 with a 0.08 margin to
auto-select. Importing a second playlist re-runs fuzzy title matching from scratch against tracks
the app has already downloaded from a known, exact source.

### 5. Numbered series normalise to the same string

`normalize()` strips a leading run of digits of length ≤ 3
([`BambiCloudPlaylistImporter.swift:189`](../../../Ilumionate/PlaylistImport/BambiCloudPlaylistImporter.swift)):

```swift
if let first = tokens.first, first.allSatisfy(\.isNumber), first.count <= 3 {
    tokens.removeFirst()
}
```

So `01 Bambi Sleep` and `02 Bambi Sleep` both normalise to `bambi sleep`. Compounding this,
`makePlan` keeps an `automaticallyUsedIDs` set
([`BambiCloudPlaylistImporter.swift:23`](../../../Ilumionate/PlaylistImport/BambiCloudPlaylistImporter.swift))
that lets each local file be auto-selected for at most one row.

Result for a numbered series: row 01 claims the file, row 02 scores identically, finds it already
claimed, falls to `.missing`, and is downloaded. The publisher's own `trackNumber` field is
available and unused.

**Together:** fuzzy match fails → row reads `.missing` → "Download all missing" → new file with a
`(1)` suffix → new `UUID` → no analysis, no rating, no play count.

## Decisions taken

| Question | Decision |
|---|---|
| Scope | Prevention **and** cleanup of the existing library |
| Exact match (same bytes / same remote track) | Silent reuse — no prompt, no download |
| Probable match (size + duration, or title + duration) | Surfaced as a review row the user resolves |
| Cleanup entry point | Audio Library toolbar |
| Matcher fixes (causes 4 and 5) | In scope — they are causes of the duplication, not adjacent polish |

## Approach

Give every file a **content identity** and a **provenance**, and consult both at every door into the
library — critically, *before* bytes are spent.

Three shapes were weighed:

| Approach | Verdict |
|---|---|
| **A. Identity + provenance, checked at each import door** | **Chosen.** Uses the fingerprint already being computed, adds the one field that makes repeat imports exact, and puts the check where the duplicate is created. |
| **B. Fingerprint-only, checked after download** | Rejected. Correct but wasteful: it still downloads the whole file before discovering the app already has it, which is the specific complaint. |
| **C. Improve title matching only** | Rejected. Fuzzy matching cannot be made reliable enough to be the sole defence, and it does nothing for the Files-picker path. |

## Components

### `RemoteAudioSource` — provenance

A new `Codable`, `Sendable` value recorded on `AudioFile`:

```swift
/// Where this file was fetched from, when it was fetched rather than imported.
nonisolated struct RemoteAudioSource: Codable, Sendable, Equatable {
    let service: String     // "bambicloud"
    let trackID: String     // the publisher's own stable track uuid
    let url: URL
}
```

Added to `AudioFile` as `var remoteSource: RemoteAudioSource?` with a matching `CodingKeys` case.
Optional, so every stored library decodes unchanged.

`PlaylistTrackDownloader` records it. This is the highest-value single change: the second playlist
that shares a track with the first matches on exact publisher identity, with no fuzzy matching and
no bytes spent.

### `AudioTitleNormalizer` — one shared normaliser

Extracted from `BambiCloudPlaylistImporter.normalize` into `Ilumionate/LibraryDedupe/` so the
matcher and the detector cannot drift apart. It also consolidates the extension-stripping logic that
[`IlumionateTests.swift:824`](../../../IlumionateTests/IlumionateTests.swift) already flags as
duplicated across six or more sites.

Behaviour change from the current normaliser: a leading track number is **retained as a
distinguishing token** rather than stripped, so `01 Bambi Sleep` and `02 Bambi Sleep` no longer
collapse to the same key. Where the remote track supplies `trackNumber`, it is compared against the
local leading number directly.

### `DuplicateAudioDetector` — one pure verdict

New `Ilumionate/LibraryDedupe/`. An index built once from the library answers a single question:

```swift
nonisolated enum DuplicateVerdict: Equatable, Sendable {
    case distinct
    case identical(existing: AudioFile.ID)
    case likely(existing: AudioFile.ID, reason: Reason)

    enum Reason: Equatable, Sendable {
        case sizeAndDuration
        case titleAndDuration
    }
}
```

Signals, evaluated in order, first match wins:

| # | Signal | Verdict | Available before download? |
|---|---|---|---|
| 1 | same `remoteSource.service` **and** `trackID` | `identical` | **yes** — free |
| 2 | same `contentFingerprint` | `identical` | no — needs the bytes |
| 3 | same `fileSize` **and** duration within 1s | `likely(.sizeAndDuration)` | **yes** — via the existing HEAD request |
| 4 | same normalised title **and** duration within 2s | `likely(.titleAndDuration)` | **yes** — free |
| — | otherwise | `distinct` | |

Signal 3 is the pre-download workhorse. Byte-exact `fileSize` combined with a matching duration
across two genuinely different recordings is vanishingly unlikely, and
`PlaylistTrackDownloader.expectedSize`
([`PlaylistTrackDownloader.swift:48`](../../../Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift))
already issues the HEAD request that supplies it — no extra network cost.

The detector is a pure value type over a library snapshot: no actor, no I/O, fully testable.

### Enforcement at the three import doors

**BambiCloud download** — `PlaylistTrackDownloader.download` is restructured so the dedupe check sits
between the `URLSession` download and the `moveItem` into `Documents`. Today `uniqueDestination` runs
first ([`PlaylistTrackDownloader.swift:91`](../../../Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift)),
which is what creates the `(1)` file before anything has a chance to object.

The download outcome becomes explicit rather than always-a-new-file:

```swift
enum PlaylistTrackDownloadOutcome: Sendable {
    case saved(AudioFile)
    case alreadyInLibrary(existing: AudioFile.ID)
}
```

`BambiCloudPlaylistImportViewModel.downloadRow` consults signals 1, 3 and 4 **before** calling
`download`. On `identical` it binds the row to the existing file and returns without a request. On
`likely` it marks the row for review. Only a `distinct` verdict spends bytes; after the download the
fingerprint is checked once more, and on `identical` the temp file is deleted and the row bound to
the existing entry — nothing enters `Documents` and nothing is added to the library.

The downloader also begins setting `contentFingerprint` and `remoteSource` on the files it does save.

**Files picker** — `AudioImportWorker.prepareAudioFile` runs the same check. `uniqueDestinationURL`
stops silently inventing `Name (1).ext` and instead reports the collision to its caller, which
resolves it as a duplicate verdict rather than a naming problem.

**URL download** — `AudioManager.downloadAudio` already stages to a temp file before transferring, so
it gains the fingerprint check on that temp file at no structural cost.

### Review row for probable matches

`BambiCloudPlaylistImportPlan.Row.Status` gains `.possibleDuplicate(existing: AudioFile.ID)`.

An associated value means dropping the enum's `String` raw type. That is safe: `Status.rawValue` has
no readers anywhere in the app or the tests — the only uses are equality comparisons such as
[`BambiCloudPlaylistImportTests.swift:188`](../../../IlumionateTests/BambiCloudPlaylistImportTests.swift),
which continue to compile unchanged.

The review table shows the existing library file alongside the remote track with two actions:

- **Use Existing** (default) — binds the row, no download
- **Keep Both** — proceeds with the download, accepting a second copy

Exact matches never reach this screen; they bind silently, as decided.

### Matcher corrections

Two changes to `BambiCloudPlaylistImporter`, both narrow:

1. `matchScore` adds `track.audioURL?.lastPathComponent` to the candidate local titles. A file
   downloaded from that CDN frequently carries exactly that filename, making it a strong signal the
   matcher currently discards.
2. Numbered-series handling per `AudioTitleNormalizer` above, so `automaticallyUsedIDs` no longer
   pushes track 02 to `.missing` because track 01 claimed the only match.

`automaticallyUsedIDs` itself is retained. It is correct in principle — one file should not silently
stand in for two different tracks — and once the normaliser distinguishes numbered entries the
over-exclusion it causes disappears.

### Cleanup — "Find Duplicates" in the Audio Library toolbar

Groups library files by the detector's identity keys and presents each group for review.

**Keeper selection**, in order: has `analysisResult` › has `transcription` › higher `playCount` ›
oldest `createdDate`.

**Merge, not just delete.** The keeper absorbs any field the losers hold and it lacks:
`analysisResult`, `transcription`, `deadTimeProfile`, `trackMetadata`, `userTitle`, `creator`,
`rating`, `detailedRating`, `tags`, `sessionNotes`. `playCount` sums across the group;
`lastPlayedDate` takes the maximum; `isFavorite` is the logical OR.

**Playlists repoint** through `PlaylistTrackBinding`
([`PlaylistTrackBinding.swift`](../../../Ilumionate/PlaylistTrackBinding.swift)), extended with an
explicit `[AudioFile.ID: AudioFile.ID]` remap so merged identifiers resolve to the keeper.

**Removal must move the file out of `Documents`.** This is a constraint, not a choice: dropping only
the library row leaves the file in place, and `discoverUnregisteredDocumentFiles`
([`AudioLibraryStore.swift:137`](../../../Ilumionate/AudioLibraryStore.swift)) re-registers it under
a new `UUID` on the next load — reproducing the duplicate. Removal therefore goes through
`PendingAudioDeletion.stage`
([`PendingAudioDeletion.swift:65`](../../../Ilumionate/PendingAudioDeletion.swift)), which relocates
files to a staging root outside `Documents` and provides the app's standard undo window.

Note that `PendingAudioDeletion` holds exactly one batch — `stage` commits any prior batch first. A
merge of several groups is therefore staged as a **single batch**, so one Undo reverses the whole
operation.

## Data flow

```
BambiCloud row marked .missing
        │
        ├─ DuplicateAudioDetector.verdict(remoteTrackID:size:duration:title:)   ← no network
        │     ├─ .identical  → bind row to existing file, done. 0 bytes.
        │     ├─ .likely     → .possibleDuplicate row, user resolves
        │     └─ .distinct   → continue
        │
        ├─ URLSession download → temp file
        │
        ├─ fingerprint(temp) → verdict
        │     ├─ .identical  → delete temp, bind row to existing. Nothing enters Documents.
        │     └─ .distinct   → continue
        │
        └─ move into Documents, AudioFile(fingerprint:, remoteSource:) → library
```

## Error handling

- A fingerprint that cannot be computed (unreadable file) yields `nil`, and signal 2 is skipped
  rather than treated as a match. Signals 3 and 4 still apply.
- A failed HEAD request means signal 3 is unavailable; the flow proceeds to download and relies on
  the post-download fingerprint check. No behaviour regression versus today.
- A merge whose file cannot be staged leaves that file in the library. Same rule as `deleteFile`
  ([`AudioLibraryView+Actions.swift:87`](../../../Ilumionate/AudioLibraryView+Actions.swift)):
  dropping the row while the file survives in `Documents` would resurrect it on the next scan.
- Detector verdicts are advisory for `.likely` and authoritative only for `.identical`. A false
  `.likely` costs one tap; there is no path by which it silently rebinds a playlist.

## Testing

Swift Testing throughout, in `IlumionateTests/`, matching the existing suite.

| Test file | Covers |
|---|---|
| `DuplicateAudioDetectorTests` | Each signal in isolation and in priority order; negatives — equal duration with different content, and equal title with different duration, are `distinct`; missing fingerprint degrades rather than throws |
| `AudioTitleNormalizerTests` | Numbered series stay distinct; extension and suffix stripping matches the behaviour the old normaliser had for every non-numeric case |
| `PlaylistTrackDownloaderTests` | Identical remote content downloaded twice yields one library file; `contentFingerprint` and `remoteSource` are populated; the temp file is removed on `alreadyInLibrary` |
| `BambiCloudPlaylistImportTests` (extended) | A second playlist sharing tracks resolves with zero downloads; a numbered series matches row-for-row; `.possibleDuplicate` rows resolve both ways |
| `DuplicateAudioMergeTests` | Keeper selection order; field union; `playCount` summed; `lastPlayedDate` maximum; `isFavorite` OR'd; playlist items repointed via the remap |
| `AudioImportWorkerTests` (extended) | Importing the same file twice from the picker does not produce `Name (1).ext` |

Run on both first-class destinations:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests
```

## Files

**New** — `Ilumionate/LibraryDedupe/`

- `RemoteAudioSource.swift`
- `AudioTitleNormalizer.swift`
- `DuplicateAudioDetector.swift`
- `DuplicateAudioGroup.swift` — grouping and merge policy
- `DuplicateAudioReviewView.swift` — the cleanup screen
- `DuplicateAudioReviewViewModel.swift`

**Modified**

- `Ilumionate/AudioFile.swift` — `remoteSource` property and coding key
- `Ilumionate/AudioImportWorker.swift` — collision reported, not renamed around
- `Ilumionate/AudioManager.swift` — fingerprint check on the URL-download temp file
- `Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift` — reordered check, outcome enum, fingerprint and provenance recorded
- `Ilumionate/PlaylistImport/BambiCloudPlaylistImporter.swift` — CDN filename candidate, shared normaliser
- `Ilumionate/PlaylistImport/BambiCloudPlaylistImportPlan.swift` — `.possibleDuplicate` status
- `Ilumionate/PlaylistImport/BambiCloudPlaylistImportViewModel.swift` — pre-download check
- `Ilumionate/PlaylistImport/BambiCloudPlaylistMatchRow.swift` — duplicate row presentation
- `Ilumionate/PlaylistTrackBinding.swift` — explicit ID remap
- `Ilumionate/AudioLibraryView.swift` — toolbar entry point

## Out of scope

- Acoustic fingerprinting (Chromaprint-style) that would match re-encodes of the same recording at
  different bitrates. SHA-256 catches byte-identical copies only. The provenance field covers the
  realistic BambiCloud case, and acoustic matching is a materially larger project.
- Cross-device or iCloud deduplication.
- Automatic background dedupe without review. Cleanup is user-initiated.
