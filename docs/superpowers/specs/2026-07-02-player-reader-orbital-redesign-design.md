# Player & reader orbital redesign — design spec

Date: 2026-07-02
Scope: structural redesign of the audio/light player (`UnifiedPlayerView`) and the Text Trance reader (`TextTrancePlayerView`).
Relationship to prior work: goes beyond the 2026-06-30 visual-elevation spec (hero orb, pills, phase atmosphere — all shipped in e4ad5db). This round changes the **layout skeleton** itself. The driving complaint: the player's bottom stack (scrubber + transport + pills + toggles) still reads as a utility panel.

Approved direction (validated via visual mockups): **orbital command cluster + whisper scrub line**, one control grammar shared by both screens.

## Design principles

- The light/word is the stage; controls are a floating command cluster and small satellites, never stacked panels.
- Resting chrome is minimal and calm; richer controls bloom on demand and melt away.
- One grammar everywhere: solid-teal action button, ghost ring buttons, satellite icons, bloom slider capsules, whisper progress line.
- No feature removal — every existing control relocates, nothing disappears.
- Reduce-motion honored; compositor-friendly animation only (opacity/scale/transform); dark-only design tokens (`TranceColors` etc.), no raw system colors.

---

## 1. Shared control grammar (new components)

Small focused files, used by both screens:

### `ScrubWhisperLine`
Evolves the reader's private `ReaderProgressLine` into a shared, interactive component. Three states:
- **whisper** — 2 pt, faint (default; always present when the mode has finite progress)
- **prominent** — slightly brighter while controls are visible
- **scrubbing** — thickens to ~6 pt under touch; a floating info overlay appears above it; drag repositions full-width

API sketch: `ScrubWhisperLine(fraction:, tint:, prominent:, onScrub: (Double) -> Void, onScrubEnd: (Double) -> Void, overlay: (Double) -> some View)`. The overlay closure renders the floating readout (player: monospaced `12:34 / 30:00`; reader: phase name + `word 412 / 890`). The reader's line keeps its phase-gradient tint. Accessibility: exposes an adjustable action (increment/decrement seeks by a step) since the visual target is too small for VoiceOver.

### `BloomSliderCapsule`
The floating glass slider capsule that blooms above the satellite row (icon + track + value label). Driven by a generic `Binding<Double>` + formatting closure. Only one bloom open at a time (owned by the satellite row state). Appears/disappears with a short scale+opacity transition; instant under reduce-motion.

### `SatelliteButton` + shared button styles
- Satellite: 30–36 pt ghost circle, icon-only, `active` state tints teal. Always has an accessibility label.
- Shared styles for the command cluster: **solid teal circular action button** (play/pause; pause in reader) and **ghost ring buttons** (±15 s, End, Settings), replacing the current heavier styles. Extracted so player and reader render identically.

---

## 2. Player — `UnifiedPlayerView`

### Resting controls state (modes with finite duration: session, audioLight, playlist)
Top → bottom:
1. Top bar — unchanged contents (close · title/subtitle · minimize), ghosted styling.
2. Hero orb — existing `PlayerHeroOrb`.
3. Title block — title + subtitle (phase pill / frequency / remaining time).
4. Command cluster — ghost −15 s · solid play/pause · ghost +15 s (restyled `PlayerTransportSection`).
5. Satellite row — icon-only satellites replacing the pill row: ◐ light sync, 🔊 volume, ☀ light level (only those valid for the mode), ··· overflow.
6. Whisper line — `ScrubWhisperLine` pinned at the bottom edge.

Removed from the resting layout: `PlayerScrubberSection` (bar), `PlayerSecondaryControls` (labeled pills), the `GlassCard` SYNC OPTIONS block, inline smart-transitions toggle, inline track-list button. All relocate (below).

### Satellite behavior
- Tapping a slider satellite (volume, light level) blooms its `BloomSliderCapsule` above the row; tapping elsewhere or re-tapping dismisses. One open at a time.
- ◐ light sync stays a toggle (with the existing photosensitivity warning flow on first enable).
- ··· opens a compact overflow sheet (`PlayerOverflowSheet`, presentation detent ~medium) containing the mode extras, reusing existing section views/bindings: sync options (session+audio), bilateral/binaural (flash), smart transitions + track list (playlist).

### Seeking
`ScrubWhisperLine` drag calls the view model's existing seek path (same code the old scrubber used). While scrubbing, the floating monospaced time shows current/total; satellites fade out; release commits the seek. Playlist scrubbing stays within the current track. Scrubbing while paused stays paused.

