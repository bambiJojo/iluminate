# Create Tab: Visual Field — Design

**Date:** 2026-08-05
**Status:** Approved, ready for planning
**Branch:** `feature/reader-hypnotic-visuals`

## Problem

Two problems, one surface.

**The Create tab has drifted.** `MindMachineView.swift` is 698 lines holding a model,
eight subviews, a hand-rolled slider and a drawn phone illustration. Every control that
decides what kind of session you get — visual mode, intensity, colour temperature,
waveform, binaural — is buried inside a single `AdvancedControlsSection` disclosure that
is collapsed by default. Meanwhile the reader and the player were rebuilt around a
different grammar: 72pt `PlayerControlTile` targets, drag for continuous values with a
haptic tick, a slot list that never reflows. Create never got that treatment.

**There is no wordless visual session.** The reader's shader backgrounds — spiral,
tunnel, moiré, drift, glass, linescape — only exist underneath moving words, modulated by
reading phase and pace. There is no way to run the field on its own and no way to
control it directly.

## What we are building

A restructured Create tab whose four session kinds sit in a segmented row above a live
preview and a tile tray, plus a new wordless **Visual Field** session driven by the
reader's existing shaders under direct user control.

### Decisions taken during design

| Question | Decision |
|---|---|
| What is the user doing? | Staring at it as the whole experience; optionally with audio playing |
| How deep does customisation go? | Effect, colour, speed, strength — plus direction. No presets, no evolution arcs |
| Tab structure | One screen, mode first. Not a hub with a push |
| What rides along | Both binaural *and* an optional library track |
| How it ends | Open-ended by default, optional timer |
| Colour control | Named palette plus a custom chip, with a luminance floor |
| Code sharing | Promote the reader's visual system to a shared module |

Explicitly **out of scope**: saved/named presets, per-session evolution arcs (a visual
that deepens over ten minutes), gradient/two-colour tints, layering two effects, and
audio-reactive visuals. Each is a reasonable follow-on; none is needed to ship this.

## Architecture

### 1. Promote the visual system to a shared module

`TextTrance/Visuals/` moves to top-level `Visuals/`, with types renamed to admit both
callers:

| Today | After |
|---|---|
| `ReaderVisual` | `TranceVisual` |
| `ReaderVisualLayer` | `VisualFieldLayer` |
| `ReaderVisualModulation` | `VisualModulation` |
| `ReaderVisualModulator` | `ReadingVisualModulator` |
| `ReaderVisuals.metal` | `TranceVisuals.metal` |

`ReaderVisualStrength` and `ReaderVisualControls` stay under `TextTrance/` — they are
reader-surface concerns, not renderer concerns.

**Why not the smaller diff.** Leaving the stack under `TextTrance/` and importing
`Reader*` types from the Create tab was considered and rejected: `ReaderVisualControls`
opens with a comment about being "the ONE place the reader's background-visual settings
are expressed", written after the visual picker drifted onto one surface and not the
other. A second consumer under `TextTrance/` recreates that condition. Forking a
Create-specific shader stack was also rejected — it means two copies of the
photosensitivity ceiling, and the copy is what rots.

**The rename is safe but not free.** `TranceVisual` must keep its exact `String` raw
values (`"none"`, `"breath"`, `"spiral"`, `"tunnel"`, `"moire"`, `"drift"`, `"glass"`,
`"linescape"`). `ReaderDisplayPreferences.visual` persists them, and `ReaderPresetStore`
decodes every script's preset as one `[String: ReaderPreset]` blob — a raw-value change
silently wipes every saved reader preference for every script. `ReaderVisualTests.rawValues()`
already pins the array and is the guard on this; it survives the rename apart from the
type name. Metal function names (`readerSpiral`, `readerTunnel`, …) also stay unchanged,
because `shaderNames()` pins them to literals and `ShaderLibrary` resolves at runtime —
a typo is a blank background, not a build error.

### 2. Two producers, one modulation struct

`VisualModulation` (tint, speed, amplitude) is unchanged, including both safety bands
(`speedBand` 0.05…0.45, `amplitudeBand` 0.25…1.0). It gains a second producer:

