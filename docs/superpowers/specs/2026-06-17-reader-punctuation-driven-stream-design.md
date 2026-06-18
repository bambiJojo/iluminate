# Reader: Punctuation-Driven Word Stream — Design

**Date:** 2026-06-17
**Status:** Approved (pending spec review)
**Feature area:** Text Trance RSVP reader (`Ilumionate/TextTrance/`)

## Summary

Rework the Text Trance reader so that **punctuation is removed from the displayed
glyphs and promoted into control signals** for word timing and motion. Three new
behaviors become the reader's baseline, plus an opt-in subliminal layer:

1. **Strip punctuation from display** — words render as clean glyphs (`drop`, not
   `drop.`). This also stabilizes the ORP pivot, which today drifts when trailing
   marks are attached.
2. **Hyphen split** — hyphenated compounds (`deeper-and-deeper`, `half-asleep`)
   split into separate short words instead of one over-long token that overflows
   the anchor.
3. **Punctuation → timing + motion** — trailing marks become pauses and
   breath-fades (comma = brief pause, em-dash = medium, period/!/? = long hold +
   fade, ellipsis = longest drift + slow fade).
4. **Subliminal fast-flash (opt-in)** — selected words blink past far faster than
   the rest. Authored `[[word]]` marks take priority; if a script has none, a
   built-in suggestion-word lexicon is auto-applied. Toggleable on/off with an
   adjustable speed, both set before reading.

This is a **deterministic, pure transform** with no AI and no new dependencies. It
lives almost entirely in `WordTokenizer` + `TextPacingEngine`, with a small opacity
change in `TextTrancePlayerView` and new setup controls.

## Goals

- Cleaner, more legible word stream (no trailing marks, no over-long compounds).
- More hypnotic pacing driven by the script's natural punctuation.
- An optional subliminal-suggestion layer that authors can target precisely or
  get automatically.
- Preserve the existing `PacedWord.startTime` / `duration` timeline contract so
  word-sizing (`TextTranceWordSizing`) and existing tests keep working.

## Non-Goals (captured as follow-on)

- **Feature 2 — Text-analyzed "trance score."** Analyzing the script to *generate*
  a synchronized score that drives the flashing background light and the macro
  pacing curve (reusing `HypnosisPhaseAnalyzer` / `SessionGenerator` / the
  `LightScore*` stack). This is a separate, larger generative feature with its own
  open questions (which analysis signals drive it, on-device AI cost/latency, how
  the flashing background composes with the reader's current post-handoff-only
  light layer, and how analysis-derived base pacing stacks with the punctuation
  pacing defined here). It slots cleanly *beneath* this feature: punctuation
  timing is a per-word multiplier that an analysis-driven base pace can sit under.
  **Documented here; specced separately later.**

## Current State (what we're changing)

- `WordTokenizer.tokenize` splits on whitespace, keeps punctuation glued to the
  word, and flags `endsSentence` from the last character.
- `WordToken` = `{ text, endsSentence }`.
- `TextPacingEngine.schedule` produces `PacedWord { text, pivotIndex, phase,
  startTime, duration }`; the only timing rule beyond base WPM is a `2.5×` hold on
  sentence-enders (`sentenceHoldMultiplier`).
- `TextTranceSession.begin` loops the schedule, setting `currentWord` /
  `currentPivotIndex` / `currentPhase` and sleeping each `duration`.
- `TextTrancePlayerView.AnchoredWord` renders each character, tinting the pivot.
- `TextTranceSetupView` configures arc / layers / reading speed and builds
  `TextTranceSessionSettings`.

## Design

### 1. Token model

`WordToken` grows from `{ text, endsSentence }` to carry display-only text plus
the two derived control signals:

```swift
struct WordToken: Equatable, Sendable {
    let text: String          // display glyphs only — punctuation stripped
    let pause: PauseKind      // derived from trailing punctuation
    let isSubliminal: Bool    // fast-flash this word
}

enum PauseKind: Equatable, Sendable {
    case none     // no trailing pause
    case brief    // , ; :
    case medium   // — (em-dash)
    case breath   // . ! ?   → long hold + fade
    case drift    // …       → longest hold + slow fade
}
```

### 2. Tokenizer pipeline (`WordTokenizer`)

Per segment text, in order:

1. **Parse authored subliminal marks `[[ … ]]` first.** A mark may wrap a single
   word (`[[relax]]`) or a phrase spanning whitespace (`[[let go]]`). Record which
   words are subliminal, then strip the `[[` / `]]` delimiters from the text.
