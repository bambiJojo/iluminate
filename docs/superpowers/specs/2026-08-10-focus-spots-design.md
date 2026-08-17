# Focus Spots — Design

**Date:** 2026-08-10
**Status:** Awaiting approval
**Surface:** `UnifiedPlayerView` light fields + `ProfileSettingsView` → Session Defaults

## Problem

The entrainment fields fill the whole screen with moving light and give the eye nothing to hold.
Users who want a fixation target — the "spot on the wall" of a classic eye-fixation induction, or a
convergence target for the bilateral split — have nowhere to rest their gaze.

Focus Spots adds an optional pair of opaque black circles rendered over the light field: holes
punched in the light, one aimed at each eye. Off by default. Position, diameter, and horizontal
spacing are user-adjustable, and are dialled in through a calibration screen rather than blind
sliders in a settings list.

## Scope

Focus Spots render over every mode that drives a **lit** field:

| Mode | Renders spots |
|---|---|
| `.flashMode` (Mind Machine) | Always |
| `.colorPulse` | Always |
| `.session`, `.playlist` | Only while `mindMachineEnabled` |
| `.audioLight` | Only while `lightSyncEnabled` |
| `.visualField` | Never |

The gate matters. With the mind machine off, `EntrainmentBackground` renders flat `Color.bgPrimary`
([`PlayerBackgrounds.swift:113`](../../../Ilumionate/PlayerBackgrounds.swift)) — black circles on a
flat dark surface would read as a rendering bug, not a feature. `.visualField` is excluded because
it is a composed shader scene, not a light field; two black holes would fight its composition.

## Two decisions taken from the existing code

### Render-time only, like `FlashTint`

`FlashTint` overrides the flash colour **at render time only**, leaving session JSON, `SessionGenerator`,
and the AI models untouched ([`FlashTint.swift:1`](../../../Ilumionate/FlashTint.swift)). Focus Spots
follows exactly that: a user-level display preference read by the view layer. Nothing enters
`LightSession`, `LightMoment`, or the session schema, and no generated session can specify spots.

### Two keys, not one blob

The codebase already mixes both shapes — `steadyLightEnabled` is a plain `@AppStorage` Bool, `flashTint`
is a JSON blob. Focus Spots uses **both**, deliberately:

- `focusSpotsEnabled` (Bool, default `false`) — binds directly to the settings toggle with no decode step.
- `focusSpots` (Data, JSON) — the geometry.

Keeping enablement out of the geometry struct avoids two sources of truth for the toggle's binding.

## Model

`FocusSpotSettings` — geometry only, `Codable, Equatable, Sendable`:

```swift
struct FocusSpotSettings: Codable, Equatable, Sendable {
    /// Fraction of field height where the spot centres sit. 0 = top, 1 = bottom.
    var verticalPosition: Double = 1.0 / 3.0
    /// Points between the two spot centres.
    var horizontalSpacing: Double = 180
    /// Points.
    var diameter: Double = 48
}
```

Ranges, enforced by the sliders and re-clamped on decode so a hand-edited or corrupted value can
never produce an unrenderable field:

| Value | Range | Default |
|---|---|---|
| `verticalPosition` | 0.1 – 0.9 | 1/3 (upper third) |
| `horizontalSpacing` | 40 – 400 pt | 180 pt |
| `diameter` | 16 – 120 pt | 48 pt |

**Why points for size and spacing, but a fraction for vertical position.** Diameter and spacing are
aimed at a physical thing — your eyes — so they should not rescale when the window does; a percentage
of width is a modest dot on an iPhone and a dinner plate on a Mac. Vertical position is inherently
proportional ("upper third" is a fraction, not a measurement), and a fraction keeps the spot in the
same relative place in portrait, landscape, and a resized Mac window.

Points are not a true physical constant across platforms — iPhone and iPad render ~163 pt/inch, a
Retina Mac closer to ~110, so a 48pt spot is roughly 7.5mm on a phone and ~11mm on a Mac display.
They are far more stable than a percentage of width, and calibration is per-device anyway.

**Reachable separation is bounded by the screen.** At ~163 pt/inch, a typical 63mm interpupillary
distance is ~404pt — wider than an iPhone in portrait (~393pt). True one-spot-per-eye separation is
only reachable in landscape, on iPad, or on a Mac. On an iPhone held at normal distance the pair is
a convergence target rather than literally one per eye. This is a reason the calibration screen is
the primary UI: the right numbers are the ones that look right on the device in hand.

### Persistence

`FocusSpotPreference`, mirroring `FlashTintPreference` ([`FlashTint.swift:52`](../../../Ilumionate/FlashTint.swift)):

- `current(defaults:) -> FocusSpotSettings` — returns `.default` for both an unset key and an
  undecodable value, then clamps every field into range.
