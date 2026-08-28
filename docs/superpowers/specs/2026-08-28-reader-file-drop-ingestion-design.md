# Reader file-drop ingestion

**Date:** 2026-08-28
**Status:** Design approved, awaiting implementation plan

Extend the Finder/Files cable-drop intake so it admits reader documents
(`.txt`, `.md`, `.pdf`, `.epub`) alongside audio, routing them into the
TextTrance reader library.

## Problem

`UIFileSharingEnabled` exposes the app's Documents root. `CableAudioImportService`
walks it, waits for files to settle, and admits audio into `AudioLibraryStore`.
Anything else is either ignored (at the root) or filed under
`_Needs Review/Unsupported Files` (in `Incoming Audio/`).

The reader can already read PDFs and ePubs — `ReadingDocumentImporter` extracts
both, and `TextTranceRootView` presents a `fileImporter` for them. But that path
is reachable only through the in-app picker and the share extension. A user who
drags a book onto LumeSync in Finder gets it rejected as "unsupported", despite
the app being able to read it.

Plain text is worse: `.txt` and `.md` are not importable **anywhere** today.
`ReadingDocumentKind` is `pdf | epub`, so no surface accepts them.

## Goals

- A dropped `.txt`, `.md`, `.pdf`, or `.epub` reaches the reader library.
- Audio intake behavior is unchanged, and provably so.
- One scan over one batch, so mixed drops cannot race.
- Nothing the user hands the app is destroyed.

## Non-goals

- `.rtf`, `.docx`, or any format needing a new extractor.
- Cloud import sources (explicitly out of scope in `plan.md`).
- Capping the existing unbounded ePub read (see Known issues).
- Changing the in-app picker or share-extension paths beyond what the new
  `ReadingDocumentKind.text` case requires.

## Decisions

| Question | Decision |
|---|---|
| Which types | `.txt`, `.md` via a new plain-text extractor; `.pdf`, `.epub` via the existing `ReadingDocumentImporter` |
| Where dropped | Documents root routes by type; new `Incoming Text/` beside `Incoming Audio/`; **both dedicated inboxes accept either kind** |
| Result reporting | One scan, one combined alert with counts for both kinds |
| Source file fate | Moves to a visible `_Imported/` folder in Documents |

### Why one service rather than two

The settle heuristic holds the *entire* batch until nothing in the directory has
changed for 5 seconds. This exists because Finder copies a batch one file at a
time, and moving an early file mid-batch makes the whole drag fail with
"required file cannot be found."

A separate text service would walk the same directories and apply that
directory-wide heuristic to a batch it can only half see. Routing inside one
service means a `.txt` that landed instantly waits alongside the 60 MB M4A still
copying — which is the correct behavior and comes for free.

## Architecture

### New files

| File | Purpose |
|---|---|
| `Ilumionate/CableInboxFileKind.swift` | Classifies a settled file into `.audio`, `.readerDocument`, `.unrecognized` — by extension, then by content prefix. The single place deciding what a dropped file is. |
| `Ilumionate/ReaderInboxAdmission.swift` | Admits one classified reader document; reports `.imported(ReadingDocument)` or `.replacedExisting`. Mirrors the audio branch's shape. |

### Modified files

**`CableAudioImportService.swift` → `CableFileImportService.swift`**

The walk, two-snapshot settle, batch-age check, `_Needs Review` filing, unique
naming, and rollback are kind-agnostic and stay as they are. The only change is
the admission gate: the

```swift
guard AudioDownloadValidation.audioExtensions.contains(...)
```

check becomes a `switch` over `CableInboxFileKind` dispatching to the audio
branch or `ReaderInboxAdmission`.

`excludedRootDirectoryNames` gains `Incoming Text` and `_Imported`. **Omitting
`_Imported` makes the recursive root walk re-scan its own output on every pass.**

The stale doc comment on `AppStoragePaths.cableRootInbox` claiming the root "is
scanned non-recursively" is corrected — the code uses a recursive
`FileManager.enumerator` with name-based exclusion, as `appOwnedDirectoryNames`
already describes.

**`CableAudioImportResult.swift` → `CableFileImportResult.swift`**

Gains `importedDocuments: [ReadingDocument]`; `merge` accumulates it like the
other outcome arrays. `title` and `message` count both kinds. Audio-only wording
is preserved exactly, so an audio-only drop reads as it does today.

**`ReadingDocumentKind`** gains `.text`, covering both `.txt` and `.md`:
`displayName` "Text", `systemImage` `doc.text`. `init?(fileExtension:)` accepts
`txt` and `md`.

**`ReadingDocumentImporter`** gains:
- `extractPlainText(from:)` — decode UTF-8, fall back to `.isoLatin1`, normalize
  via the existing `normalizeText`, require ≥ 8 words, and reject sources larger
  than 8 MB (roughly 1.3 million words — far past any plausible reader session,
  and the point where the full-string regex passes become a memory concern).
- `supportedFileExtensions: Set<String>` — one source of truth for the classifier
  and `supportedContentTypes`.
- Markdown cleanup applied to `.md` only: ATX heading markers, emphasis markers,
  list bullets, and `[text](url)` → `text`. The ORP reader displays one word at a
  time, so a literal `##` or `**word**` in the word stream is visible garbage.
  `.txt` passes through untouched.

**`ReadingDocumentStore.importDocument`** returns whether it replaced an existing
document, so the caller can report a duplicate rather than announce a fresh
import.