2. **Split on whitespace** into raw tokens.
3. **Split each token on internal hyphen `-` and em-dash `—`** into sub-words.
   Trailing punctuation rides the **last** sub-word. An em-dash split additionally
   assigns a `medium` pause to the **preceding** sub-word.
4. **Strip trailing punctuation** (`. , ! ? ; : … " ' ) ]`) from the display text
   and classify the removed mark into a `PauseKind`.
5. **Preserve internal punctuation** — keep apostrophes in contractions /
   possessives (`you're`, `don't`, `mind's`) and internal periods in numerics
   (`3.5`). Strip surrounding quotes (`"word"` → `word`).
6. **Drop empty tokens** — a token that is empty after stripping (pure
   punctuation, or a standalone `—`) is removed, and its `PauseKind` is **merged
   into the preceding word** (taking the longer of the two pauses).

> The tokenizer no longer exposes `endsSentence`; `PauseKind.breath`/`.drift`
> supersede it.

### 3. Pacing (`TextPacingEngine`)

`PacedWord` gains a fade flag and a subliminal flag:

```swift
struct PacedWord: Equatable, Sendable {
    let text: String
    let pivotIndex: Int
    let phase: TrancePhase
    let startTime: TimeInterval
    let duration: TimeInterval
    let fade: FadeKind        // .none / .breath / .drift
    let isSubliminal: Bool
}

enum FadeKind: Equatable, Sendable { case none, breath, drift }
```

`PauseKind` maps to a hold multiplier on the segment's base duration; subliminal
words use a fixed flash duration from settings instead:

| Source            | Hold multiplier            | Fade           |
|-------------------|----------------------------|----------------|
| `.none`           | 1.0×                       | none           |
| `.brief`          | 1.6×                       | none           |
| `.medium`         | 2.2×                       | none           |
| `.breath`         | 3.0×                       | `.breath`      |
| `.drift`          | 4.5×                       | `.drift`       |
| subliminal word   | fixed `flashDuration`      | none           |

Constants (replacing the single `sentenceHoldMultiplier = 2.5`):

```swift
static let briefHoldMultiplier  = 1.6
static let mediumHoldMultiplier = 2.2
static let breathHoldMultiplier = 3.0
static let driftHoldMultiplier  = 4.5
```

**Fade timing is baked inside the word's `duration`** (a visible-hold portion
followed by a fade-out portion), so the cumulative `startTime` timeline stays
consistent and word-sizing/tests are unaffected. The split between visible hold
and fade-out is a view-side rendering constant (see §5), not a schedule change.

**Subliminal precedence (script-level, two passes in `schedule`):**

1. Tokenize all playing segments.
2. If **any** token is subliminal from an authored `[[ … ]]` mark → use only those.
3. If the script has **zero** authored marks → apply the **lexicon fallback**:
   flag any token whose lowercased display text is in the suggestion-word set.

If the subliminal feature is toggled **off** in settings, skip subliminal flagging
entirely (all words pace normally; pauses/fades still apply).

### 4. Subliminal lexicon

A built-in starter set of suggestion / "power" words (case-insensitive), tunable
later:

```
deeper, relax, sleep, now, drift, calm, down, heavy, let, go,
breathe, release, still, sink, deep, rest, soften, surrender
```

Matching is per-token on the cleaned display text. (Phrases like "let go" match as
the individual words `let` and `go`.)

### 5. Rendering (`TextTrancePlayerView`)

- **Subliminal words look identical** to normal words — same font, same pivot
  tint. Only the duration differs.
- **Opacity reset:** on every new word, opacity is set to `1` **without
  animation** so a fast flash never inherits an in-progress fade.
- **Breath/drift fade:** when the current word's `fade` is `.breath` or `.drift`,
  the view displays it, holds, then animates opacity → 0 over the latter part of
  the word's `duration` (drift fades slower than breath). The next word's opacity
  reset brings it back to full instantly.

The session loop (`TextTranceSession.begin`) is unchanged in structure: it sets
the current word fields and sleeps `duration`. It additionally publishes the
current word's `fade` so the view can drive the opacity animation.

### 6. Settings (`TextTranceSetupView` + settings types)

Add a **Subliminal** card to the setup screen:

- **Toggle** — "Subliminal suggestions" (default **on**).
- **Speed picker** (shown when on) — Gentle / **Medium** (default) / Deep,
  mapping to flash durations roughly `~120ms / ~90ms / ~65ms`. Lower = faster =
  less consciously legible.

