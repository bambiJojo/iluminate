# Orbital Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the player's stacked bottom panel and the reader's control capsule with one shared "orbital" control grammar — command cluster, icon satellites, bloom slider capsules, and an interactive whisper progress line — per `docs/superpowers/specs/2026-07-02-player-reader-orbital-redesign-design.md`.

**Architecture:** Three shared SwiftUI components (`SatelliteButton`+cluster buttons, `BloomSliderCapsule`+`BloomState`, `ScrubWhisperLine`) power both `UnifiedPlayerView` and `TextTrancePlayerView`. Mode extras relocate into a `PlayerOverflowSheet`. `TextTranceSession` gains `seek(toWordIndex:)` — the only behavior change.

**Tech Stack:** SwiftUI (iOS 26, `@Observable`), Swift Testing (`import Testing`, `@Test`, `#expect`), xcodebuild.

---

## Project facts you need

- **Target membership:** the Xcode project uses synchronized file groups — a new `.swift` file dropped anywhere under `Ilumionate/` is auto-added to the app target; files under `IlumionateTests/` auto-join the test target. No pbxproj edits.
- **Build verification** (piping to `tail` hides xcodebuild's exit code — grep a log instead):
  ```bash
  cd /Users/byronquine/Documents/Programing/Swift/Practice/Ilumionate
  xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
    -destination 'generic/platform=iOS Simulator' build > /tmp/orbital-build.log 2>&1
  grep -E "\*\* BUILD (SUCCEEDED|FAILED) \*\*" /tmp/orbital-build.log
  ```
- **Run one test suite:**
  ```bash
  xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:IlumionateTests/TextTranceSessionTests > /tmp/orbital-test.log 2>&1
  grep -E "\*\* TEST (SUCCEEDED|FAILED) \*\*" /tmp/orbital-test.log
  ```
- **Design tokens** (already defined): colors `Color.roseGold` (= auroraTeal, the primary accent), `.textSecondary`, `.textGhost`, `.glassFill`, `.glassBorder`, `.voidDeep`; spacing `TranceSpacing.micro/inner/small/list/cardMargin/content/screen/statusBar`; `TranceTypography.caption/trackTitle`; `TranceHaptics.shared.light()`.
- `TrancePhase` lives in the CorpusKit package and has `.displayName`.
- The pre-existing `AnalyzerImprover` aux target does not build (unrelated, known); only verify the `Ilumionate` scheme.
- Working tree has unrelated modified files — `git add` only the specific files named in each commit step, never `git add -A`.

## File structure

| File | Responsibility |
|---|---|
| `Ilumionate/TextTrance/TextTranceSession.swift` (modify) | add `seek(toWordIndex:)`, `wordCount`, `phase(atWordIndex:)` |
| `Ilumionate/BloomSliderCapsule.swift` (new) | `BloomState` (exclusive-open logic) + floating slider capsule view |
| `Ilumionate/SatelliteButton.swift` (new) | `SatelliteButton`, `ClusterPlayButton`, `ClusterGhostButton`, `PlayPauseButtonStyle` (moved) |
| `Ilumionate/ScrubWhisperLine.swift` (new) | interactive whisper progress line (whisper → prominent → scrubbing) |
| `Ilumionate/PlayerTransportSection.swift` (modify) | restyle using cluster buttons |
| `Ilumionate/PlayerSatelliteRow.swift` (new) | player satellite row (light sync / volume / light / ···) |
| `Ilumionate/PlayerOverflowSheet.swift` (new) | relocated mode extras sheet |
| `Ilumionate/PlayerTitleBlock.swift` (new) | title + context subtitle (extracted from `PlayerTopBar`) |
| `Ilumionate/PlayerTopBar.swift` (modify) | optional title (`showsTitle`) |
| `Ilumionate/UnifiedPlayerView.swift` (modify) | recompose overlay; wire scrub line + overflow |
| `Ilumionate/TextTrance/ReaderControlCluster.swift` (new) | reader cluster + satellites + speed bloom |
| `Ilumionate/TextTrance/TextTrancePlayerView.swift` (modify) | swap in cluster; scrubbable line |
| Delete after rewiring | `PlayerSecondaryControls.swift`, `PlayerScrubberSection.swift`, `TextTrance/ReaderControlPanel.swift` |
| `IlumionateTests/TextTrance/TextTranceSessionTests.swift` (modify) | seek tests |
| `IlumionateTests/BloomStateTests.swift` (new) | bloom exclusivity tests |

---

### Task 1: `TextTranceSession.seek(toWordIndex:)`

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceSession.swift`
- Test: `IlumionateTests/TextTrance/TextTranceSessionTests.swift`

- [ ] **Step 1: Write the failing tests**

Append inside the existing `TextTranceSessionTests` struct (it already has `handoffScript()`, `noSleep`, and uses `MockLightLayer`/`MockAudioLayer` from `TextTranceLayerMocks.swift` and `PacingSleepController`):

```swift
    // MARK: - Seek (scrubbing)

    /// Two segments, distinct phases, subliminals off so word indices are
    /// deterministic: 0-2 induction ("one two three"), 3-5 deepening ("four five six").
    private func seekScript() -> TranceScript {
        TranceScript(
            schemaVersion: 1, id: "s", title: "S", theme: .relaxation,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [
                TranceScriptSegment(phase: .induction, text: "one two three",
                    pacing: SegmentPacing(baseWPM: 600), arcs: nil, triggersHandoff: nil),
                TranceScriptSegment(phase: .deepening, text: "four five six",
                    pacing: SegmentPacing(baseWPM: 600), arcs: nil, triggersHandoff: nil)
            ])
    }

    private func makeSeekSession(sleep: @escaping @Sendable (Duration) async -> Void)
        -> TextTranceSession {
        TextTranceSession(
            script: seekScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0,
                subliminalEnabled: false),
            light: MockLightLayer(), audio: MockAudioLayer(), sleep: sleep)
    }

    @Test func seekBeforeBeginIsNoOp() {
        let session = makeSeekSession(sleep: noSleep)
        session.seek(toWordIndex: 3)
        #expect(session.currentWordIndex == 0)
        #expect(session.currentWord.isEmpty)
        #expect(session.wordCount == 0)
    }

    @Test func seekClampsAndRendersWhilePausedAndStaysPaused() async {
        let controller = PacingSleepController()
        let session = makeSeekSession(sleep: controller.sleepClosure)
        controller.onSleep = { count in
            if count == 1 { session.pause() }
        }
        let run = Task { await session.begin() }
        while !session.isPaused { await Task.yield() }

        #expect(session.wordCount == 6)
        #expect(session.phase(atWordIndex: 1) == .induction)
        #expect(session.phase(atWordIndex: 4) == .deepening)
        #expect(session.phase(atWordIndex: 99) == nil)

        session.seek(toWordIndex: 999)
        #expect(session.currentWordIndex == 5)
        #expect(session.currentWord == "six")
        #expect(session.isPaused)                 // seek never unpauses

        session.seek(toWordIndex: -3)
        #expect(session.currentWordIndex == 0)
        #expect(session.currentWord == "one")

        session.end()
        await run.value
    }

    @Test func resumeAfterPausedSeekContinuesFromNewIndex() async {
        let controller = PacingSleepController()
        let session = makeSeekSession(sleep: controller.sleepClosure)
        controller.onSleep = { count in
            if count == 1 { session.pause() }
        }
        let run = Task { await session.begin() }
        while !session.isPaused { await Task.yield() }

        session.seek(toWordIndex: 4)              // "five"
        session.resume()
        await run.value

        #expect(session.isComplete)
        #expect(session.currentWord == "six")     // played 4, 5 then finished
        // Holds: word 0 (interrupted) + words 4 and 5 = 3 sleep calls total.
        #expect(controller.callCount == 3)
    }

    @Test func seekWhilePlayingJumpsWithoutReplayingSkippedWords() async {
        let controller = PacingSleepController()
        let session = makeSeekSession(sleep: controller.sleepClosure)
        controller.onSleep = { count in
            if count == 1 { session.seek(toWordIndex: 4) }
        }
        await session.begin()

        #expect(session.isComplete)
        #expect(session.currentWord == "six")
        #expect(controller.callCount == 3)        // word 0 + words 4, 5
    }

    @Test func seekAfterCompletionIsNoOp() async {
        let session = makeSeekSession(sleep: noSleep)
        await session.begin()
        let finalWord = session.currentWord
        session.seek(toWordIndex: 0)
        #expect(session.currentWord == finalWord)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command from "Project facts" (`-only-testing:IlumionateTests/TextTranceSessionTests`).
Expected: **compile error** — `seek(toWordIndex:)`, `wordCount`, `phase(atWordIndex:)` don't exist. A compile failure of the test target is the RED state here.

- [ ] **Step 3: Implement seek in `TextTranceSession.swift`**

Add a flag next to the other private state (`private var cancelled = false` etc.):

```swift
    private var seekRequested = false
```

Add the public API after `progressFraction`:

```swift
    /// Total scheduled words (0 before `begin()` builds the schedule).
    var wordCount: Int { schedule.count }

    /// Phase of the scheduled word at `index`; nil out of range or pre-begin.
    func phase(atWordIndex index: Int) -> TrancePhase? {
        schedule.indices.contains(index) ? schedule[index].phase : nil
    }

    /// Reposition the word cursor (scrubbing). Renders the target word
    /// immediately; the playback loop continues from the new index. Pause
    /// state is left untouched — a paused session stays paused.
    func seek(toWordIndex index: Int) {
        guard isReading, !isComplete, !cancelled, !schedule.isEmpty else { return }
        currentWordIndex = min(max(index, 0), schedule.count - 1)
        render(schedule[currentWordIndex])
        seekRequested = true
        holdTask?.cancel()          // break any in-flight hold promptly
    }
```

In `begin(from:)`, replace the reading loop body's increment so a seek suppresses it:

```swift
        isReading = true
        while currentWordIndex < schedule.count, !cancelled, !Task.isCancelled {
            let word = schedule[currentWordIndex]
            render(word)
            await holdCurrentWord(scaledHold(for: word))
            if cancelled || Task.isCancelled { break }
            if seekRequested {       // loop re-enters at the seeked index
                seekRequested = false
                continue
            }
            currentWordIndex += 1
        }
        isReading = false
```

In `holdCurrentWord(_:)`, bail out as soon as a seek lands (top of the loop catches the resume-from-pause path; the post-sleep check catches the mid-hold path):

```swift
    private func holdCurrentWord(_ fullDuration: TimeInterval) async {
        var remaining = fullDuration
        while remaining > 0, !cancelled, !Task.isCancelled {
            if seekRequested { return }
            if isPaused {
                await withCheckedContinuation { resumeContinuation = $0 }
                continue
            }
            let start = now()
            let holdDuration = Duration.seconds(remaining)
            let task = Task { [sleep] in await sleep(holdDuration) }
            holdTask = task
            await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            holdTask = nil
            if cancelled || Task.isCancelled { return }
            if seekRequested { return }
            if isPaused {
                let elapsed = now() - start
                remaining = max(0, remaining - elapsed)
                continue
            }
            remaining = 0
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command. Expected: `** TEST SUCCEEDED **` — all `TextTranceSessionTests` including the five new ones. If existing pause/resume/live-settings tests in this suite regressed, fix `holdCurrentWord` (the only shared code touched) — do not modify existing tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceSession.swift IlumionateTests/TextTrance/TextTranceSessionTests.swift
git commit -m "feat(reader): TextTranceSession.seek(toWordIndex:) for script scrubbing"
```

---

### Task 2: `BloomState` + `BloomSliderCapsule`

**Files:**
- Create: `Ilumionate/BloomSliderCapsule.swift`
- Test: `IlumionateTests/BloomStateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/BloomStateTests.swift`:

```swift
//  BloomStateTests.swift
//  IlumionateTests

import Testing
@testable import Ilumionate

struct BloomStateTests {
    private enum Panel { case volume, light }

    @Test func togglingOpensThenCloses() {
        var state = BloomState<Panel>()
        #expect(state.open == nil)
        state.toggle(.volume)
        #expect(state.isOpen(.volume))
        state.toggle(.volume)
        #expect(state.open == nil)
    }

    @Test func togglingAnotherPanelSwitchesExclusively() {
        var state = BloomState<Panel>()
        state.toggle(.volume)
        state.toggle(.light)
        #expect(state.isOpen(.light))
        #expect(!state.isOpen(.volume))
    }

    @Test func closeAllClears() {
        var state = BloomState<Panel>()
        state.toggle(.volume)
        state.closeAll()
        #expect(state.open == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/BloomStateTests > /tmp/orbital-test.log 2>&1
grep -E "\*\* TEST (SUCCEEDED|FAILED) \*\*|error:" /tmp/orbital-test.log | head
```
Expected: compile error — `BloomState` not found.

- [ ] **Step 3: Create `Ilumionate/BloomSliderCapsule.swift`**

```swift
//
//  BloomSliderCapsule.swift
//  Ilumionate
//
//  The floating glass slider that "blooms" above a satellite row (volume,
//  light level, reading speed), plus the exclusive-open state that guarantees
//  only one bloom is visible at a time.
//

import SwiftUI

/// Exclusive-open state for a satellite row's bloom capsules.
struct BloomState<Panel: Equatable> {
    private(set) var open: Panel?

    mutating func toggle(_ panel: Panel) {
        open = (open == panel) ? nil : panel
    }

    mutating func closeAll() { open = nil }

    func isOpen(_ panel: Panel) -> Bool { open == panel }
}

/// A single floating slider capsule. Callers wrap it in a conditional driven
/// by `BloomState` and it transitions in/out (no motion under reduce-motion).
struct BloomSliderCapsule: View {
    let systemImage: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let valueText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: TranceSpacing.small) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Slider(value: $value, in: range)
                .tint(.roseGold)
            Text(valueText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.glassBorder, lineWidth: 1))
        .padding(.horizontal, TranceSpacing.screen)
        .transition(reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.96)))
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Same command as Step 2. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/BloomSliderCapsule.swift IlumionateTests/BloomStateTests.swift
git commit -m "feat(ui): BloomState + BloomSliderCapsule shared bloom controls"
```

---

### Task 3: Cluster buttons + `SatelliteButton`

**Files:**
- Create: `Ilumionate/SatelliteButton.swift`
- Modify: `Ilumionate/PlayerTransportSection.swift` (remove the now-moved `PlayPauseButtonStyle`)

- [ ] **Step 1: Create `Ilumionate/SatelliteButton.swift`**

```swift
//
//  SatelliteButton.swift
//  Ilumionate
//
//  The shared "orbital" control grammar: icon-only satellite buttons, the
//  solid-accent circular action button, and ghost ring buttons used by both
//  the unified player and the Text Trance reader.
//

import SwiftUI

/// Icon-only ghost-circle control for satellite rows.
struct SatelliteButton: View {
    let label: String
    let systemImage: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.subheadline)
            .foregroundStyle(active ? Color.roseGold : Color.textSecondary)
            .frame(width: 36, height: 36)
            .background(active ? Color.roseGold.opacity(0.12) : Color.glassFill)
            .overlay(Circle().strokeBorder(
                active ? Color.roseGold.opacity(0.5) : Color.glassBorder, lineWidth: 1))
            .clipShape(.circle)
            .buttonStyle(PlayerButtonStyle())
    }
}

/// Solid accent circular action button — play/pause in the player, pause/resume
/// in the reader. Clean filled circle + subtle glow (no heavy gradient).
struct ClusterPlayButton: View {
    let label: String
    let systemImage: String
    var size: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(Color.voidDeep)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.roseGold))
            .shadow(color: Color.roseGold.opacity(0.35), radius: 14)
            .buttonStyle(PlayPauseButtonStyle())
    }
}

/// Ghost ring button flanking the action button (skip, end, settings).
struct ClusterGhostButton: View {
    let label: String
    let systemImage: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.body)
            .foregroundStyle(Color.textSecondary)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.glassBorder, lineWidth: 1))
            .contentShape(.circle)
            .buttonStyle(PlayerButtonStyle())
    }
}

/// Spring-bounce press effect for the solid action button.
/// (Moved from PlayerTransportSection.swift so the reader can share it.)
struct PlayPauseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}
```

- [ ] **Step 2: Delete the old private `PlayPauseButtonStyle` from `PlayerTransportSection.swift`**

Remove the entire `// MARK: - Play/Pause Button Style` block at the bottom of `Ilumionate/PlayerTransportSection.swift` (the `private struct PlayPauseButtonStyle`), since the internal one in `SatelliteButton.swift` replaces it.

- [ ] **Step 3: Build to verify**

Run the build command from "Project facts". Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/SatelliteButton.swift Ilumionate/PlayerTransportSection.swift
git commit -m "feat(ui): satellite + cluster button grammar shared by player and reader"
```

---

### Task 4: `ScrubWhisperLine`

**Files:**
- Create: `Ilumionate/ScrubWhisperLine.swift`

- [ ] **Step 1: Create `Ilumionate/ScrubWhisperLine.swift`**

```swift
//
//  ScrubWhisperLine.swift
//  Ilumionate
//
//  A whisper-thin progress line pinned to a screen's bottom edge that becomes
//  a full-width scrubber under touch: whisper (2pt, faint) → prominent
//  (brighter while controls are visible) → scrubbing (6pt + floating overlay).
//

import SwiftUI

struct ScrubWhisperLine<Overlay: View>: View {
    let fraction: Double
    var tint: Color = .roseGold
    var prominent = false
    var interactive = true
    /// Continuous during drag, with the scrubbed fraction (0…1).
    var onScrub: (Double) -> Void = { _ in }
    /// Fired once on release with the final fraction.
    var onScrubEnd: (Double) -> Void = { _ in }
    /// Step applied by the VoiceOver adjustable action (fraction units).
    var accessibilityStep: Double = 0.05
    /// Floating readout rendered above the line while scrubbing.
    @ViewBuilder let overlay: (Double) -> Overlay

    @State private var scrubFraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isScrubbing: Bool { scrubFraction != nil }

    var body: some View {
        GeometryReader { geo in
            let displayed = scrubFraction ?? min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.textGhost.opacity(isScrubbing ? 0.30 : prominent ? 0.22 : 0.12))
                Capsule()
                    .fill(tint.opacity(isScrubbing ? 1 : prominent ? 0.9 : 0.5))
                    .frame(width: max(0, geo.size.width * displayed))
            }
            .frame(height: isScrubbing ? 6 : 2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(.rect)                       // 24pt hit target
            .gesture(interactive ? dragGesture(width: geo.size.width) : nil)
            .overlay(alignment: .bottom) {
                if let scrubFraction {
                    overlay(scrubFraction)
                        .padding(.bottom, 18)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 24)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isScrubbing)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: prominent)
        .animation(.linear(duration: 0.3), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment
                ? min(1, fraction + accessibilityStep)
                : max(0, fraction - accessibilityStep)
            onScrubEnd(next)
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let f = min(1, max(0, value.location.x / max(width, 1)))
                scrubFraction = f
                onScrub(f)
            }
            .onEnded { value in
                let f = min(1, max(0, value.location.x / max(width, 1)))
                scrubFraction = nil
                onScrubEnd(f)
            }
    }
}
```

- [ ] **Step 2: Build to verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/ScrubWhisperLine.swift
git commit -m "feat(ui): ScrubWhisperLine — interactive whisper progress line"
```

