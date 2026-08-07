# Launch Threshold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play a wordless 2.6-second visual arc over the tab shell on cold launch, so the app opens with a paced handoff out of the cluttered phone environment instead of dropping the user straight into a populated UI.

**Architecture:** A pure `ThresholdChoreography` value type maps elapsed seconds to a frame of visual values (orb scale, orb opacity, vignette closure, aurora opacity). A `@MainActor @Observable ThresholdController` owns the clock and a three-case phase machine. `ThresholdView` renders the frame each tick via `TimelineView(.animation)` and overlays an already-mounted `ContentView`, so session loading hides inside the transition and the shared `AuroraBackground` — which animates off the absolute clock — carries across the exit with no visible seam.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing (`import Testing`), Xcode synchronized file groups.

**Spec:** `docs/superpowers/specs/2026-08-07-launch-threshold-design.md`

---

## Before you start

Read these four things. They are the load-bearing facts this plan depends on.

**1. New files need no Xcode project edits.** `Ilumionate.xcodeproj/project.pbxproj:188` and `:198` declare `Ilumionate/` and `IlumionateTests/` as `PBXFileSystemSynchronizedRootGroup`. Any `.swift` file you create under those directories joins the target automatically. Do not hand-edit the pbxproj. (It already shows as modified in git from unrelated prior work — leave that alone.)

**2. The aurora continuity is real, not aspirational.** `Ilumionate/DesignSystem/AuroraBackground.swift:66` computes blob phase from `context.date.timeIntervalSinceReferenceDate` — absolute wall-clock time, not a per-instance start date. `LumeOrb` spins on the same clock. This is why two separately-mounted instances render pixel-identical, and why the exit needs no `matchedGeometryEffect`. If you find yourself adding one, stop and re-read the spec.

**3. The threshold must never wait on anything.** Fixed duration, always. If you are tempted to gate it on loading state, that is the exact failure mode this feature exists to avoid.

**4. The module already defaults to main-actor isolation.** `project.pbxproj` sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` alongside `SWIFT_STRICT_CONCURRENCY = complete` on every configuration. So a `@State` property initialiser inside a `View` is already a main-actor context, and no `nonisolated` annotation is needed anywhere in this feature. Do not add one — on an `@Observable` tracked stored property it is a hard compile error (`main actor-isolated property 'phase' can not be mutated from a nonisolated context`). Keep the explicit `@MainActor` on the class regardless: 37 of the 38 `@Observable` files here carry it, and matching the house convention beats saving a line.

### Build and test commands

**Always pass `-derivedDataPath`.** The user keeps Xcode open and runs their own builds; sharing the default DerivedData causes `unable to attach DB: database is locked`. Every command below already includes the flag.

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData test -only-testing:IlumionateTests/ThresholdChoreographyTests
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData build
```

---

## File structure

| File | Responsibility |
|---|---|
| `Ilumionate/Threshold/ThresholdChoreography.swift` | Pure elapsed-time → `Frame` mapping. All timing constants. No SwiftUI, no state, no clock |
| `Ilumionate/Threshold/ThresholdController.swift` | Phase machine, start date, skip, suppression rules |
| `Ilumionate/Threshold/ThresholdVignette.swift` | The edge-closing radial mask |
| `Ilumionate/Threshold/ThresholdView.swift` | Composes aurora + orb + vignette from a `Frame`. Skip button |
| `Ilumionate/Assets.xcassets/LaunchBackground.colorset/Contents.json` | Adaptive colour matching `bgDeep`, used by `UILaunchScreen` |
| `Ilumionate/Info.plist` | `UIColorName` inside the existing empty `UILaunchScreen` dict |
| `Ilumionate/ContentView.swift` | Hosts the overlay; loses the dead `isLoading` state |
| `IlumionateTests/ThresholdChoreographyTests.swift` | Value assertions on the arc |
| `IlumionateTests/ThresholdControllerTests.swift` | Phase machine assertions |

---

## Task 1: The choreography value type

This is the whole feature's logic. It is a pure function, so it is tested exhaustively and everything downstream is dumb.

**Files:**
- Create: `IlumionateTests/ThresholdChoreographyTests.swift`
- Create: `Ilumionate/Threshold/ThresholdChoreography.swift`

- [ ] **Step 1: Write the failing tests**

Create `IlumionateTests/ThresholdChoreographyTests.swift`:

