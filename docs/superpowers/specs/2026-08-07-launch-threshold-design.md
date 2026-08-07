# Threshold — Design

**Date:** 2026-08-07
**Status:** Revised 2026-08-07 after Apple HIG review. Approved, ready for planning
**Branch:** `feature/reader-hypnotic-visuals`

## Revision note

This spec originally placed a 2.6-second animated arc on **cold app launch**. That was
wrong, and Apple says so directly:

> "The launch screen isn't an opportunity for artistic expression. It's solely intended to
> enhance the perception of your app as quick to launch and immediately ready for use."

Apple's guidance is to make the launch screen a text-free, brand-free skeleton nearly
identical to the first screen, so launch feels instant. An animated arc at launch does the
opposite — it delays readiness on purpose. The tempting dodge is that Apple means the
OS-drawn `UILaunchScreen` while ours was an in-app view on a different layer, but that is a
technicality: to the user, something animated blocks the UI for 2.6 seconds after they tap
the icon. Apple's reasoning is about the felt experience, not the implementation layer.

The ritual was not wrong — its **location** was. It now lives at session entry, where the
user has deliberately chosen to focus, and where the app already pauses.

## Problem

Two problems, related but distinct.

**Launch has no defined first frame.** `Info.plist` declared `UILaunchScreen` as an empty
dict, so iOS drew a bare white (or black) frame before `ContentView` appeared. A flash of
white before a void-dark app is the single most jarring thing a launch can do.

**Session entry pulls the nervous system the wrong way.** `PlayerCountdownOverlay` shows a
120pt bold numeral counting 3→2→1 over a dimmed background, with a haptic tap on every
second. Counting *down* is the grammar of a rocket launch or a race start — it builds
anticipation and tension. It is close to the opposite of what the five seconds before a
light therapy session should be doing. The app spends 3, 7 or 10 seconds (user's choice,
`UnifiedPlayerViewModel.swift:108`) actively winding the user up immediately before asking
them to settle.

## What we are building

**A launch screen that gets out of the way**, per Apple: the OS-drawn frame is a solid
adaptive colour matching the app's own background, so there is no flash and no seam. No
image, no wordmark, no animation. This is already implemented.

**A threshold at session entry**: the same wordless arc — void, a breathing `LumeOrb`, a
vignette that closes and releases — replacing the numeric countdown, scaled to whichever
countdown duration the user already chose. It adds no delay anywhere; it repurposes time
the app was already spending.

### Decisions taken during design

| Question | Decision |
|---|---|
| Where does the ritual live? | Session entry, not app launch |
| What does app launch get? | A colour-matched `UILaunchScreen`, nothing more |
| What happens to the numeric countdown? | Replaced by the arc. No numerals |
| What happens to the intro copy? | **Kept.** It is instructional, not decorative |
| How long is the arc? | Whatever the user's countdown setting says — 3, 7 or 10s |
| Does it add delay? | No. It occupies time already being spent |
| Can it be skipped? | Yes, tap anywhere, as the countdown could not |
| Platforms | iOS and macOS both — session entry exists on both |

## Why the copy stays

`PlayerMode.countdownIntroMessage` and `countdownHoldMessage` are not decoration:

- `.visualField` → "Soften your gaze in…"
- everything else → "Close your eyes and relax in…", held on "Close your eyes"

Whether the user's eyes are closed materially changes what a photoentrainment session
does. Stripping those instructions to achieve a pure-atmosphere aesthetic would be a
functional regression in a therapy app. The arc is wordless; the screen is not.

**The copy needs rewording.** "Close your eyes and relax in…" grammatically dangles into a
numeral that will no longer exist. Without the count it becomes "Close your eyes and
relax" and "Soften your gaze", with the held line unchanged.

## The core risk, and the answer to it

Pure atmosphere risks reading as a loading spinner — the opposite of the intent. The
distinction is structural, not decorative:

> A spinner **loops**. A threshold **progresses**.

The motion must have a legible beginning, middle and end. This is why the arc has exactly
one growth beat and one flat plateau, and why it must never wait on anything.

## Choreography

Four beats. At the default 3-second countdown the arc runs at its natural proportions;
at 7 or 10 seconds the **Settle** beat absorbs the extra time while the other three keep
their absolute durations. Stretching Bloom would make the growth imperceptibly slow;
stretching Settle just means a longer held stillness, which is exactly what more time
should buy.

| Beat | Share of a 3s arc | What happens |
|---|---|---|
| Arrival | 0 – 0.5s | Vignette closes in from the edges. Orb is a dim point at 0.6 scale |
| Bloom | 0.5 – 1.6s | Orb scales 0.6 → 1.0 on a slow ease-out. Conic ring spins up. Aurora fades in. One inhale |
| Settle | 1.6 – 2.6s **(absorbs all extra duration)** | Choreographed scale holds flat at 1.0. Only `LumeOrb`'s own breath moves |
| Opening | final 0.4s | Vignette releases outward. Orb scales 1.0 → 1.15 while fading to zero |

Three properties are load-bearing:

**Bloom is the only growth beat.** A spinner never grows. One unrepeated expansion is the
clearest signal that this has a beginning.

**Settle is flat on purpose.** The eye reads a plateau as an ending rather than a wait.
The orb is not frozen — `LumeOrb` runs its own breath off the absolute clock and we
neither can nor should phase-lock it, since it is shared with every surface that draws an
orb. Settle is *stillness with a pulse*. A completely motionless screen looks hung.