---

### Task 5: Restyle `PlayerTransportSection`

**Files:**
- Modify: `Ilumionate/PlayerTransportSection.swift`

- [ ] **Step 1: Replace the body with cluster buttons**

Replace the whole `PlayerTransportSection` struct (keep `PlayerButtonStyle` at the top of the file — other views use it):

```swift
struct PlayerTransportSection: View {
    @Bindable var viewModel: UnifiedPlayerViewModel

    var body: some View {
        HStack(spacing: 28) {
            if viewModel.mode.hasTrackNavigation {
                ClusterGhostButton(label: "Previous", systemImage: "backward.fill") {
                    Task { await viewModel.skipPrevious() }
                }
                .disabled(viewModel.isFirstTrack && viewModel.currentTime < 3)
            } else if viewModel.mode.hasSkipControls {
                ClusterGhostButton(label: "Back 15 seconds", systemImage: "gobackward.15") {
                    viewModel.skipBack15()
                }
            }

            ClusterPlayButton(
                label: viewModel.isPlaying ? "Pause" : "Play",
                systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill"
            ) {
                viewModel.togglePlayPause()
            }

            if viewModel.mode.hasTrackNavigation {
                ClusterGhostButton(label: "Next", systemImage: "forward.fill") {
                    Task { await viewModel.skipNext() }
                }
                .disabled(viewModel.isLastTrack)
            } else if viewModel.mode.hasSkipControls {
                ClusterGhostButton(label: "Forward 15 seconds", systemImage: "goforward.15") {
                    viewModel.skipForward15()
                }
            }
        }
    }
}
```