- `ReadingVisualModulator.modulation(for:speedMultiplier:reduceMotion:)` — unchanged,
  phase-driven, for the reader.
- `VisualFieldSettings.modulation(reduceMotion:)` — new, direct-driven, for Create.

```swift
struct VisualFieldSettings: Codable, Equatable, Sendable {
    var visual: TranceVisual        // default .spiral
    var tint: VisualTint            // palette case or .custom(hex)
    var speed: Double               // normalised 0…1, mapped into speedBand
    var amplitude: Double           // normalised 0…1, mapped into amplitudeBand
    var direction: VisualDirection  // .inward | .outward
    var opacity: Double             // strength, clamped to visualOpacityRange
    var duration: TimeInterval?     // nil == open-ended
}
```

`visualOpacityRange` (0.05…0.85) currently lives on `ReaderDisplayPreferences` but is the
same kind of thing as `speedBand` and `amplitudeBand` — an appearance/safety band on the
renderer, not a reader preference. It moves into the shared module alongside them, and
the four reader call sites (`ReaderDisplayPreferences.clampedVisualOpacity`,
`ReaderVisualStrength` ×2, `ReaderVisualControls`) update to the new home. The value does
not change, so no persisted preference shifts.

Speed and amplitude are stored **normalised 0…1** and mapped into the bands when the
modulation is produced. This makes the photosensitivity cap unbypassable from the
settings layer: a user at "100% speed" gets `speedBand.upperBound` (0.45), the same
ceiling the reader's deepest phase reaches — not an unbounded value.

### 3. Direction

`VisualDirection` is a new field on `VisualModulation`, carried to Metal as the **sign of
the `rate` argument**. The shared phase rule in `TranceVisuals.metal` already reads:

```
phase = convergentDepth(r, turns) * density - time * speed * rate
```

A negative `rate` reverses convergence with no new uniform and no per-effect work.

`TranceVisual.motionRate` stays **unsigned**, so `peakCrossingHz` and
`everyEffectStaysUnderTheFlickerCeiling` keep measuring magnitude and need no edit. The
sign is applied at the layer boundary when the shader argument is built. The reader
always passes `.inward`, preserving its documented "pull focus to the word" rule; only
the wordless field, which has no word to converge on, can pass `.outward`.

### 4. The focus well

Every effect ends with `alpha = ... * focusWell(pos, size)`. `focusWell` erases the
effect where the word sits — "a still, dark well the converging field falls into", and
the reason the reader needs no scrim overlay.

Wordless, that well punches a dark hole to protect a word that is not there, and removes
the compressed vanishing point that makes an inward spiral hypnotic. So the shared
uniform list gains a `focus` float, applied as:

```metal
mix(1.0h, focusWell(pos, size), focus)
```

The reader passes `1.0` and is pixel-identical to today. The visual field passes `0.0`
and gets an unbroken centre. This stays internal — it is not a seventh knob.

Safe on the aliasing front: `ringBand` already dissolves to flat tone where features
compress past the pixel grid, which is what keeps an un-welled centre from beating
against it.

### 5. Colour

`VisualTint` is an enum with six named cases mapping to existing palette colours
(`phaseInduction`, `phaseDeepener`, `roseGold`, `warmAccent`, `bwAlpha`, `bwTheta`), plus
`.custom(String)` holding a hex.

Resolution to a `Color` applies a **luminance floor**: `tint` multiplies the shader
output, so a very dark pick does not produce a moody field, it produces a black
rectangle. A pick below the floor is lifted, not rejected.

## The Create tab

`MindMachineView.swift` is split into a `Create/` folder, following the player's shape:

```
Create/
  CreateView.swift          the screen: mode row, preview, tray, start bar
  CreateSessionKind.swift   .flash | .colourPulse | .bilateral | .visualField
  CreateControlSlot.swift   which tiles each kind shows  (mirrors PlayerControlSlot)
  CreateFieldPreview.swift  the live preview panel
  LightFieldSettings.swift  frequency / intensity / kelvin / pattern / binaural
```

Top to bottom: segmented `CreateSessionKind` row → live preview → tile tray → start bar.
`MindMachineStartBar` and `AuroraBackground` stay.

