# Pink Aurora Light Mode — Design Spec

**Date:** 2026-07-18
**Status:** Approved by user (palette direction C "Pink Aurora" chosen via visual companion; approach A "adaptive semantic tokens" chosen)
**Branch:** red-team-reader

## Goal

Add a bright-pink light mode ("Pink Aurora") to LumeSync alongside the existing dark "Liminal" identity, selectable via an in-app Light/Dark/System toggle. Trance-output surfaces (session player, flash mode) always stay dark. The Text Trance RSVP reader follows the app theme but gains its own light/dark override in reader controls.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| Theme model | Both themes, in-app toggle: Light / Dark / System |
| Palette direction | C — Pink Aurora: light mirror of the dark aurora identity (pink→lavender→peach washes, frosted glass, hot-pink hero accent) |
| Session player | Always dark, regardless of theme |
| Text Trance reader | Follows app theme + per-reader light/dark override toggle in reader controls |
| Flash mode colors | `flashOn` / `flashOff` are hue-locked; never adapt |
| Architecture | A — adaptive semantic tokens via existing `Color(light:dark:)` helper |

## 1. Palette layer

New file `Ilumionate/DesignSystem/PinkAuroraPalette.swift` with a `PinkAuroraHex` enum of raw hex strings (same testable pattern as `LiminalHex` in `LiminalPalette.swift`).

| Token | Dark (Liminal, unchanged) | Light (Pink Aurora, new) |
|---|---|---|
| bgDeep (voidDeep) | `03040C` | `FFE9F4` |
| bgPrimary | `070D1F` | `FFF3F9` |
| bgSecondary/elevated | `0D1428` | `FFFFFF` |
| accent teal (`roseGold`) | `7EE8D8` | `0FA891` |
| accent blue (`roseDeep`) | `7C9EFF` | `4D6DF0` |
| blush (hero pink) | `E87CB8` | `FF2D8F` |
| lavender | `B07DC8` | `9A4DC8` |
| warmAccent (peach) | `E8B07A` | `E07A2E` |
| textPrimary | `E6EEFF` | `231024` |
| textSecondary | `8FA3CC` | `7A5A80` |
| textLight/ghost | `5A6A8A` | `B08DB8` |
| bwDelta…bwGamma | existing | `6B4788`, `9A4DC8`, `4D6DF0`, `0FA891`, `E07A2E` |
| phase colors | existing | deepened variants in same hue families (chosen during implementation for AA contrast on `FFF3F9`) |
| glassBorder | blue @ 0.18 | `FF2D8F` @ 0.18 |
| glassFill | white @ 0.06 | white @ 0.60 |
| flashOn / flashOff | `F8C8D4` / `03040C` | **not adaptive — unchanged** |

Light accents are deepened relative to their dark counterparts so text/iconography meets contrast on blush backgrounds.

## 2. Adaptive tokens

Every semantic token in `TranceDesignSystem.swift` becomes `Color(light: <PinkAurora>, dark: <Liminal>)` using the existing `Color(light:dark:)` helper (already defined in that file). Dark values remain byte-identical — dark mode cannot regress. `flashOn`/`flashOff` are excluded and stay static.

## 3. Theme setting

- `ThemeMode` enum: `system` / `light` / `dark`, `Codable`, persisted through `AppSettingsManager`.
- `themeMode.colorScheme` maps to `ColorScheme?` (`nil` for system).
- `ContentView.swift:142` — replace `.preferredColorScheme(.dark)` with `.preferredColorScheme(settings.themeMode.colorScheme)`.
- `ProfileSettingsView.swift:92` — remove forced `.dark`; add a Light/Dark/System picker in settings UI.

## 4. Always-dark surfaces

`UnifiedPlayerView` / `SessionPlayerView` (and any entrainment-output view) apply a local `.colorScheme(.dark)` (trait override, not `preferredColorScheme`) so adaptive tokens resolve to the void palette during sessions. `UnifiedPlayerView.swift:107` currently has `useDarkChrome` logic — reconcile with the always-dark rule.

## 5. Component adaptation

- `AuroraBackground` — light variant: `FFEFF7 → FDEBFF → FFF6EC` gradient wash with the same drifting aurora-blob motion (blush/lavender blobs at low opacity). Select by `@Environment(\.colorScheme)`.
- Migrate raw `void*` / `aurora*` / `text*` color usages to semantic tokens (or explicit `Color(light:dark:)` pairs where a raw hue is intentional). Affected files (grep as of 2026-07-18):
  - DesignSystem: `AuroraBackground`, `ContentTypeStyle`, `GlowButton`, `LiminalSurface`, `LumeOrb`, `PhaseTimeline`, `WaveformShape`
  - App: `HomeStreakPill`, `HomeView`, `LibraryAllFilesView`, `LibraryShelves`, `LibraryView`, `MindMachineView(+Binaural)`, `MiniPlayerBar`, `OnboardingView`, `PlayerHeroOrb`, `PlaylistArtwork`, `PlaylistGridTile`, `PlaylistHeroCard`, `SatelliteButton`, `ScrubWhisperLine`, `SessionCardViews`, `SessionDetailView`, `StreamingArtworkTile`, `TranceTabBar`
  - TextTrance: `ReaderDisplayPreferences`, `ReaderSectionNavigatorSheet`, `ReaderSettingsDrawer`, `ReadingSourceDirectoryView`, `ScriptTheme+Style`, `TextTranceLibraryView`, `TextTranceSetupView`
- Player-only components (e.g. `PlayerHeroOrb`) may keep void colors since the player is always dark; decide per file during migration.

## 6. Reader toggle

- `ReaderDisplayPreferences` gains `readerColorMode`: `followApp` / `light` / `dark` (persisted with the other reader prefs).
- Toggle surfaced in the reader settings drawer / control cluster.
- Applied as a local `.colorScheme(...)` override on the RSVP player view (`TextTrancePlayerView`); `followApp` applies no override.

## 7. Testing & verification

- Unit tests: `PinkAuroraHex` values are valid 6-digit hex; every Liminal token has a Pink Aurora counterpart; flash colors unchanged.
- Build via `xcodebuild`; simulator screenshots of Home, Library, Settings, player, and reader in both modes.
- Verify the always-dark player renders void colors while the app is in light mode.

## Out of scope

- No new third-party dependencies.
- No change to flash/entrainment hues or timing.
- No multi-theme engine beyond Light/Dark/System (approach B rejected).

## Reference

Visual mockups from the brainstorm live in `.superpowers/brainstorm/` (palette options + token mapping screens).
