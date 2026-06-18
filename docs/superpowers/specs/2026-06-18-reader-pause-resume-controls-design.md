# Text Trance Reader — Pause, Resume, Live Settings & Speed Control

**Date:** 2026-06-18
**Status:** Approved design, ready for implementation planning
**Feature area:** `Ilumionate/TextTrance/` (RSVP hypnosis reader)

## Problem

The Text Trance reader is deliberately *control-free*: the player renders only the
word stream and the sole interaction is tap-and-hold to end
([`TextTrancePlayerView.swift`](../../../Ilumionate/TextTrance/TextTrancePlayerView.swift)).
The session runs a fixed, precomputed schedule with no notion of position
([`TextTranceSession.begin()`](../../../Ilumionate/TextTrance/TextTranceSession.swift) —
`for word in schedule { await sleep(word.duration) }`).

Consequences the user wants fixed:

1. **No pause.** You cannot stop and continue.
2. **No mid-session settings.** To change speed or layers you must end the session
   and reconfigure from the setup screen, which restarts from the beginning.
3. **Coarse speed.** Speed is a 3-way `Slow / Natural / Brisk` enum (0.75 / 1.0 / 1.35),
   chosen once before starting.
4. **No resume after closing.** Leaving the reader discards your place entirely.

## Goals

- In-player **pause / resume** that preserves position (including mid-word remaining time).
- **Live settings** changeable mid-session: speed, binaural beats, subliminal flashing,
  post-handoff light.
- **Finer speed control**: a continuous slider with a words-per-minute readout, used in
  both setup and session.
- **Resume after closing** the reader: relaunch a script and continue where you left off.

## Non-goals (explicitly out of scope)

- A live reader **mini-player** (continuous background reading while using other tabs).
  "Resume after close" means relaunching the reader at the saved position, not
  uninterrupted background playback.
- Position **scrubbing / skip** within a session (seek forward/back through the script).
  May be a future addition; the resumable-driver design below makes it tractable later.

## Key insight that shapes the design

In [`TextPacingEngine.schedule`](../../../Ilumionate/TextTrance/TextPacingEngine.swift),
**every token becomes exactly one `PacedWord` regardless of speed or subliminal settings.**
Pass 1 flattens all tokens of the playing segments into `pending`; pass 2 emits one
`PacedWord` per pending item. Subliminal settings only change a word's *duration*
(flash vs. normal) and *fade*; speed only scales `effectiveWPM`. Therefore:

> The word **sequence and count are invariant** across speed and subliminal changes.
> Word index *N* is always the same word.

This means a settings change never requires re-locating the reader's position. We
regenerate the schedule array (same length and order, new durations) and keep reading
from the same `currentWordIndex`. The only settings that would change the word *set* —
the **arc** — is fixed for the lifetime of a session and is not made live-editable.

## Architecture

Preserve the existing three-layer split:

| Layer | Role | Change |
|-------|------|--------|
| `TextPacingEngine` | Pure `script + settings → [PacedWord]` transform | Unchanged logic; now called more than once per session (on subliminal change). `speed: Speed` enum input becomes `speedMultiplier: Double`. |
| `TextTranceSession` | `@MainActor @Observable` coordinator | Gains a **resumable pacing driver**, live settings, pause/resume, and progress persistence. |
| `TextTrancePlayerView` | Renders state | Gains a control overlay that mirrors `UnifiedPlayerView` via the existing `PlayerControlsVisibility`. |

### Component 1 — Resumable pacing driver (`TextTranceSession`)

Replace the fire-and-forget `for` loop with an index-driven, interruptible driver.

State the session owns:

- `private(set) var currentWordIndex: Int`
- `var speedMultiplier: Double` (live; default 1.0, range 0.5…2.0)
- `private(set) var isPaused: Bool`
- the current base `schedule: [PacedWord]` (regenerated on subliminal change)

Driver shape:

```
index = startIndex
while index < schedule.count, !cancelled {
    await waitWhilePaused()                       // suspends while paused
    guard !cancelled else { break }
    let word = schedule[index]
    render(word)                                  // publish currentWord/pivot/phase/fade
    let hold = word.isSubliminal
        ? word.duration                           // flashes are NOT speed-scaled (engine parity)
        : word.duration / speedMultiplier         // readable words scale live with the slider
    let outcome = await holdInterruptibly(hold)   // wakes early on pause or cancel
    switch outcome {
    case .completed:  index += 1; currentWordIndex = index
    case .paused:     continue                     // re-hold the SAME word's remaining time on resume
    case .cancelled:  break
    }
}
```

