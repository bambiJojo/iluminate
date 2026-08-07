# Launch Threshold — Design

**Date:** 2026-08-07
**Status:** Approved, ready for planning
**Branch:** `feature/reader-hypnotic-visuals`

## Problem

The app has no entry. `Info.plist:68` declares `UILaunchScreen` as an empty dict, so iOS
draws a bare white (or black) frame, and then `ContentView` pops straight into the
four-tab shell with a tab bar, cards, a streak pill and whatever Home has to say. The
user goes from a notification-strewn home screen to a populated UI in one frame.

That transition is at odds with what the app is for. LumeSync asks the user to settle,
narrow their attention and stay with a slow visual field for twenty minutes. It opens by
handing them another dense screen to parse. Nothing in the launch marks the boundary
between the phone they were just using and the state the app wants them in.

## What we are building

A **threshold**: a full-screen, wordless, 2.6-second visual arc that plays over the tab
shell on cold launch, then opens into Home. Void, a breathing `LumeOrb`, and a vignette
that closes and releases. No text, no branding, no data. It auto-dismisses; a tap
anywhere skips it.

The transition itself is the feature. The threshold is not a splash screen advertising
the app and not a loading screen reporting progress — it is a paced handoff from a
cluttered environment to a quiet one.

### Decisions taken during design

| Question | Decision |
|---|---|
| Static asset or in-app view? | In-app animated threshold, backed by a colour-matched `UILaunchScreen` so there is no seam |
| How does it end? | Auto-dismiss on a fixed arc; tap anywhere to skip |
| What is on screen? | Pure atmosphere — void, orb, vignette. No words, no wordmark, no stats |
| How does it compose with the shell? | Overlay above a already-mounted `ContentView`, not a scene swap |
| When does it show? | Cold launch only. Not on resume from background |
| Platforms | iOS only |
| VoiceOver | Skipped entirely |
| Coupled to loading? | No, deliberately. Fixed duration regardless of load state |

## The core risk, and the answer to it

Pure atmosphere with no words risks reading as a loading spinner — the exact opposite of
the intent. The distinction is structural, not decorative:

> A spinner **loops**. A threshold **progresses**.

So the motion must have a legible beginning, middle and end, and it must never wait on
anything. Every timing decision below serves that one constraint.

## Choreography

Four beats, 2.6s total.

| Beat | Window | What happens |
|---|---|---|
| Arrival | 0 – 0.5s | Screen opens at exactly the `UILaunchScreen` colour. Vignette closes in from the edges — the periphery, where the cluttered phone was, darkens first. Orb is a dim point at 0.6 scale |
| Bloom | 0.5 – 1.6s | Orb scales 0.6 → 1.0 on a slow ease-out. Conic ring spins up from rest. Aurora blobs fade in behind. One inhale |
| Settle | 1.6 – 2.2s | Choreographed scale holds flat at 1.0. Only `LumeOrb`'s own internal breath keeps moving. Held stillness |
| Opening | 2.2 – 2.6s | Vignette releases outward, the inverse of Arrival. Orb scales 1.0 → 1.15 while fading to zero. Home's chrome fades up through it |

Three properties of this arc are load-bearing:

**Bloom is the only growth beat.** A spinner never grows. A single unrepeated
0.6 → 1.0 expansion is the clearest available signal that this has a beginning.

**Settle is flat on purpose.** The choreographed scale does not move for 0.6 seconds. The
eye reads a plateau as an ending rather than a wait, and this is the stretch that does the
actual relaxing. It is precisely the beat every loading indicator lacks.

The orb is not frozen during Settle — `LumeOrb` runs its own breath off the absolute clock
and we neither can nor should phase-lock it, since it is shared with every other surface
that draws an orb. So Settle is *stillness with a pulse*: the threshold stops driving the
orb and lets its resting breath show through. That is the correct read anyway. A
completely motionless screen looks hung.

**Opening inverts Arrival.** The orb scaling *up* as it fades reads as the field opening,
not the orb leaving. The vignette releasing outward is literally beat 1 run backwards.

### The aurora never fades out

`auroraOpacity` runs 0 through Arrival, ramps 0 → 1 across Bloom, and then stays at 1 for
Settle *and* Opening. It must not fall at the end. The threshold's aurora is the same
field Home is already drawing underneath at identical phase and colour; fading it out
during Opening would darken the field for 0.4s and then require Home's copy to fade back
in, which is the visible seam this whole approach exists to avoid. Only the orb and the
vignette dissolve. The field is continuous by construction.

### Skip

A tap at any moment captures the current frame and interpolates from it to the resting
frame over 0.35s. A skip therefore eases out from wherever the orb happens to be rather
than snapping. Skip is available from the first frame.

### Reduce Motion