**Opening inverts Arrival.** The orb scaling *up* as it fades reads as the field opening,
not the orb leaving.

### The aurora never fades out

`auroraOpacity` runs 0 through Arrival, ramps 0 → 1 across Bloom, then stays at 1 through
Settle *and* Opening. Fading it during Opening would darken the field and force the
player's own background to fade back in — a visible seam.

### Skip

A tap captures the current frame and interpolates to the resting frame over 0.35s, so a
skip eases out rather than snapping. This is new behaviour: the numeric countdown could
not be skipped, and a user who has already settled should not have to wait out ten
seconds.

Skipping starts the session immediately. It does not shorten the session.

### Reduce Motion

Same four-beat structure expressed only in opacity: fade in, hold, fade out. Orb scale
pinned at 1.0, no spin, no vignette travel. The **hold** absorbs the user's chosen
duration, so a Reduce Motion user still gets the full countdown they configured — the
motion changes, the timing contract does not.

## Architecture

Already built and committed (Tasks 1–5 of the original plan, all reusable):

| File | Responsibility | Status |
|---|---|---|
| `Ilumionate/Threshold/ThresholdChoreography.swift` | Pure elapsed-time → `Frame` mapping | Built; **needs duration scaling** |
| `Ilumionate/Threshold/ThresholdController.swift` | Phase machine, skip | Built; **suppression rules need rework** |
| `Ilumionate/Threshold/ThresholdVignette.swift` | Edge-closing radial mask | Built, unchanged |
| `Ilumionate/Threshold/ThresholdView.swift` | Composes the arc | Built; **needs a message slot** |
| `Ilumionate/Assets.xcassets/LaunchBackground.colorset` | Adaptive launch colour | Done |
| `Ilumionate/Info.plist` | `UIColorName` in `UILaunchScreen` | Done |

### Remaining work

**Duration scaling.** `ThresholdChoreography` currently hardcodes a 2.6s arc. It gains a
`duration: TimeInterval` so Settle can absorb the difference. Beat boundaries become
derived rather than constant.

**Suppression rules change.** The original rules were launch-specific and no longer apply:

- *First launch* — irrelevant at session entry. Removed.
- *VoiceOver* — **inverted.** At launch we skipped the threshold entirely. At session
  entry the countdown carries information a screen reader user needs, so under VoiceOver
  we keep the **numeric** countdown rather than the wordless arc. The arc announces
  nothing; the numerals announce progress.
- *Non-iOS* — removed. Session entry exists on macOS and deserves the same treatment.

**Message slot.** `ThresholdView` takes an optional message and renders it beneath the orb
using the player's existing typography, so the instructional copy survives.

**Player integration.** `UnifiedPlayerView` swaps `PlayerCountdownOverlay` for the
threshold when VoiceOver is off. `UnifiedPlayerViewModel`'s countdown task drops the
per-second numeral updates and per-second haptics, keeping the intro message, the held
message, the completion haptic and the call to `beginPlayback()`.

### What is explicitly NOT happening

No threshold on cold app launch. No overlay in `ContentView`. The dead `isLoading` state
in `ContentView` is now out of scope — it was only in scope because we were editing that
file.

## Failure behaviour

- **Skip during the exit interpolation** — ignored; `skip()` is a no-op unless running.
- **Session cancelled mid-arc** — the existing `countdownTask` cancellation path already
  handles this and is unchanged.
- **Arc outlasts its budget** — impossible; the arc is derived from the budget.

## Testing

`ThresholdChoreography` remains a pure function, so its tests stay value assertions.
Existing tests are updated for the duration parameter and new ones added:

| Test | Assertion |
|---|---|
| Default duration matches the old arc | A 2.6s choreography produces the previously-pinned frames |
| Settle absorbs extra duration | At 10s, Arrival/Bloom/Opening keep their absolute lengths and Settle holds the remainder |
| Bloom timing is duration-independent | Bloom still ends 1.6s in, at every supported duration |
| Opening always occupies the final 0.4s | At 3, 7 and 10s |
| Scale still peaks at 1.0 entering Settle | At every supported duration |
| Aurora still holds at 1 through the end | At every supported duration |
| Reduced motion absorbs duration in the hold | Orb scale stays 1.0; total matches the requested duration |

Player integration is covered by the existing `UnifiedPlayerViewModel` tests plus one new
assertion that the countdown task still calls `beginPlayback()` after the full budget.

No UI tests — a timed animation is a flake generator.

## Definition of done

- Cold launch shows no white flash in either appearance, and no animation.
- Starting a session plays the arc for exactly the user's configured duration.
- The instructional copy still appears, reworded so it does not dangle.
- A tap during the arc starts the session within 0.35s.
- Reduce Motion produces the opacity-only variant at the same total duration.
- VoiceOver still gets the numeric countdown with its per-second announcements.
- The 3/7/10s setting still works and still means what it says.
- macOS and Mac Catalyst build and behave identically.
- Threshold test suites pass on both destinations; no regression elsewhere.

## Out of scope

- Any threshold on app launch.
- Changes to `OnboardingView`.
- The `iphone-performance-gaming-tier` entry in `UIRequiredDeviceCapabilities`
  (`Info.plist:71`), which restricts App Store availability to a narrow set of devices.
  Noticed while reading the plist; worth resolving before submission, unrelated to this.
