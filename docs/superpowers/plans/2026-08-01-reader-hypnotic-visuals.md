# Reader Hypnotic Visuals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the TextTrance RSVP reader four Metal-shader hypnotic backgrounds with a user-adjustable opacity, where the word stays legible because each shader fades itself out of a word-shaped ellipse.

**Architecture:** `ReaderDisplayPreferences` stores the chosen `ReaderVisual` and its opacity. A pure `ReaderVisualModulator` turns the session's current `TrancePhase` and `speedMultiplier` into a `ReaderVisualModulation` (tint, speed, amplitude) and enforces every safety cap. `ReaderVisualLayer` feeds that into one of four `[[stitchable]]` fragment shaders via `TimelineView` + `.colorEffect`, and sits between the reader's flat background and its word layer.

**Tech Stack:** SwiftUI (iOS 26 / macOS 26), Metal fragment shaders via SwiftUI's `Shader` API, Swift Testing, `xcodebuild`.

**Spec:** [`docs/superpowers/specs/2026-08-01-reader-hypnotic-visuals-design.md`](../specs/2026-08-01-reader-hypnotic-visuals-design.md)

---

## Before You Start

### Corrections to the spec

The spec has one inaccuracy, found while writing this plan. **Follow this plan, not the spec, where they disagree:**

- Spec §6 says the settings UI uses "a labelled chip row reusing the drawer's existing chip idiom". That is wrong. `ReaderSettingsDrawer` is a SwiftUI `Form` of `Section`s built from `Picker`, `Slider`, and `LabeledContent` (see `ReaderDisplayFormSection`). Task 9 uses a `Picker` + `Slider` to match. There is no chip idiom in that file.

### Commands you will use

Simulator destinations are **ambiguous by name** on this machine — there are 5 devices called `iPhone 17` and 5 called `iPhone 17 Pro`. If `xcodebuild` errors on ambiguity, get a concrete UDID:

```bash
xcrun simctl list devices available | grep "iPhone 17"
```

and substitute `-destination 'platform=iOS Simulator,id=<UDID>'`.

```bash
# iOS unit tests (single suite)
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:IlumionateTests/<SuiteName> 2>&1 | grep -E "Test case|TEST (SUCCEEDED|FAILED)|error:"

# iOS build
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD"

# Native macOS build — REQUIRED, this project ships macOS as first-class
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=macOS,arch=arm64' build 2>&1 | grep -E "error:|BUILD"
```

### Known pre-existing test failures — do not chase these

Running the whole `IlumionateTests` suite shows 5 failures that are timing-sensitive and pass in isolation, unrelated to this work: `PlayerControlsVisibilityTests/idleTimerHides`, `.../closingDrawerReArmsTimer`, `.../interactionPostponesHide`, `AudioImportWorkerTests/slowFileTransferDoesNotBlockMainActor`, `AudioLibraryStoreTests/savingLargeLibraryDoesNotBlockMainActor`, `StagedAnalysisPipelineTests/keepsWhisperPrefetchOutOfContentAnalysis`. Prefer `-only-testing:` on your own suites.

### Branch first

You are likely on `main`. Create a branch before Task 1:

```bash
git checkout -b feature/reader-hypnotic-visuals
```

---

## File Structure

**Create:**

| Path | Responsibility |
| --- | --- |
| `Ilumionate/TextTrance/Visuals/ReaderVisual.swift` | The effect enum: cases, display names, shader names |
| `Ilumionate/TextTrance/Visuals/TrancePhase+Atmosphere.swift` | The single phase→colour table, extracted from the player view |
| `Ilumionate/TextTrance/Visuals/ReaderVisualModulation.swift` | Pure modulation + all safety caps |
| `Ilumionate/TextTrance/Visuals/ReaderVisualLayer.swift` | SwiftUI wrapper feeding the shaders |
| `Ilumionate/TextTrance/Visuals/ReaderVisuals.metal` | Four fragment shaders + the shared `centreFade` |
| `IlumionateTests/ReaderVisualTests.swift` | Enum metadata invariants |
| `IlumionateTests/ReaderVisualModulatorTests.swift` | Modulation + safety caps |

**Modify:**

| Path | Change |
| --- | --- |
| `Ilumionate/TextTrance/ReaderDisplayPreferences.swift` | Add `visual`, `visualOpacity`, range, clamp, back-compat decode |
| `Ilumionate/TextTrance/TextTrancePlayerView.swift` | Insert the layer; delete local `phaseColor`, call the extracted one |
| `Ilumionate/TextTrance/ReaderSettingsDrawer.swift` | Add the Visual section |
| `IlumionateTests/ReaderColorModeTests.swift` | Extend legacy-decode coverage for the new fields |

---

## Task 1: Metal feasibility spike (throwaway)

This project has **no `.metal` file, no `import Metal`, and no `ShaderLibrary` usage**. A missing shader function fails at *runtime*, not build time, so prove the toolchain works before writing four effects.

**Files:**
- Create: `Ilumionate/TextTrance/Visuals/SpikeShader.metal` (deleted in step 7)
- Create: `Ilumionate/TextTrance/Visuals/SpikeShaderView.swift` (deleted in step 7)

