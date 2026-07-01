# Player redesign — design spec

Date: 2026-06-30
Scope: two screens — the audio/light player (`UnifiedPlayerView`) and the Text Trance reader (`TextTrancePlayerView`).
Goal (from user): make both feel **more immersive and premium**, keeping all existing controls and behavior. Not a functional rewrite — a visual/hierarchy elevation.

## Constraints (apply to both)

- Preserve every existing capability and interaction (no feature removal, no behavior regressions).
- Honor `accessibilityReduceMotion` — no essential info conveyed by motion alone; heavy pulses/glows disabled when reduce-motion is on.
- Dark-only aesthetic already forced app-wide; use the design-system tokens (`TranceColors`/`TranceSpacing`/`TranceTypography`/`auroraTeal` etc.), no raw system colors.
- Keep animations compositor-friendly (opacity/scale/transform) and cheap — these screens run alongside the light engine / RSVP timer.
- Reuse existing subviews where possible; keep files focused (extract new pieces into their own files).

---

## 1. Audio/light player — "Now Playing hero" (Direction A)

Applies to the **audio-light** and **session** presentations of `UnifiedPlayerView` (modes with a scrubber and/or a central visual). Flash and color-pulse modes already fill the screen with their light visual and keep their current minimal overlay — unchanged except for shared transport polish.

### Current state
`controlsOverlay` stacks: top bar → (mandala only in session) → `bottomControls` = scrubber, transport, light-sync pill, and **separate labeled `GlassCard` sections for VOLUME and LIGHT INTENSITY**. Reads as stacked utility panels; the visual center is empty in audio mode.

### Target layout (top → bottom)
1. **Top bar** — unchanged structurally (close · title/subtitle · minimize), lighter styling.
2. **Hero visual** — a reactive aurora **orb** centered in the upper region, reacting to `engine.brightness` (and playback state). In session mode this replaces/absorbs the existing `MandalaVisualizer`; in audio mode it fills the previously empty center. Soft radial teal→blue glow, gentle breathing scale, disabled under reduce-motion (static orb).
3. **Title block** — track/session title + subtitle (phase pill / frequency / time) centered under the orb.
4. **Scrubber** — thin, refined progress bar with monospaced time labels (reuse `AudioScrubber`, restyle).
5. **Transport row** — back-15 · play/pause · forward-15. Play/pause becomes a refined solid teal circle (drop the heavy drop-shadowed gradient in favor of a cleaner filled circle + subtle glow). Reuse `PlayerTransportSection`.
6. **Secondary controls as pills** — replace the two stacked `GlassCard` slider sections with a single row of **expandable pill toggles**: Light Sync, Volume, Light level (only the ones valid for the mode). Tapping a pill expands its slider inline (single-row control revealed under the pill row), so the resting state is calm and one control is visible at a time. Reuse the existing binding logic from `PlayerVolumeSection` / `PlayerBrightnessSection` / `PlayerLightSyncButton`.

### Optional follow-on (not in first pass)
Tap the orb to drop into a full-screen "ambient immersion" mode (Direction B), hiding chrome except a minimal bar. Deferred; call out as a stretch.

### Files
- `UnifiedPlayerView.swift` — recompose `controlsOverlay` / `bottomControls` for the hero layout.
- New: `PlayerHeroOrb.swift` — the reactive orb visual (driven by `engine.brightness`, `isPlaying`, reduce-motion).
- New: `PlayerSecondaryControls.swift` — the expandable pill row wrapping the existing volume/brightness/light-sync bindings.
- Light touch: `PlayerTransportSection.swift` (refine play/pause), `PlayerScrubberSection.swift` (thin styling).
- Leave `PlayerVolumeSection`/`PlayerBrightnessSection` as the inner slider bodies the pills reveal (or inline equivalent).

---

## 2. Reader — "Refined minimal + phase-aware depth" (Blend A + B)

`TextTrancePlayerView`. Keep it control-free by default (protects the trance); elevate atmosphere and add a subtle sense of progress.

### Keep exactly as-is
Control-free default with auto-hiding controls; tap/swipe to reveal; **long-press (1.2s) to exit**; pause-on-background; the `AnchoredWord` pivot-letter (teal) RSVP mechanic; breath/drift word fades.

### Additions / refinements
1. **Phase-aware atmosphere** — the background radial glow color follows the current segment phase (induction → `phaseIntro`/blue, deepening → `phaseDeepener`/violet, suggestion → `phaseSuggestion`, emergence/awakening → warm), crossfading slowly on phase change. Replaces the single fixed-teal pulse. Subtle, low-opacity; disabled/flattened under reduce-motion.
2. **Gentle word glow** — a soft shadow/glow on the current word (very low intensity), removed under reduce-motion. Keeps legibility first.
3. **Thin progress line** — a whisper-thin progress indicator (word index / total) near the bottom edge. Always faintly present (so there's always a sense of "how far in"), brightening slightly while controls are visible. It's an indicator, not an interactive scrubber.
4. **Refined control capsule** — restyle `ReaderControlPanel` into a floating glass capsule (rounded, `.ultraThinMaterial`, tighter rhythm) — same contents (speed slider + WPM, End · Pause/Play · Settings).
5. **Settings drawer cohesion** — tint `ReaderSettingsDrawer`'s `Form` to the void background (`scrollContentBackground(.hidden)` + `bgPrimary`) to match the reader (same fix already applied to the audio-library filters sheet).

### Files
- `TextTrancePlayerView.swift` — phase-aware background, word glow, progress line, wire phase→color.
- `ReaderControlPanel.swift` — capsule restyle.
- `ReaderSettingsDrawer.swift` — void background tint.
- Possibly a small helper mapping `phase → Color`.

---

## Verification
- `xcodebuild ... build` clean (iPhone 17 destination).
- Live on the iPhone 17 simulator: audio/light player (inject/import a file), session player, flash mode (regression), and the reader (drive Read → script → Begin) — screenshot each and confirm no regressions, reduce-motion behavior, and that all controls still function.

## Non-goals
- No changes to playback/light-engine/pacing logic.
- No new features beyond the visual layout (the tap-to-immersive mode is a deferred stretch).
- Flash/color-pulse immersive modes keep their current full-screen behavior.