A real variant, not a disable. Same four-beat structure, no motion: a 0.4s opacity fade
in, a held beat, a 0.3s fade out. Orb scale is pinned at 1.0 throughout, no spin, no
vignette travel. About 0.9s total.

## Why an overlay, not a scene swap

`ContentView` stays mounted underneath and the threshold renders above it in a `ZStack`.
Three consequences, all of them wins:

**Real work hides inside the ritual.** `ContentView`'s `.task` — `loadSessions()`,
`loadAudioFiles()`, `restoreManualRecoveries()`, first-launch and consent checks — runs
behind the threshold. Launch latency becomes part of the transition rather than adding
to it. A scene-level swap would mount `ContentView` *after* the arc, starting that work
late and making launch genuinely slower.

**The aurora field is continuous.** `AuroraBackground.animatedBlobs`
(`AuroraBackground.swift:66`) derives blob phase from
`context.date.timeIntervalSinceReferenceDate` — absolute wall-clock time, not a
per-instance start. Two instances mounted seconds apart render pixel-identical. `LumeOrb`
spins on the same absolute clock. So when the threshold draws
`AuroraBackground(mood:)` with the mood from the same `PortalRecommender.category(forHour:)`
call Home makes at `HomeView.swift:111`, the two fields match in phase *and* colour. The
exit is not a crossfade between two screens; only the threshold's own layers dissolve
while the field underneath continues untouched.

**No geometry coupling.** A `matchedGeometryEffect` morph of the orb into a Home position
would be more cinematic but would couple `ThresholdView` to `HomeView`'s internals, and
matched geometry across a tab shell during first load is fragile. The shared absolute
clock buys the continuity without the coupling.

## Architecture

New directory `Ilumionate/Threshold/`.

### `ThresholdChoreography.swift`

A `Sendable` value type, and the heart of the feature. A pure function of elapsed time to
a frame of visual values:

```swift
struct ThresholdChoreography: Sendable {
    enum Motion: Sendable { case full, reduced }

    struct Frame: Equatable, Sendable {
        var orbScale: Double
        var orbOpacity: Double
        var vignetteClosure: Double   // 0 = wide open, 1 = fully closed
        var auroraOpacity: Double
    }

    let motion: Motion

    var totalDuration: TimeInterval { get }
    func frame(atElapsed: TimeInterval) -> Frame
    func exitFrame(from: Frame, progress: Double) -> Frame
}
```

No SwiftUI, no timers, no state, no clock of its own. Every timing constant in the
choreography table above lives here as a named `static let`. Because it is pure, the
whole arc is testable by calling `frame(atElapsed:)` with arbitrary values, and the
controller can compute the current frame itself without the view feeding state back.

### `ThresholdController.swift`

`@MainActor @Observable final class`. Owns the start date and a phase:

```swift
enum Phase: Equatable {
    case running(start: Date)
    case exiting(from: ThresholdChoreography.Frame, start: Date)
    case finished
}
```

Decides whether to present at all (see Suppression below), drives the transition to
`.finished` via a `.task` that sleeps for `totalDuration`, and handles `skip()` by
computing the current frame from the choreography and moving to `.exiting`.

The per-frame visuals come from `TimelineView(.animation)` in the view; the phase
transition comes from the sleeping task. Both are anchored to the same start date and
read the same duration constant, so drift across a 2.6s arc is under one frame.

### `ThresholdView.swift`

Presentation only. `TimelineView(.animation)` computes the frame each tick — the same
pattern `LumeOrb` already uses. Renders `AuroraBackground(mood:)`, the orb, and the
vignette. The skip target is a full-bleed `Button` with a `Color.clear` label and
`.contentShape(.rect)`, per the house rule against `onTapGesture` for plain taps.

### `ThresholdVignette.swift`

The edge-closing radial mask. Separated because it is the one piece with fiddly geometry
and benefits from its own preview.

### Modified files

**`ContentView.swift`** gains `@State private var threshold = ThresholdController()` and
a `ZStack` overlay above `mainLayout`. `ContentView` mounts once per process launch, so
`@State` gives cold-launch-only semantics for free — no separate "already shown" flag and
no `UserDefaults`. Resume from background does not remount and therefore does not
re-trigger.

**`Info.plist`** gets `UIColorName` inside the existing empty `UILaunchScreen` dict.

**`Assets.xcassets`** gets a `LaunchBackground` colour set with light and dark variants
matching `Color.bgDeep`, so the OS-drawn launch frame is indistinguishable from frame one
of Arrival in both appearances.

## Suppression

The threshold does not show when:

- **VoiceOver is running.** A decorative animation with nothing to announce that blocks
  the shell for 2.6 seconds is hostile to a screen reader user. Straight to Home.