```swift
//
//  ThresholdChoreographyTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct ThresholdChoreographyTests {

    private let full = ThresholdChoreography(motion: .full)
    private let reduced = ThresholdChoreography(motion: .reduced)

    // MARK: - Arrival

    @Test("The arc opens with the orb invisible and the vignette wide open")
    func arrivalStart() {
        let frame = full.frame(atElapsed: 0)
        #expect(frame.orbOpacity == 0)
        #expect(frame.vignetteClosure == 0)
        #expect(frame.auroraOpacity == 0)
    }

    @Test("Arrival closes the vignette from the edges")
    func arrivalClosesVignette() {
        // The periphery — where the cluttered phone was — darkens first.
        let samples = stride(from: 0.0, through: 0.5, by: 0.05)
            .map { full.frame(atElapsed: $0).vignetteClosure }
        for (earlier, later) in zip(samples, samples.dropFirst()) {
            #expect(later >= earlier)
        }
        #expect(full.frame(atElapsed: 0.5).vignetteClosure == 1)
    }

    // MARK: - Bloom

    @Test("Bloom is the only beat where the orb grows")
    func bloomGrows() {
        // A spinner never grows. One unrepeated expansion is the clearest
        // available signal that this arc has a beginning.
        let samples = stride(from: 0.5, through: 1.6, by: 0.05)
            .map { full.frame(atElapsed: $0).orbScale }
        for (earlier, later) in zip(samples, samples.dropFirst()) {
            #expect(later > earlier)
        }
        #expect(abs(full.frame(atElapsed: 0.5).orbScale - 0.6) < 0.0001)
        #expect(abs(full.frame(atElapsed: 1.6).orbScale - 1.0) < 0.0001)
    }

    // MARK: - Settle

    @Test("Settle holds the choreographed scale perfectly flat")
    func settleIsFlat() {
        // The plateau is the point. The eye reads a flat stretch as an ending
        // rather than a wait — this is the beat a loading indicator lacks.
        for elapsed in stride(from: 1.6, through: 2.2, by: 0.05) {
            #expect(abs(full.frame(atElapsed: elapsed).orbScale - 1.0) < 0.0001)
        }
    }

    // MARK: - Opening

    @Test("Opening clears the orb and releases the vignette")
    func openingClears() {
        let frame = full.frame(atElapsed: full.totalDuration)
        #expect(frame.orbOpacity == 0)
        #expect(frame.vignetteClosure == 0)
    }

    @Test("Opening lifts the orb outward as it fades")
    func openingLifts() {
        // Scaling up while fading reads as the field opening, not the orb leaving.
        #expect(full.frame(atElapsed: 2.4).orbScale > 1.0)
        #expect(full.frame(atElapsed: full.totalDuration).orbScale > 1.0)
    }

    @Test("The aurora never fades out, including on the final frame")
    func auroraHolds() {
        // The threshold's aurora is the same field Home is already drawing
        // underneath. Fading it during Opening would darken the screen and
        // force Home's copy to fade back in — the exact seam this avoids.
        for elapsed in stride(from: 1.6, through: full.totalDuration, by: 0.05) {
            #expect(full.frame(atElapsed: elapsed).auroraOpacity == 1)
        }
        #expect(full.frame(atElapsed: full.totalDuration).auroraOpacity == 1)
    }

    // MARK: - Clamping

    @Test("Elapsed past the end clamps to the final frame")
    func clampsPastEnd() {
        #expect(full.frame(atElapsed: full.totalDuration * 2)
                == full.frame(atElapsed: full.totalDuration))
    }

    @Test("Negative elapsed clamps to the first frame")
    func clampsBeforeStart() {
        #expect(full.frame(atElapsed: -1) == full.frame(atElapsed: 0))
    }

    // MARK: - Reduce Motion

    @Test("Reduced motion pins the orb scale at rest")
    func reducedMotionDoesNotScale() {
        for elapsed in stride(from: 0.0, through: reduced.totalDuration, by: 0.05) {
            #expect(reduced.frame(atElapsed: elapsed).orbScale == 1.0)
        }
    }

    @Test("Reduced motion never travels the vignette")
    func reducedMotionHasNoVignette() {
        for elapsed in stride(from: 0.0, through: reduced.totalDuration, by: 0.05) {
            #expect(reduced.frame(atElapsed: elapsed).vignetteClosure == 0)
        }
    }

    @Test("Reduced motion still fades the orb in and back out")
    func reducedMotionFades() {
        #expect(reduced.frame(atElapsed: 0).orbOpacity == 0)
        #expect(reduced.frame(atElapsed: 0.5).orbOpacity == 1)
        #expect(reduced.frame(atElapsed: reduced.totalDuration).orbOpacity == 0)
    }

    @Test("Reduced motion is markedly shorter than the full arc")
    func reducedMotionIsShort() {
        #expect(reduced.totalDuration < 1.0)
        #expect(reduced.totalDuration < full.totalDuration)
    }

    @Test("Reduced motion also holds the aurora up")
    func reducedMotionHoldsAurora() {
        #expect(reduced.frame(atElapsed: reduced.totalDuration).auroraOpacity == 1)
    }

    // MARK: - Skip

    @Test("A skip that runs to completion lands on the resting frame")
    func skipLandsAtRest() {
        let midBloom = full.frame(atElapsed: 1.0)
        #expect(full.exitFrame(from: midBloom, progress: 1)
                == full.frame(atElapsed: full.totalDuration))
    }

    @Test("A skip begins from exactly where the arc was")
    func skipStartsWhereItWas() {
        // Easing out from the current frame is what stops a skip snapping.
        let midBloom = full.frame(atElapsed: 1.0)
        #expect(full.exitFrame(from: midBloom, progress: 0) == midBloom)
    }

    @Test("Skip progress is clamped at both ends")
    func skipClamps() {
        let midBloom = full.frame(atElapsed: 1.0)
        #expect(full.exitFrame(from: midBloom, progress: -0.5) == midBloom)
        #expect(full.exitFrame(from: midBloom, progress: 2)
                == full.exitFrame(from: midBloom, progress: 1))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData test -only-testing:IlumionateTests/ThresholdChoreographyTests
```