- [ ] **Step 1: Create the directory and a trivial shader**

```bash
mkdir -p Ilumionate/TextTrance/Visuals
```

`Ilumionate/TextTrance/Visuals/SpikeShader.metal`:

```metal
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Throwaway: proves .metal files compile into this target and that
// ShaderLibrary can resolve a stitchable function at runtime.
[[ stitchable ]] half4 spikeFill(float2 pos, half4 color, float2 size, float time) {
    float2 uv = pos / size;
    half v = half(0.5 + 0.5 * sin(time + uv.x * 6.0));
    return half4(v, v * 0.4h, 1.0h - v, 1.0h);
}
```

- [ ] **Step 2: Create a temporary preview host**

`Ilumionate/TextTrance/Visuals/SpikeShaderView.swift`:

```swift
import SwiftUI

/// Throwaway spike host. Deleted at the end of Task 1.
struct SpikeShaderView: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Rectangle()
                    .foregroundStyle(.black)
                    .colorEffect(
                        ShaderLibrary.spikeFill(
                            .float2(proxy.size),
                            .float(Float(t.truncatingRemainder(dividingBy: 3600)))
                        )
                    )
            }
        }
        .ignoresSafeArea()
    }
}

#Preview { SpikeShaderView() }
```

- [ ] **Step 3: Build for iOS**

Run:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

If you instead see an error about `SwiftUI_Metal.h` not being found, the header include is wrong for this SDK — try `#include <SwiftUI/SwiftUI.h>` removed entirely and keep only `metal_stdlib`, since `[[stitchable]]` needs no extra header on iOS 26. Re-run.

- [ ] **Step 4: Build for native macOS**

Run:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=macOS,arch=arm64' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Confirm the shader actually resolves at runtime**

A build success does **not** prove `ShaderLibrary` can find the function. Verify visually.

Temporarily render the spike as the reader background by adding it as the first child of the `ZStack` in `TextTrancePlayerView.body` (line 53), directly after `displayPrefs.adjustedBackground.ignoresSafeArea()`:

```swift
SpikeShaderView()
```

Then build, install, launch, open the Read tab, and start any script. Take a screenshot.

Expected: an animated blue/orange vertical gradient behind the word.

**If the screen is black instead:** `ShaderLibrary` did not resolve `spikeFill`. The `.metal` file is not being compiled into the target. Stop and report — the fallback is the `TimelineView` + `Canvas` approach from the spec's Risks section, which changes Tasks 6 and 7 only.

- [ ] **Step 6: Remove the temporary line from the player view**

Delete the `SpikeShaderView()` line you added in step 5.

- [ ] **Step 7: Delete the spike files and commit the directory decision**

```bash
rm Ilumionate/TextTrance/Visuals/SpikeShader.metal
rm Ilumionate/TextTrance/Visuals/SpikeShaderView.swift
```

Nothing to commit yet — the spike leaves no trace. Record in your notes that Metal works, then proceed.

---

## Task 2: `ReaderVisual` enum

**Files:**
- Create: `Ilumionate/TextTrance/Visuals/ReaderVisual.swift`
- Test: `IlumionateTests/ReaderVisualTests.swift`

- [ ] **Step 1: Write the failing test**

`IlumionateTests/ReaderVisualTests.swift`:

```swift
//
//  ReaderVisualTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct ReaderVisualTests {

    @Test("Every case has a non-empty display name")
    func displayNames() {
        for visual in ReaderVisual.allCases {
            #expect(visual.displayName.isEmpty == false)
        }
    }

    @Test("Only shader-backed cases carry a shader name")
    func shaderNames() {
        #expect(ReaderVisual.none.shaderName == nil)
        #expect(ReaderVisual.breath.shaderName == nil)
        #expect(ReaderVisual.spiral.shaderName == "readerSpiral")
        #expect(ReaderVisual.tunnel.shaderName == "readerTunnel")
        #expect(ReaderVisual.moire.shaderName == "readerMoire")
        #expect(ReaderVisual.drift.shaderName == "readerDrift")
    }

    @Test("Shader names are unique")
    func shaderNamesUnique() {
        let names = ReaderVisual.allCases.compactMap(\.shaderName)
        #expect(Set(names).count == names.count)
    }

    @Test("Raw values are stable for persistence")
    func rawValues() {
        #expect(ReaderVisual.allCases.map(\.rawValue)
                == ["none", "breath", "spiral", "tunnel", "moire", "drift"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:IlumionateTests/ReaderVisualTests 2>&1 | grep -E "error:|TEST"
```

Expected: build failure, `cannot find 'ReaderVisual' in scope`.

- [ ] **Step 3: Write the implementation**

`Ilumionate/TextTrance/Visuals/ReaderVisual.swift`:

```swift
//  ReaderVisual.swift
//  Ilumionate
//
//  The reader's animated background choices. `.none` and `.breath` are handled
//  without a shader — `.breath` is the phase-tinted radial glow the reader has
//  always had, kept as a named option so it can stay the default.

import Foundation

enum ReaderVisual: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case breath
    case spiral
    case tunnel
    case moire
    case drift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:   return "None"
        case .breath: return "Breath"
        case .spiral: return "Spiral"
        case .tunnel: return "Tunnel"
        case .moire:  return "Moiré"
        case .drift:  return "Drift"
        }
    }

    /// The `[[stitchable]]` Metal function backing this visual, or nil when the
    /// effect is rendered without a shader. This is the ONLY place shader names
    /// are written — `ShaderLibrary` resolves them at runtime, so a typo here is
    /// a blank background rather than a build error.
    var shaderName: String? {
        switch self {
        case .none, .breath: return nil
        case .spiral:        return "readerSpiral"
        case .tunnel:        return "readerTunnel"
        case .moire:         return "readerMoire"
        case .drift:         return "readerDrift"
        }
    }

    /// A one-line description for the settings row.
    var summary: String {
        switch self {
        case .none:   return "Flat background"
        case .breath: return "Slow phase-tinted glow"
        case .spiral: return "Rotating arms"
        case .tunnel: return "Rings falling inward"
        case .moire:  return "Interfering rings"
        case .drift:  return "Particles on a slow vortex"
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:IlumionateTests/ReaderVisualTests 2>&1 | grep -E "Test case|TEST"
```

