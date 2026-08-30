# BambiCloud Playlist Import — Finishing Design

**Date:** 2026-07-25
**Status:** Approved, ready for implementation planning
**Scope:** Verify and complete the existing untracked `Ilumionate/PlaylistImport/` implementation

## Context

A prior session built an end-to-end BambiCloud playlist importer that maps a shared
playlist's tracks onto audio **already in the user's library**, downloading nothing.
The work was never committed, never specced, and never validated against the live
service.

This document records what verification found and specifies the remaining work.
It is a finishing design, not a greenfield design — link validation, the fetch
client, and the security posture are verified sound and are explicitly **out of
scope for change**.

### Existing implementation (untracked, 13 files / ~950 lines)

| File | Role |
|---|---|
| `BambiCloudPlaylistLink.swift` | Validates a pasted link, rebuilds the API URL |
| `BambiCloudPlaylistClient.swift` | Fetches public playlist metadata |
| `BambiCloudPlaylist.swift` | Decodes the response subset used for import |
| `BambiCloudPlaylistImporter.swift` | Scores and matches tracks to local audio |
| `BambiCloudPlaylistImportPlan.swift` | Reviewable track→file mapping |
| `BambiCloudPlaylistImportViewModel.swift` | Load / select / build playlist |
| `BambiCloudPlaylistImportView.swift` | Sheet host, entry ↔ review states |
| `BambiCloudPlaylistLinkEntryView.swift` | Link paste UI |
| `BambiCloudPlaylistReviewView.swift` | Match review list |
| `BambiCloudPlaylistMatchRow.swift` | Per-track row |
| `LocalAudioMatchPicker.swift` + `…Row.swift` | Manual file selection |
| `PlaylistLinkImportError.swift` | User-facing error copy |

Entry point: `LibraryView.swift:109` → Playlists sheet → `PlaylistLibraryView`
`+` menu → "Import from Link" → `BambiCloudPlaylistImportView`.

## Verification results (2026-07-25)

| Check | Result |
|---|---|
| Build, `Ilumionate` scheme, iOS Simulator | `** BUILD SUCCEEDED **`, 0 errors, 0 warnings in new files |
| Tests, iPhone 17 / iOS 26.5, `-parallel-testing-enabled NO` | `** TEST SUCCEEDED **`, 6/6 pass |
| UI reachability | Confirmed reachable from Library |
| Live API contract | **Confirmed** — HTTP 200, 21KB JSON |

### Live contract confirmation

`GET https://api.bambicloud.com/playlists?uuid=<uuid>` returns:

```
{ playlists: [ { uuid, name, description, expLevel, files: [ … ] } ],
  totalItems, pageSize, pageOffset }
```

Each file carries `uuid`, `name`, `duration`, `fileType`, `trackNum` — every field
the decoder requires. Findings:

- **Durations are milliseconds.** `154000` = 2:34. The decoder's `/1000` is correct.
- **Extra fields are additive** (`totalItems`, `pageSize`, `creator`, `imageURL`,
  `audioURL`, `scriptURL`, `hapticsURL`, `patreonTiers`, `triggers`, `warnings`, …).
  Ignoring them is safe.
- **Array order matched `trackNum` order**, but `trackNum` is *not* dense — the
  observed playlist numbered `[0,1,2,3,4,5,7]`. The importer relies on array order,
  which is correct; it must not assume `trackNum` is a contiguous index.
- `playlist.order` was `null` and carries no ordering information.

### Security posture (verified, unchanged by this work)

- Host allowlist: `bambicloud.com` / `www.bambicloud.com` only; https-only.
- The API URL is **rebuilt from the parsed UUID**, never followed from the pasted
  link, so a lookalike host cannot redirect the importer.
- 2MB response cap, 15s timeout.
- `audioURL` and friends are never requested. Nothing is downloaded.

## Gaps to fix

Gaps 1, 2 and 6 were derived from code reading and are each to be proven by a
failing test before being fixed.

### Gap 1 — Short titles are all-or-nothing

`BambiCloudPlaylistImporter.titleSimilarity` returns `0` unless
`min(tokenCount) >= 3`, with exact normalized equality the only escape hatch.
Two of the seven real tracks are two-token names ("Bimbodoll Trancetone",
"Bimbodoll Sleepener"). A local `Bimbodoll Sleepener 320.mp3` therefore scores 0
and lands in `.missing` — the user is told they do not own a file they own, and
gets no manual-pick prompt.

