# Text Trance — RSVP Trance-Reading Feature Design

**Date:** 2026-06-10
**Status:** Approved (brainstorm complete, pending implementation plan)
**Inspiration:** Readrrr's RSVP focus-reading, recast as a trance-induction modality for LumeSync.

---

## 1. Concept

A dedicated **Text Trance** screen where AI-generated hypnosis scripts flash word-by-word at a fixed point (RSVP), layered over the app's existing light entrainment and binaural beats. Reading becomes the induction vehicle: attention fixates on the word stream while light and sound entrain underneath.

The user composes a session from three layers:

| Layer | Status | Source |
|---|---|---|
| Light pulse | exists | `FlashController` (Mind Machine engine) |
| Binaural beats | exists | Mind Machine binaural engine |
| Reading text | **new** | This feature |

User-selectable combinations: reading only (silent), beats only, reading + beats — light pulse available under all of them.

## 2. Decisions Log

| Question | Decision |
|---|---|
| Text/audio relationship | Composable layers, user picks per session (not either/or modes) |
| Script sourcing | **Hybrid**: vetted bundled library in v1; live AI generation in a later milestone (UI placeholder ships greyed-out in v1) |
| Text presentation | **RSVP word stream** (steady cuts) as base; **entrainment-lock** mode (word opacity pulses with light frequency) as experimental, settings-gated option |
| Focus anchoring | **ORP pivot letter**: each word aligned so its pivot letter sits at a fixed anchor, tinted with the Trance accent color; optional tick marks fade as session deepens |
| Placement | **Dedicated screen/tab** ("Text Trance"), not a Mind Machine mode and not a session-player track |
| Session arc | **Per-session user choice**: `fullText` (eyes-open start to finish, including read emergence) or `handoff` (text inducts → eyes close → light/binaural carry the remainder; non-visual emergence) |
| v1 themes | All four: relaxation, sleep, focus, self-suggestion (self-suggestion gets heaviest content review) |
| Architecture | **Structured script + runtime pacing engine** (approach 2): scripts are plain-text phase segments; timing computed at runtime |

## 3. Architecture

New components (pink) and reused components (green) from the approved diagram:

```
TranceScript (model, JSON)          CorpusGenerator (tool, existing)
        │  loads/validates                │ gains script-output mode
        ▼                                 ▼
TranceScriptLibrary (loader)  ◄── bundled resources + (later) AI output
        │  selected script + options (arc, layers, speed)
        ▼
TextTranceSession (@Observable @MainActor coordinator)
        │ drives
        ├──► TextPacingEngine (new, pure logic)
        ├──► FlashController (existing: bg pulse, post-handoff light, shared clock)
        └──► Binaural engine (existing, optional layer)
        │ renders
        ▼
TextTranceView (new screen) + Trance UI kit + photosensitivity safety (existing)
```

**Key boundary:** `TextPacingEngine` knows nothing about UI or script content. Input: (words, phase, settings, clock). Output: timed word events. Fully unit-testable, same philosophy as the light engine.

### Component responsibilities

- **`TranceScript`** — Codable model for the JSON schema (§4). Carries metadata + ordered phase segments.
- **`TranceScriptLibrary`** — discovers bundled scripts, validates schema, exposes by theme/arc. Mirrors the `LightScoreReader` pattern: malformed files are excluded with a log, never crash the picker.
- **`TextTranceSession`** — owns the running session: phase progression, arc handling, layer lifecycle (start/stop text, light, binaural), emergence signaling, sleep-theme self-termination.
- **`TextPacingEngine`** — computes per-word display timing: `baseWPM (per phase) × deepening curve × user speed multiplier`. Sentence-ending punctuation gets a hold pause (~2.5× word duration). Computes ORP pivot index per word. In entrainment-lock mode, emits opacity modulation sampled from the shared flash clock — **pivot letter excluded** (the fixation point never flickers; only surrounding letters pulse).
- **`TextTranceView`** — library picker → setup → player. Player is control-free: fixed-point ORP word display over a dim pulsing background, thin phase rail as the only progress cue, tap-and-hold to end (borrows session lock pattern).