- `set(_:defaults:)` — encodes, silently no-ops on encode failure.

`AppSettingsManager.Key` gains `focusSpotsEnabled` and `focusSpots`. `resetPreferences` sets the
Bool `false` and removes the blob. Not added to `ExportSettings` — `flashTint` and `steadyLightEnabled`
aren't there either, and widening the export snapshot is a separate decision.

## Geometry — `FocusSpotLayout`

A `nonisolated enum` with one pure function, testable without a view:

```swift
static func resolve(_ settings: FocusSpotSettings, in size: CGSize) -> Resolved?
```

`Resolved` carries `diameter: CGFloat`, `left: CGPoint`, `right: CGPoint`. Returns `nil` for an empty
or degenerate size.

Clamping, in order:

1. `diameter = min(settings.diameter, size.width / 2, size.height)` — two spots must always fit side
   by side, and one must always fit vertically.
2. `spacing = min(settings.horizontalSpacing, size.width - diameter)` — the outer edges stay inside
   the field. A Mac window narrowed to 300pt must not push spots off-screen.
3. `y = (settings.verticalPosition * size.height)`, clamped to `diameter/2 ... size.height - diameter/2`.
4. Centres at `(midX - spacing/2, y)` and `(midX + spacing/2, y)`.

In bilateral flash mode the field is an `HStack` of two halves; symmetric centres put exactly one
spot in each half for any spacing greater than zero, so bilateral needs no special case.

## Rendering — `FocusSpotOverlay`

A single view resolving its own geometry from the container:

- Two `Circle().fill(.black)` at the resolved centres — genuinely opaque, hard-edged. Holes in the
  light, as specified. SwiftUI antialiases the edge; no feather.
- `.ignoresSafeArea()` — the fields it sits on all do.
- `.allowsHitTesting(false)` — it must never intercept the pull-to-reveal drag that
  [`UnifiedPlayerView`](../../../Ilumionate/UnifiedPlayerView.swift) attaches to the minimal overlay.
- `.accessibilityHidden(true)` — decorative, and it conveys nothing to VoiceOver.
- Reads `@AppStorage("focusSpotsEnabled")` and `@AppStorage("focusSpots")` as raw `Data`, so editing
  the preference re-renders a live session — the same trick `FlashGridBackground` uses for the tint
  ([`PlayerBackgrounds.swift:47`](../../../Ilumionate/PlayerBackgrounds.swift)).
- Size comes from `.onGeometryChange(for: CGSize.self)`, not `GeometryReader`, matching how
  `UnifiedPlayerView` already measures its overlay.

### Placement in the player

One layer in `UnifiedPlayerView`'s ZStack, directly above `backgroundLayer` and below `SessionLockView`
([`UnifiedPlayerView.swift:52`](../../../Ilumionate/UnifiedPlayerView.swift)). Everything above it —
controls, threshold, pause, completion, safety warning — continues to draw over the spots, which is
correct: those surfaces are meant to be read.

Alternatives weighed:

| Approach | Verdict |
|---|---|
| **A. One overlay layer in `UnifiedPlayerView`** | **Chosen.** One render site for all four qualifying modes; the background views stay unaware of it. Costs an explicit "are the lights on?" gate. |
| **B. Spots drawn inside each background view** | Rejected. Three copies of the same code, and `SessionView` is shared with callers that should not grow a display preference. |
| **C. A `.focusSpots(active:)` view modifier** | Rejected. Buys nothing over A when a single ZStack already composes the layers. |

### Visibility gate — `FocusSpotVisibility`

`PlayerMode` gains a capability flag beside its existing ones
([`PlayerMode.swift:80`](../../../Ilumionate/PlayerMode.swift)):

```swift
var supportsFocusSpots: Bool  // false for .visualField, true otherwise
```

and a `nonisolated` pure function decides the rest, mirroring `PlayerControlTray.lightsAreOn`
([`PlayerControlTray.swift:34`](../../../Ilumionate/PlayerControlTray.swift)):

```swift
static func isVisible(
    mode: PlayerMode,
    isEnabled: Bool,
    mindMachineEnabled: Bool,
    lightSyncEnabled: Bool
) -> Bool
```

Pure and view-free, so every mode × lights-state combination is unit-testable — the same shape as
`MindMachineRetentionPolicy` and `PlayerControlSlot.slots(for:)`.

## Settings

In the **Session Defaults** card ([`ProfileSettingsView+Sections.swift:151`](../../../Ilumionate/ProfileSettingsView+Sections.swift)),
below Flash Colour:

- **Focus Spots** toggle (`settingsToggle`), with the description "Two dark spots to rest your eyes
  on, over the light field."
- **Calibrate…** row, shown only while the toggle is on, in the same style as the Flash Colour row.