- **First launch.** `ContentView.checkForFirstLaunch()` raises `OnboardingView` 800ms
  after appear when `hasCompletedOnboarding` is false — landing squarely inside the Bloom
  beat, with a `fullScreenCover` animating up through a threshold that is still playing.
  Onboarding is the entry experience on first launch; the threshold stands down. The
  controller reads the same `hasCompletedOnboarding` key.
- **Not iOS.** There is no cluttered iPhone environment to leave on macOS, and a
  threshold overlay inside a resizable window reads as a modal glitch. Gated at the
  `ContentView` overlay seam with `#if os(iOS)`; the `Threshold/` files themselves stay
  platform-free and compile everywhere.

`UIAccessibility.isVoiceOverRunning` is UIKit, so it sits behind `#if canImport(UIKit)`
inside the controller as a narrow adapter, consistent with the project's platform-boundary
rule.

## Deliberately not coupled to loading

`isLoading` in `ContentView.swift:32` is currently dead state — assigned at lines 242 and
254, read by nothing. It is tempting to gate the threshold on it. We are not doing that.

If the threshold waited for loading, it would become an indefinite loading screen, which
is the precise failure mode this feature exists to avoid. The arc runs for a fixed
duration and exits on schedule. If sessions are still loading when it ends, Home shows
its own loading state — that is Home's job.

`isLoading` is deleted as part of this work, since it is dead code in a file we are
already modifying.

## Failure behaviour

There is nothing here that can fail — no I/O, no decoding, no network. The two
degenerate cases:

- **Load outruns the arc.** Threshold exits anyway; Home renders whatever it has.
- **Skip during the exit interpolation.** Ignored. `skip()` is a no-op unless the phase
  is `.running`.

## Testing

`ThresholdChoreography` is a pure function, so tests are direct value assertions with
Swift Testing. New file `IlumionateTests/ThresholdChoreographyTests.swift`:

| Test | Assertion |
|---|---|
| Arrival start | `frame(atElapsed: .zero)` has `orbOpacity` near 0, `vignetteClosure` 0 |
| Arrival closes the vignette | `vignetteClosure` is monotonically increasing across 0 → 0.5s |
| Bloom grows | `orbScale` is strictly increasing across 0.5 → 1.6s, reaching 1.0 |
| Settle is flat | `orbScale` is constant at 1.0 across 1.6 → 2.2s — the plateau is asserted, not incidental |
| Opening clears | at `totalDuration`, `orbOpacity == 0` and `vignetteClosure == 0` |
| Opening lifts | `orbScale` exceeds 1.0 during 2.2 → 2.6s |
| Aurora holds | `auroraOpacity == 1` at every sampled value from 1.6s through `totalDuration`, including the final frame |
| Reduced motion pins scale | with `.reduced`, `orbScale == 1.0` at every sampled elapsed value |
| Reduced motion is shorter | `.reduced` `totalDuration` is under 1.0s |
| Skip lands correctly | `exitFrame(from: midBloomFrame, progress: 1.0)` equals the frame at `totalDuration` |
| Skip interpolates | `exitFrame` at progress 0 equals the captured frame |
| Past the end is clamped | `frame(atElapsed: totalDuration * 2)` equals the frame at `totalDuration` |
| Negative elapsed is clamped | `frame(atElapsed: -1)` equals the frame at 0 |

No UI tests. There is nothing a UI test would catch here that a value test would not, and
a UI test of a 2.6-second animation is a flake generator.

`ThresholdController` gets light coverage for the phase machine: `skip()` from `.running`
moves to `.exiting`; `skip()` from `.exiting` or `.finished` is a no-op.

## Definition of done

- Cold launch on iOS shows the four-beat arc with no white flash and no visible seam at
  the OS handoff, in both light and dark appearance.
- The aurora field does not jump, shift or recolour at the moment the threshold exits.
- A tap at any point during the arc eases out within 0.35s.
- Resume from background does not replay the threshold.
- First launch goes straight to Home and then Onboarding, with no threshold underneath it.
- Reduce Motion produces the short fade variant with no scaling or spinning.
- VoiceOver launches straight into Home.
- macOS and Mac Catalyst build and launch unchanged.
- `ThresholdChoreographyTests` passes on both the macOS and iOS Simulator destinations.
- No regression in the existing suite.

## Out of scope

- Extending the threshold to cover entry into a session or the player. The same grammar
  would likely apply, but it is a separate decision about a different seam.
- Any change to `OnboardingView`, which remains the first-launch experience and is
  unrelated.
- The `iphone-performance-gaming-tier` entry in `UIRequiredDeviceCapabilities`
  (`Info.plist:71`), which restricts App Store availability to a narrow set of devices.
  Noticed while reading the plist during this design; worth resolving before submission,
  but not part of this work.