Expected: 4 tests pass, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/Visuals/ReaderVisual.swift IlumionateTests/ReaderVisualTests.swift
git commit -m "feat(reader): add ReaderVisual effect enum"
```

---

## Task 3: Persist the visual choice and its opacity

**Files:**
- Modify: `Ilumionate/TextTrance/ReaderDisplayPreferences.swift`
- Test: `IlumionateTests/ReaderColorModeTests.swift`

- [ ] **Step 1: Write the failing tests**

Append inside the `ReaderColorModeTests` struct in `IlumionateTests/ReaderColorModeTests.swift`, before the closing brace:

```swift
    // MARK: - Reader Visuals

    @Test("Default visual is breath at 0.35 opacity")
    func visualDefaults() {
        #expect(ReaderDisplayPreferences.standard.visual == .breath)
        #expect(ReaderDisplayPreferences.standard.visualOpacity == 0.35)
    }

    @Test("Legacy persisted JSON without visual fields decodes to the defaults")
    func legacyVisualDecoding() throws {
        let legacy = """
        {"theme":"void","font":"monospaced","fontScale":1.0,"lineSpacing":1.0,
         "orpColor":"teal","backgroundBrightness":0.5,"hideControls":false,
         "dyslexiaFriendly":false,"colorMode":"followApp"}
        """.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(ReaderDisplayPreferences.self, from: legacy)
        #expect(prefs.visual == .breath)
        #expect(prefs.visualOpacity == 0.35)
    }

    @Test("Visual fields round-trip through Codable")
    func visualRoundTrip() throws {
        var prefs = ReaderDisplayPreferences.standard
        prefs.visual = .moire
        prefs.visualOpacity = 0.7
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(ReaderDisplayPreferences.self, from: data)
        #expect(decoded.visual == .moire)
        #expect(decoded.visualOpacity == 0.7)
    }

    @Test("Visual opacity clamps to its range at both bounds")
    func visualOpacityClamps() {
        var prefs = ReaderDisplayPreferences.standard
        prefs.visualOpacity = 5.0
        #expect(prefs.clampedVisualOpacity == ReaderDisplayPreferences.visualOpacityRange.upperBound)
        prefs.visualOpacity = -3.0
        #expect(prefs.clampedVisualOpacity == ReaderDisplayPreferences.visualOpacityRange.lowerBound)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:IlumionateTests/ReaderColorModeTests 2>&1 | grep -E "error:|TEST"
```

Expected: build failure, `value of type 'ReaderDisplayPreferences' has no member 'visual'`.

- [ ] **Step 3: Add the stored properties**

In `Ilumionate/TextTrance/ReaderDisplayPreferences.swift`, add two properties after `colorMode` (line 17):

```swift
    var visual: ReaderVisual
    var visualOpacity: Double
```

Extend the memberwise `init` signature — add these two parameters after `colorMode`:

```swift
         colorMode: ReaderColorMode = .followApp,
         visual: ReaderVisual = .breath,
         visualOpacity: Double = 0.35) {
```

and assign them at the end of the init body:

```swift
        self.visual = visual
        self.visualOpacity = visualOpacity
```

- [ ] **Step 4: Extend `CodingKeys` and the custom decoder**

Add to `CodingKeys`:

```swift
        case visual, visualOpacity
```

Add to `init(from:)`, after the `colorMode` line — `decodeIfPresent` is what keeps older stored preferences loading, exactly as `colorMode` already does:

```swift
        visual = try c.decodeIfPresent(ReaderVisual.self, forKey: .visual) ?? .breath
        visualOpacity = try c.decodeIfPresent(Double.self, forKey: .visualOpacity) ?? 0.35
```

- [ ] **Step 5: Add the range and clamp**

In the `extension ReaderDisplayPreferences` block, beside the other ranges:

```swift
    /// Capped below 1.0 on purpose: at full strength even a centre-faded effect
    /// starts competing with the word at the ellipse boundary.
    static let visualOpacityRange: ClosedRange<Double> = 0.05...0.85

    var clampedVisualOpacity: Double {
        min(max(visualOpacity, Self.visualOpacityRange.lowerBound),
            Self.visualOpacityRange.upperBound)
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:IlumionateTests/ReaderColorModeTests 2>&1 | grep -E "Test case|TEST"
```

Expected: all tests pass, including the 4 new ones.

- [ ] **Step 7: Commit**

```bash
git add Ilumionate/TextTrance/ReaderDisplayPreferences.swift IlumionateTests/ReaderColorModeTests.swift
git commit -m "feat(reader): persist visual choice and opacity"
```

---

## Task 4: Extract the phase→colour table

The background tint and the word's glow must never disagree, so there can be only one table. It currently lives as a private computed property on `TextTrancePlayerView` (line 315).

**Files:**
- Create: `Ilumionate/TextTrance/Visuals/TrancePhase+Atmosphere.swift`
- Modify: `Ilumionate/TextTrance/TextTrancePlayerView.swift`
- Test: `IlumionateTests/ReaderVisualTests.swift`

- [ ] **Step 1: Write the failing test**

Append inside `ReaderVisualTests`, before the closing brace:

```swift
    // MARK: - Phase Atmosphere

    @Test("Every phase resolves to an atmosphere colour")
    func everyPhaseHasAtmosphere() {
        for phase in TrancePhase.allCases {
            #expect(phase.atmosphereColor != Color.clear)
        }
    }

    @Test("Structural phases keep their established colours")
    func knownPhaseColors() {
        #expect(TrancePhase.induction.atmosphereColor == Color.phaseInduction)
        #expect(TrancePhase.deepening.atmosphereColor == Color.phaseDeepener)
        #expect(TrancePhase.emergence.atmosphereColor == Color.phaseAwakening)
        #expect(TrancePhase.preTalk.atmosphereColor == Color.phaseIntro)
    }
```

Add `import SwiftUI` to the top of the file, beside the existing imports.

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:IlumionateTests/ReaderVisualTests 2>&1 | grep -E "error:|TEST"
```

Expected: build failure, `value of type 'TrancePhase' has no member 'atmosphereColor'`.

- [ ] **Step 3: Create the extension**

`Ilumionate/TextTrance/Visuals/TrancePhase+Atmosphere.swift`:

```swift
//  TrancePhase+Atmosphere.swift
//  Ilumionate
//
//  The single phase→colour table for the reader. Both the background visual and
//  the word's glow read this, so they can never drift apart.

import SwiftUI

extension TrancePhase {
    var atmosphereColor: Color {
        switch self {
        case .preTalk, .transitional:    return .phaseIntro
        case .induction:                 return .phaseInduction
        case .deepening:                 return .phaseDeepener
        case .fractionation, .confusion: return .phaseFractionation
        case .suggestions, .therapy, .eroticSuggestions, .conditioning, .brainwashing:
            return .phaseSuggestion
        case .emergence:                 return .phaseAwakening
        }
    }
}
```

- [ ] **Step 4: Point the player view at it**

In `Ilumionate/TextTrance/TextTrancePlayerView.swift`, delete the whole private `phaseColor` computed property (lines 314–325, including its doc comment) and replace it with a forwarding property so the four existing call sites keep working unchanged:

```swift
    /// Atmosphere + word-glow color for the current reading phase.
    private var phaseColor: Color { session.currentPhase.atmosphereColor }
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:IlumionateTests/ReaderVisualTests 2>&1 | grep -E "Test case|TEST"
```

Expected: 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/TextTrance/Visuals/TrancePhase+Atmosphere.swift \
        Ilumionate/TextTrance/TextTrancePlayerView.swift \
        IlumionateTests/ReaderVisualTests.swift
git commit -m "refactor(reader): extract the phase atmosphere colour table"
```

---

## Task 5: Phase modulation and safety caps

This is where the coverage lives, because shader source cannot be unit-tested.

**Files:**
- Create: `Ilumionate/TextTrance/Visuals/ReaderVisualModulation.swift`
- Test: `IlumionateTests/ReaderVisualModulatorTests.swift`

- [ ] **Step 1: Write the failing tests**

`IlumionateTests/ReaderVisualModulatorTests.swift`:

```swift
//
//  ReaderVisualModulatorTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct ReaderVisualModulatorTests {

    @Test("Speed never leaves the safe band, for any phase at any pace")
    func speedAlwaysInBand() {
        for phase in TrancePhase.allCases {
            for multiplier in [-10.0, 0.0, 0.25, 1.0, 4.0, 1_000.0] {
                let m = ReaderVisualModulator.modulation(
                    for: phase, speedMultiplier: multiplier, reduceMotion: false
                )
                #expect(ReaderVisualModulator.speedBand.contains(m.speed))
            }
        }
    }

    @Test("Amplitude never leaves its band")
    func amplitudeAlwaysInBand() {
        for phase in TrancePhase.allCases {
            let m = ReaderVisualModulator.modulation(
                for: phase, speedMultiplier: 1.0, reduceMotion: false
            )
            #expect(ReaderVisualModulator.amplitudeBand.contains(m.amplitude))
        }
    }

    @Test("Reduce Motion pins speed to zero for every phase")
    func reduceMotionFreezes() {
        for phase in TrancePhase.allCases {
            let m = ReaderVisualModulator.modulation(
                for: phase, speedMultiplier: 2.0, reduceMotion: true
            )
            #expect(m.speed == 0)
        }
    }

    @Test("Reduce Motion still reports the phase tint")
    func reduceMotionKeepsTint() {
        let m = ReaderVisualModulator.modulation(
            for: .deepening, speedMultiplier: 1.0, reduceMotion: true
        )
        #expect(m.tint == Color.phaseDeepener)
    }

    @Test("Amplitude deepens through the arc and eases off at emergence")
    func amplitudeFollowsTheArc() {
        func amp(_ phase: TrancePhase) -> Double {
            ReaderVisualModulator.modulation(
                for: phase, speedMultiplier: 1.0, reduceMotion: false
            ).amplitude
        }
        #expect(amp(.preTalk) < amp(.induction))
        #expect(amp(.induction) < amp(.deepening))
        #expect(amp(.deepening) < amp(.fractionation))
        #expect(amp(.emergence) < amp(.deepening))
    }

    @Test("A faster reading pace yields a faster visual")
    func paceRaisesSpeed() {
        let slow = ReaderVisualModulator.modulation(
            for: .deepening, speedMultiplier: 0.5, reduceMotion: false
        )
        let fast = ReaderVisualModulator.modulation(
            for: .deepening, speedMultiplier: 2.0, reduceMotion: false
        )
        #expect(fast.speed > slow.speed)
    }

    @Test("Tint comes from the shared phase table")
    func tintMatchesPhase() {
        let m = ReaderVisualModulator.modulation(
            for: .emergence, speedMultiplier: 1.0, reduceMotion: false
        )
        #expect(m.tint == TrancePhase.emergence.atmosphereColor)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:IlumionateTests/ReaderVisualModulatorTests 2>&1 | grep -E "error:|TEST"
```

Expected: build failure, `cannot find 'ReaderVisualModulator' in scope`.

- [ ] **Step 3: Write the implementation**

`Ilumionate/TextTrance/Visuals/ReaderVisualModulation.swift`:

```swift
//  ReaderVisualModulation.swift
//  Ilumionate
//
//  Turns the session's reading phase and pace into the three values the shaders
//  take. Every safety limit lives here rather than in Metal, so the caps are
//  unit-testable and cannot be bypassed by editing a shader constant.

import SwiftUI

struct ReaderVisualModulation: Equatable, Sendable {
    /// Phase tint, from the shared `TrancePhase.atmosphereColor` table.
    let tint: Color
    /// Normalised motion rate. Each shader interprets this for its own geometry;
    /// see the per-effect rate comments in ReaderVisuals.metal.
    let speed: Double
    /// Pattern strength, 0…1.
    let amplitude: Double

    static let still = ReaderVisualModulation(tint: .phaseIntro, speed: 0, amplitude: 0.25)
}

enum ReaderVisualModulator {

    /// Upper bound chosen so that every shader's fastest repeating feature stays
    /// under 3 Hz at a fixed pixel — see the rate arithmetic beside each effect.
    static let speedBand: ClosedRange<Double> = 0.05...0.45
    static let amplitudeBand: ClosedRange<Double> = 0.25...1.0

    static func modulation(
        for phase: TrancePhase,
        speedMultiplier: Double,
        reduceMotion: Bool
    ) -> ReaderVisualModulation {
        let tint = phase.atmosphereColor
        let depth = depthWeight(for: phase)

        guard reduceMotion == false else {
            return ReaderVisualModulation(
                tint: tint, speed: 0, amplitude: amplitude(for: depth)
            )
        }

        // Reading pace nudges the visual, but depth dominates: a fast reader in
        // pre-talk should still see something calm.
        let pace = (min(max(speedMultiplier, 0.5), 2.0) - 0.5) / 1.5   // 0…1
        let blend = depth * (0.7 + 0.3 * pace)

        return ReaderVisualModulation(
            tint: tint,
            speed: clamp(
                speedBand.lowerBound
                    + (speedBand.upperBound - speedBand.lowerBound) * blend,
                to: speedBand
            ),
            amplitude: amplitude(for: depth)
        )
    }

    private static func amplitude(for depth: Double) -> Double {
        clamp(
            amplitudeBand.lowerBound
                + (amplitudeBand.upperBound - amplitudeBand.lowerBound) * depth,
            to: amplitudeBand
        )
    }

    /// How deep into trance a phase sits, 0…1. Drives both speed and amplitude
    /// so the background intensifies with the script and eases off on the way out.
    private static func depthWeight(for phase: TrancePhase) -> Double {
        switch phase {
        case .preTalk:            return 0.10
        case .emergence:          return 0.20
        case .induction:          return 0.45
        case .transitional:       return 0.50
        case .suggestions:        return 0.62
        case .therapy:            return 0.62
        case .eroticSuggestions:  return 0.70
        case .conditioning:       return 0.70
        case .deepening:          return 0.78
        case .brainwashing:       return 0.85
        case .confusion:          return 0.92
        case .fractionation:      return 0.95
        }
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:IlumionateTests/ReaderVisualModulatorTests 2>&1 | grep -E "Test case|TEST"
```

Expected: 7 tests pass, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/Visuals/ReaderVisualModulation.swift \
        IlumionateTests/ReaderVisualModulatorTests.swift
git commit -m "feat(reader): add phase modulation with capped motion"
```

---

## Task 6: The four shaders

**Files:**
- Create: `Ilumionate/TextTrance/Visuals/ReaderVisuals.metal`

There are no unit tests here — this is the untestable part, verified in Task 10.

- [ ] **Step 1: Write the shader file**

`Ilumionate/TextTrance/Visuals/ReaderVisuals.metal`:

```metal
//  ReaderVisuals.metal
//  Ilumionate
//
//  Reader background effects. Every function shares one uniform list —
//  (size, time, tint, speed, amplitude) — so a mismatch between Swift and Metal
//  is impossible by inspection. `speed` is the normalised value from
//  ReaderVisualModulator, capped at 0.45.
//
//  SAFETY: each effect notes the per-pixel rate of its fastest repeating
//  feature at speed = 0.45. All must stay under 3 Hz.

#include <metal_stdlib>
using namespace metal;

static constant float kTau = 6.2831853;

/// Erases the effect where the word sits. The word is pivot-anchored at the
/// view's centre and is far wider than it is tall, so the protected region is a
/// squashed ellipse. Every effect multiplies its alpha by this, which is why
/// there is no scrim overlay anywhere in the reader.
static half centreFade(float2 pos, float2 size) {
    float2 d = (pos - size * 0.5) / (size * 0.5);
    d.y /= 0.46;                     // wide-and-short protected region
    return half(smoothstep(0.35, 1.0, length(d)));
}

/// Normalised radius, 0 at centre and 1 at the nearer edge.
static float unitRadius(float2 pos, float2 size) {
    return length(pos - size * 0.5) / (min(size.x, size.y) * 0.5);
}

/// Fades every effect out near the frame edges so nothing terminates abruptly.
static half edgeFade(float r) {
    return half(1.0 - smoothstep(0.85, 1.35, r));
}

static half4 composite(half4 tint, half alpha) {
    // SwiftUI expects premultiplied colour out of a colorEffect shader.
    return half4(tint.rgb * alpha, alpha);
}

// MARK: - Spiral
// 5 arms × speed 0.45 = 2.25 Hz per pixel. Under 3 Hz.
[[ stitchable ]] half4 readerSpiral(float2 pos, half4 color, float2 size,
                                    float time, half4 tint,
                                    float speed, float amplitude) {
    float2 c = pos - size * 0.5;
    float r = unitRadius(pos, size);
    float a = atan2(c.y, c.x);
    // The r term is what turns rays into a spiral.
    float v = sin(a * 5.0 + r * 9.0 - time * speed * kTau);
    half arms = half(smoothstep(0.0, 0.6, v));
    half alpha = arms * edgeFade(r) * half(amplitude) * centreFade(pos, size);
    return composite(tint, alpha);
}

// MARK: - Tunnel
// 6 rings × speed 0.45 = 2.7 Hz per pixel. Under 3 Hz.
[[ stitchable ]] half4 readerTunnel(float2 pos, half4 color, float2 size,
                                    float time, half4 tint,
                                    float speed, float amplitude) {
    float r = unitRadius(pos, size);
    // pow compresses rings toward the centre, which reads as depth.
    float depth = pow(max(r, 0.02), 0.65);
    float v = sin(kTau * (depth * 6.0 - time * speed * 6.0));
    half rings = half(smoothstep(0.1, 0.75, v));
    half alpha = rings * edgeFade(r) * half(amplitude) * centreFade(pos, size);
    return composite(tint, alpha);
}

// MARK: - Moiré
// Motion here is the OFFSET drifting, not rings sweeping past. Ring density is
// ~14 across the half-width, so a sweeping term would breach 3 Hz; the drifting
// offset changes any pixel's local phase far more slowly.
[[ stitchable ]] half4 readerMoire(float2 pos, half4 color, float2 size,
                                   float time, half4 tint,
                                   float speed, float amplitude) {
    float2 centre = size * 0.5;
    float2 offset = float2(sin(time * speed * 0.9), cos(time * speed * 0.7))
                    * size.x * 0.06;
    float k = kTau / (size.x / 14.0);
    float v = sin(length(pos - centre - offset) * k)
            * sin(length(pos - centre + offset) * k);
    half interference = half(smoothstep(0.15, 0.85, v));
    half alpha = interference * edgeFade(unitRadius(pos, size))
               * half(amplitude) * centreFade(pos, size);
    return composite(tint, alpha);
}

// MARK: - Drift
// Positional motion only — no repeating full-frame luminance cycle, so the 3 Hz
// ceiling does not bind here.
static float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

[[ stitchable ]] half4 readerDrift(float2 pos, half4 color, float2 size,
                                   float time, half4 tint,
                                   float speed, float amplitude) {
    float2 c = (pos - size * 0.5) / (min(size.x, size.y) * 0.5);
    half acc = 0.0h;
    for (int i = 0; i < 18; i++) {
        float fi = float(i);
        float seed = hash11(fi + 1.0);
        float radius = 0.25 + 0.70 * hash11(fi + 21.0);
        float rate = 0.4 + 0.9 * seed;
        float angle = seed * kTau + time * speed * rate;
        float2 p = float2(cos(angle) * radius, sin(angle) * radius * 0.82);
        float d = length(c - p);
        acc += half(exp(-d * d * 320.0));
    }
    half alpha = min(acc, 1.0h) * half(amplitude) * centreFade(pos, size);
    return composite(tint, alpha);
}
```

- [ ] **Step 2: Build for iOS**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Build for native macOS**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=macOS,arch=arm64' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/TextTrance/Visuals/ReaderVisuals.metal
git commit -m "feat(reader): add four hypnotic background shaders"
```

---

## Task 7: The SwiftUI layer

**Files:**
- Create: `Ilumionate/TextTrance/Visuals/ReaderVisualLayer.swift`

- [ ] **Step 1: Write the view**

`Ilumionate/TextTrance/Visuals/ReaderVisualLayer.swift`:

```swift
//  ReaderVisualLayer.swift
//  Ilumionate
//
//  Feeds a ReaderVisual's shader with the current modulation. Renders nothing
//  for `.none` and `.breath` — `.breath` is the RadialGradient that already
//  lives in TextTrancePlayerView.

import SwiftUI

struct ReaderVisualLayer: View {
    let visual: ReaderVisual
    let modulation: ReaderVisualModulation
    let opacity: Double

    var body: some View {
        if let shaderName = visual.shaderName {
            GeometryReader { proxy in
                // paused: stops the schedule entirely when Reduce Motion pinned
                // speed to zero, so the shader is evaluated once and never again.
                TimelineView(.animation(paused: modulation.speed == 0)) { timeline in
                    Rectangle()
                        .foregroundStyle(.black)
                        .colorEffect(
                            ShaderLibrary[dynamicMember: shaderName](
                                .float2(proxy.size),
                                .float(Self.shaderTime(timeline.date)),
                                .color(modulation.tint),
                                .float(Float(modulation.speed)),
                                .float(Float(modulation.amplitude))
                            )
                        )
                }
            }
            .opacity(opacity)
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }

    /// Seconds, wrapped hourly. An unwrapped absolute timestamp loses float
    /// precision and the motion visibly stutters after a while.
    private static func shaderTime(_ date: Date) -> Float {
        Float(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600))
    }
}
```

- [ ] **Step 2: Build for iOS**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

If `ShaderLibrary[dynamicMember:]` does not compile, replace that call with a `switch` over `visual` that uses the static form (`ShaderLibrary.readerSpiral(...)` and so on) with the identical argument list.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/TextTrance/Visuals/ReaderVisualLayer.swift
git commit -m "feat(reader): add the shader-backed visual layer view"
```

---

## Task 8: Wire the layer into the player

**Files:**
- Modify: `Ilumionate/TextTrance/TextTrancePlayerView.swift`

- [ ] **Step 1: Add the modulation accessor**

Add beside the existing `displayPrefs` computed property (after line 31):

```swift
    /// Current modulation for the background visual. Reduce Motion is read from
    /// the environment, so toggling it mid-session pauses the layer immediately.
    private var visualModulation: ReaderVisualModulation {
        ReaderVisualModulator.modulation(
            for: session.currentPhase,
            speedMultiplier: session.speedMultiplier,
            reduceMotion: reduceMotion
        )
    }
```

- [ ] **Step 2: Insert the layer into the ZStack**

In `body`, immediately after `displayPrefs.adjustedBackground.ignoresSafeArea()` (line 54) and **before** the phase-atmosphere `RadialGradient`:

```swift
            ReaderVisualLayer(
                visual: displayPrefs.visual,
                modulation: visualModulation,
                opacity: displayPrefs.clampedVisualOpacity
            )
```

- [ ] **Step 3: Stop the breath glow from doubling up**

The `RadialGradient` is the `.breath` visual. Gate it so it only draws when `.breath` is selected. Change its `phaseColor.opacity(...)` argument (lines 61–66) from:

```swift
                    phaseColor.opacity(
                        displayPrefs.theme.showsPhaseAtmosphere
                            ? (backgroundPulse ? 0.24 : 0.10)
                            : 0
                    ),
```

to:

```swift
                    phaseColor.opacity(
                        displayPrefs.theme.showsPhaseAtmosphere
                            && displayPrefs.visual == .breath
                            ? (backgroundPulse ? 0.24 : 0.10)
                            : 0
                    ),
```

- [ ] **Step 4: Build for iOS and macOS**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD"
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=macOS,arch=arm64' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextTrancePlayerView.swift
git commit -m "feat(reader): render the visual layer behind the word"
```

---

## Task 9: Settings

**Files:**
- Modify: `Ilumionate/TextTrance/ReaderSettingsDrawer.swift`

- [ ] **Step 1: Add the opacity binding**

In `private struct ReaderDisplayFormSection`, beside the other bindings (after `brightnessBinding`, line 205):

```swift
    private var visualOpacityBinding: Binding<Double> {
        Binding(
            get: { preferences.clampedVisualOpacity },
            set: { preferences.visualOpacity = $0 }
        )
    }
```

- [ ] **Step 2: Add the Visual section**

In the same struct's `body`, add a new `Section` after the existing `Section("Reader display") { … }` closes:

```swift
        Section("Visual") {
            Picker("Effect", selection: $preferences.visual) {
                ForEach(ReaderVisual.allCases) {
                    Text($0.displayName).tag($0)
                }
            }

            Text(preferences.visual.summary)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)

            if preferences.visual != .none {
                LabeledContent(
                    "Strength",
                    value: preferences.clampedVisualOpacity
                        .formatted(.percent.precision(.fractionLength(0)))
                )
                Slider(
                    value: visualOpacityBinding,
                    in: ReaderDisplayPreferences.visualOpacityRange
                )
            }
        }
```

Note `.formatted(.percent…)` rather than `String(format:)` — this project's CLAUDE.md forbids C-style number formatting. (The neighbouring line spacing row at line 230 predates that rule; leave it alone.)

- [ ] **Step 3: Build for iOS**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/TextTrance/ReaderSettingsDrawer.swift
git commit -m "feat(reader): add visual effect and strength controls"
```

---

## Task 10: On-device verification

The shaders have no unit tests. This is their acceptance gate, and it is not optional.

**Files:** none — verification only.

- [ ] **Step 1: Run every new suite together**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:IlumionateTests/ReaderVisualTests \
       -only-testing:IlumionateTests/ReaderVisualModulatorTests \
       -only-testing:IlumionateTests/ReaderColorModeTests 2>&1 | grep -E "Test case|TEST"
```

Expected: all pass, `** TEST SUCCEEDED **`.

- [ ] **Step 2: Install and launch**

```bash
D=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
APP=$(find ~/Library/Developer/Xcode/DerivedData -name Ilumionate.app -path "*Debug-iphonesimulator*" | head -1)
xcrun simctl install "$D" "$APP" && xcrun simctl launch "$D" com.byronquine.lumenSync
```

- [ ] **Step 3: Walk the matrix and screenshot each combination**

Open the Read tab, start any script, open Settings, and check every box:

| Check | Pass condition |
| --- | --- |
| Each of `spiral`, `tunnel`, `moire`, `drift` at strength 0.85 | The word is fully legible; no effect intrudes inside the centre ellipse |
| Same four at strength 0.05 | Effect is faint but visible, not absent |
| `none` | Flat background, no glow, no pattern |
| `breath` | The original slow phase glow, and **only** that — no shader pattern |
| Themes Void, Dusk, Dawn, Paper, Sepia, Contrast with `spiral` at 0.5 | Legible on all six; note that Paper and Sepia set `showsPhaseAtmosphere == false`, which gates only `.breath`, so shader effects still draw there — confirm that reads acceptably |
| Centre-fade boundary | No hard seam or visible ellipse edge |
| Settings → Simulator → Accessibility → Reduce Motion ON | Pattern freezes to a still frame; no residual animation |
| Scrub the progress line across phases | Tint shifts with phase; shape does not change |

- [ ] **Step 4: Confirm the frame budget**

With `drift` (the heaviest — 18 blobs per pixel) at strength 0.85, watch the word timer for a full minute. Word transitions must stay even. If they stutter, reduce the loop count in `readerDrift` from 18 to 12 and re-check.

- [ ] **Step 5: Verify on native macOS**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=macOS,arch=arm64' build 2>&1 | grep -E "error:|BUILD"
```

Then run the Mac app and repeat the spiral-at-0.5 check in one dark and one light theme. `.colorEffect` is supported on macOS, but this project ships it as a first-class destination so it must be seen working.

- [ ] **Step 6: Commit the verification note**

```bash
git commit --allow-empty -m "test(reader): verify hypnotic visuals on iOS and macOS

Walked the effect × strength × theme matrix, confirmed legibility at 0.85,
Reduce Motion freezes to a still frame, and word pacing holds with drift."
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
| --- | --- |
| §1 Data model (`ReaderVisual`, opacity, back-compat) | 2, 3 |
| §2 Effect roster | 2 (metadata), 6 (shaders) |
| §3 Phase modulation + safety caps | 5 |
| §4 Shader layer + `centreFade` | 6 |
| §5 SwiftUI wrapper + insertion point | 7, 8 |
| §6 Settings UI | 9 |
| Error handling — missing shader degrades to flat | 2 (unique-name test), 10 (visual check) |
| Error handling — legacy prefs | 3 |
| Error handling — opacity clamp | 3 |
| Testing plan | 2, 3, 5, 10 |
| Risks — Metal integration | 1 |
| Shared phase→colour table (spec §3 refactor note) | 4 |

No spec requirement is unimplemented.

**Type consistency:** `ReaderVisual.shaderName` values match the four `[[stitchable]]` function names in Task 6 exactly (`readerSpiral`, `readerTunnel`, `readerMoire`, `readerDrift`). `ReaderVisualModulation` fields (`tint`, `speed`, `amplitude`) are consumed in the same order and types by Task 7's argument list and Task 6's uniform lists. `ReaderVisualModulator.speedBand` / `.amplitudeBand` are referenced by name in Task 5's tests. `clampedVisualOpacity` and `visualOpacityRange` are defined in Task 3 and used in Tasks 8 and 9.

**Deviation from spec, recorded:** the settings UI uses `Form` + `Picker` + `Slider`, not a chip row — see Before You Start.