### The tray

`CreateControlSlot.slots(for:)` takes **only** a `CreateSessionKind` and nothing else, so
no value change can add or remove a tile and the tray cannot reflow under a finger
mid-drag. This mirrors `PlayerControlSlot.slots(for:)` and its stated reasoning. Tiles
are the same 72pt `PlayerControlTile` with gauge fills.

| Kind | Tiles |
|---|---|
| Visual field | Effect · Colour · Speed · Strength · Direction · Duration |
| Flash | Frequency · Intensity · Warmth · Waveform · Binaural · Duration |
| Colour pulse | Frequency · Intensity · Duration |
| Bilateral | Frequency · Intensity · Warmth · Waveform · Binaural · Duration |

Six tiles lay out as two rows of three. Effect, Waveform, Direction and Duration are
tap-to-advance. Speed, Strength, Frequency, Intensity and Warmth are drags.

Colour taps to open a palette sheet carrying the six swatches and the custom chip — it
does **not** cycle on tap with a long-press for the grid. `PlayerControlTile` states that
a tile "is either tappable or draggable, never both, which keeps gesture arbitration out
of the picture entirely"; adding a third gesture to one tile would reintroduce exactly
that. A sheet also gives the custom picker somewhere to live.

### Deletions

- `AdvancedControlsSection` — burial was the problem; every control it hid now has a tile.
- `PhoneScreenOrb` — a drawn phone illustrating the effect is strictly worse than the effect.
- `CustomSlider` — nothing in the new tray uses it; tiles own their drag handling.
- `BrowseSessionsLink` **moves to Library** — it is a browsing affordance in a making surface.

### The preview

Live and real. For `.visualField` it is `VisualFieldLayer` rendering the actual settings
inside a rounded rect — the same shader the session will run, at the same modulation. For
the light kinds it is a `LumeOrb`-style pulse at the configured frequency and warmth.

Two constraints: it renders at the configured *strength*, so what you see is what you
get; and it holds to the same flicker ceiling as the session, because a preview is a
small light flashing at you for as long as you sit on the screen.

### Analytics

`CreateMode` and `MindMachineMode` each gain a `visualField` case. Existing
`createModeSelected` and `mindMachineStartRequested` calls carry it unchanged otherwise.

## Session runtime

### Player mode

```swift
case visualField(
    settings: VisualFieldSettings,
    audioFile: AudioFile?,
    binaural: BinauralSettings?
)
```

`id` is `"visualField-" + UUID()`, matching `flashMode`. `title` is "Visual Field".

`BinauralSettings` is new — a small `Equatable, Sendable` struct of `enabled`, `carrier`,
`volume`. `flashMode` currently carries those three as loose parameters; it is **not**
changed here. Folding it in is a tidy follow-on, but it touches every `flashMode` call
site and none of that work serves this feature.

Capability flags: `hasAudioScrubber` and `hasVolumeControl` are both `audioFile != nil`.
`hasBrightnessControl` is `false` — strength is the visual's own knob, not screen
brightness.

### In-session tray

`PlayerControlSlot` gains `.visualStrength` and `.visualSpeed`, both draggable, so the
field can be tuned while running without ending the session — the affordance the reader's
tray already gives. `slots(for: .visualField)` returns `[.visualStrength, .visualSpeed]`,
plus `.volume` when there is a track and `.more` when binaural is on. Still a fixed list
per mode, so the no-reflow rule holds.

### Audio

Binaural reuses `BinauralBeatsEngine` exactly as `flashMode` does. A library track reuses
the `audioLight` playback path minus the light-sync generation — the visual field is not
driven by the audio, it plays underneath. Both are independently optional, and silence is
a valid configured state, not an unconfigured one.

### Duration

`settings.duration == nil` runs open-ended. When set, the field fades its strength to
zero over the final 20 seconds and then dismisses, so a timed session ends by receding
rather than cutting to black. Reuses `flashMode`'s existing `goalDuration` machinery
rather than adding a second timer.

### Screen sleep

`PlatformApplication`'s idle-timer wrapper is already gated on
`AppSettingsManager.keepScreenAwakeDuringSessions`. `.visualField` opts in on the same
terms as every other mode. On macOS the window-filling cover behaves as the reader's does.