**`AppStoragePaths`** gains `cableTextInbox` (`Incoming Text/`) and
`cableImported` (`_Imported/`).

### Concurrency

`CableFileImportService` is an actor; `ReadingDocumentStore` is `@MainActor`.
`ReaderInboxAdmission` takes an injected `@MainActor @Sendable` import closure
defaulting to `ReadingDocumentStore.shared` — the pattern `CableAudioImportModel`
already uses for `refreshLibrary`. Extraction stays on the existing `@concurrent`
`ReadingDocumentImportWorker`, off the main actor.

## Data flow

Per settled file:

1. Classify.
2. `.unrecognized` at root → left alone (someone else's file). In either
   dedicated inbox → `_Needs Review/Unsupported Files`.
3. `.audio` → existing branch, unchanged.
4. `.readerDocument` → extract, store, **then** move the original to `_Imported/`.

Step 4's ordering is load-bearing. If the move fails after a successful store,
the document is already in the reader and the original is still in the inbox: the
next scan re-extracts, the content hash matches, the replace is idempotent, and
the move is retried. The failure self-heals rather than stranding a file.

The audio path's `registeredURLs` guard — which prevents moving a file a library
row still points at — has no reader analogue and is not needed. Reader documents
store extracted text in Application Support and never reference an inbox URL.

## Error handling

| Condition | Outcome |
|---|---|
| Extension claims document, content prefix is binary | `_Needs Review/Invalid Documents` (new category, parallel to `Invalid Audio`) |
| Extraction yields < 8 words (`noReadableText`) | `_Needs Review/Invalid Documents` — rescanning every pass would be pointless |
| Content hash or filename matches an existing document | `_Needs Review/Duplicates`, reported as a duplicate |
| Plain text file exceeds 8 MB | `_Needs Review/Invalid Documents` |
| Store write or disk error | `failures`; file left where found, retried next scan |

### Duplicate semantics differ from audio, deliberately

`ReadingDocumentImportWorker.prepare` replaces any document matching content hash
**or** original filename, and has no "already in library" signal — the hash is not
knowable until after extraction. So a re-dropped file is always re-extracted. The
replace is idempotent (same text, same hash), so the store ends up correct either
way; the service reports it as a duplicate and files the original under
`_Needs Review/Duplicates`, matching audio's user-visible behavior.

## UI

- Alert title counts both kinds: `"2 Audio Files, 3 Documents Added"`.
- Message keeps its existing per-outcome lines, with a document line added.
- Buttons: **Analyze** when audio was imported (existing behavior), **Open Reader**
  when documents were (sets `selectedTab = .read`), **OK** otherwise.
- `LibraryAddMenu`: "Check Incoming Audio" → "Check Incoming Files";
  `isCheckingIncomingAudio` → `isCheckingIncomingFiles`.
- The empty-inbox guidance stops saying "drag audio".
- No refresh plumbing for the reader: `ReadingDocumentStore` is
  `@MainActor @Observable` and mutated directly, so the Read tab updates itself.
  Audio still needs `AudioLibraryCache.refresh()`.

## Testing

The 542 lines of *service* tests across `CableAudioImportTests` and
`CableAudioRootInboxTests` are the regression net. They get a mechanical rename;
**no behavioral assertion changes.** If audio intake still passes, routing inside
the existing service cost nothing.

`CableAudioImportModelTests` is the exception. Four assertions in
`CableAudioImportTitleTests` pin exact alert copy — `"5 Audio Files Added"`,
`"1 Audio File Added"`, `"No New Audio Found"` — and that copy deliberately
generalizes, because the alert now reports both kinds. The prior-import path
cannot know which kind an earlier scan admitted, so it reads "N Files Added";
`"No New Audio Found"` becomes `"No New Files Found"`. A scan that admitted only
audio still reads `"2 Audio Files Added"`, so the common case is unchanged.

New service tests:
- Mixed batch (audio + `.txt` + `.pdf` + junk) admitted in one pass.
- `.txt` at root routes to the reader.
- `.txt` in `Incoming Audio/` still imports (the forgiving rule).
- `.pdf` in `Incoming Text/` imports.
- Unrecognized file in either dedicated inbox → `_Needs Review/Unsupported Files`.
- Re-dropped document → duplicate, filed under `_Needs Review/Duplicates`.
- Successful document → original present in `_Imported/`.
- **`_Imported/` and `Incoming Text/` are excluded from the walk** — direct
  regression test for the infinite-rescan bug.

New importer tests: `.txt` extraction, `.md` cleanup, Latin-1 fallback,
under-8-words rejection, oversize rejection.

New result tests: combined counts in `title`/`message`; audio-only wording
unchanged.

Run on both destinations via `Scripts/run-tests.sh`, which fails when zero cases
run (see ERRORS.md ERR-002).

## iOS 18 compatibility

Nothing here touches `FoundationModels`. PDFKit, Compression, and CryptoKit are
all available at the 18.0 floor, and `doc.text` predates it, so no `@available`
gates are needed. Verified by building against the iPhone 16 Pro / OS 18.5
runtime rather than by inspection — a too-new SF Symbol renders blank with no
build error.

## Known issues, not fixed here

`ReadingDocumentImporter.extractEPUB` reads the whole file via
`Data(contentsOf: url)` with no size cap, and `EPUBArchive` inflates entries into
memory. This predates this work and capping it is a separate behavioral decision.
To be logged in `ERRORS.md` during implementation, status `identified`.
