# Reader Hypnotic Visuals — Design

**Date:** 2026-08-01
**Status:** Approved, ready for implementation planning
**Surface:** TextTrance reader (`Ilumionate/TextTrance/`)

## Goal

Give the RSVP reader animated hypnotic backgrounds with a user-adjustable opacity,
without ever compromising the legibility of the word being read.

Reference for the visual vocabulary: `https://hypno.nimja.com/visual` — a catalogue of
150+ effects (spirals, tunnels, moiré, particles, waves). We are deliberately not
matching its breadth.

## Context

The reader is an **RSVP player**: one word at a time, its pivot letter anchored to a
fixed horizontal centre ([`TextTrancePlayerView`](../../../Ilumionate/TextTrance/TextTrancePlayerView.swift),
`AnchoredWord`). Two consequences shape the whole design:

1. Only a small, **fixed** region of the screen ever holds text, so a local readability
   guard is cheap and reliable.
2. There is a per-word timer running. Anything on screen competes with it for frame
   budget.

Today's background stack, back to front:

| Layer | Source |
| --- | --- |
| Flat theme colour | `displayPrefs.adjustedBackground` |
| Phase-tinted radial glow, 4s breath cycle | `RadialGradient` + `backgroundPulse` |
| Word | `wordLayer` / `AnchoredWord` |
| Controls, scrub line | `ReaderControlCluster`, `ScrubWhisperLine` |

`ReaderDisplayPreferences` already owns theme, `backgroundBrightness`, `fontScale`,
`colorMode`, and friends, and already decodes newer fields with `decodeIfPresent`
so older stored preferences keep loading. `TextTrancePlayerView` already reads
`accessibilityReduceMotion` and already maps reading phase to colour via `phaseColor`.

## Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Library size | **Curated: 4 effects + none + breath** | Each effect gets hand-tuned and perf-checked. A broad catalogue would need a data-driven effect system and would leave most effects barely tuned. |
| Phase behaviour | **Chosen shape stays fixed; phase modulates tint, speed, amplitude only** | User correction during review: the visual should shift *slightly* with phase, not swap. Removes all cross-fade/transition machinery. |
| Readability guard | **Centre fade, computed in the renderer** | Theme-agnostic (no dark scrim to invert on Paper/Sepia/Dawn), no extra compositing layer, no muddy blob. Works because the word's anchor is fixed. |
| Safety | **Capped by construction; freeze on Reduce Motion** | No effect can strobe, so no consent gate is needed in a reading surface. |
| Renderer | **Metal fragment shaders via SwiftUI `.colorEffect`** | Chosen for visual ceiling — true moiré interference and smooth gradients beat stroked lines. Accepted trade-off: shaders are not unit-testable and this is the project's first Metal code. See Risks. |

### Renderer trade-off, recorded

`TimelineView` + `Canvas` was recommended instead, because it matches existing patterns
(`AuroraBackground`, `LumeOrb`, `PlayerBackgrounds`), keeps geometry as pure testable Swift,
and needs no `#if os`. Metal was chosen anyway for output quality. The cost is real and is
mitigated, not eliminated:

- Shader source cannot be unit-tested → coverage comes from the parameter layer (§3).
- `ShaderLibrary` name and uniform mismatches fail at **runtime**, not build time →
  identical uniform list across all four effects, and a feasibility spike first.

## Architecture

```
ReaderDisplayPreferences          visual: ReaderVisual, visualOpacity: Double
        │                         (persisted, back-compat decoded)
        ▼
ReaderVisualModulator             pure: (phase, speedMultiplier, reduceMotion)
        │                               → ReaderVisualModulation
        │                         ← all safety caps enforced here
        ▼
ReaderVisualLayer                 SwiftUI: TimelineView + Rectangle.colorEffect
        │
        ▼
ReaderVisuals.metal               4 × [[stitchable]] half4, each × centreFade()
```

### 1 · Data model

```swift
enum ReaderVisual: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, breath, spiral, tunnel, moire, drift

    var id: String { rawValue }
    var displayName: String            // "None", "Breath", "Spiral", …
    var shaderName: String?            // nil for .none and .breath
}
```

Added to `ReaderDisplayPreferences`:

```swift
var visual: ReaderVisual = .breath
var visualOpacity: Double = 0.35

static let visualOpacityRange: ClosedRange<Double> = 0.05...0.85
var clampedVisualOpacity: Double     // mirrors clampedBackgroundBrightness
```