Expected: compile failure, `cannot find 'ThresholdChoreography' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Ilumionate/Threshold/ThresholdChoreography.swift`:

```swift
//
//  ThresholdChoreography.swift
//  Ilumionate
//
//  The launch threshold's arc, as a pure function of elapsed time.
//
//  A spinner loops; a threshold progresses. Every constant here serves that
//  one distinction — a single unrepeated growth beat, a flat plateau the eye
//  reads as an ending, and an exit that inverts the entrance.
//
//  No SwiftUI, no timers, no clock. Given a number of seconds, it returns the
//  frame that belongs at that moment. That is the whole type.
//

import Foundation

struct ThresholdChoreography: Sendable {

    enum Motion: Sendable, Equatable {
        case full
        /// Same four-beat structure, expressed only in opacity.
        case reduced
    }

    /// Everything the view needs to draw one moment of the arc.
    struct Frame: Equatable, Sendable {
        /// Choreographed scale applied *on top of* LumeOrb's own breath.
        var orbScale: Double
        var orbOpacity: Double
        /// 0 = wide open, 1 = fully closed in around the centre.
        var vignetteClosure: Double
        var auroraOpacity: Double
    }

    // MARK: - Beat boundaries (seconds from launch)

    private enum Beat {
        static let arrivalEnd: TimeInterval = 0.5
        static let bloomEnd: TimeInterval = 1.6
        static let settleEnd: TimeInterval = 2.2
        static let openingEnd: TimeInterval = 2.6
    }

    private enum ReducedBeat {
        static let fadeInEnd: TimeInterval = 0.4
        static let holdEnd: TimeInterval = 0.6
        static let fadeOutEnd: TimeInterval = 0.9
    }

    /// The orb starts as a dim point rather than nothing, so Bloom reads as
    /// something opening rather than something appearing.
    private static let seedScale = 0.6
    private static let seedOpacity = 0.25
    /// Overshooting rest on the way out is what makes the exit read as the
    /// field opening instead of the orb being taken away.
    private static let liftScale = 1.15

    let motion: Motion

    var totalDuration: TimeInterval {
        switch motion {
        case .full: Beat.openingEnd
        case .reduced: ReducedBeat.fadeOutEnd
        }
    }

    // MARK: - The arc

    func frame(atElapsed elapsed: TimeInterval) -> Frame {
        let t = min(max(elapsed, 0), totalDuration)
        return switch motion {
        case .full: fullFrame(at: t)
        case .reduced: reducedFrame(at: t)
        }
    }

    private func fullFrame(at t: TimeInterval) -> Frame {
        if t <= Beat.arrivalEnd {
            let p = progress(t, from: 0, to: Beat.arrivalEnd)
            return Frame(
                orbScale: Self.seedScale,
                orbOpacity: Self.seedOpacity * p,
                vignetteClosure: easeInOut(p),
                auroraOpacity: 0
            )
        }

        if t <= Beat.bloomEnd {
            let p = progress(t, from: Beat.arrivalEnd, to: Beat.bloomEnd)
            let eased = easeOut(p)
            return Frame(
                orbScale: lerp(Self.seedScale, 1.0, eased),
                orbOpacity: lerp(Self.seedOpacity, 1.0, eased),
                vignetteClosure: 1,
                auroraOpacity: p
            )
        }

        if t <= Beat.settleEnd {
            // Nothing moves here but the orb's own breath. That is the point.
            return Frame(orbScale: 1, orbOpacity: 1, vignetteClosure: 1, auroraOpacity: 1)
        }

        let p = progress(t, from: Beat.settleEnd, to: Beat.openingEnd)
        return Frame(
            orbScale: lerp(1.0, Self.liftScale, easeIn(p)),
            orbOpacity: 1 - p,
            vignetteClosure: 1 - easeInOut(p),
            // Held at full. The field underneath must never dip.
            auroraOpacity: 1
        )
    }

    private func reducedFrame(at t: TimeInterval) -> Frame {
        if t <= ReducedBeat.fadeInEnd {
            let p = progress(t, from: 0, to: ReducedBeat.fadeInEnd)
            return Frame(orbScale: 1, orbOpacity: p, vignetteClosure: 0, auroraOpacity: p)
        }

        if t <= ReducedBeat.holdEnd {
            return Frame(orbScale: 1, orbOpacity: 1, vignetteClosure: 0, auroraOpacity: 1)
        }

        let p = progress(t, from: ReducedBeat.holdEnd, to: ReducedBeat.fadeOutEnd)
        return Frame(orbScale: 1, orbOpacity: 1 - p, vignetteClosure: 0, auroraOpacity: 1)
    }

    // MARK: - Skip

    /// Interpolates from a captured frame to the resting frame, so a skip eases
    /// out from wherever the arc happened to be rather than snapping.
    func exitFrame(from captured: Frame, progress: Double) -> Frame {
        let p = min(max(progress, 0), 1)
        let rest = frame(atElapsed: totalDuration)
        return Frame(
            orbScale: lerp(captured.orbScale, rest.orbScale, p),
            orbOpacity: lerp(captured.orbOpacity, rest.orbOpacity, p),
            vignetteClosure: lerp(captured.vignetteClosure, rest.vignetteClosure, p),
            auroraOpacity: lerp(captured.auroraOpacity, rest.auroraOpacity, p)
        )
    }

    /// How long a skip takes to ease out.
    static let skipDuration: TimeInterval = 0.35

    // MARK: - Curves

    private func progress(_ t: TimeInterval, from: TimeInterval, to: TimeInterval) -> Double {
        guard to > from else { return 1 }
        return min(max((t - from) / (to - from), 0), 1)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private func easeIn(_ t: Double) -> Double {
        t * t * t
    }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData test -only-testing:IlumionateTests/ThresholdChoreographyTests
```

