# Playlist UI Redesign — Design Spec

**Date:** 2026-07-04
**Status:** Approved (design), pending implementation plan
**Scope:** Full visual redesign of the three "playlist" surfaces to match the current void/aurora + orbital design language, fixing the reported rendering bugs as a consequence.

---

## Problem

The playlist screens predate the app's migration to the **void/aurora** dark design system. They still hardcode **light-theme** styling that clashes with the current `bgPrimary = voidPrimary` (near-black) background, which is why they look "old" and render incorrectly. Two concrete bugs were reported:

1. **"Cards / tags on top of each other"** — overlapping content within cards.
2. **"Cards sometimes load as black"** — tiles rendering black instead of artwork.

### Root-cause analysis

| Symptom | Location | Root cause |
|---|---|---|
| Old / washed look, invisible text | `PlaylistLibraryView.swift` (`EnhancedPlaylistCard`, `playlistStatsHeader`) | Card backgrounds hardcoded `Color.white.opacity(0.7/0.8)` and text uses `.foregroundStyle(.primary)`. Against `voidPrimary`, white-on-pale-white text is near-invisible; the pale card on a dark screen reads as broken. |
| Overlapping meta / tags | `EnhancedPlaylistCard` meta `HStack` (tracks · duration · Crossfade labels) | Multiple `Label`s in a single non-wrapping `HStack` on a narrow card overflow/clip; the editor artwork uses `GeometryReader` + absolute `.position()` quadrants which is fragile. |
| **Black artwork tiles** | `StreamingBrowserView.swift:567` `PlaylistRow` | `AsyncImage(url:)` uses the 2-parameter `content`/`placeholder` initializer with **no `.failure` phase handling** and no guard for a `nil`/invalid `artworkURL`. A dark or failed remote image, or a nil URL, leaves an unstyled/black tile. |

Because the user chose a **full redesign**, each surface is rebuilt from scratch with correct SwiftUI constraints and the shared design tokens. This structurally eliminates the overlap bugs (no absolute positioning, wrapping-safe layouts) and the black-tile bug (explicit phase-based artwork with an always-visible aurora fallback).

---

## Design Language (shared)

Rebuild everything on existing tokens — **no new hardcoded colors**:

- **Backgrounds:** `Color.bgPrimary` (void) screen; glass cards via `Color.bgCard` (`voidElevated.opacity(0.65)`) + `Color.glassBorder` stroke. Reuse the existing `GlassCard` / `GlassBackground` where it fits.
- **Accents:** aurora gradients from `roseGold`(teal) → `roseDeep`(blue), plus `blush`(pink) / `lavender`(violet). Play buttons and primary CTAs use a teal→blue `LinearGradient`.
- **Text:** `.textPrimary` / `.textSecondary` / `.textLight` (never `.primary`/`.white`-on-light).
- **Content-type gradient mosaic:** keep the existing content-type → color mapping (`contentTypeColor`) for generated artwork; extract it into one shared helper so the editor header, card thumbnails, and badges stay consistent (removes the current duplication across `PlaylistEditorView` and `TrackRow`).
- **Spacing/radius:** `TranceSpacing` / `TranceRadius` tokens only.

---

## Surface 1 — Playlists tab (`PlaylistLibraryView`) — "Bento Hero" (Direction B)

- **Header:** "Playlists" title + subtitle (`N playlists · Hh Mm total`). Keep the existing `+` create action in the toolbar.
- **Hero card:** the most-played (or first) non-empty playlist as a large glass card with a gradient wash derived from its dominant content types, a bottom scrim, "MOST PLAYED" label, name, meta, and an aurora play button. Tapping plays; a secondary tap target opens the editor.
- **Grid below:** remaining playlists as a 2-up glass grid, each with a generated gradient thumbnail, name, and `tracks · duration` meta.
- **Empty state:** keep the existing rich empty state, re-themed to void/aurora (it is already close; just swap light colors for tokens).
- **Crossfade** indicated with a small aurora chip, not a free-floating `Label` in an overflowing HStack.

**Components:** `PlaylistHeroCard`, `PlaylistGridTile`, shared `PlaylistArtwork` (gradient mosaic). Extracted into their own files (keep `PlaylistLibraryView` lean).

## Surface 2 — Playlist editor (`PlaylistEditorView`)

- **Artwork hero:** keep the 4-quadrant content-type gradient mosaic, but render it with a `Grid`/`HStack`+`VStack` (or fixed half-size frames) instead of `GeometryReader` + `.position()` to remove the fragile absolute layout. Aurora shadow.
- **Name:** inline editable `TextField` with `.textPrimary` + teal tint.
- **Smart Transitions:** glass row with a content badge, description, and aurora-tinted `Toggle`.
- **Sessions list:** glass-backed track rows with content-type badge, title, `creator · duration` meta, and drag handle. Native `.onMove` / `.onDelete` preserved. `Add` pill in the section header (aurora tint).
- Re-theme `SessionPickerView` (search field, filter chips, rows, floating "Add N Sessions" button) to tokens — mostly a color swap; it is already structurally sound.

## Surface 3 — Streaming Featured Playlists (`StreamingBrowserView` → `PlaylistRow`, `CategoryCard`)

- **Artwork (the bug fix):** replace the 2-arg `AsyncImage` with the **phase-based** `AsyncImage(url:) { phase in … }`:
  - `.empty` (loading) → aurora gradient tile + music glyph (optionally a subtle shimmer).
  - `.success(image)` → `image.resizable().scaledToFill()` clipped to the tile.
  - `.failure` → aurora gradient tile + music glyph (same as loading, so it **never renders black**).
  - Guard `nil` `artworkURL` up front → gradient fallback directly.
  - The gradient uses the service color / a fixed aurora pair, matching the mockup.
- **Row & cards:** glass background, `.textPrimary`/`.textSecondary` meta, aurora service tag. `CategoryCard` re-themed to tokens.

---

## Non-goals (YAGNI)

- No changes to playlist **data model**, persistence (`PlaylistStore`), or playback (`UnifiedPlayerView`, `PlaylistPlayerController`).
- No changes to streaming networking/auth (`StreamingManager`, `SoundCloudService`) — only the artwork rendering and card styling.
- No new artwork-caching layer (SwiftUI `AsyncImage` already caches via `URLSession`); revisit only if flicker is observed.

---

## Testing & Verification

- **Unit-testable logic** extracted from views: the content-type → color/icon mapping and the "dominant content types" derivation become pure functions/helpers with Swift Testing coverage.
- **Manual/visual verification** (the reported bugs are runtime-visual): build and run in the iOS simulator; confirm on the three screens that (a) no text/tag overlap at the smallest supported width and with Dynamic Type larger sizes, and (b) streaming tiles show the aurora fallback while loading, on nil URL, and on a forced failure — never black.
- Existing test suite must remain green (note: some analyzer tests are pre-existing failures unrelated to this work).

---

## Affected files

- `PlaylistLibraryView.swift` (rebuild card grid → hero + grid; new component files)
- `PlaylistEditorView.swift` (re-theme; de-`GeometryReader` the artwork; shared artwork helper)
- `Ilumionate/StreamingBrowserView.swift` (`PlaylistRow` phase-based artwork; `CategoryCard`/rows re-theme)
- New: `PlaylistArtwork.swift` (+ `PlaylistHeroCard.swift`, `PlaylistGridTile.swift`) — shared, token-based, testable.
- New content-type style helper (or reuse `DesignSystem/ContentTypeStyle.swift` if suitable) to remove duplication.

New Swift files must be added to the Ilumionate target (synchronized group — verify membership).