## 4. Script JSON Format

```json
{
  "schemaVersion": 1,
  "id": "deep-drift-01",
  "title": "Deep Drift",
  "theme": "relaxation",
  "supportedArcs": ["fullText", "handoff"],
  "language": "en",
  "source": { "kind": "bundled", "generator": "corpus-gen 1.4", "reviewed": true },
  "segments": [
    { "phase": "induction",  "text": "Allow your eyes to rest softly…", "pacing": { "baseWPM": 140 } },
    { "phase": "deepening",  "text": "Deeper and deeper with every word…", "pacing": { "baseWPM": 100 } },
    { "phase": "suggestions", "text": "You find calm easily now…", "pacing": { "baseWPM": 85 } },
    { "phase": "emergence",  "text": "In a moment you will return…", "pacing": { "baseWPM": 130 }, "arcs": ["fullText"] },
    { "phase": "transitional", "text": "And now… let your eyes gently close…", "pacing": { "baseWPM": 85 }, "arcs": ["handoff"], "triggersHandoff": true }
  ]
}
```

Schema decisions:
- **Phases** are `TrancePhase` raw values from CorpusKit (e.g. `induction` / `deepening` / `suggestions` / `emergence` / `transitional`). There is **no** new `handoffCue` phase — the eyes-close cue is a `transitional` segment tagged `arcs: ["handoff"]` with `triggersHandoff: true`. (Note the raw value is `suggestions`, plural.)
- **Arc-conditional segments** (`arcs:`) let one file serve both arcs — emergence plays only in `fullText`; the eyes-close cue plays only in `handoff`.
- **`pacing.baseWPM` is a hint**, never a hard timing — the engine multiplies it by the deepening curve and user speed.
- **`source.reviewed`** flags human-vetted content; surfaced as a "reviewed" badge in the library UI.

## 5. Runtime Data Flow

1. User picks script + options (arc, layers, speed). `TextTranceSession` filters segments by arc, tokenizes into words, starts chosen layers.
2. `TextPacingEngine` walks the word list, emitting `(word, pivotIndex, displayDuration, opacityCurve)` events.
3. View renders each word with its pivot letter aligned to the fixed anchor; background pulse runs off `FlashController` at low intensity.
4. **Handoff arc:** after the `triggersHandoff` segment, text fades out, `FlashController` ramps to the session's target frequency, binaural continues if enabled, duration timer runs the remainder. Emergence = light frequency ramp-up + optional chime — no text.
5. **Sleep theme + handoff:** no emergence — light fades to black, audio fades, session self-terminates.

### ORP pivot rule

Standard ORP indexing: 1-letter word → 1st letter; 2–5 letters → 2nd; 6–9 → 3rd; 10+ → 4th. Pivot tinted with Trance accent color.

## 6. UI Flow (approved wireframes)

1. **Library** — theme filter chips (All / Relax / Sleep / Focus / Suggest); script cards show title, theme, estimated read time, supported-arc chips, reviewed badge. Greyed-out "Generate new script…" card reserves the AI milestone's place.
2. **Setup** — arc segmented control ("Read → eyes close" / "Read everything"); layer toggles (light pulse, binaural [headphones note], entrainment-lock [experimental label]); reading speed (Slow / Natural / Brisk — curve multipliers, not raw WPM); post-handoff duration + emergence style.
3. **Player** — no visible controls. Fixed-point ORP word over radial pulsing field. Thin phase-rail progress. Tap-and-hold to end. Tick marks fade once past induction.

## 7. Error Handling

- Malformed bundled scripts: excluded at load with a log (LightScoreReader posture).
- Script not supporting the chosen arc: that arc simply isn't offered in setup.
- Binaural start failure (no headphone route): session continues without it; quiet notice.
- Entrainment-lock mode: gated behind existing photosensitivity validation; cannot activate if the session's light parameters fail safety checks.