(The old 80 pt gradient `playPauseIcon` and its `.scaleEffect(isPlaying)` breathing are deliberately dropped per the spec.)

- [ ] **Step 2: Build to verify** — expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/PlayerTransportSection.swift
git commit -m "feat(player): transport restyled as orbital command cluster"
```

---

### Task 6: `PlayerSatelliteRow`

**Files:**
- Create: `Ilumionate/PlayerSatelliteRow.swift`

Replaces `PlayerSecondaryControls` (deleted in Task 8). Note one deliberate change: the old code hid the volume pill in session-with-audio mode because the SYNC OPTIONS card duplicated it; the overflow sheet's sync section (Task 7) drops that duplicate slider, so the volume satellite is now shown whenever `hasVolumeControl`.

- [ ] **Step 1: Create `Ilumionate/PlayerSatelliteRow.swift`**

```swift
//
//  PlayerSatelliteRow.swift
//  Ilumionate
//
//  Icon-only satellite controls for the unified player: light sync, volume,
//  light level, and the "more" overflow. Slider satellites bloom a capsule
//  above the row; only one bloom is open at a time.
//

import SwiftUI

struct PlayerSatelliteRow: View {
    @Bindable var viewModel: UnifiedPlayerViewModel
    @Bindable var engine: LightEngine
    @Binding var showingOverflow: Bool