### Gap 2 — Extra local tokens are punished hard

Coverage divides by `max(remoteCount, localCount)`. Local
`Instant Bimbo Sleepdoll - Bambi Sleep.mp3` (5 tokens) against the 3-token remote
title yields `3/5 = 0.6`, below the `0.65` floor → `.missing`. Artist and
collection suffixes in filenames are common, so this misfires routinely.

### Gap 3 — Unmatched tracks disappear with no record

`makePlaylist()` silently drops unmatched rows. Nothing states that the source had
7 tracks while 5 were imported.

**Decision:** keep the drop-silently behavior, but state it before it happens.
No persistence, no `Playlist` model change.

### Gap 4 — No contract regression test

All six tests are mocked. Correct for unit tests, but no fixture guards the
decoder against the API changing shape.

### Gap 5 — Dead code

`BambiCloudPlaylistImportViewModel.canImport` is unused; the view inlines
`matchedCount == 0`.

### Gap 6 — O(tracks × files) catalog scans on the main actor

`matchScore` calls `KnownAudioCatalog.shared.match(audioFile:)` once per
(track × file) pair. That method linearly scans 54 entries / 218 aliases. For
7 tracks × 300 files that is ~2,100 scans (~1M string operations) executed
synchronously inside `@MainActor loadPlaylist()`. The catalog title for a given
audio file is invariant across tracks, so the work is redundant.

## Design

### 1. Extract `AudioTitleMatcher.swift` (new, ~110 lines)

`BambiCloudPlaylistImporter.swift` currently mixes plan building, candidate
ranking, score tiers, and string normalization in 199 lines. Normalization and
similarity move into a pure type with no knowledge of playlist models, testable in
isolation. The importer drops to ~90 lines with no knowledge of string munging.

Boundary: `AudioTitleMatcher` takes two strings and returns a similarity in
`0…0.94`. It does not know about `AudioFile`, `BambiCloudPlaylist`, tiers, or
durations.

Normalization is carried over unchanged from the current `normalize(_:)`:
case/diacritic folding, non-alphanumerics to spaces, drop a leading all-digit
token of ≤3 characters, drop trailing disposable suffixes
(`audio`, `final`, `hq`, `official`, `remastered`, `mp3`, `m4a`, `wav`, `aac`,
`flac`, `v2`, `320kbps`).

Three signals, take the maximum:

| Signal | Score | Purpose |
|---|---|---|
| Exact normalized equality | 0.94 | Preserves current behavior |
| Space-stripped equality | 0.92 | `Bimbo Doll Sleepener` ↔ `Bimbodoll Sleepener` |
| Asymmetric token containment | 0.70–0.88 | Gaps 1 and 2 |

Containment replaces `common / max(remote, local)` with:

```
remoteCoverage = |remote ∩ local| / |remote|
extraPenalty   = min(0.06, 0.02 × (|local| − |remote ∩ local|))
score          = base(remoteCoverage, |remote|) − extraPenalty
```

`remoteCoverage` asks *how much of the remote title the local file contains*,
so extra local tokens reduce the score mildly instead of failing a hard gate.

Base by remote token count:

| Remote tokens | Rule | Base |
|---|---|---|
| 1 | Containment disabled — exact/stripped signals only | — |
| 2 | Requires `remoteCoverage == 1.0` | 0.80 |
| ≥3 | `remoteCoverage == 1.0` | 0.88 |
| ≥3 | `remoteCoverage >= 0.80` | 0.80 |
| ≥3 | `remoteCoverage >= 0.65` | 0.70 |
| ≥3 | otherwise | 0 |

The single-token exclusion is deliberate: it prevents a title like "Sleep" from
matching every file containing that word. The two-token full-coverage requirement
is what fixes Gap 1 without opening that door.

### 2. Unchanged: tiers and duration bonus

Kept exactly as they are, in the importer:

- The existing guards are retained: a normalized remote title shorter than 4
  characters scores 0, and a title score below 0.55 is discarded before the
  duration bonus is considered.
- Candidate floor 0.55; duration bonus `+0.06` within `max(3s, 1%)`,
  `+0.03` within `max(10s, 3%)`, else 0. Duration can only corroborate.
- `.exact` ≥ 0.98 and margin ≥ 0.04; `.probable` ≥ 0.90 and margin ≥ 0.08;
  `.needsReview` ≥ 0.75; else `.missing`.
- Each local file is auto-selected at most once.

### 3. Expected behavior against the real playlist