Turning the toggle **on** immediately presents the calibration screen. Turning it off just turns it
off; the saved geometry is kept, so re-enabling restores the last calibration rather than the defaults.

## Calibration — `FocusSpotCalibrationView`

Presented with `platformFullScreenCover` ([`PlatformFullScreenCover.swift:20`](../../../Ilumionate/PlatformFullScreenCover.swift)),
so it covers the screen on iOS and fills the window on macOS.

**Background:** a **steady** lit field in the current Flash Colour — `FlashTintPreference.current().color(colorTemperature: 3000)`
at a fixed 0.6 opacity over black. Deliberately not strobing: a settings screen should not
flash, and a strobing preview would drag the photosensitivity warning into Settings.

**Foreground:** the live spots, drawn by the same `FocusSpotOverlay` geometry, at true size in the
real field — so what you tune is what you get.

**Controls**, in a glass tray:

- Vertical Position — 0.1 to 0.9, **snapping to detents at 1/3, 1/2 and 2/3** when within 0.02, with
  a selection haptic on entering a detent (the same feel as `PlayerControlTray.tick`). The three
  presets stay one flick away; everything between them is reachable.
- Horizontal Spacing — 40 to 400 pt.
- Diameter — 16 to 120 pt.

The tray sits at the bottom, and **moves to the top when `verticalPosition > 0.5`**, so it never
covers the spots you are aiming.

**Save** commits the working copy through `FocusSpotPreference.set`. **Cancel** discards it, and — if
the screen was opened by the toggle rather than the Calibrate row — flips the toggle back off, so
backing out of the auto-presented screen leaves the feature genuinely off rather than on with
untuned defaults.

**Accessibility:** each slider carries an `accessibilityValue` in its own units ("48 points",
"upper third"), since a VoiceOver user cannot read the preview.

## Testing

Swift Testing, in `IlumionateTests/`, run on macOS and iOS Simulator.

**`FocusSpotLayoutTests`**
- Each detent maps to the expected y (1/3, 1/2, 2/3 of height).
- Centres are symmetric about the midline and ordered left-then-right.
- A field narrower than the requested spacing clamps both spots fully inside.
- A diameter larger than half the width clamps so two spots still fit.
- `verticalPosition` at the extremes keeps the whole circle on screen.
- An empty or zero-height size returns `nil`.

**`FocusSpotSettingsTests`**
- `FocusSpotPreference` round-trips a non-default value.
- An unset key returns `.default`.
- Corrupt data returns `.default` rather than throwing.
- Out-of-range stored values are clamped on read.
- `AppSettingsManager.resetPreferences` sets `focusSpotsEnabled` to `false` and removes the geometry blob.

**`FocusSpotVisibilityTests`**
- Every `PlayerMode` case × enabled/disabled × mind-machine on/off × light-sync on/off.
- `.visualField` is never visible, even when enabled.
- `.session` with lights off is not visible; with lights on it is.

**`FocusSpotDetentTests`**
- A value within tolerance of a detent snaps to it; outside tolerance it does not.
- Snapping is idempotent at exact detent values.

## Files

`Ilumionate/` and `IlumionateTests/` are `PBXFileSystemSynchronizedRootGroup`s, so new files join
their targets automatically — no `project.pbxproj` edits.

**New — `Ilumionate/FocusSpots/`**

| File | Contents |
|---|---|
| `FocusSpotSettings.swift` | Model, ranges, clamping, `FocusSpotPreference`, detent snapping |
| `FocusSpotLayout.swift` | Pure geometry resolver |
| `FocusSpotVisibility.swift` | Pure gate + `PlayerMode.supportsFocusSpots` |
| `FocusSpotOverlay.swift` | The rendered pair |
| `FocusSpotCalibrationView.swift` | Calibration screen |

**New — tests:** `FocusSpotLayoutTests.swift`, `FocusSpotSettingsTests.swift`,
`FocusSpotVisibilityTests.swift`, `FocusSpotDetentTests.swift`

**Edited**

| File | Change |
|---|---|
| `UnifiedPlayerView.swift` | One overlay layer above `backgroundLayer` |
| `AppSettingsManager.swift` | Two keys, plus both in `resetPreferences` |
| `ProfileSettingsView.swift` | Calibration state + `platformFullScreenCover` |
| `ProfileSettingsView+Sections.swift` | Toggle + Calibrate row in Session Defaults |

## Out of scope

- Focus spots over `.visualField`.
- An in-session toggle or control-tray tile — settings only, per the brief.
- Per-session or per-score overrides; nothing enters the session JSON schema.
- Any colour other than black, soft/feathered edges, or more than two spots.
- Drag-to-position in the calibration screen — sliders only.
- Adding the preference to `AppSettingsManager.ExportSettings`.