- **Remaining-time tracking** uses an injectable clock (`ContinuousClock` by default). On
  pause mid-word, record elapsed; on resume, hold only the remainder so a long breath/drift
  word does not restart from zero.
- **Speed** applies live at the hold site for readable words; flash/subliminal durations stay
  fixed, matching today's engine where speed does not affect flashes. No schedule regen for speed.
- **Subliminal change** calls `TextPacingEngine.schedule` with the new subliminal settings,
  replaces `schedule`, and keeps `currentWordIndex` (sequence invariant). The currently
  displayed word's identity is unchanged; only future (and the current word's) durations differ.
- **Binaural / light** are layer toggles, not schedule inputs (see Component 4).
- **Testability:** the existing injected `sleep` plus a new injected clock make the driver
  deterministic under Swift Testing.

`begin(from startIndex: Int = 0)` lets the session start at a resumed position.

### Component 2 — Control surfacing (`TextTrancePlayerView`)

Mirror `UnifiedPlayerView` so the reader feels like the audio player:

- Reuse [`PlayerControlsVisibility`](../../../Ilumionate/PlayerControlsVisibility.swift):
  controls visible on entry, auto-hide after the idle delay, **tap or swipe-up reveals**,
  **swipe-down hides**, never auto-hides while the settings drawer is open (`isDrawerOpen`).
  Status bar hidden when controls are hidden.
- **Clean state:** just the anchored word stream (unchanged `AnchoredWord`).
- **Control panel** (fades in over the stream):
  - Pause / play transport button.
  - Speed slider + WPM readout (Component 3).
  - A **Settings** button opening the live-settings drawer (Component 4).
  - An explicit **End** affordance; **tap-and-hold-to-end is retained** as the existing gesture.
- **Pause overlay** when paused *and* controls hidden, mirroring
  [`PlayerPauseOverlay`](../../../Ilumionate/PlayerPauseOverlay.swift): a paused session
  reads as paused, tap brings controls back.

### Component 3 — Speed slider + WPM readout

- Replaces the setup screen's 3-way `SpeedCard` picker. The slider is the single source of
  truth in **both** setup and session.
- Range **0.5×–2.0×** (wider than the old 0.75–1.35). Default **1.0×** (Natural).
- Readout: **nominal WPM = `TextPacingEngine.defaultBaseWPM` (150) × multiplier**, shown as
  "~N wpm" (≈75–300). Honest given per-segment WPM varies; predictable to drag against.
- The old `Slow / Natural / Brisk` presets, if kept at all, become labeled anchor ticks on
  the slider — purely cosmetic, not the timing source.

### Component 4 — Live settings drawer

A sheet/drawer consistent with the existing track-list sheet pattern. Opening it sets
`controlsVisibility.isDrawerOpen = true` to suppress auto-hide. Contents and apply behavior:

| Setting | Apply behavior |
|---------|----------------|
| Binaural beats on/off | Start/stop `BinauralBeatsEngine` immediately; tied to play state. |
| Subliminal flashing on/off + flash speed | Regenerate base schedule via `TextPacingEngine`; preserve `currentWordIndex`. |
| Light pulse after handoff on/off | Affects only the post-handoff tail; applied when the tail begins. |

Pause is *not* required to open the drawer, but any schedule-affecting change takes effect at
the current/next word boundary.

### Component 5 — Resume-after-close persistence

**Model** (`Codable, Sendable`):

```
struct ReaderResumeState {
    let scriptId: String
    let wordIndex: Int
    let settings: PersistedReaderSettings   // arc, speedMultiplier, subliminalEnabled,
                                            // subliminalSpeed, binauralEnabled, lightEnabled,
                                            // beatFrequency
    let phase: ResumePhase                   // .reading | .handoffTail(elapsed:)
    let scriptContentHash: String            // guards against changed source text
    let savedAt: Date
}
```