    enum Panel { case volume, light }
    @State private var bloom = BloomState<Panel>()

    private var showVolume: Bool { viewModel.mode.hasVolumeControl }
    private var showLight: Bool { viewModel.mode.hasBrightnessControl }
    private var showLightSync: Bool { viewModel.mode.hasLightSyncToggle }
    private var showOverflow: Bool {
        viewModel.mode.hasSyncOptions || viewModel.mode.hasBilateralToggle
            || viewModel.mode.hasBinauralToggle || viewModel.mode.hasSmartTransitions
            || viewModel.mode.hasTrackList
    }
    private var hasAny: Bool { showVolume || showLight || showLightSync || showOverflow }

    var body: some View {
        if hasAny {
            VStack(spacing: TranceSpacing.list) {
                if bloom.isOpen(.volume), showVolume {
                    BloomSliderCapsule(
                        systemImage: "speaker.wave.2.fill",
                        value: $viewModel.volumeDouble,
                        valueText: "\(Int((viewModel.volume * 100).rounded()))%")
                }
                if bloom.isOpen(.light), showLight {
                    BloomSliderCapsule(
                        systemImage: "sun.max.fill",
                        value: $engine.userBrightnessMultiplier,
                        range: 0.1...1.0,
                        valueText: "\(Int((engine.userBrightnessMultiplier * 100).rounded()))%")
                }

                HStack(spacing: TranceSpacing.small) {
                    if showLightSync {
                        SatelliteButton(
                            label: viewModel.lightSyncEnabled ? "Light sync on" : "Light sync off",
                            systemImage: viewModel.lightSyncEnabled ? "lightbulb.fill" : "lightbulb",
                            active: viewModel.lightSyncEnabled
                        ) { viewModel.toggleLightSync() }
                    }
                    if showVolume {
                        SatelliteButton(
                            label: "Volume",
                            systemImage: viewModel.volume > 0
                                ? "speaker.wave.2.fill" : "speaker.slash.fill",
                            active: bloom.isOpen(.volume)
                        ) { toggle(.volume) }
                    }
                    if showLight {
                        SatelliteButton(
                            label: "Light level",
                            systemImage: "sun.max.fill",
                            active: bloom.isOpen(.light)
                        ) { toggle(.light) }
                    }
                    if showOverflow {
                        SatelliteButton(label: "More options", systemImage: "ellipsis") {
                            showingOverflow = true
                        }
                    }
                }
            }
            .padding(.horizontal, TranceSpacing.screen)
            .animation(.easeInOut(duration: 0.2), value: bloom.open)
        }
    }