Extend the settings types:

```swift
struct TextPacingSettings {
    enum SubliminalSpeed: String, CaseIterable, Sendable, Identifiable {
        case gentle, medium, deep
        var id: String { rawValue }
        var flashDuration: TimeInterval { /* 0.12 / 0.09 / 0.065 */ }
        var displayName: String { /* Gentle / Medium / Deep */ }
    }
    let arc: ScriptArc
    let speed: Speed
    let subliminalEnabled: Bool
    let subliminalSpeed: SubliminalSpeed
}
```

`TextTranceSessionSettings` carries `subliminalEnabled` + `subliminalSpeed`
through to `TextPacingEngine.schedule`.

> **Open at review:** this design makes punctuation-stripping, hyphen-split, and
> pause/fade the reader's new *baseline* (always on), and only the subliminal
> layer is user-toggleable. If a master off-switch for the entire feature is
> wanted, raise it at spec review.

## Data Flow

```
TranceScript.segments[].text
   └─ WordTokenizer.tokenize          → [WordToken]  (clean text + pause + subliminal)
        └─ (script-level subliminal resolution: authored marks ?: lexicon)
   └─ TextPacingEngine.schedule       → [PacedWord]  (+ duration, fade, isSubliminal)
        └─ TextTranceSession.begin    → publishes currentWord / pivot / phase / fade
             └─ TextTrancePlayerView.AnchoredWord  → renders glyphs + fade animation
```

## Testing (Swift Testing)

All core logic is pure functions → high-coverage unit tests, no UI tests needed.

**Tokenizer (`WordTokenizerTests`):**
- Trailing `. , ! ? ; :` stripped from display; correct `PauseKind` assigned.
- Ellipsis `…` and `...` → `.drift`.
- Hyphen split: `deeper-and-deeper` → three tokens; trailing punctuation rides the
  last (`half-asleep.` → `half`, `asleep` with `.breath`).
- Em-dash split assigns `.medium` to the preceding sub-word.
- Authored marks: `[[relax]]` → one subliminal token, marks stripped; `[[let go]]`
  → both words subliminal.
- Internal apostrophes/periods preserved (`you're`, `don't`, `3.5`); surrounding
  quotes stripped.
- Empty/pure-punctuation tokens dropped, pause merged into preceding word.

**Pacing (`TextPacingEngineTests`):**
- Each `PauseKind` produces the expected hold multiplier.
- `.breath`/`.drift` set the correct `FadeKind`.
- Subliminal words use the settings `flashDuration`; Gentle/Medium/Deep differ.
- Lexicon fallback gating: a script **with** `[[ … ]]` marks flags only those; a
  script **without** marks flags lexicon matches; subliminal **off** flags none.
- `startTime` remains the running cumulative sum of `duration` (timeline contract).

**Regression:** existing `TextTranceWordSizingTests` and session/decoding tests
still pass (clean display text changes the reference character count but the
derivation stays valid).

## Risks / Edge Cases

- **Abbreviations** (`Dr.`, `Mr.`) get a `.breath` pause + fade — acceptable; rare
  in hypnosis scripts. Documented, not handled specially.
- **Numerics** (`3.5`) keep the internal period (trailing-only stripping handles
  this); a number ending a sentence (`...by 3.`) correctly strips the trailing dot.
- **Authored marks in AI-generated scripts** — the generator can emit `[[ … ]]`
  later; not required for this feature (lexicon fallback covers unmarked scripts).
- **Very fast flashes vs. display refresh** — 65ms ≈ 2–4 frames at 60/120Hz;
  acceptable. Durations are wall-clock sleeps, not frame-locked.

## Files Touched

- `Ilumionate/TextTrance/WordTokenizer.swift` — new pipeline + `WordToken` /
  `PauseKind`.
- `Ilumionate/TextTrance/TextPacingEngine.swift` — `PacedWord` fields, pause→hold
  mapping, subliminal resolution, settings additions.
- `Ilumionate/TextTrance/TextTranceSession.swift` — publish `fade`; thread
  subliminal settings.
- `Ilumionate/TextTrance/TextTrancePlayerView.swift` — opacity reset + breath/drift
  fade animation.
- `Ilumionate/TextTrance/TextTranceSetupView.swift` — Subliminal card.
- Tests: `IlumionateTests/TextTrance/WordTokenizerTests.swift` (new),
  `TextPacingEngineTests.swift` (new/extended).