Both decoded with `decodeIfPresent`, following the precedent set by `colorMode`.

**The default is `.breath`** — a name for the phase glow that already exists. Existing
readers see no visual change until they opt in, and `.breath` keeps rendering the current
`RadialGradient` rather than going through a shader.

### 2 · Effect roster

| Case | Look | Shader |
| --- | --- | --- |
| `.none` | Flat theme colour only | — |
| `.breath` | Today's phase-tinted radial glow, 4s cycle | — (existing `RadialGradient`) |
| `.spiral` | Rotating Archimedean arms | `readerSpiral` |
| `.tunnel` | Concentric rings falling inward; depth without rotation | `readerTunnel` |
| `.moire` | Two offset ring sets interfering; slow shimmer | `readerMoire` |
| `.drift` | Particles on a slow vortex; calmest option | `readerDrift` |

### 3 · Phase modulation — the testable core

```swift
struct ReaderVisualModulation: Equatable, Sendable {
    let tint: Color        // from the existing phaseColor mapping
    let speed: Double      // clamped to the safe band
    let amplitude: Double  // density / intensity, 0…1
}

enum ReaderVisualModulator {
    static func modulation(for phase: TrancePhase,
                           speedMultiplier: Double,
                           reduceMotion: Bool) -> ReaderVisualModulation
}
```

`TrancePhase` is the CorpusKit enum already used by `TextTranceSession.currentPhase`
(12 cases including `.transitional`). `speedMultiplier` is the session's existing
property — the session exposes no WPM value.

Behaviour:

- **Tint** reuses the same phase→colour mapping as `phaseColor`, so the background and
  the word's glow always agree. This requires a small refactor: `phaseColor` is currently
  a private computed property on `TextTrancePlayerView`. It moves to a shared
  `TrancePhase` extension (or alongside the modulator) and the player view calls that,
  so there is exactly one phase→colour table.
- **Speed** scales gently with `speedMultiplier` and with phase depth (deepening and
  fractionation slightly faster than pre-talk), then is clamped to the safe band.
- **Amplitude** rises through induction → deepening, easing back for emergence.
- `reduceMotion == true` forces `speed == 0`, which is the signal the view layer uses
  to stop redrawing entirely.

**All safety limits live in this function, not in the shader**, so they are unit-testable:

```swift
static let speedBand: ClosedRange<Double> = 0.05...0.45
```

`speed` is a **normalised scalar**, not a physical rate — each shader defines what it
means for its own geometry (revolutions/sec for `.spiral`, ring crossings/sec for
`.tunnel`, and so on). The band is chosen so that at the upper bound, every effect's
slowest-moving repeating feature crosses any fixed pixel **below 3 Hz**. That invariant
is a property of each shader's constants, so it is recorded as a comment beside each
effect's period constant and re-checked during the visual verification pass — the unit
test can only assert that `speed` never leaves the band.

### 4 · Shader layer

`Ilumionate/TextTrance/Visuals/ReaderVisuals.metal` — one `[[stitchable]] half4` function
per effect, with a shared helper that makes the readability guard intrinsic:

```metal
static half centreFade(float2 pos, float2 size) {
    float2 d = (pos - size * 0.5) / (size * 0.5);
    d.y /= 0.46;                                 // elliptical, word-shaped
    return half(smoothstep(0.35, 1.0, length(d)));
}
```

Every effect multiplies its alpha by `centreFade(...)`. The word's protection is therefore
one line per effect rather than a compositing layer, and it cannot be forgotten without the
effect visibly bleeding into the text.

Uniform list, **identical across all four** to avoid runtime mismatch:

```
float2 size, float time, float3 tint, float speed, float amplitude
```

### 5 · SwiftUI wrapper

```swift
struct ReaderVisualLayer: View {
    let visual: ReaderVisual
    let modulation: ReaderVisualModulation
    let opacity: Double

    var body: some View {
        if let name = visual.shaderName {
            TimelineView(.animation(paused: modulation.speed == 0)) { timeline in
                Rectangle()
                    .foregroundStyle(.black)
                    .colorEffect(shader(name, at: timeline.date))
            }
            .opacity(opacity)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}
```

`paused:` is the whole Reduce Motion story: the schedule stops firing, so the shader is
evaluated once and never again. That is an accessibility win and a battery win with no
separate code path.

Insertion into `TextTrancePlayerView.body`, between the flat background and the word:

```
displayPrefs.adjustedBackground
ReaderVisualLayer(...)              ← new; renders nothing for .none / .breath
RadialGradient (breath)             ← unchanged; still gated on showsPhaseAtmosphere
wordLayer
controls / scrub line
```

### 6 · Settings UI

`ReaderSettingsDrawer` gains a **Visual** section:

- A labelled chip row over `ReaderVisual.allCases`, reusing the drawer's existing chip idiom.
- An opacity slider bound to `visualOpacity`, shown only when `visual != .none`.

No preview thumbnails. The drawer is a sheet presented over the live player, so the chosen
effect is already animating behind it while the slider moves — the real thing beats a
thumbnail and costs nothing.

## Error handling

- **Missing or renamed shader function.** `ShaderLibrary` resolves lazily and fails at
  runtime. `ReaderVisual.shaderName` is the single place names are written, and the
  `ReaderVisualTests` case-coverage test asserts every shader-backed case has one. A
  failed lookup renders nothing, which degrades to the flat theme background rather
  than crashing or showing a black screen.
- **Legacy preferences.** Absent `visual` / `visualOpacity` keys decode to `.breath` / `0.35`.
  Covered by test.
- **Out-of-range opacity** (hand-edited or from a future build) clamps via
  `clampedVisualOpacity` rather than being trusted.

## Testing

| Suite | Covers |
| --- | --- |
| `ReaderVisualModulatorTests` | phase→tint mapping; speed always within the safe band for every `TrancePhase` × extreme `speedMultiplier`; `reduceMotion` ⇒ speed 0; amplitude monotonic through the arc |
| `ReaderDisplayPreferencesTests` | new fields round-trip; legacy JSON lacking both keys decodes to `.breath`/0.35; opacity clamps at both bounds |
| `ReaderVisualTests` | every case has a non-empty `displayName`; shader-backed cases have a `shaderName`; `.none`/`.breath` do not |

Swift Testing (`@Test`/`#expect`), matching the project's existing suites.

**Not unit-tested:** the shader source itself. Verification is visual, on the iOS simulator
and the native macOS build, against a checklist: legibility of the word at 0.85 opacity for
each effect and each of the six themes; no visible seam at the centre-fade boundary; Reduce
Motion produces a still frame.

## Files

New:

```
Ilumionate/TextTrance/Visuals/ReaderVisual.swift             ~60
Ilumionate/TextTrance/Visuals/ReaderVisualModulation.swift   ~90
Ilumionate/TextTrance/Visuals/ReaderVisualLayer.swift        ~80
Ilumionate/TextTrance/Visuals/ReaderVisuals.metal           ~140
IlumionateTests/ReaderVisualModulatorTests.swift             ~90
IlumionateTests/ReaderVisualTests.swift                      ~40
```

Modified:

```
Ilumionate/TextTrance/ReaderDisplayPreferences.swift     +~15
Ilumionate/TextTrance/TextTrancePlayerView.swift          +~8
Ilumionate/TextTrance/ReaderSettingsDrawer.swift         +~40
IlumionateTests/…ReaderDisplayPreferences coverage       +~30
```

All well inside the 200–400 line norm and nowhere near the 800-line cap.

## Risks

1. **First `.metal` file in the project** — highest risk, and the reason for step 1 below.
   No Metal source, `import Metal`, or `ShaderLibrary` usage exists today. Xcode's
   file-system-synchronized groups *should* compile a `.metal` file into the default
   library automatically, but if they do not, the failure is a silent runtime lookup miss.
2. **Two shipping platforms.** `.colorEffect` is supported on both, but the project builds
   native macOS as a first-class destination, so the spike must pass on both.
3. **Frame budget.** Shaders should be effectively free, but the reader runs a per-word
   timer; the spike measures rather than assumes.

**Mitigation — the plan's first step is a throwaway spike**: one trivial shader
(a solid colour that varies with `time`), rendered via `.colorEffect`, confirmed on the
iOS simulator *and* the native macOS build, before any effect is written. If it fails, fall
back to `TimelineView` + `Canvas`, which changes §4 and §5 but leaves §1–§3, §6 and the
whole test plan intact.

## Out of scope

- Effects beyond the six listed. The roster is deliberately closed.
- Strobe, flicker, or any effect needing a photosensitivity consent gate.
- Reader-visual settings syncing to the audio player's light modes.
- Per-script saved visual choices. Visual lives in `ReaderDisplayPreferences`, which
  `ReaderPresetStore` already persists per script as a side effect — no new mechanism.