Expected: all 17 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/Threshold/ThresholdChoreography.swift IlumionateTests/ThresholdChoreographyTests.swift
git commit -m "feat(threshold): map the launch arc as a pure function of elapsed time"
```

---

## Task 2: The controller and its phase machine

**Files:**
- Create: `IlumionateTests/ThresholdControllerTests.swift`
- Create: `Ilumionate/Threshold/ThresholdController.swift`

- [ ] **Step 1: Write the failing tests**

Create `IlumionateTests/ThresholdControllerTests.swift`:

```swift
//
//  ThresholdControllerTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct ThresholdControllerTests {

    @Test("A controller that is allowed to run starts out presenting")
    func runsWhenAllowed() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        #expect(controller.isPresenting)
    }

    @Test("A suppressed controller never presents")
    func suppressedNeverPresents() {
        // VoiceOver and first launch both land here.
        let controller = ThresholdController(isSuppressed: true, motion: .full)
        #expect(controller.isPresenting == false)
    }

    @Test("Skipping a running threshold moves it into the exit")
    func skipStartsExit() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        controller.skip(now: .now)
        #expect(controller.isExiting)
        #expect(controller.isPresenting)
    }

    @Test("Skipping twice is a no-op")
    func skipTwiceIsIgnored() {
        // Otherwise a double tap restarts the exit interpolation and stutters.
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        let start = Date.now
        controller.skip(now: start)
        let firstExit = controller.frame(at: start.addingTimeInterval(0.1))
        controller.skip(now: start.addingTimeInterval(0.1))
        #expect(controller.frame(at: start.addingTimeInterval(0.1)) == firstExit)
    }

    @Test("Finishing stops presentation")
    func finishStopsPresenting() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        controller.finish()
        #expect(controller.isPresenting == false)
    }

    @Test("Skipping after finishing is a no-op")
    func skipAfterFinishIsIgnored() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        controller.finish()
        controller.skip(now: .now)
        #expect(controller.isPresenting == false)
    }

    @Test("While running, the frame tracks elapsed time from the start date")
    func runningFrameTracksElapsed() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        let start = Date.now
        controller.begin(at: start)
        let choreography = ThresholdChoreography(motion: .full)
        #expect(controller.frame(at: start.addingTimeInterval(1.0))
                == choreography.frame(atElapsed: 1.0))
    }

    @Test("The exit interpolates from the frame captured at the moment of the tap")
    func exitInterpolatesFromCapturedFrame() {
        let controller = ThresholdController(isSuppressed: false, motion: .full)
        let start = Date.now
        controller.begin(at: start)
        let tapTime = start.addingTimeInterval(1.0)
        let choreography = ThresholdChoreography(motion: .full)
        let captured = choreography.frame(atElapsed: 1.0)

        controller.skip(now: tapTime)

        #expect(controller.frame(at: tapTime) == captured)
        #expect(controller.frame(at: tapTime.addingTimeInterval(ThresholdChoreography.skipDuration))
                == choreography.frame(atElapsed: choreography.totalDuration))
    }

    @Test("Reduced motion controllers use the short arc")
    func reducedMotionUsesShortArc() {
        let controller = ThresholdController(isSuppressed: false, motion: .reduced)
        #expect(controller.totalDuration < 1.0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData test -only-testing:IlumionateTests/ThresholdControllerTests
```

Expected: compile failure, `cannot find 'ThresholdController' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Ilumionate/Threshold/ThresholdController.swift`:

```swift
//
//  ThresholdController.swift
//  Ilumionate
//
//  Owns the launch threshold's clock, its phase, and the decision about
//  whether it should run at all.
//
//  The controller takes an injected `now` on every call rather than reading the
//  clock itself, so the whole phase machine is testable without waiting.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class ThresholdController {

    enum Phase: Equatable {
        case running(start: Date)
        case exiting(from: ThresholdChoreography.Frame, start: Date)
        case finished
    }

    private let choreography: ThresholdChoreography
    private(set) var phase: Phase

    /// - Parameters:
    ///   - isSuppressed: when true the threshold never appears. See
    ///     `shouldSuppress` for the two cases that set it.
    ///   - motion: `.reduced` mirrors the Reduce Motion accessibility setting.
    init(isSuppressed: Bool, motion: ThresholdChoreography.Motion, now: Date = .now) {
        self.choreography = ThresholdChoreography(motion: motion)
        self.phase = isSuppressed ? .finished : .running(start: now)
    }

    var isPresenting: Bool {
        phase != .finished
    }

    var isExiting: Bool {
        if case .exiting = phase { return true }
        return false
    }

    var totalDuration: TimeInterval {
        choreography.totalDuration
    }

    /// Restarts the clock. The view calls this on appear so the arc is timed
    /// from the first frame actually drawn, not from init.
    func begin(at now: Date) {
        guard case .running = phase else { return }
        phase = .running(start: now)
    }

    /// Captures the current frame and eases out from it. A no-op unless the
    /// arc is still running, so a double tap cannot restart the interpolation.
    func skip(now: Date) {
        guard case .running = phase else { return }
        phase = .exiting(from: frame(at: now), start: now)
    }

    func finish() {
        phase = .finished
    }

    func frame(at now: Date) -> ThresholdChoreography.Frame {
        switch phase {
        case .running(let start):
            choreography.frame(atElapsed: now.timeIntervalSince(start))
        case .exiting(let captured, let start):
            choreography.exitFrame(
                from: captured,
                progress: now.timeIntervalSince(start) / ThresholdChoreography.skipDuration
            )
        case .finished:
            choreography.frame(atElapsed: choreography.totalDuration)
        }
    }

    /// True once the current phase has run its course at `now`.
    func hasElapsed(at now: Date) -> Bool {
        switch phase {
        case .running(let start):
            now.timeIntervalSince(start) >= choreography.totalDuration
        case .exiting(_, let start):
            now.timeIntervalSince(start) >= ThresholdChoreography.skipDuration
        case .finished:
            true
        }
    }

    // MARK: - Suppression

    /// The threshold stands down in two situations, both of them cases where
    /// playing it would actively hurt.
    static var shouldSuppress: Bool {
        // First launch: `ContentView.checkForFirstLaunch()` raises Onboarding
        // 800ms after appear — squarely inside the Bloom beat. Onboarding is
        // the entry experience that time; the threshold is not needed.
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            return true
        }

        #if canImport(UIKit)
        // VoiceOver: a decorative animation with nothing to announce that
        // blocks the shell for 2.6 seconds is hostile to a screen reader user.
        if UIAccessibility.isVoiceOverRunning {
            return true
        }
        #endif

        return false
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData test -only-testing:IlumionateTests/ThresholdControllerTests
```

Expected: all 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/Threshold/ThresholdController.swift IlumionateTests/ThresholdControllerTests.swift
git commit -m "feat(threshold): add the phase machine and suppression rules"
```

---

## Task 3: The vignette

A radial mask that darkens the periphery. `closure` 0 draws nothing at all; 1 draws a fully closed vignette.

**Files:**
- Create: `Ilumionate/Threshold/ThresholdVignette.swift`

- [ ] **Step 1: Write the view**

Create `Ilumionate/Threshold/ThresholdVignette.swift`:

```swift
//
//  ThresholdVignette.swift
//  Ilumionate
//
//  Darkness that closes in from the edges during Arrival and releases during
//  Opening. The periphery is where the cluttered phone was, so the periphery
//  is what goes first.
//

import SwiftUI

struct ThresholdVignette: View {
    /// 0 = wide open (invisible), 1 = fully closed in around the centre.
    var closure: Double

    var body: some View {
        // At full closure the clear centre is a little under half the screen's
        // shorter edge, so the orb always sits inside untouched space.
        let innerFraction = 0.85 - 0.45 * closure

        GeometryReader { proxy in
            let extent = max(proxy.size.width, proxy.size.height)
            RadialGradient(
                colors: [.clear, Color.bgDeep],
                center: .center,
                startRadius: extent * innerFraction * 0.5,
                endRadius: extent * 0.78
            )
            .opacity(closure)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Closed") {
    ZStack { Color.bgPrimary.ignoresSafeArea(); LumeOrb(size: .hero); ThresholdVignette(closure: 1) }
}
#Preview("Open") {
    ZStack { Color.bgPrimary.ignoresSafeArea(); LumeOrb(size: .hero); ThresholdVignette(closure: 0) }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/Threshold/ThresholdVignette.swift
git commit -m "feat(threshold): add the closing vignette"
```

---

## Task 4: The threshold view

**Files:**
- Create: `Ilumionate/Threshold/ThresholdView.swift`

- [ ] **Step 1: Write the view**

Create `Ilumionate/Threshold/ThresholdView.swift`:

```swift
//
//  ThresholdView.swift
//  Ilumionate
//
//  The launch threshold. Void, a breathing orb, and a vignette that closes and
//  releases — then the app is simply there.
//
//  The aurora drawn here is deliberately the same field Home draws, at the same
//  mood and the same phase: `AuroraBackground` animates off the absolute clock,
//  so two instances mounted seconds apart are pixel-identical. That is what
//  makes the exit seamless without any geometry matching.
//

import SwiftUI

struct ThresholdView: View {
    /// Plain `let` is correct here — `@Observable` tracks reads without
    /// `@Bindable`, and nothing in this view needs a two-way binding.
    let controller: ThresholdController

    /// Same call Home makes, so the two fields agree on colour as well as phase.
    private var mood: BrainwaveCategory {
        PortalRecommender.category(forHour: Calendar.current.component(.hour, from: .now))
    }

    var body: some View {
        TimelineView(.animation) { context in
            let frame = controller.frame(at: context.date)

            ZStack {
                Color.bgDeep
                    .ignoresSafeArea()

                AuroraBackground(mood: mood)
                    .opacity(frame.auroraOpacity)

                LumeOrb(size: .hero)
                    .scaleEffect(frame.orbScale)
                    .opacity(frame.orbOpacity)

                ThresholdVignette(closure: frame.vignetteClosure)

                Button {
                    controller.skip(now: .now)
                } label: {
                    Color.clear.contentShape(.rect)
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()
                .accessibilityLabel("Skip the opening")
            }
            .onChange(of: controller.hasElapsed(at: context.date)) { _, elapsed in
                if elapsed { controller.finish() }
            }
        }
        .task {
            controller.begin(at: .now)
        }
    }
}

#Preview("Full motion") {
    ThresholdView(controller: ThresholdController(isSuppressed: false, motion: .full))
}
#Preview("Reduced motion") {
    ThresholdView(controller: ThresholdController(isSuppressed: false, motion: .reduced))
}
```

- [ ] **Step 2: Verify it compiles**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/Threshold/ThresholdView.swift
git commit -m "feat(threshold): compose the arc over a shared aurora field"
```

---

## Task 5: Colour-matched launch frame

Without this the OS draws a white (or black) frame before any of your code runs, and the threshold begins with a flash — the opposite of the intent.

**Files:**
- Create: `Ilumionate/Assets.xcassets/LaunchBackground.colorset/Contents.json`
- Modify: `Ilumionate/Info.plist:68-69`

- [ ] **Step 1: Create the colour set**

The values match `Color.bgDeep` — `TranceDesignSystem.swift:44` resolves it to `dawnDeep` (`#FFE9F4`) in light and `voidDeep` (`#03040C`) in dark.

```bash
mkdir -p Ilumionate/Assets.xcassets/LaunchBackground.colorset
```

Create `Ilumionate/Assets.xcassets/LaunchBackground.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0xF4",
          "green" : "0xE9",
          "red" : "0xFF"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0x0C",
          "green" : "0x04",
          "red" : "0x03"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 2: Point the launch screen at it**

In `Ilumionate/Info.plist`, replace:

```xml
	<key>UILaunchScreen</key>
	<dict/>
```

with:

```xml
	<key>UILaunchScreen</key>
	<dict>
		<key>UIColorName</key>
		<string>LaunchBackground</string>
	</dict>
```

- [ ] **Step 3: Verify the launch frame matches**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData build
```

Expected: BUILD SUCCEEDED.

Then launch the app in the simulator in dark appearance and watch the first moment. Expected: no white flash — the OS frame is already the void colour, and the first frame of Arrival continues it. Repeat in light appearance; the frame should be the pale dawn wash, not white.

> If the colour still flashes white, the asset name in `Info.plist` does not match the `.colorset` directory name. It is matched by name at runtime, so a typo fails silently.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/Assets.xcassets/LaunchBackground.colorset/Contents.json Ilumionate/Info.plist
git commit -m "feat(threshold): match the OS launch frame to the void"
```

---

## Task 6: Wire the overlay into the shell

**Files:**
- Modify: `Ilumionate/ContentView.swift:32` (delete `isLoading`), `:44-45` (the overlay), `:242` and `:254` (the dead assignments)

- [ ] **Step 1: Add the controller state**

In `Ilumionate/ContentView.swift`, replace this line (currently line 32):

```swift
    @State private var isLoading = true
```

with:

```swift
    @State private var threshold = ThresholdController(
        isSuppressed: ThresholdController.shouldSuppress,
        motion: .full
    )
```

> `isLoading` is dead — assigned at two places and read by nothing. It goes now rather than becoming a tempting thing to gate the threshold on, which is how a ritual turns back into a loading screen.

- [ ] **Step 2: Remove the two dead assignments**

Delete the line `isLoading = true` (around line 242) and the line `isLoading = false` (around line 254). Find them with:

```bash
grep -n "isLoading" Ilumionate/ContentView.swift
```

Expected after deleting: no output.

- [ ] **Step 3: Overlay the threshold**

Replace the opening of `body`:

```swift
    var body: some View {
        mainLayout
        .task {
```

with:

```swift
    var body: some View {
        ZStack {
            mainLayout

            #if os(iOS)
            if threshold.isPresenting {
                ThresholdView(controller: threshold)
                    .transition(.identity)
            }
            #endif
        }
        .task {
```

> `.transition(.identity)` matters: the view animates its own exit through the choreography, and letting SwiftUI add an implicit fade on top would double the dissolve.

> The `#if os(iOS)` is the only platform fork. There is no cluttered iPhone environment to leave on macOS, and an overlay inside a resizable window reads as a modal glitch. The `Threshold/` files themselves stay platform-free.

- [ ] **Step 4: Add the motion switch to the controller**

In `Ilumionate/Threshold/ThresholdController.swift`, replace:

```swift
    private let choreography: ThresholdChoreography
```

with:

```swift
    private(set) var choreography: ThresholdChoreography
```

and add this method directly after `begin(at:)`:

```swift
    /// Swaps to the short opacity-only arc, and restarts the clock so the
    /// shorter arc gets its full length. Called once on appear, because the
    /// accessibility environment is not readable from a property initialiser.
    func adoptReducedMotion(at now: Date) {
        guard case .running = phase, choreography.motion == .full else { return }
        choreography = ThresholdChoreography(motion: .reduced)
        phase = .running(start: now)
    }
```

- [ ] **Step 5: Honour Reduce Motion from the shell**

The controller is built in a property initialiser, which cannot read `@Environment`, so the switch happens on appear instead. Add the environment value alongside the existing `scenePhase` property near line 17:

```swift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

Then inside the existing `.task { ... }` block, as its first line — before `await analysisManager.restoreManualRecoveries()`:

```swift
            if reduceMotion { threshold.adoptReducedMotion(at: .now) }
```

- [ ] **Step 6: Run the full test suite**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData test -only-testing:IlumionateTests
```

Expected: all tests pass, including the two new suites and every pre-existing test.

- [ ] **Step 7: Commit**

```bash
git add Ilumionate/ContentView.swift Ilumionate/Threshold/ThresholdController.swift Ilumionate/Threshold/ThresholdChoreography.swift
git commit -m "feat(threshold): open the app through the threshold on cold launch"
```

---

## Task 7: Verify both platforms and every suppression path

Nothing here is automated. These are the behaviours the value tests cannot reach.

**Files:** none modified.

- [ ] **Step 1: Confirm macOS is untouched**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData build
```

Expected: BUILD SUCCEEDED. Launch it. Expected: the sidebar shell appears immediately with no threshold.

- [ ] **Step 2: Confirm Mac Catalyst still compiles**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the macOS test suite**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/claude-501/-Users-byronquine-Projects-Ilumionate/3129a8f3-f525-4d0a-878c-a8e688c164ba/scratchpad/DerivedData test -only-testing:IlumionateTests
```

Expected: all tests pass. The choreography is platform-free, so it must pass here too.

- [ ] **Step 4: Walk the iOS behaviours**

On an iPhone 17 Pro simulator, with onboarding already completed, check each of these:

| Check | Expected |
|---|---|
| Cold launch, dark appearance | No white flash. Vignette closes, orb blooms, holds, opens into Home |
| Cold launch, light appearance | Same arc over the dawn wash. The OS frame is pale, not white |
| The exit moment | The aurora does **not** jump, shift, dim or recolour as the threshold clears. This is the single most important thing to watch |
| Tap during Bloom | Eases out within ~0.35s from where the orb was. No snap |
| Tap during Arrival | Same, no crash, no stutter |
| Double tap | Behaves exactly like a single tap |
| Background then foreground | No replay. The threshold is cold-launch only |
| Settings → Reduce Motion on, then cold launch | Short fade, no scaling, no spinning, no vignette travel |
| Settings → VoiceOver on, then cold launch | Straight to Home, no threshold |
| Delete app, reinstall, launch | No threshold. Onboarding appears as it always did |

- [ ] **Step 5: Commit if anything needed fixing**

```bash
git add -A
git commit -m "fix(threshold): address issues found in platform verification"
```

---

## Definition of done

- [ ] Cold launch on iOS shows the four-beat arc with no white flash and no seam at the OS handoff, in both appearances
- [ ] The aurora field does not jump, shift or recolour when the threshold exits
- [ ] A tap at any point eases out within 0.35s
- [ ] Resume from background does not replay the threshold
- [ ] First launch goes to Onboarding with no threshold underneath
- [ ] Reduce Motion produces the short fade variant
- [ ] VoiceOver launches straight into Home
- [ ] macOS and Mac Catalyst build and launch unchanged
- [ ] `ThresholdChoreographyTests` and `ThresholdControllerTests` pass on both the macOS and iOS Simulator destinations
- [ ] No regression in the existing suite