    private func toggle(_ panel: Panel) {
        TranceHaptics.shared.light()
        bloom.toggle(panel)
    }
}
```

- [ ] **Step 2: Build to verify** — expected `** BUILD SUCCEEDED **`. (The old `PlayerSecondaryControls` still compiles alongside; it's removed in Task 8.)

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/PlayerSatelliteRow.swift
git commit -m "feat(player): satellite row with bloom sliders and overflow trigger"
```

---

### Task 7: `PlayerOverflowSheet`

**Files:**
- Create: `Ilumionate/PlayerOverflowSheet.swift`

- [ ] **Step 1: Create `Ilumionate/PlayerOverflowSheet.swift`**

Relocates the mode extras that used to stack in `bottomControls`. Reuses the existing `SyncToggle`, `PlayerBilateralSection`, `PlayerBinauralSection` views unchanged.

```swift
//
//  PlayerOverflowSheet.swift
//  Ilumionate
//
//  The "···" sheet holding relocated mode extras: sync options (session+audio),
//  bilateral / binaural (flash), smart transitions + track list (playlist).
//

import SwiftUI

struct PlayerOverflowSheet: View {
    @Bindable var viewModel: UnifiedPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    private var smartTransitionsBinding: Binding<Bool> {
        Binding(get: { viewModel.smartTransitions },
                set: { viewModel.smartTransitions = $0 })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: TranceSpacing.cardMargin) {
                if viewModel.mode.hasSyncOptions {
                    GlassCard(label: "SYNC OPTIONS") {
                        SyncToggle(isOn: $viewModel.isSyncEnabled)
                    }
                }

                if viewModel.mode.hasBilateralToggle || viewModel.mode.hasBinauralToggle {
                    GlassCard(label: "LIGHT & AUDIO") {
                        HStack(spacing: 32) {
                            if viewModel.mode.hasBilateralToggle {
                                PlayerBilateralSection(viewModel: viewModel)
                            }
                            if viewModel.mode.hasBinauralToggle {
                                PlayerBinauralSection(viewModel: viewModel)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if viewModel.mode.hasSmartTransitions {
                    Toggle("Smart Transitions", isOn: smartTransitionsBinding)
                        .tint(.roseGold)
                }

                if viewModel.mode.hasTrackList {
                    Button("Track List", systemImage: "list.number") {
                        dismiss()
                        viewModel.showingTrackList = true
                    }
                    .foregroundStyle(Color.textPrimary)
                }

                Spacer()
            }
            .padding(TranceSpacing.screen)
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.bgPrimary)
    }
}
```