**Store:** `ReaderProgressStore` (`@MainActor @Observable`), injectable, persisting a
`[scriptId: ReaderResumeState]` map as JSON in the application-support directory. Chosen over
`UserDefaults` deliberately — file storage is cleanly testable and avoids the `UserDefaults`
write race the project already encountered with `PlaylistStore`. Entries are pruned on
completion and expire after **30 days**, so the map cannot grow unbounded.

**Write points (owned by the session, not the view):** save a snapshot on pause, on app
background, and on dismiss-while-incomplete; **clear** the entry on completion. Keeping
persistence inside the session makes it unit-testable and keeps the view thin.

**Surfacing:** when a script's setup screen loads and a *valid* resume snapshot exists, the
primary button becomes **Resume** with a secondary **Start over**; otherwise **Begin** as
today. Resume launches the session with `begin(from: savedState.wordIndex)` and the saved
settings.

**Staleness guard:** the snapshot stores a content hash of the script text. On load, if the
hash no longer matches (likely for imported web reading sources whose text can change), or the
saved `wordIndex` is out of range, **discard the resume and start fresh** rather than jump to
a wrong position.

**Resume into the handoff tail:** if closed during the post-handoff light tail, resume restarts
the tail from its saved `elapsed` (the reading itself is already complete).

## Data flow

```
Setup screen ──(arc, speedMultiplier, layers)──▶ TextTranceSession.init
ReaderProgressStore ──(optional ReaderResumeState)──▶ begin(from: index)

TextTranceSession
  ├─ TextPacingEngine.schedule(...) ──▶ base schedule  (regenerated on subliminal change)
  ├─ pacing driver ──▶ currentWord / pivot / phase / fade ──▶ TextTrancePlayerView
  ├─ speedMultiplier (live) ──▶ readable-word hold scaling
  ├─ layer toggles ──▶ BinauralBeatsEngine / FlashController
  └─ snapshot on pause/background/dismiss ──▶ ReaderProgressStore  (cleared on completion)

PlayerControlsVisibility ──▶ control overlay visibility (tap/swipe/idle)
```

## Edge cases & error handling

- **Pause** halts word advance *and* the binaural layer; **resume** restores both.
- **Pause during the handoff tail** stops the tail countdown and the light; resume continues
  the remaining tail.
- **End** (tap-and-hold or End button) works from any state including paused: cancels the
  driver, stops all layers, dismisses.
- **Backgrounding** auto-pauses (so wall-clock time does not advance the reader unseen) and
  persists a snapshot; returning shows controls in the paused state.
- **Subliminal toggle** mid-word: current word keeps its identity; its remaining hold and all
  future holds use the regenerated durations.
- **Resume staleness:** content-hash mismatch or out-of-range index → discard and start fresh.
- **Empty / single-word scripts:** driver handles `schedule.count <= 1` without special-casing
  (loop bound covers it).

## Testing strategy

Swift Testing (`import Testing`), using the injected `sleep` + clock:

- **Driver:** pause holds index and re-holds only remaining time; resume advances; `end` while
  paused tears down layers; reaching the end sets `isComplete` and clears the resume entry.
- **Speed:** changing `speedMultiplier` alters readable-word holds but leaves flash durations
  unchanged.
- **Subliminal:** toggling regenerates the schedule yet preserves `currentWordIndex` and the
  current word's text/identity.
- **Engine invariant (the property this design relies on):** word *sequence and count* are
  identical across speed and subliminal settings for a given arc.
- **Persistence:** snapshot round-trips; expiry prunes >30-day entries; content-hash mismatch
  and out-of-range index are rejected; completion clears the entry.
- **WPM readout:** nominal WPM maps correctly from multiplier.

## Affected files (anticipated)

- `TextTranceSession.swift` — pacing driver, live settings, pause/resume, persistence hooks.
- `TextPacingEngine.swift` / `TextPacingSettings` — `speed: Speed` → `speedMultiplier: Double`.
- `TextTrancePlayerView.swift` — control overlay, pause overlay, gestures.
- `TextTranceSetupView.swift` — speed slider replaces `SpeedCard`; Resume / Start over / Begin.
- **New:** `ReaderProgressStore.swift`, `ReaderResumeState.swift` (+ `PersistedReaderSettings`).
- New control-panel / settings-drawer subviews (small focused `View` structs).
- Tests under `IlumionateTests/TextTrance/`.