### Safety

**No flash warning gate for `.visualField`.** `PlayerSafetyWarningView` exists for the
entrainment path and `LightSafety` governs that path's frequency cap; neither applies
here, because the visual field never drives `FlashController` or `LightEngine`. Its worst
case is moiré at 2.7 Hz peak crossing, below the 3 Hz threshold — which is exactly why
the reader ships these effects without a warning today. Keeping the warning tied to the
flash path preserves its meaning; showing it everywhere teaches people to dismiss it. The
three light kinds gate exactly as they do now.

### Reduce Motion

`VisualFieldLayer` already stops the `TimelineView` schedule when speed is zero, so a
Reduce Motion user gets a static field rather than a frozen animation loop. Correct — but
in the reader the visual is decoration and here it *is* the content, so the Create screen
shows a line under the preview stating that motion is reduced by a system setting, rather
than leaving someone dragging a Speed tile that does nothing.

### Platforms

All shared code. `#if os(...)` appears only where it already does: the idle timer and the
full-screen cover presentation.

## Persistence

`VisualFieldStore` — `@MainActor @Observable`, JSON in `UserDefaults` — holds the
last-used `VisualFieldSettings` so reopening Create restores what you had. It decodes
field-by-field with `decodeIfPresent` and per-field defaults, copying
`ReaderDisplayPreferences.init(from:)` for the reason stated in that file: a single
unreadable field must degrade to its default, never discard the whole blob.

Light-kind settings persist the same way, which they do not today — `MindMachineModel` is
`@State` and resets whenever you leave the tab.

## Failure behaviour

| Failure | Behaviour |
|---|---|
| Audio fails (missing file, decode error, interruption) | Session continues; the field is the content and audio must never take it down. Non-blocking notice in the tray; volume tile goes `.disabled` |
| Corrupt persisted settings | Per-field fallback to defaults |
| Unparseable custom hex | Resolves to the default palette tint, never clear or black |
| Missing shader | Blank background, not a crash — `ShaderLibrary` resolves at runtime; `shaderNames()` pins every name |

## Testing

New suites, all pure-value so they run on both destinations:

- **`VisualFieldSettingsTests`** — normalised speed/amplitude map into `speedBand` /
  `amplitudeBand` and stay inside them for hostile inputs (negative, > 1, NaN). This is
  the test that makes the cap unbypassable from the settings layer.
- **`VisualDirectionTests`** — inward and outward produce opposite-signed rate with
  identical magnitude, so the flicker ceiling holds in both directions.
- **`VisualTintTests`** — the luminance floor lifts dark picks; palette cases resolve to
  expected colours; malformed hex falls back.
- **`VisualFieldFadeTests`** — the timed-ending fade as a pure function of
  elapsed/duration/configured-strength, kept out of the view in the same spirit as
  `ReaderVisualStrength` and `DragValueMapper`.
- **`CreateControlSlotTests`** — `slots(for:)` is a pure function of kind; each kind's
  list is pinned. Mirrors `ReaderControlSlotTests`.
- **`VisualFieldStoreTests`** — decode fallback per field.

Extended: `PlayerControlSlot` gains `.visualField` coverage. The renamed
`TranceVisualTests` keeps `rawValues()` pinning the persisted strings — the guard on the
whole rename.

**Unchanged, deliberately:** `everyEffectStaysUnderTheFlickerCeiling`,
`moireHasTheLeastHeadroom`, and both modulator band tests. If the rename touches those
assertions, something has gone wrong.

Per `CLAUDE.md`, the suite runs on both destinations:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests
```

## Definition of done

1. The reader behaves identically to before the rename — same effects, same modulation,
   same saved preferences surviving an app relaunch.
2. Create shows four session kinds in a segmented row, each with a live preview and a
   fixed tile tray. No disclosure group.
3. A Visual Field session runs full-screen from Create with effect, colour, speed,
   strength and direction all under direct control, open-ended or timed.
4. Binaural and a library track can each independently ride along, and either failing
   leaves the field running.
5. Both destinations build; the full test suite passes on both.