## 8. Safety & Content Review

- Entrainment-lock text mode is **experimental and settings-gated** until tested for comfort/photosensitivity; subject to the existing max-frequency and rapid-change validation.
- All bundled scripts are human-reviewed before shipping (`source.reviewed: true`). Self-suggestion themed scripts get the strictest review.
- `fullText`-eligible segments must contain no eyes-closure phrasing ("close your eyes" etc.) — enforced by a regression test.
- Sleep scripts using `handoff` end without emergence by design; all other arcs must include an emergence path.

## 9. Testing Strategy

| Target | Approach |
|---|---|
| `TextPacingEngine` | Deep unit coverage: timing math, deepening curve, punctuation holds, arc filtering, ORP pivot indexing, entrainment-lock phase alignment vs mock clock |
| `TranceScriptLibrary` | Schema validation, malformed-file exclusion, theme/arc filtering |
| `TextTranceSession` | Integration tests for arc transitions (text → handoff → light-only → emergence) with accelerated time |
| Bundled scripts | Corpus-style regression tests: parses, covers required phases, no eyes-closure phrasing in `fullText` segments, WPM hints in sane range |
| Entrainment-lock | Photosensitivity validation tests before the mode can activate |

## 10. Read Tab as Unified Reading Hub (added 2026-06-11)

The Read tab is the single home for everything Text Trance:

- **Bundled scripts** we author and review (this spec's core).
- **External script discovery** via the **Reading Sources** companion feature: a curated directory of external sites (public-domain libraries, script directories) plus user-added URL bookmarks. **Strictly link-only** — opens sites in the external browser; never fetches, scrapes, parses, caches, or redistributes third-party text. Already implemented in a parallel session; see `docs/superpowers/handoffs/2026-06-11-reading-sources-handoff.md` for the model (`ReadingSource`, `ReadingSourceStore`, `ReadingSourceDirectoryView`), policy constraints (no `adultOnly` sources by default, HTTP/HTTPS-only, duplicate rejection), and the production-readiness gates (curated-source audit, App Store compliance, accessibility, expanded tests).
- **Session controls** (reading speed, binaural audio, light/flash settings) — in the per-session Setup screen reached from this tab.

Reading Sources keeps its Library-tab entry point and gains a second entry point inside the Read tab's library screen ("Find more scripts online"). Importing external text into the RSVP reader is a **separate future milestone** that requires its own rights/import design and compliance review (handoff §10) — M1 ships link-only.

## 11. Milestones

1. **M1 — Core engine + bundled library**: `TranceScript` schema, library loader, pacing engine (RSVP + ORP), Text Trance screens, fullText + handoff arcs, light/binaural layer integration, initial hand-reviewed script set (all four themes, authored via CorpusGenerator offline). **Part B (after core):** commit + review the existing Reading Sources work and surface it from the Read tab (plan Part B, Tasks B1–B3).
2. **M2 — Entrainment-lock mode**: settings-gated, safety-validated, user comfort testing.
3. **M3 — AI generation**: in-app script generation (CorpusGenerator pipeline → on-device or API), personalization input, un-grey the library card. Generated scripts marked `reviewed: false` with appropriate UI treatment.
4. **M4 — External text import (design-gated)**: explicit user action, per-source rights validation, terms reminder, local-only storage; requires its own approved spec per the handoff's §10 release gate.

## 12. Out of Scope (for now)

- Folding text tracks into the `LightSession` schema (approach 3) — revisit after the feature proves itself.
- Narrated-audio caption sync (`WordTimestamp`-driven "trance karaoke") — the engine's event model doesn't preclude it, but it's not in this feature.
- Non-English scripts.
- Fetching/parsing/caching any third-party website text (Reading Sources stays link-only until M4 has an approved spec).
- Adult-only content sources — excluded from the curated catalog until there is a content policy, age gating, and an App Store review strategy.
