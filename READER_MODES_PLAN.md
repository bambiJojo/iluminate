# Reader Modes — settings reorganisation plan

**Branch:** `feature/reader-hypnotic-visuals`
**Status:** proposed, not started
**Date:** 2026-08-04

## Problem

The reader's settings are one undifferentiated pile. Today:

| Surface | Top level | Behind "Advanced" |
|---|---|---|
| `TextTranceSetupView` | Script, Arc, Pacing preset, Visual | Layers *(light, binaural)*, Attention, Speed training *(6 controls)*, Reader display *(9 controls)*, Subliminal *(2)* |
| `ReaderSettingsDrawer` | *everything, flat — no split at all* | — |

Concretely wrong:

1. **Font size is two taps deep** ([TextTranceSetupView.swift:463](Ilumionate/TextTrance/TextTranceSetupView.swift:463)) — the most-reached-for control in any reader.
2. **Binaural beats is inside a card called "Layers" inside Advanced** — a headline feature under a label that means nothing to a user.
3. **The drawer has no basic/advanced split**, so mid-session you scroll past ramp-start WPM sliders to reach brightness. Worst possible ordering for the surface used while in trance.
4. **The two surfaces disagree** about what counts as advanced, because tiering is hardcoded separately in each.
5. **Advanced mixes everyday preferences with genuine tuning** — theme and font sit next to ramp-start WPM.

### The real cause

"Basic vs advanced" is the wrong axis. There are **two distinct reading modes**, and the settings only look chaotic because both modes' controls are shown at once:

- **Plain reading** — RSVP speed reading, word by word. A reading tool.
- **Hypnotic trance** — a scripted hypnosis experience.

The data model already encodes this, badly. Imported content is forced into the hypnosis script shape:

```swift
// WebReadableTextImporter.swift:80 and ReadingDocumentStore.swift:71
theme: .focus,                    // a hypnosis theme, for a PDF
supportedArcs: [.fullText],
segments: [TranceScriptSegment(
    phase: .induction,            // a news article, labelled an induction
```

So a Wikipedia page is modelled as a trance induction, and therefore gets offered arcs, binaural beats and subliminal flashing.

The honest distinction is already available in [TranceScript.swift:46](Ilumionate/TextTrance/TranceScript.swift:46):

```swift
enum Kind { case bundled, generated, importedWeb, importedDocument }
```

## Decisions

Settled during design:

| Question | Decision |
|---|---|
| One reader or two? | **One reader.** Mode reconfigures it; the library stays unified. |
| Mode derived or chosen? | **Derived from `ScriptSource.Kind`, with a per-script override.** Right by default, never a trap. |
| Visuals in plain reading? | **Always toggleable.** Mode must never remove the visual picker. |
| What does mode affect? | **The settings hierarchy only.** The rendering surface is untouched. |

That last decision is deliberately narrow. `ReaderVisual` already has a `.none` case and `showsPhaseAtmosphere` already keys off the user's theme, so both are under user control today. Mode does not get to override either.

## Target structure

### Shared by both modes

**Main**
- Reading comfort — reader mode (light/dark), font, size
- Visual
- Attention

**Advanced**
- Display detail — line spacing, highlight colour, background brightness, hide controls, dyslexia-friendly
- Speed detail — speed mode, warm-up WPM, ramp-start WPM, words per flash, punctuation pauses

### Plain reading only

**Main**
- Speed — target WPM, exposed as a number

**Absent:** Arc, Binaural, Subliminal, Light handoff

### Hypnotic trance only

**Main**
- Arc
- Pacing preset
- Binaural

**Advanced**
- Subliminal
- Light pulse after handoff *(already conditional on `arc == .handoff`)*

### Why this works

Advanced shrinks because roughly half the settings genuinely don't apply to the mode you're in — not because of a judgement call about what's "advanced."

Speed lands in its right home in both modes. **In plain reading, WPM is the point** — it's a speed-reader, so the number goes top-level. In trance it stays tuning underneath the named pacing preset. Same underlying `ReaderSpeedTrainingSettings.targetWPM`, two honest presentations.

Binaural stops being a buried "Layer" and becomes a headline control — but only in the mode where it means anything.

## Implementation

### 1. `ReaderMode`

New file `Ilumionate/TextTrance/ReaderMode.swift`:

```swift
enum ReaderMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case reading
    case trance

    /// Default for a script, from how the content arrived. Imported articles and
    /// documents are things you read; bundled and generated scripts are trance.
    static func derived(from source: ScriptSource) -> ReaderMode {
        switch source.kind {
        case .importedWeb, .importedDocument: .reading
        case .bundled, .generated:            .trance
        }
    }
}
```

### 2. Single source of truth for tiering

New `ReaderSettingsCatalog` describing, for each settings group, which modes show it and at which tier. Both surfaces read this instead of hardcoding their own arrangement — the same centralising move already made by `LightSafety` and `ReaderPacingPreset`, and what stops the two surfaces drifting apart again.

```swift
enum ReaderSettingsGroup: CaseIterable {
    case readingComfort, visual, attention
    case speedTarget, arc, pacingPreset, binaural
    case displayDetail, speedDetail, subliminal, lightHandoff

    func tier(in mode: ReaderMode) -> ReaderSettingsTier?   // nil == absent
}
```

### 3. Persist the override

Add `mode: ReaderMode?` to `ReaderPreset` ([ReaderPresetStore.swift](Ilumionate/TextTrance/ReaderPresetStore.swift)). `nil` means "use the derived value"; a non-nil value is an explicit user override for that script only. Follow the existing `decodeIfPresent` migration pattern from `ReaderDisplayPreferences` so presets saved before this field still load.

### 4. Rewire the two surfaces

- **`TextTranceSetupView`** — group cards by tier from the catalog; retire the "Layers" card, splitting binaural into its own main-tier control and leaving light with the handoff group.
- **`ReaderSettingsDrawer`** — add the matching Advanced disclosure it currently lacks, driven by the same catalog.

`TextTranceSetupView` is already 560+ lines; the card structs should move to their own files while this work is happening, per the 800-line guidance in the coding-style rules.

### 5. Mode switcher

A single control in setup showing the derived mode with the option to override. Not in the drawer — switching mode mid-session would reshuffle the surface underneath someone who is, by design, in trance.

## Testing

- `ReaderMode.derived(from:)` for all four `ScriptSource.Kind` cases
- `ReaderSettingsGroup.tier(in:)` — every group in both modes, asserting the absent set
- `ReaderPreset` round-trips with `mode` nil and non-nil
- A preset JSON saved *before* `mode` existed still decodes
- Existing `ReaderQuickStartPlanTests` and `ReaderProgressStoreTests` still pass

## Out of scope

Flagged, deliberately not fixed here:

- **Imported content is modelled as `.induction`.** A real data-modelling problem — it makes imported documents inherit induction-phase atmosphere colour. Cosmetic today because both the visual and the atmosphere are user-toggleable, and because `effectiveBaseWPM` prefers the importer's explicit `baseWPM: 150` over the depth-derived slowdown. Worth its own fix.
- **The macOS test destination is broken** — `IlumionateTests` crashes with `signal abrt` before the runner connects, on a clean tree. CLAUDE.md lists macOS as a first-class test destination.
- **Five unrelated iOS test failures** — `slowFileTransferDoesNotBlockMainActor`, `savingLargeLibraryDoesNotBlockMainActor`, `idleTimerHides`, `closingDrawerReArmsTimer`, `keepsWhisperPrefetchOutOfContentAnalysis`. All main-actor/timing tests taking 35–54s each; reads like simulator load rather than real regressions.