| Local filename | Score | Status | Change |
|---|---|---|---|
| `08 - Bimbodoll Sleepener.m4a` | 1.00 | `.exact` | unchanged — existing test |
| `Bimbo Doll Sleepener.mp3` | 0.98 | `.exact` | was `.missing` |
| `Instant Bimbo Sleepdoll - Bambi Sleep.mp3` | 0.90 | `.probable` | was `.missing` (Gap 2) |
| `Bimbodoll Sleepener 320.mp3` | 0.84 | `.needsReview` | was `.missing` (Gap 1) |
| `Total Bimbo Wipeout Doll` vs `Blissful Bimbo Dumbdown Doll` | 0 | no candidate | unchanged — guard holds |
| Two identical local titles | margin 0 | `.needsReview` | unchanged — existing test |

The last two rows are the regression anchors: the change must not create
cross-matches between same-family titles, and must not auto-resolve ambiguity.

### 4. Precompute local candidates once

Build, once per import, an array of `(id, normalizedTitles, duration)` where
`normalizedTitles` folds in filename, `displayName`, `userTitle`,
`trackMetadata.embeddedTitle`, `trackMetadata.generatedTitle`, and the
`KnownAudioCatalog` title. Then score every track against that precomputed array.

One catalog lookup per audio file instead of one per (track × file) pair, and
per-pair work reduces to set intersections. Fixes Gap 6.

### 5. Honest skip confirmation

When `unresolvedCount > 0`, the Import action raises a confirmation before
building the playlist:

> Import 5 of 7 tracks?
> 2 tracks aren't in your library and will be skipped.

Cancellable. Behavior on confirm is identical to today. When
`unresolvedCount == 0` the import proceeds without a prompt. Fixes Gap 3.

### 6. Contract fixture test

Commit the live response as a test fixture **trimmed to only the fields the
decoder reads** — `audioURL`, `scriptURL`, `hapticsURL`, `uploaderId`,
`patreonTiers` and `creator` are stripped rather than committed, so no media URLs
or creator data enter the repository. Real track names and durations are retained
(the existing tests already use them).

Asserts: 7 tracks decode, order preserved, ms→s conversion, non-dense `trackNum`
tolerated, and unknown extra keys ignored.

### 7. Remove dead `canImport`

## Testing

TDD, one failing test before each fix:

1. Two-token remote title with a decorated local filename → `.needsReview`, not `.missing` (Gap 1)
2. Extra local tokens with full remote coverage → `.probable`, not `.missing` (Gap 2)
3. Space-stripped equivalence → `.exact`
4. Single-token remote title does **not** match an unrelated file containing that token
5. Same-family titles do not cross-match (regression guard)
6. Catalog lookups occur once per file, not per pair (Gap 6)
7. Contract fixture decode (Gap 4)
8. Confirmation appears only when `unresolvedCount > 0` (Gap 3)

Existing six tests must continue to pass unmodified — they encode the `.exact`
and ambiguity behaviors this change must preserve.

Full suite run serially (`-parallel-testing-enabled NO`) in the real working copy,
per the known-flakiness notes: three main-actor latency tests and
`KeywordPipelineEvaluationTests/timelineMetricsOverCorpus` fail for environmental
reasons and are not regressions.

## End-to-end verification

Seed a simulator library with files shaped like the real track names, deliberately
including the decorated and word-split variants that expose Gaps 1 and 2, then
drive the import sheet and capture the review screen.

**Risk:** seeding may require writing `AudioLibraryStore`'s JSON directly rather
than going through the normal import path. To be confirmed early; if it turns
fiddly, report rather than silently substituting a weaker check.

**Risk:** generated audio needs plausible durations, since duration feeds the
tier bonuses. Silent files at the real durations (154s, 876s, 1390s, …) suffice.

## Out of scope

- Downloading audio. The importer maps to owned files only.
- Persisting the source link or unmatched tracks for later re-sync (Gap 3
  alternative, deferred).
- Any change to link validation, the fetch client, or the security model.
- Character-level fuzzy matching (trigram Dice) for typos. Not justified by
  observed failures; revisit if the three signals prove insufficient.

## Definition of done

- [ ] Each gap has a test that failed before its fix
- [ ] Six original tests pass unmodified
- [ ] Build clean, no new warnings
- [ ] Full suite green apart from the four known environmental failures
- [ ] Import verified in the simulator against a seeded library
- [ ] `Ilumionate/PlaylistImport/` and its tests committed