If `GlassCard`'s initializer differs from `GlassCard(label:) { content }`, match the call sites already in `UnifiedPlayerView.sessionSyncOptions` (that exact pattern exists there today). Note the sync card intentionally no longer contains a volume slider — the volume satellite owns volume.

- [ ] **Step 2: Build to verify** — expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/PlayerOverflowSheet.swift
git commit -m "feat(player): overflow sheet for relocated mode extras"
```

---

### Task 8: Recompose `UnifiedPlayerView` (+ title block, top bar)

**Files:**
- Create: `Ilumionate/PlayerTitleBlock.swift`
- Modify: `Ilumionate/PlayerTopBar.swift`
- Modify: `Ilumionate/UnifiedPlayerView.swift`
- Delete: `Ilumionate/PlayerScrubberSection.swift`, `Ilumionate/PlayerSecondaryControls.swift`

- [ ] **Step 1: Create `Ilumionate/PlayerTitleBlock.swift`**

The title + context subtitle move out of the top bar and under the orb for hero modes. The subtitle builder is lifted verbatim from `PlayerTopBar.subtitle`:

```swift
//
//  PlayerTitleBlock.swift
//  Ilumionate
//
//  Title + context subtitle (phase pill / frequency / track / time) shown
//  under the hero orb in finite-duration modes, and inside the top bar
//  in full-screen light modes.
//

import SwiftUI

struct PlayerTitleBlock: View {
    let viewModel: UnifiedPlayerViewModel

    var body: some View {
        VStack(spacing: TranceSpacing.micro) {
            Text(viewModel.mode.title)
                .font(TranceTypography.trackTitle)
                .foregroundStyle(viewModel.labelColor)
                .lineLimit(1)

            subtitle
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if viewModel.mode.hasPhaseIndicator {
            PhasePill(phase: viewModel.currentPhase)
        } else if viewModel.mode.hasFrequencyDisplay {
            HStack(spacing: 6) {
                Text("\(viewModel.flashFrequency, format: .number.precision(.fractionLength(1))) Hz")
                    .font(TranceTypography.caption)
                    .foregroundStyle(viewModel.secondaryLabelColor)
                if case .flashMode(_, _, let colorTemp, _, _, _, _) = viewModel.mode {
                    Text("·")
                        .foregroundStyle(viewModel.secondaryLabelColor.opacity(0.5))
                    Text("\(colorTemp)K")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.fromKelvin(colorTemp))
                }
            }
        } else if viewModel.mode.hasTrackNavigation {
            Text("\(viewModel.currentTrackIndex + 1) of \(viewModel.trackCount) — \(viewModel.currentTrackName)")
                .font(TranceTypography.caption)
                .foregroundStyle(viewModel.secondaryLabelColor)
                .lineLimit(1)
        } else {
            Text(viewModel.formatTime(viewModel.currentTime) + " / " + viewModel.formatTime(viewModel.duration))
                .font(TranceTypography.caption)
                .foregroundStyle(viewModel.secondaryLabelColor)
                .monospacedDigit()
        }
    }
}
```

- [ ] **Step 2: Slim `PlayerTopBar`**

In `Ilumionate/PlayerTopBar.swift`: add `var showsTitle = true` after `let viewModel`, replace the center `VStack(spacing: 2) { … }` (title + subtitle) with:

```swift
            if showsTitle {
                PlayerTitleBlock(viewModel: viewModel)
            }
```

and delete the now-unused private `subtitle` builder from this file (it lives in `PlayerTitleBlock`).

- [ ] **Step 3: Recompose `UnifiedPlayerView`**

In `Ilumionate/UnifiedPlayerView.swift`:

a) Add state next to `controlsVisibility`:

```swift
    @State private var showingOverflow = false
    @State private var isScrubbing = false
```

b) Replace `controlsOverlay` and `bottomControls` with:

```swift
    private var isHeroMode: Bool { viewModel.mode.hasAudioScrubber }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            PlayerTopBar(
                viewModel: viewModel,
                showsTitle: !isHeroMode,
                onClose: {
                    viewModel.stopAll()
                    dismiss()
                },
                onMinimize: {
                    viewModel.dismissToMiniPlayer = true
                    dismiss()
                }
            )

            Spacer()

            if isHeroMode {
                PlayerHeroOrb(engine: viewModel.engine, isPlaying: viewModel.isPlaying)
                    .padding(.vertical, TranceSpacing.content)
                PlayerTitleBlock(viewModel: viewModel)
                Spacer()
            }

            bottomControls
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showingControls)
    }

    private var bottomControls: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            PlayerTransportSection(viewModel: viewModel)

            PlayerSatelliteRow(
                viewModel: viewModel,
                engine: viewModel.engine,
                showingOverflow: $showingOverflow
            )
            .opacity(isScrubbing ? 0 : 1)

            if isHeroMode {
                scrubLine
            }
        }
        .padding(.bottom, TranceSpacing.statusBar)
    }

    private var scrubLine: some View {
        ScrubWhisperLine(
            fraction: viewModel.progress,
            prominent: true,
            onScrub: { _ in
                if !isScrubbing { isScrubbing = true }
                controlsVisibility.registerInteraction()
            },
            onScrubEnd: { fraction in
                viewModel.seekByProgress(fraction)
                isScrubbing = false
            }
        ) { fraction in
            Text(viewModel.formatTime(fraction * viewModel.duration)
                 + " / " + viewModel.formatTime(viewModel.duration))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(viewModel.labelColor)
        }
        .padding(.horizontal, TranceSpacing.screen)
    }