### Flash / color-pulse modes
Keep their full-screen light visuals and current auto-hide behavior. They have no finite duration → **no whisper line, no time readout**. Their revealed controls adopt the same grammar: command cluster (play/pause solid; no skip buttons) + satellites (🔊 volume where applicable, ··· overflow with bilateral/binaural). No stacked panels anywhere.

### Unchanged
Auto-hide `PlayerControlsVisibility` behavior, minimal overlay, pause/countdown/safety overlays, session lock, mini-player dismissal, track-list sheet contents, all view-model logic.

---

## 3. Reader — `TextTrancePlayerView`

### Resting state — untouched
Word on its anchor, phase-aware atmosphere, whisper line, long-press (1.2 s) exit, auto-pause on background, tap/swipe reveal. No changes.

### Revealed state
`ReaderControlPanel` (capsule with always-visible speed slider) is replaced by:
1. Command cluster — ghost ✕ End · solid pause/play · ghost ⚙ Settings.
2. Satellite row — ⚡ speed (blooms the live WPM slider capsule, same binding as today's slider, formatted "142 wpm"), ◐ light toggle, 〰 binaural toggle (the live-settings controls from `ReaderSettingsDrawer`'s quick section).
3. Whisper line brightens (prominent state).

The word stays visible (dimmed) behind the controls. Auto-hide timing unchanged. `ReaderSettingsDrawer` sheet remains for deep settings (arc, subliminal, post-handoff, …).

### Script scrubbing (the one new capability)
The whisper line becomes a script scrubber:
- `TextTranceSession` gains `seek(toWordIndex:)`: pauses word ticking, repositions the cursor (clamped to `0..<wordCount`), and resumes from that index on scrub release (or stays paused if the session was paused). Reuses the same word-index machinery as `begin(from:)` / resume snapshots — the word sequence is settings-invariant, so an index is a stable position.
- While scrubbing, the overlay shows the **phase name** at the target index + `word N / total`. The line's gradient is tinted by the phases it crosses.
- Word fade/breath state resets cleanly on reposition (snap to opacity 1, no stale animations).
- Post-handoff (light-only tail) has no word index → line becomes display-only there.

---

## 4. Edge cases & accessibility

- **Reduce-motion**: blooms and line-thickening appear without animation; orb static (already handled); no motion-only information.
- **VoiceOver**: every satellite labeled; cluster buttons labeled (existing); `ScrubWhisperLine` exposes adjustable actions (player: ±15 s; reader: ±1 sentence or ~10 words).
- **One-bloom invariant**: opening a bloom closes any other; revealing/hiding controls closes blooms.
- **Warnings preserved**: light-sync photosensitivity alert, safety warning overlay, session lock — untouched.
- **Analytics**: existing screen/start/complete events unchanged; no new events required.

## 5. Testing & verification

Unit (Swift Testing):
- `TextTranceSession.seek(toWordIndex:)` — clamping, phase at index, resume-from-index, paused-stays-paused, snapshot consistency, post-handoff no-op.
- Bloom exclusivity state (extract as small observable if needed for testability).
- Player seek fraction→time mapping incl. playlist current-track bounds.

Live verification (iPhone 17 simulator): audio/light player, session player, playlist, flash + color-pulse (regression — controls grammar, no line), reader (reveal, speed bloom, scrub-and-resume), reduce-motion pass. Screenshot each.

Build: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build` clean.

## 6. Non-goals

- No playback / light-engine / pacing logic changes beyond `seek(toWordIndex:)`.
- No full-screen immersion mode (still deferred).
- No changes to setup/entry screens, mini-player, or completion flows.
- Flash/color-pulse full-screen visuals unchanged.

## 7. Files

New: `ScrubWhisperLine.swift`, `BloomSliderCapsule.swift`, `SatelliteButton.swift` (incl. shared cluster button styles), `PlayerOverflowSheet.swift`.
Modified: `UnifiedPlayerView.swift`, `PlayerTransportSection.swift`, `TextTrance/TextTrancePlayerView.swift`, `TextTrance/TextTranceSession.swift` (seek).
Retired (deleted once replacements land): `TextTrance/ReaderControlPanel.swift`, `PlayerSecondaryControls.swift`, `PlayerScrubberSection.swift` — their bindings/logic move into the new satellite row and cluster.
Tests: `IlumionateTests/` additions per §5.
