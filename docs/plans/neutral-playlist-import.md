# Neutral playlist import — keeping playlist download without shipping a site integration

**Status:** complete and verified on iOS 18.5

Implemented: shape-driven JSON/M3U/PLS/RSS parsing, feed autodiscovery, host-derived
provenance, source-relative download restrictions, the renamed import/review UI, and all
library/playlist entry-point rewiring. The focused iOS 18.5 playlist run passes 65 tests;
the complete iOS suite passes 1687 tests.
**Date:** 2026-08-30
**Decision owner:** user (chosen 2026-08-30: "go with 1 but make sure that it is still
compatible with bambicloud")

## The decision

Keep playlist download and import in full. Remove the *hardcoded named-site integration*,
not the feature. The importer keys on **response format**, never on domain, so the shipping
binary contains no reference to any particular website — while a BambiCloud playlist still
imports, because its JSON matches a conventional playlist shape.

This mirrors the Custom Sources decision already made for Reader: LumeSync supplies a general
tool, the user supplies the source.

## What exists today

Everything is deleted in the working tree only. Every line is intact at HEAD `14c9a98`.

| Part | Lines | Site-specific |
|---|---|---|
| `BambiCloudPlaylistLink`, `BambiCloudPlaylistClient`, `BambiCloudPlaylist` | ~200 | **yes** |
| `PlaylistTrackDownloader`, `PendingLargeDownload`, `PlaylistTrackDownloadError`, `PlaylistLinkImportError`, `PlaylistImportRequest` | ~330 | no |
| `BambiCloudPlaylistImportPlan`, `…ImportViewModel`, `…ImportView`, `…ReviewView`, `…MatchRow`, `…LinkEntryView`, `LocalAudioMatchPicker`, `LocalAudioMatchPickerRow`, `PlaylistLinkBrowserView` | ~1,100 | naming only |
| Tests | ~1,300 | mixed |

The only true site knowledge is in `BambiCloudPlaylistLink.swift`: a host allowlist
(`bambicloud.com`, `www.bambicloud.com`), a `/playlist/<uuid>` path shape, and the derived
API host `api.bambicloud.com`.

## Design

### 1. `PlaylistSourceDocument` — format detection, no domain logic

Fetch any user-supplied `https` URL, then dispatch on content, not host:

| Detected by | Format |
|---|---|
| leading `#EXTM3U` | M3U / M3U8 (`#EXTINF:<seconds>,<title>`) |
| leading `[playlist]` | PLS (`FileN`, `TitleN`, `LengthN`) |
| root `<rss>` / `<feed>` | RSS / Atom / podcast (`<enclosure url>`, `<itunes:duration>`) |
| valid JSON | generic JSON playlist (below) |
| `<html>` | feed autodiscovery via `<link rel="alternate">`, else a clear error |

Only `http`/`https`. No `javascript:`, `data:`, `file:`.

### 2. `GenericPlaylistJSON` — shape-driven, and this is what keeps BambiCloud working

Decode a *family* of conventional shapes rather than one service's schema:

- **Playlist object**: top level, or the first element of an array found under any of
  `playlists`, `items`, `data`, `results`, `entries`.
- **Title**: `name` ?? `title`.
- **Tracks**: `files` ?? `tracks` ?? `items` ?? `entries`.
- **Track title**: `name` ?? `title`.
- **Track duration**: `duration` ?? `length`, with unit inference — a value that yields an
  implausible runtime in seconds is treated as milliseconds. BambiCloud sends `162000` for a
  2m42s track.
- **Track order**: `trackNum` ?? `track` ?? `position` ?? `index`, else array order.
- **Track audio**: `audioURL` ?? `url` ?? `src` ?? `file` ?? `enclosure`, optional.
- **Track identity**: `uuid` ?? `id`, optional.

BambiCloud's documented response decodes cleanly under these rules with no mention of the
service. That is the compatibility requirement, and it is satisfied by shape, not by
exception.

### 3. Getting to the data URL without shipping a domain

The deleted code turned a *page* link into an *API* link. That derivation is site knowledge
and does not come back. Three neutral routes, in order of preference:

1. **Paste the playlist data URL directly** — an M3U, PLS, RSS, or JSON endpoint. For
   BambiCloud that is `https://api.<host>/playlists?uuid=<uuid>`, which the user supplies.
2. **HTML feed autodiscovery** — if the URL returns HTML, honour `<link rel="alternate">`.
   A web standard, useful everywhere, no per-site knowledge.
3. **User-defined playlist sources** *(optional, later)* — the user saves their own
   `page URL → data URL` template in settings. Convenience returns without the app shipping
   any domain, exactly as Custom Sources does for Reader.

**Known cost, accepted:** pasting `bambicloud.com/playlist/<uuid>` will no longer resolve by
itself. The user pastes the JSON endpoint instead, or defines a source template once. The
"looks like a web page, not a playlist" error must say this plainly.

### 4. Rename, keep behaviour

`BambiCloudPlaylist*` → `Playlist*` (`PlaylistImportPlan`, `PlaylistImportViewModel`,
`PlaylistImportView`, `PlaylistReviewView`, `PlaylistMatchRow`, `PlaylistLinkEntryView`).
Downloading, large-download confirmation, local-library matching, and review-before-import
are restored unchanged — none of it was ever site-specific.

## Restore and rework list

Restore from HEAD unchanged:
`PlaylistTrackDownloader.swift`, `PlaylistTrackDownloadError.swift`,
`PlaylistLinkImportError.swift`, `PlaylistImportRequest.swift`, `PendingLargeDownload.swift`,
`LocalAudioMatchPicker.swift`, `LocalAudioMatchPickerRow.swift`.

Restore and rename only:
`BambiCloudPlaylistImportPlan/ImportView/ImportViewModel/ReviewView/MatchRow/LinkEntryView`,
`PlaylistLinkBrowserView.swift`.

Replace:
`BambiCloudPlaylistLink.swift` → `PlaylistSourceURL.swift` (scheme validation only, no host
allowlist).
`BambiCloudPlaylistClient.swift` → `PlaylistSourceClient.swift` (fetch + format dispatch).
`BambiCloudPlaylist.swift` → `Playlist.swift` + `GenericPlaylistJSON.swift`.

Rewire: `LibraryAddMenu` ("Import from Link", "Browse for a Playlist"),
`LibraryView.swift:227`, `PlaylistEditorView.swift:152`, `PlaylistLibraryView.swift:84`.

## Tests (Swift Testing)

1. The BambiCloud fixture at `HEAD:IlumionateTests/Fixtures_BambiCloudPlaylistResponse.json`
   decodes to the right title, track count, order, and durations — **the compatibility
   guarantee, kept as a regression test**. Rename the fixture neutrally; keep the bytes.
2. M3U, PLS, and RSS samples each decode to the same `Playlist` model.
3. Millisecond vs second duration inference.
4. Alternate key names (`title`/`tracks`/`url`) decode identically.
5. Non-web schemes and non-playlist payloads produce named errors, not crashes.
6. HTML input reports "not a playlist" and mentions pasting the data URL.
7. No shipped source contains a hardcoded playlist host — invariant test.
8. Restored downloader/match tests pass unchanged
   (`PlaylistTrackDownloaderTests`, `DownloadedTrackAnalysisTests`, `DuplicateTrackPlaylistTests`).

## Risks

- Some services need auth or reject non-browser clients; those will fail. Surface a useful
  error, add no per-site workaround.
- Restoring ~1,400 lines re-adds `URLSession` download paths. Keep the existing validation
  (`AudioDownloadValidation` magic-byte check) on that path.
- This reverses part of an in-flight release cleanup. Coordinate before committing.
- App Review exposure is reduced, not eliminated. Do not describe it as guaranteed compliant.