```

c) Delete the now-unused private views from `UnifiedPlayerView`: `sessionSyncOptions`, `flashModeControls`, `smartTransitionsToggle`, `trackListButton`, and the `volumeBinding` / `smartTransitionsBinding` properties (they moved to the overflow sheet).

d) Add the overflow sheet + drawer-state wiring next to the track-list sheet modifier:

```swift
        .sheet(isPresented: $showingOverflow) {
            PlayerOverflowSheet(viewModel: viewModel)
        }
        .onChange(of: showingOverflow) { _, open in
            controlsVisibility.isDrawerOpen = open || viewModel.showingTrackList
        }
```

and change the existing `showingTrackList` onChange to the same combined form:

```swift
        .onChange(of: viewModel.showingTrackList) { _, open in
            controlsVisibility.isDrawerOpen = open || showingOverflow
        }
```

- [ ] **Step 4: Delete the retired player files**

```bash
git rm Ilumionate/PlayerScrubberSection.swift Ilumionate/PlayerSecondaryControls.swift
grep -rn "PlayerScrubberSection\|PlayerSecondaryControls" Ilumionate IlumionateTests
```
Expected: grep returns nothing. If it finds references, fix them before proceeding.

- [ ] **Step 5: Build to verify** — expected `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/UnifiedPlayerView.swift Ilumionate/PlayerTopBar.swift Ilumionate/PlayerTitleBlock.swift
git commit -m "feat(player): orbital layout — cluster + satellites + scrub whisper line"
```

---

### Task 9: `ReaderControlCluster`

**Files:**
- Create: `Ilumionate/TextTrance/ReaderControlCluster.swift`
- Modify: `Ilumionate/TextTrance/TextTrancePlayerView.swift`
- Delete: `Ilumionate/TextTrance/ReaderControlPanel.swift`

- [ ] **Step 1: Create `Ilumionate/TextTrance/ReaderControlCluster.swift`**

```swift
//  ReaderControlCluster.swift
//  Ilumionate
//
//  Revealed-state controls for the Text Trance reader in the shared orbital
//  grammar: End · pause/resume · Settings cluster, with satellites for the
//  live in-trance settings (speed bloom, light, binaural). Deep settings
//  stay in ReaderSettingsDrawer.

import SwiftUI

struct ReaderControlCluster: View {
    @Bindable var session: TextTranceSession
    let onSettings: () -> Void
    let onEnd: () -> Void

    private enum Panel { case speed }
    @State private var bloom = BloomState<Panel>()

    private var speedBinding: Binding<Double> {
        Binding(get: { session.speedMultiplier },
                set: { session.setSpeed(multiplier: $0) })
    }

    var body: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            if bloom.isOpen(.speed) {
                BloomSliderCapsule(
                    systemImage: "speedometer",
                    value: speedBinding,
                    range: TextPacingEngine.minSpeedMultiplier...TextPacingEngine.maxSpeedMultiplier,
                    valueText: "~\(TextPacingEngine.nominalWPM(forMultiplier: session.speedMultiplier)) wpm")
            }

            HStack(spacing: 36) {
                ClusterGhostButton(label: "End session", systemImage: "xmark", action: onEnd)

                ClusterPlayButton(
                    label: session.isPaused ? "Resume" : "Pause",
                    systemImage: session.isPaused ? "play.fill" : "pause.fill",
                    size: 56
                ) {
                    if session.isPaused { session.resume() } else { session.pause() }
                }

                ClusterGhostButton(label: "Settings", systemImage: "slider.horizontal.3",
                                   action: onSettings)
            }

            HStack(spacing: TranceSpacing.small) {
                SatelliteButton(
                    label: "Reading speed",
                    systemImage: "speedometer",
                    active: bloom.isOpen(.speed)
                ) {
                    TranceHaptics.shared.light()
                    bloom.toggle(.speed)
                }

                if session.settings.arc == .handoff {
                    SatelliteButton(
                        label: session.lightEnabledLive ? "Light pulse on" : "Light pulse off",
                        systemImage: session.lightEnabledLive ? "lightbulb.fill" : "lightbulb",
                        active: session.lightEnabledLive
                    ) { session.setLightEnabled(!session.lightEnabledLive) }
                }

                SatelliteButton(
                    label: session.binauralActive ? "Binaural on" : "Binaural off",
                    systemImage: "waveform",
                    active: session.binauralActive
                ) { session.setBinaural(enabled: !session.binauralActive) }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.bottom, TranceSpacing.statusBar)
    }
}
```

- [ ] **Step 2: Swap it into `TextTrancePlayerView`**

In `Ilumionate/TextTrance/TextTrancePlayerView.swift`, replace the `ReaderControlPanel(...)` usage:

```swift
            if controlsVisibility.isVisible {
                VStack {
                    Spacer()
                    ReaderControlCluster(
                        session: session,
                        onSettings: { showingSettings = true },
                        onEnd: { session.end(); dismiss() })
                }
                .transition(.opacity)
            } else if session.isPaused {
                pausedWhisper
            }
