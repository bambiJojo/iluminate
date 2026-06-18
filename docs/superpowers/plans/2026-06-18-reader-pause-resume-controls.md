# Reader Pause / Resume / Live Settings / Speed Control — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the control-free Text Trance RSVP reader into a pausable, resumable, live-tunable session with continuous speed control and resume-after-close persistence.

**Architecture:** Keep the existing three-layer split — `TextPacingEngine` (pure schedule), `TextTranceSession` (`@MainActor @Observable` coordinator), `TextTrancePlayerView` (render). The session gains an index-driven, interruptible pacing driver; speed becomes a live `Double` multiplier applied at the hold site; subliminal/binaural/light are live-toggleable; a new `ReaderProgressStore` persists a per-script resume snapshot. The reader's control overlay reuses the audio player's `PlayerControlsVisibility` so surfacing is identical.

**Tech Stack:** Swift 6.2, SwiftUI, `@Observable`, Swift Testing (`import Testing`), Xcode project `Ilumionate.xcodeproj` (scheme `Ilumionate`).

**Spec:** `docs/superpowers/specs/2026-06-18-reader-pause-resume-controls-design.md`

---

## Conventions used in every task

**Build/test command** (adjust the simulator name to one from `xcrun simctl list devices available` if iPhone 15 is absent):

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 15' test 2>&1 | tail -40
```

New `.swift` files under `Ilumionate/TextTrance/` and `IlumionateTests/TextTrance/` must be added to the correct Xcode target (app target for sources, test target for tests). Xcode 16 synchronized groups usually pick these up automatically; **Task 13 verifies membership explicitly.** Until Task 13, if a new file's symbols are "not found," confirm target membership before debugging code.

**Commit style:** Conventional commits, one per task (or per red→green cycle for larger tasks).

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `Ilumionate/TextTrance/TextPacingEngine.swift` | Pure schedule + speed model | Modify: `speed: Speed` → `speedMultiplier: Double`; add nominal-WPM + clamp constants |
| `Ilumionate/TextTrance/TextTranceSession.swift` | Session coordinator + driver + persistence hooks | Heavy modify |
| `Ilumionate/TextTrance/ReaderResumeState.swift` | Codable resume snapshot + persisted settings | **Create** |
| `Ilumionate/TextTrance/ReaderProgressStore.swift` | File-backed per-script resume store | **Create** |
| `Ilumionate/TextTrance/ReaderControlPanel.swift` | In-session control panel subview (transport, speed) | **Create** |
| `Ilumionate/TextTrance/ReaderSettingsDrawer.swift` | Live-settings sheet (binaural/subliminal/light) | **Create** |
| `Ilumionate/TextTrance/TextTrancePlayerView.swift` | Render + control overlay + gestures | Heavy modify |
| `Ilumionate/TextTrance/TextTranceSetupView.swift` | Speed slider; Resume / Start over / Begin | Modify |
| `IlumionateTests/TextTrance/PacingSleepController.swift` | Test helper: step-controllable sleep | **Create** |
| `IlumionateTests/TextTrance/*Tests.swift` | Driver, store, engine tests | Create/modify |

---

## Task 1: Migrate speed to a continuous `speedMultiplier`

**Files:**
- Modify: `Ilumionate/TextTrance/TextPacingEngine.swift`
- Test: `IlumionateTests/TextTrance/TextPacingEngineTests.swift`

The `Speed` enum is retained only as preset anchors and as a convenience initializer so existing call sites (`speed: .natural`) keep compiling. The timing source of truth becomes `speedMultiplier: Double`.

- [ ] **Step 1: Write the failing test**

Add to `IlumionateTests/TextTrance/TextPacingEngineTests.swift`:

```swift
@Test func speedMultiplierScalesReadableDurationsInversely() {
    let script = TranceScript(
        schemaVersion: 1, id: "s", title: "S", theme: .relaxation,
        supportedArcs: [.fullText], language: "en",
        source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
        segments: [TranceScriptSegment(phase: .induction, text: "alpha bravo charlie",
            pacing: SegmentPacing(baseWPM: 120), arcs: nil, triggersHandoff: nil)])
    let slow = TextPacingEngine.schedule(
        for: script, settings: TextPacingSettings(arc: .fullText, speedMultiplier: 1.0,
                                                  subliminalEnabled: false))
    let fast = TextPacingEngine.schedule(
        for: script, settings: TextPacingSettings(arc: .fullText, speedMultiplier: 2.0,
                                                  subliminalEnabled: false))
    // 2x multiplier => 2x WPM => half the duration per word.
    #expect(abs(slow[0].duration - fast[0].duration * 2) < 0.0001)
}

@Test func wordSequenceIsInvariantAcrossSpeedAndSubliminal() {
    let script = TranceScript(
        schemaVersion: 1, id: "i", title: "I", theme: .relaxation,
        supportedArcs: [.fullText], language: "en",
        source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
        segments: [TranceScriptSegment(phase: .induction, text: "go deeper now and rest",
            pacing: SegmentPacing(baseWPM: 120), arcs: nil, triggersHandoff: nil)])
    let a = TextPacingEngine.schedule(for: script,
        settings: TextPacingSettings(arc: .fullText, speedMultiplier: 0.5, subliminalEnabled: true))
    let b = TextPacingEngine.schedule(for: script,
        settings: TextPacingSettings(arc: .fullText, speedMultiplier: 1.7, subliminalEnabled: false))
    #expect(a.map(\.text) == b.map(\.text))
    #expect(a.count == b.count)
}

@Test func nominalWPMMapsFromMultiplier() {
    #expect(TextPacingEngine.nominalWPM(forMultiplier: 1.0) == 150)
    #expect(TextPacingEngine.nominalWPM(forMultiplier: 2.0) == 300)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the build/test command. Expected: compile failure — `speedMultiplier:` initializer and `nominalWPM` do not exist yet.

- [ ] **Step 3: Modify `TextPacingSettings` and the engine**

In `TextPacingEngine.swift`, replace the `TextPacingSettings` struct's stored field and initializer (lines ~85–98) so it stores `speedMultiplier` and offers both initializers:

```swift
    let arc: ScriptArc
    let speedMultiplier: Double
    let subliminalEnabled: Bool
    let subliminalSpeed: SubliminalSpeed

    init(arc: ScriptArc,
         speedMultiplier: Double,
         subliminalEnabled: Bool = true,
         subliminalSpeed: SubliminalSpeed = .medium) {
        self.arc = arc
        self.speedMultiplier = speedMultiplier
        self.subliminalEnabled = subliminalEnabled
        self.subliminalSpeed = subliminalSpeed
    }

    /// Convenience for the legacy three presets (setup anchors, tests).
    init(arc: ScriptArc,
         speed: Speed,
         subliminalEnabled: Bool = true,
         subliminalSpeed: SubliminalSpeed = .medium) {
        self.init(arc: arc, speedMultiplier: speed.multiplier,
                  subliminalEnabled: subliminalEnabled, subliminalSpeed: subliminalSpeed)
    }
```

Keep the `Speed` and `SubliminalSpeed` enums exactly as they are (still used by the convenience init and for slider anchor labels).

In the `TextPacingEngine` enum, add constants and helper near the other `static let`s:

```swift
    /// Live speed slider bounds (multiplier on nominal WPM).
    static let minSpeedMultiplier: Double = 0.5
    static let maxSpeedMultiplier: Double = 2.0

    /// Representative WPM for the slider readout. Per-segment WPM varies; this
    /// is the nominal default-base rate scaled by the multiplier.
    static func nominalWPM(forMultiplier multiplier: Double) -> Int {
        Int((defaultBaseWPM * multiplier).rounded())
    }
```

Change `effectiveWPM` (lines ~177–185) to take the multiplier:

```swift
    private static func effectiveWPM(for segment: TranceScriptSegment,
                                     speedMultiplier: Double) -> Double {
        if let hint = segment.pacing?.baseWPM, hint > 0 {
            return hint * speedMultiplier
        }
        let depth = segment.phase.tranceDepthEstimate
        let depthFactor = 1.0 - depth * (1.0 - deepeningFloor)
        return defaultBaseWPM * depthFactor * speedMultiplier
    }
```

Update its call site in `schedule` (line ~120):

```swift
            let baseDuration = 60.0 / effectiveWPM(for: segment, speedMultiplier: settings.speedMultiplier)
```

- [ ] **Step 4: Run tests to verify they pass**

Run the build/test command. Expected: PASS. Existing engine/session tests using `speed: .natural` still compile via the convenience init.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextPacingEngine.swift IlumionateTests/TextTrance/TextPacingEngineTests.swift
git commit -m "feat(reader): continuous speedMultiplier in pacing engine"
```

---

## Task 2: Add `speedMultiplier` to session settings

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceSession.swift:11-38` (the `TextTranceSessionSettings` struct)

Replace the `speed: Speed` field with `speedMultiplier: Double`, keeping a `speed:` convenience init so existing tests/setup call sites compile.

- [ ] **Step 1: Modify `TextTranceSessionSettings`**

Replace the struct body (keep `arc`, layers, etc.) so the speed field is a multiplier:

```swift
struct TextTranceSessionSettings: Sendable {
    let arc: ScriptArc
    let speedMultiplier: Double
    let lightEnabled: Bool
    let binauralEnabled: Bool
    let beatFrequency: Double
    let postHandoffDuration: TimeInterval
    let subliminalEnabled: Bool
    let subliminalSpeed: TextPacingSettings.SubliminalSpeed

    init(arc: ScriptArc,
         speedMultiplier: Double,
         lightEnabled: Bool,
         binauralEnabled: Bool,
         beatFrequency: Double,
         postHandoffDuration: TimeInterval,
         subliminalEnabled: Bool = true,
         subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium) {
        self.arc = arc
        self.speedMultiplier = speedMultiplier
        self.lightEnabled = lightEnabled
        self.binauralEnabled = binauralEnabled
        self.beatFrequency = beatFrequency
        self.postHandoffDuration = postHandoffDuration
        self.subliminalEnabled = subliminalEnabled
        self.subliminalSpeed = subliminalSpeed
    }

    /// Convenience for the legacy three presets (tests, anchors).
    init(arc: ScriptArc,
         speed: TextPacingSettings.Speed,
         lightEnabled: Bool,
         binauralEnabled: Bool,
         beatFrequency: Double,
         postHandoffDuration: TimeInterval,
         subliminalEnabled: Bool = true,
         subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium) {
        self.init(arc: arc, speedMultiplier: speed.multiplier,
                  lightEnabled: lightEnabled, binauralEnabled: binauralEnabled,
                  beatFrequency: beatFrequency, postHandoffDuration: postHandoffDuration,
                  subliminalEnabled: subliminalEnabled, subliminalSpeed: subliminalSpeed)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build/test command. Expected: PASS (the session body still references `settings.speed` at two spots — those are fixed in Task 3, but the convenience init means `settings.speed` no longer exists, so **a compile error here is expected and resolved in Task 3**). To keep this task green on its own, also apply the two edits in Task 3 Step 1 now, then build. (Tasks 2 and 3 may be committed together.)

- [ ] **Step 3: Commit (with Task 3)**

Defer the commit to the end of Task 3.

---

## Task 3: Build the resumable pacing driver (index loop, no pause yet)

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceSession.swift`
- Test: `IlumionateTests/TextTrance/TextTranceSessionTests.swift`

Introduce `currentWordIndex`, centralize schedule generation, build the base schedule at multiplier 1.0 (speed is applied live at the hold site), and add `begin(from:)`. Behavior stays identical to today; existing tests must still pass.

- [ ] **Step 1: Replace the session's stored state, init, and `begin()`**

In `TextTranceSession`, update the rendered-state block to add the index and a live speed var, and replace the immutable `settings`-derived schedule call. Replace the property block and `init` so the reference-char-count schedule is built at multiplier 1.0 and live setting copies exist:

```swift
    // Rendered state
    private(set) var currentWord: String = ""
    private(set) var currentPivotIndex: Int = 0
    private(set) var currentPhase: TrancePhase = .preTalk
    private(set) var isReading = false
    private(set) var lightActive = false
    private(set) var isComplete = false
    private(set) var currentFade: FadeKind = .none
    private(set) var currentDuration: TimeInterval = 0

    // Control state
    private(set) var currentWordIndex = 0
    var speedMultiplier: Double

    // Live, mutable copies of schedule-affecting settings.
    private(set) var subliminalEnabled: Bool
    private(set) var subliminalSpeed: TextPacingSettings.SubliminalSpeed

    let script: TranceScript
    let settings: TextTranceSessionSettings
    let readerReferenceCharacterCount: Int

    private let light: (any LightLayerControlling)?
    private let audio: (any AudioLayerControlling)?
    private let sleep: @Sendable (Duration) async -> Void
    private var schedule: [PacedWord] = []
    private var cancelled = false
    private var isRunning = false

    init(script: TranceScript,
         settings: TextTranceSessionSettings,
         light: (any LightLayerControlling)?,
         audio: (any AudioLayerControlling)?,
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.script = script
        self.settings = settings
        self.speedMultiplier = settings.speedMultiplier
        self.subliminalEnabled = settings.subliminalEnabled
        self.subliminalSpeed = settings.subliminalSpeed
        self.light = light
        self.audio = audio
        self.sleep = sleep
        // Sizing depends on word lengths, not durations; build at neutral speed.
        self.readerReferenceCharacterCount = TextTranceWordSizing.referenceCharacterCount(
            for: TextPacingEngine.schedule(
                for: script,
                settings: TextPacingSettings(arc: settings.arc,
                                             speedMultiplier: 1.0,
                                             subliminalEnabled: settings.subliminalEnabled,
                                             subliminalSpeed: settings.subliminalSpeed)))
    }

    /// Base schedule at neutral speed; live speed is applied per-word at the hold site.
    private func makeSchedule() -> [PacedWord] {
        TextPacingEngine.schedule(
            for: script,
            settings: TextPacingSettings(arc: settings.arc,
                                         speedMultiplier: 1.0,
                                         subliminalEnabled: subliminalEnabled,
                                         subliminalSpeed: subliminalSpeed))
    }

    /// Live-scaled hold: readable words scale inversely with speed; flashes are fixed.
    private func scaledHold(for word: PacedWord) -> TimeInterval {
        word.isSubliminal ? word.duration : word.duration / max(speedMultiplier, 0.0001)
    }

    private func render(_ word: PacedWord) {
        currentWord = word.text
        currentPivotIndex = word.pivotIndex
        currentPhase = word.phase
        currentFade = word.fade
        currentDuration = scaledHold(for: word)
    }
```

Now replace `begin()` with an index-driven version plus `begin(from:)`:

```swift
    /// Run the session to completion (or until `end()` cancels it).
    func begin() async { await begin(from: 0) }

    func begin(from startIndex: Int) async {
        guard !cancelled, !isComplete, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        if settings.binauralEnabled, let audio {
            audio.syncBeatFrequency(to: settings.beatFrequency)
            audio.start()
        }

        schedule = makeSchedule()
        currentWordIndex = min(max(startIndex, 0), schedule.count)

        isReading = true
        while currentWordIndex < schedule.count, !cancelled, !Task.isCancelled {
            let word = schedule[currentWordIndex]
            render(word)
            await holdCurrentWord(scaledHold(for: word))
            if cancelled || Task.isCancelled { break }
            currentWordIndex += 1
        }
        isReading = false

        if settings.arc == .handoff, !cancelled, !Task.isCancelled {
            if settings.lightEnabled, let light {
                light.start()
                lightActive = true
            }
            await sleep(.seconds(settings.postHandoffDuration))
            if lightActive {
                light?.stop()
                lightActive = false
            }
        }

        if settings.binauralEnabled { audio?.stop() }
        isComplete = !cancelled && !Task.isCancelled
    }

    /// Hold the current word. (Pause/resume is added in Task 5.)
    private func holdCurrentWord(_ duration: TimeInterval) async {
        await sleep(.seconds(duration))
    }
```

Keep the existing `end()` unchanged for now.

- [ ] **Step 2: Add a test for `begin(from:)` and index exposure**

Add to `TextTranceSessionTests.swift`:

```swift
@Test func beginFromStartsAtGivenIndex() async {
    let session = TextTranceSession(
        script: handoffScript(),
        settings: TextTranceSessionSettings(
            arc: .fullText, speedMultiplier: 1.0,
            lightEnabled: false, binauralEnabled: false,
            beatFrequency: 10, postHandoffDuration: 0),
        light: MockLightLayer(), audio: MockAudioLayer(), sleep: noSleep)
    // fullText schedule for "one two" => indices 0:"one", 1:"two".
    await session.begin(from: 1)
    #expect(session.currentWord == "two")
    #expect(session.isComplete)
}
```

- [ ] **Step 3: Run the full suite**

Run the build/test command. Expected: PASS — existing session tests (`lastReadWordIsExposed`, handoff, end, cancellation) plus the new test. The cancellation test relies on `Task.isCancelled` which the `while` loop checks.

- [ ] **Step 4: Commit (Tasks 2 + 3)**

```bash
git add Ilumionate/TextTrance/TextTranceSession.swift IlumionateTests/TextTrance/TextTranceSessionTests.swift
git commit -m "feat(reader): index-driven pacing driver with begin(from:) and live speed"
```

---

## Task 4: Test helper — step-controllable sleep

**Files:**
- Create: `IlumionateTests/TextTrance/PacingSleepController.swift`

A `@MainActor` helper that counts `sleep` calls and runs a per-call hook, letting tests inject `pause()` at a chosen word boundary deterministically.

- [ ] **Step 1: Create the helper**

```swift
//  PacingSleepController.swift
//  IlumionateTests

import Foundation
@testable import Ilumionate

/// Step-controllable sleep for driver tests. Each call increments `callCount`
/// and invokes `onSleep(callCount)` so a test can trigger pause/resume/settings
/// changes at a precise word boundary. Returns immediately (no real delay).
@MainActor
final class PacingSleepController {
    private(set) var callCount = 0
    var onSleep: (Int) -> Void = { _ in }

    func sleep(_ duration: Duration) async {
        callCount += 1
        onSleep(callCount)
    }

    /// The closure to inject into `TextTranceSession(sleep:)`.
    var sleepClosure: @Sendable (Duration) async -> Void {
        { [self] duration in await self.sleep(duration) }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build/test command. Expected: PASS (no behavior change yet; helper unused).

- [ ] **Step 3: Commit**

```bash
git add IlumionateTests/TextTrance/PacingSleepController.swift
git commit -m "test(reader): step-controllable sleep helper for driver tests"
```

---

## Task 5: Pause / resume

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceSession.swift`
- Test: `IlumionateTests/TextTrance/TextTranceSessionTests.swift`

Pause halts word advance and the binaural layer; resume restores both and continues the current word's remaining hold.

- [ ] **Step 1: Write the failing tests**

Add to `TextTranceSessionTests.swift`:

```swift
@Test func pauseHoldsIndexThenResumeCompletes() async {
    let audio = MockAudioLayer()
    let controller = PacingSleepController()
    let session = TextTranceSession(
        script: handoffScript(),
        settings: TextTranceSessionSettings(
            arc: .fullText, speedMultiplier: 1.0,
            lightEnabled: false, binauralEnabled: true,
            beatFrequency: 10, postHandoffDuration: 0),
        light: MockLightLayer(), audio: audio, sleep: controller.sleepClosure)

    // Pause when the first word's hold begins (callCount == 1).
    controller.onSleep = { call in if call == 1 { session.pause() } }

    let task = Task { await session.begin() }
    while !session.isPaused { await Task.yield() }

    #expect(session.currentWordIndex == 0)   // did not advance past word 0
    #expect(audio.stopCount == 1)            // binaural paused
    #expect(!session.isComplete)

    controller.onSleep = { _ in }            // stop re-pausing
    session.resume()
    await task.value

    #expect(session.isComplete)
    #expect(audio.startCount == 2)           // started, then restarted on resume
    #expect(session.currentWord == "two")
}

@Test func endWhilePausedTearsDownAndDoesNotComplete() async {
    let audio = MockAudioLayer()
    let controller = PacingSleepController()
    let session = TextTranceSession(
        script: handoffScript(),
        settings: TextTranceSessionSettings(
            arc: .handoff, speedMultiplier: 1.0,
            lightEnabled: true, binauralEnabled: true,
            beatFrequency: 10, postHandoffDuration: 60),
        light: MockLightLayer(), audio: audio, sleep: controller.sleepClosure)

    controller.onSleep = { call in if call == 1 { session.pause() } }
    let task = Task { await session.begin() }
    while !session.isPaused { await Task.yield() }

    session.end()
    await task.value

    #expect(!session.isComplete)
    #expect(audio.stopCount >= 1)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the build/test command. Expected: compile failure — `pause()`, `resume()`, `isPaused` do not exist.

- [ ] **Step 3: Implement pause/resume**

In `TextTranceSession`, add control state near the other private vars:

```swift
    private(set) var isPaused = false
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private var holdTask: Task<Void, Never>?
    private let now: @Sendable () -> TimeInterval
```

Add `now` to the initializer signature (default to a monotonic clock) and store it. Update the `init` parameter list to include, after `sleep`:

```swift
         now: @escaping @Sendable () -> TimeInterval = { ContinuousClock().now.secondsSinceArbitraryEpoch }) {
```

…and at the end of `init` set `self.now = now`. Add this helper at file scope (bottom of the file):

```swift
private extension ContinuousClock.Instant {
    /// Monotonic seconds from an arbitrary fixed epoch (process start-ish).
    var secondsSinceArbitraryEpoch: TimeInterval {
        let d = ContinuousClock().now - self   // negative; magnitude is fine for deltas
        return -(Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18)
    }
}
```

> Note: only *deltas* of `now()` are used (elapsed within a word), so the epoch is irrelevant. In tests `now` is injected to return scripted values.

Replace `holdCurrentWord` with a pause-aware version:

```swift
    /// Hold the current word, honoring pause. On pause mid-hold we keep the
    /// remaining time and suspend until `resume()`.
    private func holdCurrentWord(_ fullDuration: TimeInterval) async {
        var remaining = fullDuration
        while remaining > 0, !cancelled, !Task.isCancelled {
            if isPaused {
                await withCheckedContinuation { resumeContinuation = $0 }
                continue
            }
            let start = now()
            let task = Task { [sleep] in await sleep(.seconds(remaining)) }
            holdTask = task
            await task.value
            holdTask = nil
            if cancelled || Task.isCancelled { return }
            if isPaused {
                let elapsed = now() - start
                remaining = max(0, remaining - elapsed)
                continue
            }
            remaining = 0
        }
    }
```

Add `pause()` / `resume()`:

```swift
    /// Pause word advance and the binaural layer.
    func pause() {
        guard isReading, !isPaused, !isComplete else { return }
        isPaused = true
        holdTask?.cancel()                 // wake the in-flight hold promptly
        if settings.binauralEnabled { audio?.stop() }
    }

    /// Resume word advance and the binaural layer.
    func resume() {
        guard isPaused, !isComplete else { return }
        isPaused = false
        if settings.binauralEnabled, isReading { audio?.start() }
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
```

Update `end()` to also release a parked continuation so a paused `begin` can unwind:

```swift
    func end() {
        guard !isComplete else { return }
        cancelled = true
        holdTask?.cancel()
        if isPaused {
            isPaused = false
            resumeContinuation?.resume()
            resumeContinuation = nil
        }
        if lightActive {
            light?.stop()
            lightActive = false
        }
        if settings.binauralEnabled { audio?.stop() }
        isReading = false
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the build/test command. Expected: PASS, including the two new pause tests and all prior tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceSession.swift IlumionateTests/TextTrance/TextTranceSessionTests.swift
git commit -m "feat(reader): pause and resume with remaining-time tracking"
```

---

## Task 6: Live subliminal regen + binaural/light toggles

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceSession.swift`
- Test: `IlumionateTests/TextTrance/TextTranceSessionTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func togglingSubliminalKeepsIndexAndCurrentWord() async {
    let controller = PacingSleepController()
    let session = TextTranceSession(
        script: handoffScript(),
        settings: TextTranceSessionSettings(
            arc: .fullText, speedMultiplier: 1.0,
            lightEnabled: false, binauralEnabled: false,
            beatFrequency: 10, postHandoffDuration: 0,
            subliminalEnabled: false),
        light: MockLightLayer(), audio: MockAudioLayer(), sleep: controller.sleepClosure)

    controller.onSleep = { call in if call == 1 { session.pause() } }
    let task = Task { await session.begin() }
    while !session.isPaused { await Task.yield() }

    let wordBefore = session.currentWord
    let indexBefore = session.currentWordIndex
    session.setSubliminal(enabled: true, speed: .deep)   // regenerates schedule
    #expect(session.currentWordIndex == indexBefore)
    #expect(session.currentWord == wordBefore)

    controller.onSleep = { _ in }
    session.resume()
    await task.value
    #expect(session.isComplete)
}

@Test func setBinauralStartsAndStopsAudioLive() async {
    let audio = MockAudioLayer()
    let controller = PacingSleepController()
    let session = TextTranceSession(
        script: handoffScript(),
        settings: TextTranceSessionSettings(
            arc: .fullText, speedMultiplier: 1.0,
            lightEnabled: false, binauralEnabled: false,
            beatFrequency: 10, postHandoffDuration: 0),
        light: MockLightLayer(), audio: audio, sleep: controller.sleepClosure)

    controller.onSleep = { call in if call == 1 { session.pause() } }
    let task = Task { await session.begin() }
    while !session.isPaused { await Task.yield() }

    session.setBinaural(enabled: true)
    #expect(audio.startCount == 1)
    #expect(audio.lastBeatFrequency == 10)
    session.setBinaural(enabled: false)
    #expect(audio.stopCount == 1)

    controller.onSleep = { _ in }
    session.resume()
    await task.value
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the build/test command. Expected: compile failure — `setSubliminal`, `setBinaural` undefined.

- [ ] **Step 3: Implement the live setters**

Add a live `binauralActive` flag near the control state:

```swift
    private(set) var binauralActive: Bool
    private(set) var lightEnabledLive: Bool
```

Initialize in `init` (after the existing assignments):

```swift
        self.binauralActive = settings.binauralEnabled
        self.lightEnabledLive = settings.lightEnabled
```

Update `begin(from:)` to use `binauralActive` instead of `settings.binauralEnabled` for the initial audio start, and `lightEnabledLive` for the tail. Replace the audio-start block and tail-light condition:

```swift
        if binauralActive, let audio {
            audio.syncBeatFrequency(to: settings.beatFrequency)
            audio.start()
        }
```

```swift
        if settings.arc == .handoff, !cancelled, !Task.isCancelled {
            if lightEnabledLive, let light {
                light.start()
                lightActive = true
            }
```

Update `pause()`/`resume()` to gate on `binauralActive` instead of `settings.binauralEnabled`:

```swift
        if binauralActive { audio?.stop() }     // in pause()
```
```swift
        if binauralActive, isReading { audio?.start() }   // in resume()
```
and the tail-end stop in `begin` and `end`:
```swift
        if binauralActive { audio?.stop() }
```

Add the setters:

```swift
    /// Toggle subliminal flashing mid-session. Regenerates the base schedule
    /// (word sequence is invariant) and keeps the current index/word.
    func setSubliminal(enabled: Bool, speed: TextPacingSettings.SubliminalSpeed) {
        subliminalEnabled = enabled
        subliminalSpeed = speed
        let index = currentWordIndex
        schedule = makeSchedule()
        currentWordIndex = min(index, max(schedule.count - 1, 0))
        if currentWordIndex < schedule.count { render(schedule[currentWordIndex]) }
    }

    /// Toggle the binaural layer live.
    func setBinaural(enabled: Bool) {
        guard enabled != binauralActive else { return }
        binauralActive = enabled
        guard isReading, !isPaused else { return }
        if enabled, let audio {
            audio.syncBeatFrequency(to: settings.beatFrequency)
            audio.start()
        } else {
            audio?.stop()
        }
    }

    /// Toggle the post-handoff light tail (applied when the tail begins).
    func setLightEnabled(_ enabled: Bool) {
        lightEnabledLive = enabled
    }

    /// Clamp + apply a live speed multiplier.
    func setSpeed(multiplier: Double) {
        speedMultiplier = min(max(multiplier, TextPacingEngine.minSpeedMultiplier),
                              TextPacingEngine.maxSpeedMultiplier)
        if currentWordIndex < schedule.count { render(schedule[currentWordIndex]) }
    }
```

> Note: `makeSchedule()` already reads the live `subliminalEnabled`/`subliminalSpeed`, so the regen picks up the new values. Speed is not baked into the schedule, so `setSpeed` needs no regen — it only re-renders the current word's `currentDuration`.

- [ ] **Step 4: Run tests to verify they pass**

Run the build/test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceSession.swift IlumionateTests/TextTrance/TextTranceSessionTests.swift
git commit -m "feat(reader): live subliminal/binaural/light/speed setters"
```

---

## Task 7: Resume model + persisted settings

**Files:**
- Create: `Ilumionate/TextTrance/ReaderResumeState.swift`
- Test: `IlumionateTests/TextTrance/ReaderResumeStateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//  ReaderResumeStateTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct ReaderResumeStateTests {
    @Test func roundTripsThroughJSON() throws {
        let state = ReaderResumeState(
            scriptId: "abc",
            wordIndex: 42,
            settings: PersistedReaderSettings(
                arc: .handoff, speedMultiplier: 1.25,
                subliminalEnabled: true, subliminalSpeed: .deep,
                binauralEnabled: false, lightEnabled: true, beatFrequency: 10),
            phase: .reading,
            scriptContentHash: "hash123",
            savedAt: Date(timeIntervalSince1970: 1_000_000))
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReaderResumeState.self, from: data)
        #expect(decoded.wordIndex == 42)
        #expect(decoded.settings.speedMultiplier == 1.25)
        #expect(decoded.phase == .reading)
    }

    @Test func contentHashIsStableForSameText() {
        let a = ReaderResumeState.contentHash(for: "drift down now")
        let b = ReaderResumeState.contentHash(for: "drift down now")
        let c = ReaderResumeState.contentHash(for: "drift down NOW")
        #expect(a == b)
        #expect(a != c)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the build/test command. Expected: compile failure — types undefined.

- [ ] **Step 3: Create the model**

```swift
//  ReaderResumeState.swift
//  Ilumionate
//
//  Codable snapshot of an in-progress reading session, used to resume after
//  the player is closed. Persisted per script by ReaderProgressStore.

import Foundation
import CryptoKit

/// Settings needed to faithfully reconstruct a session on resume.
struct PersistedReaderSettings: Codable, Sendable, Equatable {
    let arc: ScriptArc
    let speedMultiplier: Double
    let subliminalEnabled: Bool
    let subliminalSpeed: TextPacingSettings.SubliminalSpeed
    let binauralEnabled: Bool
    let lightEnabled: Bool
    let beatFrequency: Double
}

/// Where in the arc the user left off.
enum ResumePhase: Codable, Sendable, Equatable {
    case reading
    case handoffTail(elapsed: TimeInterval)
}

struct ReaderResumeState: Codable, Sendable, Equatable {
    let scriptId: String
    let wordIndex: Int
    let settings: PersistedReaderSettings
    let phase: ResumePhase
    let scriptContentHash: String
    let savedAt: Date

    /// Stable hash of the script's rendered text, used to detect that the
    /// source changed (e.g. an imported web reading source) since saving.
    static func contentHash(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

> `TextPacingSettings.SubliminalSpeed` and `ScriptArc` are already `Codable` (`String`-backed enums), so they encode directly.

- [ ] **Step 4: Run test to verify it passes**

Run the build/test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/ReaderResumeState.swift IlumionateTests/TextTrance/ReaderResumeStateTests.swift
git commit -m "feat(reader): ReaderResumeState snapshot model with content hash"
```

---

## Task 8: ReaderProgressStore (file-backed, injectable)

**Files:**
- Create: `Ilumionate/TextTrance/ReaderProgressStore.swift`
- Test: `IlumionateTests/TextTrance/ReaderProgressStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
//  ReaderProgressStoreTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct ReaderProgressStoreTests {
    private func tempDir() -> URL {
        URL.temporaryDirectory.appending(path: "reader-store-\(UUID().uuidString)")
    }

    private func makeState(id: String, savedAt: Date = .now) -> ReaderResumeState {
        ReaderResumeState(
            scriptId: id, wordIndex: 5,
            settings: PersistedReaderSettings(
                arc: .fullText, speedMultiplier: 1.0,
                subliminalEnabled: true, subliminalSpeed: .medium,
                binauralEnabled: false, lightEnabled: false, beatFrequency: 10),
            phase: .reading, scriptContentHash: "h", savedAt: savedAt)
    }

    @Test func savesAndLoadsByScriptId() {
        let store = ReaderProgressStore(directory: tempDir())
        store.save(makeState(id: "alpha"))
        #expect(store.resumeState(forScriptId: "alpha")?.wordIndex == 5)
        #expect(store.resumeState(forScriptId: "missing") == nil)
    }

    @Test func persistsAcrossInstances() {
        let dir = tempDir()
        let a = ReaderProgressStore(directory: dir)
        a.save(makeState(id: "beta"))
        let b = ReaderProgressStore(directory: dir)
        #expect(b.resumeState(forScriptId: "beta")?.wordIndex == 5)
    }

    @Test func clearRemovesEntry() {
        let store = ReaderProgressStore(directory: tempDir())
        store.save(makeState(id: "gamma"))
        store.clear(scriptId: "gamma")
        #expect(store.resumeState(forScriptId: "gamma") == nil)
    }

    @Test func expiredEntriesArePrunedOnLoad() {
        let dir = tempDir()
        let old = Date.now.addingTimeInterval(-31 * 24 * 60 * 60)
        let a = ReaderProgressStore(directory: dir)
        a.save(makeState(id: "stale", savedAt: old))
        let b = ReaderProgressStore(directory: dir)   // prunes on load
        #expect(b.resumeState(forScriptId: "stale") == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the build/test command. Expected: compile failure — `ReaderProgressStore` undefined.

- [ ] **Step 3: Create the store**

```swift
//  ReaderProgressStore.swift
//  Ilumionate
//
//  File-backed, per-script resume snapshots for the Text Trance reader.
//  Chosen over UserDefaults for testability (injectable directory) and to
//  avoid the write race seen with PlaylistStore. Entries expire after 30 days.

import Foundation

@MainActor
@Observable
final class ReaderProgressStore {
    static let shared = ReaderProgressStore()

    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60
    private let fileURL: URL
    private var entries: [String: ReaderResumeState] = [:]

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "TextTrance")) {
        self.fileURL = directory.appending(path: "reader-progress.json")
        load()
    }

    func resumeState(forScriptId id: String) -> ReaderResumeState? {
        entries[id]
    }

    func save(_ state: ReaderResumeState) {
        entries[state.scriptId] = state
        persist()
    }

    func clear(scriptId: String) {
        entries[scriptId] = nil
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: ReaderResumeState].self, from: data)
        else { return }
        let cutoff = Date.now.addingTimeInterval(-Self.maxAge)
        entries = decoded.filter { $0.value.savedAt >= cutoff }
        if entries.count != decoded.count { persist() }   // write back the pruned set
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Non-fatal: resume is a convenience, not core playback.
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the build/test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/ReaderProgressStore.swift IlumionateTests/TextTrance/ReaderProgressStoreTests.swift
git commit -m "feat(reader): file-backed ReaderProgressStore with 30-day expiry"
```

---

## Task 9: Wire persistence into the session

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceSession.swift`
- Test: `IlumionateTests/TextTrance/TextTranceSessionTests.swift`

The session writes a snapshot on pause and on `end()` (incomplete), and clears the entry on completion. The store and a content hash are injected.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func savesSnapshotOnPauseAndClearsOnCompletion() async {
    let store = ReaderProgressStore(directory:
        URL.temporaryDirectory.appending(path: "rp-\(UUID().uuidString)"))
    let controller = PacingSleepController()
    let session = TextTranceSession(
        script: handoffScript(),
        settings: TextTranceSessionSettings(
            arc: .fullText, speedMultiplier: 1.0,
            lightEnabled: false, binauralEnabled: false,
            beatFrequency: 10, postHandoffDuration: 0),
        light: MockLightLayer(), audio: MockAudioLayer(),
        sleep: controller.sleepClosure, progressStore: store, scriptContentHash: "h")

    controller.onSleep = { call in if call == 1 { session.pause() } }
    let task = Task { await session.begin() }
    while !session.isPaused { await Task.yield() }

    #expect(store.resumeState(forScriptId: handoffScript().id) != nil)

    controller.onSleep = { _ in }
    session.resume()
    await task.value
    #expect(store.resumeState(forScriptId: handoffScript().id) == nil)   // cleared on completion
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the build/test command. Expected: compile failure — `progressStore:`/`scriptContentHash:` params undefined.

- [ ] **Step 3: Implement persistence hooks**

Add stored deps and extend `init` (after `now`):

```swift
    private let progressStore: ReaderProgressStore?
    private let scriptContentHash: String
```

Add to the `init` parameter list:

```swift
         progressStore: ReaderProgressStore? = nil,
         scriptContentHash: String = "") {
```

and assign at the end of `init`:

```swift
        self.progressStore = progressStore
        self.scriptContentHash = scriptContentHash
```

Add a snapshot builder and persistence calls:

```swift
    private func currentSnapshot() -> ReaderResumeState {
        ReaderResumeState(
            scriptId: script.id,
            wordIndex: currentWordIndex,
            settings: PersistedReaderSettings(
                arc: settings.arc,
                speedMultiplier: speedMultiplier,
                subliminalEnabled: subliminalEnabled,
                subliminalSpeed: subliminalSpeed,
                binauralEnabled: binauralActive,
                lightEnabled: lightEnabledLive,
                beatFrequency: settings.beatFrequency),
            phase: .reading,
            scriptContentHash: scriptContentHash,
            savedAt: .now)
    }

    /// Persist the current position so the session can resume after close.
    func persistProgress() {
        guard !isComplete, isReading else { return }
        progressStore?.save(currentSnapshot())
    }
```

Call `persistProgress()` at the end of `pause()`. In `begin(from:)`, after `isComplete = ...`, clear on completion:

```swift
        isComplete = !cancelled && !Task.isCancelled
        if isComplete { progressStore?.clear(scriptId: script.id) }
```

In `end()`, persist before tearing down (so closing keeps the place) — add near the top of `end()` after `cancelled = true`:

```swift
        if isReading, !isComplete { progressStore?.save(currentSnapshot()) }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the build/test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceSession.swift IlumionateTests/TextTrance/TextTranceSessionTests.swift
git commit -m "feat(reader): persist resume snapshot on pause/close, clear on completion"
```

---

## Task 10: In-session control panel subview

**Files:**
- Create: `Ilumionate/TextTrance/ReaderControlPanel.swift`

Pure presentational view: pause/play transport, speed slider + WPM readout, Settings and End buttons. State lives in the session/parent; this view takes a `@Bindable` session and closures.

- [ ] **Step 1: Create the view**

```swift
//  ReaderControlPanel.swift
//  Ilumionate
//
//  In-session control overlay panel for the Text Trance reader: transport,
//  live speed slider with WPM readout, settings, and end. Purely presentational.

import SwiftUI

struct ReaderControlPanel: View {
    @Bindable var session: TextTranceSession
    let onSettings: () -> Void
    let onEnd: () -> Void

    private var speedBinding: Binding<Double> {
        Binding(get: { session.speedMultiplier },
                set: { session.setSpeed(multiplier: $0) })
    }

    var body: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            speedControl

            HStack(spacing: 40) {
                Button("End", systemImage: "xmark", action: onEnd)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)

                Button {
                    if session.isPaused { session.resume() } else { session.pause() }
                } label: {
                    Image(systemName: session.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.auroraTeal)
                        .contentTransition(.symbolEffect(.replace))
                }

                Button("Settings", systemImage: "slider.horizontal.3", action: onSettings)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(TranceSpacing.screen)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.bottom, TranceSpacing.statusBar)
    }

    private var speedControl: some View {
        VStack(spacing: TranceSpacing.micro) {
            HStack {
                Text("Reading speed")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("~\(TextPacingEngine.nominalWPM(forMultiplier: session.speedMultiplier)) wpm")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
            }
            Slider(value: speedBinding,
                   in: TextPacingEngine.minSpeedMultiplier...TextPacingEngine.maxSpeedMultiplier)
                .tint(.auroraTeal)
        }
    }
}
```

> Verify `TranceSpacing.micro`, `TranceTypography.caption`, `Color.auroraTeal`, `Color.textSecondary` exist (they are used in `TextTrancePlayerView` / `UnifiedPlayerView`). If a token name differs, match the one used in `TextTranceSetupView.swift`.

- [ ] **Step 2: Build to verify it compiles**

Run the build/test command. Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/TextTrance/ReaderControlPanel.swift
git commit -m "feat(reader): in-session control panel with live speed slider"
```

---

## Task 11: Live-settings drawer subview

**Files:**
- Create: `Ilumionate/TextTrance/ReaderSettingsDrawer.swift`

- [ ] **Step 1: Create the view**

```swift
//  ReaderSettingsDrawer.swift
//  Ilumionate
//
//  Mid-session live-settings sheet: binaural, subliminal, and (handoff) light.
//  Changes apply immediately via the session's live setters.

import SwiftUI

struct ReaderSettingsDrawer: View {
    @Bindable var session: TextTranceSession
    @Environment(\.dismiss) private var dismiss

    private var binauralBinding: Binding<Bool> {
        Binding(get: { session.binauralActive },
                set: { session.setBinaural(enabled: $0) })
    }
    private var subliminalBinding: Binding<Bool> {
        Binding(get: { session.subliminalEnabled },
                set: { session.setSubliminal(enabled: $0, speed: session.subliminalSpeed) })
    }
    private var subliminalSpeedBinding: Binding<TextPacingSettings.SubliminalSpeed> {
        Binding(get: { session.subliminalSpeed },
                set: { session.setSubliminal(enabled: session.subliminalEnabled, speed: $0) })
    }
    private var lightBinding: Binding<Bool> {
        Binding(get: { session.lightEnabledLive },
                set: { session.setLightEnabled($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Binaural beats") {
                    Toggle("Enabled", isOn: binauralBinding)
                }
                Section("Subliminal flashing") {
                    Toggle("Flash suggestion words", isOn: subliminalBinding)
                    if session.subliminalEnabled {
                        Picker("Flash speed", selection: subliminalSpeedBinding) {
                            ForEach(TextPacingSettings.SubliminalSpeed.allCases) {
                                Text($0.displayName).tag($0)
                            }
                        }
                    }
                }
                if session.settings.arc == .handoff {
                    Section("After handoff") {
                        Toggle("Light pulse", isOn: lightBinding)
                    }
                }
            }
            .tint(.auroraTeal)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build/test command. Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/TextTrance/ReaderSettingsDrawer.swift
git commit -m "feat(reader): live-settings drawer (binaural/subliminal/light)"
```

---

## Task 12: Player view — control overlay, gestures, auto-pause

**Files:**
- Modify: `Ilumionate/TextTrance/TextTrancePlayerView.swift`

Add the auto-hiding control overlay (reusing `PlayerControlsVisibility`), a pause overlay, the settings sheet, swipe gestures, and background auto-pause. Keep the existing `AnchoredWord` rendering and tap-and-hold-to-end.

- [ ] **Step 1: Replace the `TextTrancePlayerView` struct**

```swift
struct TextTrancePlayerView: View {
    @State private var session: TextTranceSession
    @State private var controlsVisibility = PlayerControlsVisibility()
    @State private var showingSettings = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var backgroundPulse = false
    @State private var wordOpacity: Double = 1

    init(session: TextTranceSession) {
        _session = State(initialValue: session)
    }

    var body: some View {
        ZStack {
            Color.voidDeep.ignoresSafeArea()

            RadialGradient(
                colors: [Color.auroraTeal.opacity(backgroundPulse ? 0.22 : 0.08), .clear],
                center: .center, startRadius: 20, endRadius: 420)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true),
                           value: backgroundPulse)

            wordLayer

            if controlsVisibility.isVisible {
                VStack {
                    Spacer()
                    ReaderControlPanel(
                        session: session,
                        onSettings: { showingSettings = true },
                        onEnd: { session.end(); dismiss() })
                }
                .transition(.opacity)
            } else if session.isPaused {
                pausedWhisper
            }
        }
        .contentShape(.rect)
        .gesture(endHoldGesture)
        .simultaneousGesture(revealHideDrag)
        .onTapGesture { controlsVisibility.registerInteraction() }
        .task {
            backgroundPulse = true
            controlsVisibility.registerInteraction()
            await session.begin()
            if session.isComplete { dismiss() }
        }
        .statusBarHidden(!controlsVisibility.isVisible)
        .onChange(of: showingSettings) { _, open in
            controlsVisibility.isDrawerOpen = open
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, session.isReading, !session.isPaused {
                session.pause()
                controlsVisibility.registerInteraction()
            }
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsDrawer(session: session)
        }
        .onDisappear {
            if !session.isComplete { session.end() }
        }
    }

    @ViewBuilder
    private var wordLayer: some View {
        if session.isReading {
            AnchoredWord(
                text: session.currentWord,
                pivot: session.currentPivotIndex,
                referenceCharacterCount: session.readerReferenceCharacterCount
            )
            .opacity(session.isPaused ? 0.4 : wordOpacity)
            .onChange(of: session.currentWord) { _, _ in applyWordFade() }
        } else if session.lightActive {
            Text("…")
                .font(.system(size: 40))
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var pausedWhisper: some View {
        Text("Paused")
            .font(TranceTypography.caption)
            .foregroundStyle(Color.textSecondary.opacity(0.6))
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, TranceSpacing.statusBar)
    }

    private func applyWordFade() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { wordOpacity = 1 }

        switch session.currentFade {
        case .none: break
        case .breath:
            withAnimation(.easeIn(duration: session.currentDuration)) { wordOpacity = 0.05 }
        case .drift:
            withAnimation(.easeIn(duration: session.currentDuration)) { wordOpacity = 0 }
        }
    }

    private var endHoldGesture: some Gesture {
        LongPressGesture(minimumDuration: 1.2)
            .onEnded { _ in session.end(); dismiss() }
    }

    private var revealHideDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                if value.translation.height < -40 {
                    controlsVisibility.registerInteraction()
                } else if value.translation.height > 40 {
                    controlsVisibility.hideNow()
                }
            }
    }
}
```

Keep the existing private `AnchoredWord` struct. Update the `#Preview` at the bottom to use the multiplier initializer:

```swift
    let session = TextTranceSession(
        script: script,
        settings: TextTranceSessionSettings(arc: .fullText, speedMultiplier: 0.75,
            lightEnabled: false, binauralEnabled: false,
            beatFrequency: 10, postHandoffDuration: 0),
        light: nil, audio: nil)
```

- [ ] **Step 2: Build to verify it compiles**

Run the build/test command. Expected: PASS. (No new unit tests — this is a SwiftUI view; behavior is covered by the session tests and verified manually in Task 14.)

> Note: `.onTapGesture` is used here intentionally to register a controls-reveal interaction; this is the same reveal affordance the audio player exposes via its minimal overlay button. It coexists with the long-press end gesture and the drag reveal/hide.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/TextTrance/TextTrancePlayerView.swift
git commit -m "feat(reader): auto-hiding control overlay, settings sheet, background auto-pause"
```

---

## Task 13: Setup view — speed slider + Resume / Start over / Begin

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceSetupView.swift`

Replace the 3-way `SpeedCard` with a slider, and offer Resume when a valid snapshot exists.

- [ ] **Step 1: Update state, session builder, and bottom bar**

Change the speed state and add the store + resume lookup at the top of `TextTranceSetupView`:

```swift
    let script: TranceScript

    @State private var arc: ScriptArc
    @State private var speedMultiplier: Double = 1.0
    @State private var lightEnabled = true
    @State private var binauralEnabled = false
    @State private var subliminalEnabled = true
    @State private var subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium
    @State private var startPlayer = false
    @State private var resumeIndex = 0

    private let progressStore = ReaderProgressStore.shared

    init(script: TranceScript) {
        self.script = script
        _arc = State(initialValue: script.supportedArcs.first ?? .fullText)
    }

    private var scriptText: String { script.segments.map(\.text).joined(separator: " ") }
    private var contentHash: String { ReaderResumeState.contentHash(for: scriptText) }

    /// A resume snapshot only if it matches the current script text and is in range.
    private var validResume: ReaderResumeState? {
        guard let s = progressStore.resumeState(forScriptId: script.id),
              s.scriptContentHash == contentHash,
              s.wordIndex > 0 else { return nil }
        return s
    }
```

Replace `SpeedCard(speed: $speed)` in the body with `SpeedCard(multiplier: $speedMultiplier)`.

Replace `makeSession()` and the bottom inset. New `makeSession(from:)`:

```swift
    private func makeSession(from startIndex: Int) -> TextTranceSession {
        let useLight = arc == .handoff && lightEnabled
        let session = TextTranceSession(
            script: script,
            settings: TextTranceSessionSettings(
                arc: arc,
                speedMultiplier: speedMultiplier,
                lightEnabled: useLight,
                binauralEnabled: binauralEnabled,
                beatFrequency: 10,
                postHandoffDuration: 600,
                subliminalEnabled: subliminalEnabled,
                subliminalSpeed: subliminalSpeed),
            light: useLight ? FlashController(frequency: 10, intensity: 0.7, pattern: .sine) : nil,
            audio: binauralEnabled ? BinauralBeatsEngine() : nil,
            progressStore: progressStore,
            scriptContentHash: contentHash)
        return session
    }

    /// Seed the editable controls from a resume snapshot before launching.
    private func applyResumeSettings(_ s: ReaderResumeState) {
        arc = s.settings.arc
        speedMultiplier = s.settings.speedMultiplier
        lightEnabled = s.settings.lightEnabled
        binauralEnabled = s.settings.binauralEnabled
        subliminalEnabled = s.settings.subliminalEnabled
        subliminalSpeed = s.settings.subliminalSpeed
    }
```

Replace the `.safeAreaInset(edge: .bottom)` content with Resume/Start-over/Begin:

```swift
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: TranceSpacing.list) {
                if let resume = validResume {
                    GlowButton(title: "Resume", systemImage: "play.fill", kind: .primary) {
                        applyResumeSettings(resume)
                        resumeIndex = resume.wordIndex
                        startPlayer = true
                    }
                    .frame(maxWidth: .infinity)
                    GlowButton(title: "Start over", systemImage: "arrow.counterclockwise", kind: .secondary) {
                        progressStore.clear(scriptId: script.id)
                        resumeIndex = 0
                        startPlayer = true
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    GlowButton(title: "Begin", systemImage: "play.fill", kind: .primary) {
                        resumeIndex = 0
                        startPlayer = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.top, TranceSpacing.cardMargin)
            .padding(.bottom, TranceSpacing.tabBarClearance)
        }
        .fullScreenCover(isPresented: $startPlayer) {
            TextTrancePlayerView(session: makeSession(from: resumeIndex))
        }
```

> Confirm `GlowButton` supports a `.secondary` kind; if the enum case differs (e.g. `.ghost`), use the existing secondary style name. Check `GlowButton`'s definition.

The player must start at the resumed index. In `TextTrancePlayerView.body`'s `.task`, replace `await session.begin()` with a stored start index. Simplest: add an `init(session:startIndex:)` is unnecessary — instead, pass the index through the session by launching with `begin(from:)`. Update the player's `.task` to call the session's resume index. Add to `TextTrancePlayerView`:

```swift
    private let startIndex: Int

    init(session: TextTranceSession, startIndex: Int = 0) {
        _session = State(initialValue: session)
        self.startIndex = startIndex
    }
```

and in `.task` use `await session.begin(from: startIndex)`. Then in the setup `fullScreenCover`, pass it:

```swift
            TextTrancePlayerView(session: makeSession(from: resumeIndex), startIndex: resumeIndex)
```

- [ ] **Step 2: Replace `SpeedCard`**

```swift
private struct SpeedCard: View {
    @Binding var multiplier: Double

    var body: some View {
        LiminalCard(label: "Reading speed") {
            VStack(spacing: TranceSpacing.micro) {
                HStack {
                    Text("~\(TextPacingEngine.nominalWPM(forMultiplier: multiplier)) wpm")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
                Slider(value: $multiplier,
                       in: TextPacingEngine.minSpeedMultiplier...TextPacingEngine.maxSpeedMultiplier)
                    .tint(.auroraTeal)
            }
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run the build/test command. Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceSetupView.swift Ilumionate/TextTrance/TextTrancePlayerView.swift
git commit -m "feat(reader): speed slider in setup + Resume/Start over launch"
```

---

## Task 14: Target membership, full build, and manual smoke test

**Files:**
- Possibly modify: `Ilumionate.xcodeproj/project.pbxproj` (only if synchronized groups did not auto-add the new files)

- [ ] **Step 1: Confirm new files are in the right targets**

New source files (`ReaderResumeState.swift`, `ReaderProgressStore.swift`, `ReaderControlPanel.swift`, `ReaderSettingsDrawer.swift`) must be in the **app** target; new test files (`PacingSleepController.swift`, `ReaderResumeStateTests.swift`, `ReaderProgressStoreTests.swift`) in the **test** target. With Xcode 16 synchronized groups under `Ilumionate/TextTrance/` and `IlumionateTests/TextTrance/`, this is automatic. Verify by building.

- [ ] **Step 2: Full build + test run**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 15' test 2>&1 | tail -50
```

Expected: build succeeds; all `IlumionateTests/TextTrance/*` tests pass, including new driver/store tests and the unchanged engine/session tests.

- [ ] **Step 3: Manual smoke test (simulator)**

Launch the app, open Text Trance, pick a script, set the speed slider, Begin. Verify:
1. Word stream runs; controls auto-hide after the idle delay.
2. Tap or swipe up reveals the control panel; swipe down hides it.
3. Pause stops the stream (word dims, "Paused" whisper when controls hidden); resume continues from the same word.
4. Dragging the speed slider changes pace and the WPM readout live.
5. Settings drawer toggles binaural/subliminal/(handoff) light; subliminal toggle does not jump position.
6. Background the app mid-read, return → it is paused at the same word.
7. End the session (X or tap-and-hold), reopen the same script → Resume appears and continues near where you left off; Start over begins fresh.

- [ ] **Step 4: Commit any project file changes**

```bash
git add Ilumionate.xcodeproj/project.pbxproj
git commit -m "chore(reader): ensure target membership for new TextTrance files"
```

(Skip if nothing changed.)

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Pause/resume with remaining time → Tasks 5. ✅
- Live speed slider + WPM readout → Tasks 1 (engine), 10 (panel), 13 (setup). ✅
- Live binaural/subliminal/light → Task 6 (session), 11 (drawer). ✅
- Index stability across settings → Tasks 1 (invariant test), 6 (regen keeps index). ✅
- Control surfacing consistent with audio player (`PlayerControlsVisibility`) → Task 12. ✅
- Resume-after-close (model, store, wiring, surfacing) → Tasks 7, 8, 9, 13. ✅
- Staleness guard (content hash, range check) → Tasks 7 (hash), 13 (`validResume`). ✅
- Background auto-pause → Task 12. ✅
- Handoff-tail behavior → tail uses `lightEnabledLive`; pause during reading covered. (Tail-specific pause is handled by `end`/background; sub-tail resume `elapsed` is modeled in `ResumePhase` but the session persists `.reading` only — see note below.) ⚠️

**Known simplification:** `ResumePhase.handoffTail(elapsed:)` exists in the model but `currentSnapshot()` always records `.reading`. Resuming during the post-handoff light tail is rare (reading already complete) and is treated as "session effectively done." If full tail-resume is desired, extend `currentSnapshot()` to detect `lightActive` and record elapsed; this was deliberately deferred to keep the first cut focused, consistent with the spec's emphasis on reading-phase resume.

**Placeholder scan:** No TBD/TODO; every code step shows complete code.

**Type consistency:** `speedMultiplier` (Double) used uniformly; `setSpeed/setBinaural/setSubliminal/setLightEnabled` names consistent between session (Task 6) and views (Tasks 10–11); `ReaderProgressStore` API (`resumeState(forScriptId:)`, `save`, `clear`) consistent between Tasks 8 and 9 and 13; `begin(from:)` consistent between Tasks 3, 12, 13.