```

- [ ] **Step 3: Delete the retired panel**

```bash
git rm Ilumionate/TextTrance/ReaderControlPanel.swift
grep -rn "ReaderControlPanel" Ilumionate IlumionateTests
```
Expected: grep returns nothing.

- [ ] **Step 4: Build to verify** — expected `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/ReaderControlCluster.swift Ilumionate/TextTrance/TextTrancePlayerView.swift
git commit -m "feat(reader): control capsule replaced by orbital command cluster"
```

---

### Task 10: Reader script scrubbing

**Files:**
- Modify: `Ilumionate/TextTrance/TextTrancePlayerView.swift`

- [ ] **Step 1: Replace `ReaderProgressLine` with `ScrubWhisperLine`**

In `TextTrancePlayerView.swift`:

a) Add state next to `wordOpacity`:

```swift
    @State private var isScrubbing = false
    @State private var wasPausedBeforeScrub = false
```

b) Replace the `ReaderProgressLine(...)` block in `body` (including its `.allowsHitTesting(false)`) with:

```swift
            ScrubWhisperLine(
                fraction: session.progressFraction,
                tint: phaseColor,
                prominent: controlsVisibility.isVisible,
                interactive: session.isReading,
                onScrub: { fraction in
                    if !isScrubbing {
                        isScrubbing = true
                        wasPausedBeforeScrub = session.isPaused
                        if !session.isPaused { session.pause() }
                    }
                    controlsVisibility.registerInteraction()
                    session.seek(toWordIndex: wordIndex(for: fraction))
                },
                onScrubEnd: { fraction in
                    session.seek(toWordIndex: wordIndex(for: fraction))
                    if isScrubbing, !wasPausedBeforeScrub { session.resume() }
                    isScrubbing = false
                }
            ) { fraction in
                scrubReadout(for: fraction)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.bottom, TranceSpacing.inner)
```

c) Add the helpers next to `phaseColor`:

```swift
    private func wordIndex(for fraction: Double) -> Int {
        guard session.wordCount > 0 else { return 0 }
        return Int((fraction * Double(session.wordCount - 1)).rounded())
    }

    @ViewBuilder
    private func scrubReadout(for fraction: Double) -> some View {
        let index = wordIndex(for: fraction)
        VStack(spacing: TranceSpacing.micro) {
            if let phase = session.phase(atWordIndex: index) {
                Text(phase.displayName.uppercased())
                    .font(TranceTypography.caption)
                    .kerning(1.5)
                    .foregroundStyle(phaseColor)
            }
            Text("word \(index + 1) / \(session.wordCount)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
        }
    }
```

d) Delete the now-unused private `ReaderProgressLine` struct at the bottom of the file.

Behavior notes baked into this wiring:
- First `onScrub` pauses a playing session (so words don't tick under the finger); release resumes only if it was playing before — a paused session stays paused (matches Task 1 semantics and the spec).
- `interactive: session.isReading` makes the line display-only in the post-handoff light tail (seek would no-op anyway).
- `onScrubEnd` also handles the VoiceOver adjustable path (which never fires `onScrub`): `isScrubbing` is false there, so it seeks without touching pause state.

- [ ] **Step 2: Build to verify** — expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the reader test suites**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/TextTranceSessionTests \
  -only-testing:IlumionateTests/BloomStateTests > /tmp/orbital-test.log 2>&1
grep -E "\*\* TEST (SUCCEEDED|FAILED) \*\*" /tmp/orbital-test.log
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/TextTrance/TextTrancePlayerView.swift
git commit -m "feat(reader): whisper line becomes a script scrubber with phase readout"
```

---

### Task 11: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Full clean build** — run the build command; expected `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Full unit-test suite**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests > /tmp/orbital-fulltest.log 2>&1
grep -E "\*\* TEST (SUCCEEDED|FAILED) \*\*" /tmp/orbital-fulltest.log
```
Expected: `** TEST SUCCEEDED **`. Investigate any failure — fix implementation, not tests, unless a test asserts the old retired layout.

- [ ] **Step 3: Live simulator verification (iPhone 17)**

Launch the app in the iPhone 17 simulator (Xcode MCP tools or `xcrun simctl`) and screenshot each state:
1. Audio/light player: resting orbital layout; volume satellite bloom; light satellite bloom; scrub the whisper line (time readout appears, seek lands); ··· overflow sheet.
2. Session player: same skeleton, phase pill under orb, light-level satellite.
3. Playlist: prev/next cluster, track subtitle, overflow shows Smart Transitions + Track List.
4. Flash mode (regression): full-screen visual unchanged; revealed controls = cluster + satellites; bilateral/binaural in overflow; **no whisper line**.
5. Color-pulse (regression): same expectations as flash.
6. Reader: reveal controls (cluster + speed/light/binaural satellites); speed bloom live-updates WPM; scrub the line (phase + word readout, resumes reading at new position, paused-stays-paused when scrubbed while paused).
7. Reduce Motion ON (Settings → Accessibility → Motion): blooms appear without motion, line thickens instantly, orb static.

- [ ] **Step 4: Update the knowledge graph**

```bash
graphify update .
```

- [ ] **Step 5: Final commit (only if verification produced fixes)**

```bash
git add <specific files you fixed>
git commit -m "fix(player): orbital redesign polish from live verification"
```

---

## Self-review checklist (already applied)

- Spec §1 grammar → Tasks 2–4; §2 player → Tasks 5–8; §3 reader → Tasks 1, 9, 10; §4 edge/a11y → baked into component code (reduce-motion transitions, satellite labels, adjustable action) + Task 11 step 3.7; §5 testing → Tasks 1, 2, 11; §7 file list → matches, plus `PlayerSatelliteRow.swift`/`PlayerTitleBlock.swift` (named additions).
- Known intentional deltas from current behavior: volume satellite shown in session-with-audio (duplicate slider removed from sync card); title moves from top bar to under-orb block in hero modes (per approved mockups).
