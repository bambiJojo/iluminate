# Create Tab: Visual Field Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the Create tab around the player's tile-tray grammar and add a wordless, directly-controlled "Visual Field" session built on the reader's existing shaders.

**Architecture:** The reader's visual stack (`ReaderVisual`, `ReaderVisualLayer`, `ReaderVisualModulation`, `ReaderVisuals.metal`) is promoted out of `TextTrance/` into a shared top-level `Visuals/` module with reading-agnostic names. It gains two capabilities the reader does not use — a signed motion rate for outward travel, and an optional focus well — plus a second modulation producer, `VisualFieldSettings`, driven directly by the user instead of by reading phase. The Create tab is then rebuilt as a segmented kind picker over a live preview and a fixed tile tray, and a new `PlayerMode.visualField` runs the session full-screen.

**Tech Stack:** Swift 6.2, SwiftUI, Metal (`[[stitchable]]` colorEffect shaders), Swift Testing, Xcode 16 file-system-synchronized project groups.

**Source spec:** `docs/superpowers/specs/2026-08-05-create-tab-visual-field-design.md`

---

## Before you start

**You do not need to touch the Xcode project file.** `Ilumionate/` and `IlumionateTests/` are `PBXFileSystemSynchronizedRootGroup`s (see `Ilumionate.xcodeproj/project.pbxproj:187-205`), so any `.swift` or `.metal` file created inside those directories joins the target automatically. Never hand-edit `project.pbxproj`.

**Build and test commands** (from `CLAUDE.md`) — both destinations are first-class, and both must pass:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests
```

**Running a single test suite** — pass the suite name after the target:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/VisualFieldSettingsTests
```

**Testing conventions.** This project uses Swift Testing, not XCTest. Suites are plain structs, tests are `@Test` functions using `#expect`. Every test file starts:

```swift
import Testing
import SwiftUI
@testable import Ilumionate
```

**The three rules this codebase enforces that you must not break:**

1. **The photosensitivity ceiling.** No effect may make a repeating feature cross a fixed pixel at 3 Hz or more. This is enforced by `everyEffectStaysUnderTheFlickerCeiling`, not by comments. Never widen `speedBand`, never raise a `motionRate`, never make the shader multiply `rate` by anything.
2. **Persisted raw values are frozen.** `TranceVisual`'s raw strings are stored in user preferences and decoded as one blob; changing one silently wipes every saved reader preference for every script.
3. **The tray never reflows.** Slot lists are pure functions of the mode/kind and have no access to runtime state.

---

# Phase 1 — The shared visual module

Phase 1 is a pure refactor plus two new capabilities. When it is done the reader must behave exactly as it does today, and no user-visible change has shipped.

---

### Task 1: Move and rename the visual module

**Files:**
- Move: `Ilumionate/TextTrance/Visuals/` → `Ilumionate/Visuals/`
- Rename within: `ReaderVisual.swift` → `TranceVisual.swift`, `ReaderVisualLayer.swift` → `VisualFieldLayer.swift`, `ReaderVisualModulation.swift` → `VisualModulation.swift`, `ReaderVisuals.metal` → `TranceVisuals.metal`
- Move back to reader surface: `ReaderVisualControls.swift`, `TrancePhase+Atmosphere.swift` → `Ilumionate/TextTrance/`
- Modify (identifier rename only): 16 files listed in Step 2
- Test: `IlumionateTests/ReaderVisualTests.swift` → `IlumionateTests/TranceVisualTests.swift`, `IlumionateTests/ReaderVisualModulatorTests.swift` → `IlumionateTests/ReadingVisualModulatorTests.swift`

This task changes no behaviour. Its whole purpose is that the tests which pass before it must pass after it, unchanged in substance.

- [ ] **Step 1: Confirm the test suite is green before you touch anything**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`. If it is not green now, stop and fix that first — you will not be able to tell your rename from a pre-existing failure.

- [ ] **Step 2: Move the files with git mv**

```bash
mkdir -p Ilumionate/Visuals
git mv Ilumionate/TextTrance/Visuals/ReaderVisual.swift            Ilumionate/Visuals/TranceVisual.swift
git mv Ilumionate/TextTrance/Visuals/ReaderVisualLayer.swift       Ilumionate/Visuals/VisualFieldLayer.swift
git mv Ilumionate/TextTrance/Visuals/ReaderVisualModulation.swift  Ilumionate/Visuals/VisualModulation.swift
git mv Ilumionate/TextTrance/Visuals/ReaderVisuals.metal           Ilumionate/Visuals/TranceVisuals.metal
git mv Ilumionate/TextTrance/Visuals/ReaderVisualControls.swift    Ilumionate/TextTrance/ReaderVisualControls.swift
git mv Ilumionate/TextTrance/Visuals/TrancePhase+Atmosphere.swift  Ilumionate/TextTrance/TrancePhase+Atmosphere.swift
rmdir Ilumionate/TextTrance/Visuals
git mv IlumionateTests/ReaderVisualTests.swift          IlumionateTests/TranceVisualTests.swift
git mv IlumionateTests/ReaderVisualModulatorTests.swift IlumionateTests/ReadingVisualModulatorTests.swift
```

`ReaderVisualControls` and `TrancePhase+Atmosphere` stay on the reader surface deliberately: the first is a reader settings control, the second is the reader's phase→colour table. Only the renderer is shared.

- [ ] **Step 3: Rename the identifiers, longest name first**

Order matters. `ReaderVisualModulator`, `ReaderVisualModulation` and `ReaderVisualLayer` all begin with `ReaderVisual`, so the general rename must run last and must be word-bounded — otherwise it corrupts `ReaderVisualStrength` and `ReaderVisualControls`, which keep their names. Use `perl`, not `sed`: BSD `sed` on macOS does not support `\b`.

```bash
FILES=$(grep -rl "ReaderVisual" Ilumionate IlumionateTests --include="*.swift")
perl -pi -e 's/\bReaderVisualModulator\b/ReadingVisualModulator/g'  $FILES
perl -pi -e 's/\bReaderVisualModulation\b/VisualModulation/g'       $FILES
perl -pi -e 's/\bReaderVisualLayer\b/VisualFieldLayer/g'            $FILES
perl -pi -e 's/\bReaderVisual\b/TranceVisual/g'                     $FILES
perl -pi -e 's/\bReaderVisualTests\b/TranceVisualTests/g'           IlumionateTests/TranceVisualTests.swift
perl -pi -e 's/\bReaderVisualModulatorTests\b/ReadingVisualModulatorTests/g' IlumionateTests/ReadingVisualModulatorTests.swift
```

- [ ] **Step 4: Verify no stale identifiers survive and nothing was over-renamed**

```bash
grep -rn "\bReaderVisual\b\|\bReaderVisualLayer\b\|\bReaderVisualModulation\b" Ilumionate IlumionateTests --include="*.swift"
```

Expected: no output.

```bash
grep -rc "ReaderVisualStrength\|ReaderVisualControls" Ilumionate --include="*.swift" | grep -v ":0"
```

Expected: non-zero counts — these two names must have survived untouched.

- [ ] **Step 5: Split the modulator out of the modulation file**

`VisualModulation.swift` holds both the shared struct and the reader-specific phase modulator. The struct is shared; the modulator is not. The modulator is the tail of the file — it starts at `enum ReadingVisualModulator {` and runs to the last line — so split it mechanically rather than by hand, to guarantee the body is byte-identical:

```bash
SRC=Ilumionate/Visuals/VisualModulation.swift
DST=Ilumionate/TextTrance/ReadingVisualModulator.swift
START=$(grep -n "^enum ReadingVisualModulator {" "$SRC" | cut -d: -f1)

cat > "$DST" <<'HEADER'
//  ReadingVisualModulator.swift
//  Ilumionate
//
//  Turns the session's reading phase and pace into a VisualModulation. This is
//  the reader's producer; the Create tab's Visual Field produces the same struct
//  directly from VisualFieldSettings instead.
//
//  Every safety limit lives on VisualModulation itself rather than here, so no
//  producer can exceed the bands.

import SwiftUI

HEADER

tail -n "+$START" "$SRC" >> "$DST"
head -n "$((START - 1))" "$SRC" > "$SRC.tmp" && mv "$SRC.tmp" "$SRC"
```

Verify the split landed:

```bash
grep -c "enum ReadingVisualModulator" Ilumionate/Visuals/VisualModulation.swift Ilumionate/TextTrance/ReadingVisualModulator.swift
```

Expected: `0` for the first file, `1` for the second.

Then update the header comment of `Ilumionate/Visuals/VisualModulation.swift` so it describes only the struct and its bands — the existing header talks about turning reading phase and pace into shader values, which is now the other file's job:

```swift
//  VisualModulation.swift
//  Ilumionate
//
//  The three values every visual shader takes, and the bands they must stay
//  inside. Two producers build this struct: ReadingVisualModulator, from the
//  reader's phase and pace, and VisualFieldSettings, from the Create tab's
//  direct controls.
//
//  Every safety limit lives here rather than in Metal, so the caps are
//  unit-testable and cannot be bypassed by editing a shader constant.
```

- [ ] **Step 6: Update the file header comments in the moved files**

Each moved file's header still says "the reader's". Fix the four headers so they describe a shared renderer:

`Ilumionate/Visuals/TranceVisual.swift`:

```swift
//  TranceVisual.swift
//  Ilumionate
//
//  The animated background effects, shared by the reader and the Create tab's
//  wordless Visual Field. `.none` and `.breath` are handled without a shader —
//  `.breath` is the phase-tinted radial glow the reader has always had, kept as
//  a named option so it can stay the reader's default.
//
//  Shader-backed effects converge toward the centre of the frame by default;
//  the Visual Field can reverse that with VisualDirection.
```

`Ilumionate/Visuals/VisualFieldLayer.swift`:

```swift
//  VisualFieldLayer.swift
//  Ilumionate
//
//  Feeds a TranceVisual's shader with the current modulation. Renders nothing
//  for `.none` and `.breath` — `.breath` is the RadialGradient that lives in
//  TextTrancePlayerView.
```

- [ ] **Step 7: Build both destinations**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Repeat for `'platform=iOS Simulator,name=iPhone 17 Pro'`.

- [ ] **Step 8: Run the full test suite on both destinations**

Expected: `** TEST SUCCEEDED **` on both. Every test that passed in Step 1 must still pass. In particular `rawValues()` must still assert `["none", "breath", "spiral", "tunnel", "moire", "drift", "glass", "linescape"]` — if you changed a raw value, you have just wiped every user's saved reader preferences.

- [ ] **Step 9: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "refactor: promote the reader's visual system to a shared Visuals module"
```

---

### Task 2: Move the opacity band to the shared module

**Files:**
- Modify: `Ilumionate/Visuals/VisualModulation.swift`
- Modify: `Ilumionate/TextTrance/ReaderDisplayPreferences.swift:209-234`
- Modify: `Ilumionate/TextTrance/ReaderVisualStrength.swift:15,20`
- Modify: `Ilumionate/TextTrance/ReaderVisualControls.swift:117`
- Test: `IlumionateTests/VisualModulationBandsTests.swift`

`visualOpacityRange` lives on `ReaderDisplayPreferences` but is the same kind of thing as `speedBand` and `amplitudeBand` — an appearance band on the renderer, not a reader preference. The value does not change, so no persisted preference shifts.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/VisualModulationBandsTests.swift`:

```swift
//
//  VisualModulationBandsTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct VisualModulationBandsTests {

    @Test("The opacity band lives on the renderer and keeps its established values")
    func opacityBand() {
        #expect(VisualModulation.opacityBand.lowerBound == 0.05)
        #expect(VisualModulation.opacityBand.upperBound == 0.85)
    }

    @Test("The reader's clamp still uses the shared band")
    func readerClampUsesSharedBand() {
        var preferences = ReaderDisplayPreferences.standard
        preferences.visualOpacity = 9.0
        #expect(preferences.clampedVisualOpacity == VisualModulation.opacityBand.upperBound)
        preferences.visualOpacity = -1.0
        #expect(preferences.clampedVisualOpacity == VisualModulation.opacityBand.lowerBound)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/VisualModulationBandsTests 2>&1 | tail -20
```

Expected: compile failure — `type 'VisualModulation' has no member 'opacityBand'`.

- [ ] **Step 3: Add the band to the shared module**

In `Ilumionate/Visuals/VisualModulation.swift`, inside `extension VisualModulation` (create the extension if there is none), add:

```swift
extension VisualModulation {
    /// Strength band for any surface drawing an effect.
    ///
    /// Capped below 1.0 on purpose: at full strength even a centre-faded effect
    /// starts competing with the reader's word at the ellipse boundary. The
    /// Visual Field has no word, but shares the band so one strength value means
    /// the same thing on both surfaces.
    static let opacityBand: ClosedRange<Double> = 0.05...0.85
}
```

- [ ] **Step 4: Point the reader at it**

In `Ilumionate/TextTrance/ReaderDisplayPreferences.swift`, delete the `visualOpacityRange` declaration and replace every use. The declaration to delete:

```swift
    /// Capped below 1.0 on purpose: at full strength even a centre-faded effect
    /// starts competing with the word at the ellipse boundary.
    static let visualOpacityRange: ClosedRange<Double> = 0.05...0.85
```

Replace `clampedVisualOpacity` with:

```swift
    var clampedVisualOpacity: Double {
        min(max(visualOpacity, VisualModulation.opacityBand.lowerBound),
            VisualModulation.opacityBand.upperBound)
    }
```

In `Ilumionate/TextTrance/ReaderVisualStrength.swift`:

```swift
    static let dragRange: ClosedRange<Double> =
        0...VisualModulation.opacityBand.upperBound

    static var offThreshold: Double {
        VisualModulation.opacityBand.lowerBound
    }
```

In `Ilumionate/TextTrance/ReaderVisualControls.swift:117`, change `in: ReaderDisplayPreferences.visualOpacityRange` to `in: VisualModulation.opacityBand`.

- [ ] **Step 5: Verify no references survive**

```bash
grep -rn "visualOpacityRange" Ilumionate IlumionateTests --include="*.swift"
```

Expected: no output.

- [ ] **Step 6: Run the tests on both destinations**

Expected: `** TEST SUCCEEDED **`, including the pre-existing `ReaderVisualStrengthTests`.

- [ ] **Step 7: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "refactor: move the visual opacity band onto VisualModulation"
```

---

### Task 3: Add VisualDirection

**Files:**
- Create: `Ilumionate/Visuals/VisualDirection.swift`
- Modify: `Ilumionate/Visuals/VisualModulation.swift`
- Modify: `Ilumionate/Visuals/VisualFieldLayer.swift`
- Modify: `Ilumionate/TextTrance/ReadingVisualModulator.swift`
- Test: `IlumionateTests/VisualDirectionTests.swift`

Direction reaches Metal as the **sign of the existing `rate` argument**. No new uniform, no shader edit in this task, and `motionRate` stays unsigned so the flicker-ceiling test keeps measuring magnitude.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/VisualDirectionTests.swift`:

```swift
//
//  VisualDirectionTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct VisualDirectionTests {

    @Test("Inward and outward are opposite signs")
    func signsAreOpposite() {
        #expect(VisualDirection.inward.sign == 1)
        #expect(VisualDirection.outward.sign == -1)
    }

    @Test("Direction changes the sign of the shader rate but never its magnitude")
    func magnitudeIsUnchanged() {
        for visual in TranceVisual.allCases {
            let inward = visual.motionRate * VisualDirection.inward.sign
            let outward = visual.motionRate * VisualDirection.outward.sign
            #expect(abs(inward) == abs(outward))
            #expect(inward == -outward || visual.motionRate == 0)
        }
    }

    @Test("The flicker ceiling holds in both directions")
    func ceilingHoldsBothWays() {
        // peakCrossingHz is derived from the unsigned motionRate, so reversing
        // travel cannot smuggle an effect past the budget.
        for visual in TranceVisual.allCases {
            #expect(visual.peakCrossingHz < 3.0)
            #expect(visual.motionRate >= 0)
        }
    }

    @Test("Raw values are stable for persistence")
    func rawValues() {
        #expect(VisualDirection.allCases.map(\.rawValue) == ["inward", "outward"])
    }

    @Test("The reader always converges inward")
    func readerIsAlwaysInward() {
        for phase in TrancePhase.allCases {
            let modulation = ReadingVisualModulator.modulation(
                for: phase, speedMultiplier: 1.0, reduceMotion: false
            )
            #expect(modulation.direction == .inward)
        }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/VisualDirectionTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'VisualDirection' in scope`.

- [ ] **Step 3: Create the type**

Create `Ilumionate/Visuals/VisualDirection.swift`:

```swift
//  VisualDirection.swift
//  Ilumionate
//
//  Which way an effect travels. Reaches Metal as the SIGN of the shader's `rate`
//  argument rather than as a uniform of its own: every effect derives motion
//  from the shared phase rule
//
//      phase = convergentDepth(r, turns) * density - time * speed * rate
//
//  so negating `rate` reverses the direction of travel with no per-effect work.
//
//  `TranceVisual.motionRate` stays unsigned so `peakCrossingHz` and the
//  photosensitivity ceiling keep measuring magnitude. Reversing travel must
//  never be a way past the budget.

import Foundation

enum VisualDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Toward the centre. The reader's only option — its effects exist to pull
    /// focus to the word.
    case inward
    /// Away from the centre. Wordless only.
    case outward

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inward:  return "Inward"
        case .outward: return "Outward"
        }
    }

    var summary: String {
        switch self {
        case .inward:  return "Drawing toward the centre"
        case .outward: return "Streaming out of the centre"
        }
    }

    var systemImage: String {
        switch self {
        case .inward:  return "arrow.down.right.and.arrow.up.left"
        case .outward: return "arrow.up.left.and.arrow.down.right"
        }
    }

    /// Multiplier applied to the shader's `rate` argument.
    var sign: Double {
        switch self {
        case .inward:  return 1
        case .outward: return -1
        }
    }
}
```

- [ ] **Step 4: Add direction to the modulation struct**

In `Ilumionate/Visuals/VisualModulation.swift`, add the property, the initialiser parameter and update `still`:

```swift
struct VisualModulation: Equatable, Sendable {
    let tint: Color
    let speed: Double
    let amplitude: Double
    /// Which way the effect travels. The reader is always `.inward`.
    let direction: VisualDirection

    init(tint: Color, speed: Double, amplitude: Double, direction: VisualDirection = .inward) {
        self.tint = tint
        self.speed = speed
        self.amplitude = amplitude
        self.direction = direction
    }

    static let still = VisualModulation(
        tint: .phaseIntro, speed: 0, amplitude: 0.25, direction: .inward
    )
}
```

The default on `direction` keeps `ReadingVisualModulator`'s two existing construction sites compiling untouched, which is why the reader test in Step 1 passes without editing the modulator.

- [ ] **Step 5: Apply the sign in the layer**

In `Ilumionate/Visuals/VisualFieldLayer.swift`, change the `rate` argument:

```swift
                            // Sourced from Swift, not hardcoded in Metal, so
                            // the photosensitivity ceiling is testable. The sign
                            // carries direction; the magnitude is what the
                            // ceiling test measures.
                            .float(Float(visual.motionRate * modulation.direction.sign))
```

- [ ] **Step 6: Run the tests on both destinations**

Expected: `** TEST SUCCEEDED **`. `everyEffectStaysUnderTheFlickerCeiling` and `moireHasTheLeastHeadroom` must be untouched and still passing.

- [ ] **Step 7: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(visuals): add VisualDirection, carried as the sign of the shader rate"
```

---

### Task 4: Make the focus well optional

**Files:**
- Modify: `Ilumionate/Visuals/TranceVisuals.metal`
- Modify: `Ilumionate/Visuals/VisualFieldLayer.swift`
- Test: manual visual check (shader output is not unit-testable)

Every effect ends with `alpha = ... * focusWell(pos, size)`, which erases the effect where the reader's word sits. Wordless, that punches a dark hole to protect a word that is not there and removes the vanishing point. The uniform list gains a `focus` float: reader `1.0` (identical to today), Visual Field `0.0`.

- [ ] **Step 1: Add the uniform to all six shader signatures**

In `Ilumionate/Visuals/TranceVisuals.metal`, every `[[ stitchable ]]` function gains a trailing `float focus` parameter. There are six: `readerSpiral`, `readerTunnel`, `readerMoire`, `readerDrift`, `readerGlass`, `readerLinescape`. **Do not rename the functions** — `shaderNames()` pins them to literals and `ShaderLibrary` resolves them by name at runtime, so a rename is a blank background, not a build error.

For each, change:

```metal
[[ stitchable ]] half4 readerSpiral(float2 pos, half4 color, float4 bounds,
                                    float time, half4 tint,
                                    float speed, float amplitude, float rate) {
```

to:

```metal
[[ stitchable ]] half4 readerSpiral(float2 pos, half4 color, float4 bounds,
                                    float time, half4 tint,
                                    float speed, float amplitude, float rate,
                                    float focus) {
```

Verify you got all six:

```bash
grep -c "float focus)" Ilumionate/Visuals/TranceVisuals.metal
```

Expected: `6`.

- [ ] **Step 2: Add the blend helper**

In the "Shared grammar" section of `TranceVisuals.metal`, immediately after the existing `focusWell` function, add:

```metal
/// How much of the focus well to apply. `focus` is 1 for the reader, which needs
/// the well to protect its word, and 0 for the wordless Visual Field, which has
/// no word to protect and wants the compressed centre the well would erase.
///
/// A blend rather than a branch: `focus` is uniform across the frame, so there is
/// no divergence cost, and intermediate values stay available without adding a
/// second code path to reason about.
static half focusMask(float2 pos, float2 size, float focus) {
    return mix(1.0h, focusWell(pos, size), half(clamp(focus, 0.0, 1.0)));
}
```

- [ ] **Step 3: Route every effect through the helper**

Replace all six `focusWell(pos, size)` call sites in the effect bodies (lines ~171, ~191, ~222, ~285, ~346, ~387) with `focusMask(pos, size, focus)`:

```bash
perl -pi -e 's/\* focusWell\(pos, size\)/* focusMask(pos, size, focus)/g' Ilumionate/Visuals/TranceVisuals.metal
perl -pi -e 's/^(\s+)\* focusWell\(pos, size\);/$1* focusMask(pos, size, focus);/' Ilumionate/Visuals/TranceVisuals.metal
```

Verify exactly one definition and six uses remain:

```bash
grep -c "focusMask(pos, size, focus)" Ilumionate/Visuals/TranceVisuals.metal
grep -n "focusWell(pos, size)" Ilumionate/Visuals/TranceVisuals.metal
```

Expected: `6` for the first. The second must show only the line inside `focusMask` itself.

- [ ] **Step 4: Pass the argument from Swift**

In `Ilumionate/Visuals/VisualFieldLayer.swift`, add the parameter with a reader-preserving default and pass it as the last shader argument:

```swift
struct VisualFieldLayer: View {
    let visual: TranceVisual
    let modulation: VisualModulation
    let opacity: Double
    /// How much of the centre focus well to apply. 1 protects a word at the
    /// centre — the reader's case, and the default so its call sites are
    /// unchanged. 0 leaves the centre unbroken, which is what the wordless
    /// Visual Field wants: the compressed vanishing point IS the effect there.
    var focus: Double = 1
```

and inside the `colorEffect` argument list, after the `rate` argument:

```swift
                            .float(Float(visual.motionRate * modulation.direction.sign)),
                            .float(Float(min(max(focus, 0), 1)))
```

- [ ] **Step 5: Build both destinations**

Expected: `** BUILD SUCCEEDED **`. A Metal signature mismatch does **not** fail the build — `ShaderLibrary` resolves at runtime — so the build passing is necessary, not sufficient. Step 6 is the real check.

- [ ] **Step 6: Verify the reader renders unchanged**

Run the app, open the reader, and select each of the six shader-backed effects in turn. Each must render exactly as before this task: a still, dark elliptical well at the centre with the word sitting in it, and no scrim.

A blank or black background means the shader signature and the Swift argument list disagree — recount the arguments in `VisualFieldLayer` against the Metal parameter list; there must now be seven after `pos`/`color`: `bounds, time, tint, speed, amplitude, rate, focus`.

- [ ] **Step 7: Run the full test suite on both destinations**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(visuals): make the focus well optional via a focus uniform"
```

---

### Task 5: Add VisualTint with a luminance floor

**Files:**
- Create: `Ilumionate/Visuals/VisualTint.swift`
- Test: `IlumionateTests/VisualTintTests.swift`

`tint` multiplies the shader output, so a very dark custom pick does not produce a moody field — it produces a black rectangle. The floor lifts such picks rather than rejecting them.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/VisualTintTests.swift`:

```swift
//
//  VisualTintTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct VisualTintTests {

    // MARK: - Palette

    @Test("Every palette case has a non-empty display name")
    func displayNames() {
        for tint in VisualTint.palette {
            #expect(tint.displayName.isEmpty == false)
        }
    }

    @Test("The palette cases are visually distinct from one another")
    func paletteIsDistinct() {
        let colors = VisualTint.palette.map(\.color)
        #expect(Set(colors).count == colors.count)
    }

    @Test("Raw values are stable for persistence")
    func rawValuesRoundTrip() throws {
        for tint in VisualTint.palette + [.custom("FF8800")] {
            let data = try JSONEncoder().encode(tint)
            let decoded = try JSONDecoder().decode(VisualTint.self, from: data)
            #expect(decoded == tint)
        }
    }

    // MARK: - Luminance floor

    @Test("A bright colour passes through the floor untouched")
    func brightColourUnchanged() {
        let lifted = VisualTint.lift(red: 0.9, green: 0.9, blue: 0.9)
        #expect(abs(lifted.red - 0.9) < 0.0001)
        #expect(abs(lifted.green - 0.9) < 0.0001)
        #expect(abs(lifted.blue - 0.9) < 0.0001)
    }

    @Test("A near-black colour is lifted to the floor, keeping its hue")
    func darkColourIsLifted() {
        let lifted = VisualTint.lift(red: 0.04, green: 0.0, blue: 0.0)
        #expect(VisualTint.luminance(lifted) >= VisualTint.luminanceFloor - 0.0001)
        // Hue preserved: red still dominates and the dark channels stay dark.
        #expect(lifted.red > lifted.green)
        #expect(lifted.red > lifted.blue)
    }

    @Test("Pure black becomes a neutral grey at the floor rather than staying black")
    func pureBlackBecomesGrey() {
        let lifted = VisualTint.lift(red: 0, green: 0, blue: 0)
        #expect(VisualTint.luminance(lifted) >= VisualTint.luminanceFloor - 0.0001)
        #expect(lifted.red == lifted.green)
        #expect(lifted.green == lifted.blue)
    }

    @Test("Lifting never pushes a channel out of range")
    func liftedChannelsStayInRange() {
        for value in [0.0, 0.01, 0.2, 0.5, 0.99, 1.0] {
            let lifted = VisualTint.lift(red: value, green: value * 0.5, blue: 0)
            for channel in [lifted.red, lifted.green, lifted.blue] {
                #expect(channel >= 0)
                #expect(channel <= 1)
            }
        }
    }

    // MARK: - Custom hex

    @Test("A malformed hex falls back to the default tint, never to black or clear")
    func malformedHexFallsBack() {
        #expect(VisualTint.custom("nonsense").color == VisualTint.default.color)
        #expect(VisualTint.custom("").color == VisualTint.default.color)
        #expect(VisualTint.custom("#12").color == VisualTint.default.color)
    }

    @Test("A well-formed hex is accepted with or without its hash")
    func wellFormedHexIsAccepted() {
        #expect(VisualTint.custom("FF8800").color == VisualTint.custom("#FF8800").color)
        #expect(VisualTint.custom("FF8800").color != VisualTint.default.color)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/VisualTintTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'VisualTint' in scope`.

- [ ] **Step 3: Create the type**

Create `Ilumionate/Visuals/VisualTint.swift`:

```swift
//  VisualTint.swift
//  Ilumionate
//
//  The colour driving a wordless Visual Field. The reader takes its tint from
//  the reading phase instead — see TrancePhase.atmosphereColor.
//
//  The palette cases are drawn from the app's existing phase table so a Visual
//  Field session looks like it belongs to this app. `.custom` exists because a
//  fixed palette eventually feels like a cage.
//
//  THE FLOOR IS LOAD-BEARING. `tint` multiplies the shader's output, so a very
//  dark colour does not render a moody field — it renders a black rectangle that
//  reads as a broken screen. Dark picks are lifted, not rejected.

import SwiftUI

enum VisualTint: Codable, Equatable, Hashable, Sendable {
    case teal
    case violet
    case rose
    case amber
    case ice
    case gold
    case custom(String)   // hex, with or without a leading '#'

    static let `default`: VisualTint = .violet

    /// The named cases, in picker order. Not `allCases` — `custom` carries a
    /// payload and has no place in a swatch list.
    static let palette: [VisualTint] = [.teal, .violet, .rose, .amber, .ice, .gold]

    var displayName: String {
        switch self {
        case .teal:     return "Teal"
        case .violet:   return "Violet"
        case .rose:     return "Rose"
        case .amber:    return "Amber"
        case .ice:      return "Ice"
        case .gold:     return "Gold"
        case .custom:   return "Custom"
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    // MARK: - Resolution

    var color: Color {
        switch self {
        case .teal:   return .phaseInduction
        case .violet: return .phaseDeepener
        case .rose:   return .phaseSuggestion
        case .amber:  return .phaseFractionation
        case .ice:    return .bwAlpha
        case .gold:   return .phaseAwakening
        case .custom(let hex):
            guard let channels = Self.channels(fromHex: hex) else {
                return Self.default.color
            }
            let lifted = Self.lift(
                red: channels.red, green: channels.green, blue: channels.blue
            )
            return Color(red: lifted.red, green: lifted.green, blue: lifted.blue)
        }
    }

    // MARK: - Hex parsing

    struct Channels: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// Parses `RRGGBB`, with or without a leading `#`. Returns nil for anything
    /// else so the caller can fall back rather than render black.
    static func channels(fromHex hex: String) -> Channels? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing("#", with: "")
        guard trimmed.count == 6,
              let value = Int(trimmed, radix: 16) else { return nil }
        return Channels(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue:  Double(value & 0xFF) / 255
        )
    }

    // MARK: - Luminance floor

    /// Below this, a tint renders as an apparently broken screen rather than as
    /// a dark mood. Chosen so the dimmest palette case sits comfortably above it.
    static let luminanceFloor: Double = 0.30

    /// Rec. 709 relative luminance.
    static func luminance(_ channels: Channels) -> Double {
        0.2126 * channels.red + 0.7152 * channels.green + 0.0722 * channels.blue
    }

    /// Lifts a colour to the floor, preserving hue where there is a hue to
    /// preserve. Pure black has no hue to keep, so it becomes neutral grey.
    static func lift(red: Double, green: Double, blue: Double) -> Channels {
        let clamped = Channels(
            red: min(max(red, 0), 1),
            green: min(max(green, 0), 1),
            blue: min(max(blue, 0), 1)
        )
        let current = luminance(clamped)
        guard current < luminanceFloor else { return clamped }
        guard current > 0 else {
            return Channels(
                red: luminanceFloor, green: luminanceFloor, blue: luminanceFloor
            )
        }
        // Scale toward white rather than multiplying: a pure-red pick multiplied
        // by 8 saturates to the same red and never reaches the floor, because a
        // channel that is already 1.0 cannot contribute more luminance.
        let t = min(max((luminanceFloor - current) / max(1 - current, 0.0001), 0), 1)
        return Channels(
            red: clamped.red + (1 - clamped.red) * t,
            green: clamped.green + (1 - clamped.green) * t,
            blue: clamped.blue + (1 - clamped.blue) * t
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/VisualTintTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`.

If `darkColourIsLifted` fails its hue assertion, the lift is scaling toward white too aggressively — check that `t` uses the headroom denominator `(1 - current)` and not `current`.

- [ ] **Step 5: Run the full suite on both destinations**

Expected: `** TEST SUCCEEDED **` on both.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(visuals): add VisualTint with a luminance floor"
```

---

### Task 6: Add VisualFieldSettings

**Files:**
- Create: `Ilumionate/Visuals/VisualFieldSettings.swift`
- Test: `IlumionateTests/VisualFieldSettingsTests.swift`

This is the direct-control producer of `VisualModulation`, and the test below is what makes the photosensitivity cap unbypassable from the settings layer.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/VisualFieldSettingsTests.swift`:

```swift
//
//  VisualFieldSettingsTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct VisualFieldSettingsTests {

    private func settings(
        speed: Double = 0.5,
        amplitude: Double = 0.5,
        direction: VisualDirection = .inward
    ) -> VisualFieldSettings {
        VisualFieldSettings(
            visual: .spiral,
            tint: .violet,
            speed: speed,
            amplitude: amplitude,
            direction: direction,
            opacity: 0.4,
            duration: nil
        )
    }

    // MARK: - The cap

    @Test("Speed always lands inside the safety band, whatever is asked for",
          arguments: [-99.0, -1.0, 0.0, 0.25, 0.5, 1.0, 2.0, 1_000.0])
    func speedAlwaysInBand(requested: Double) {
        let modulation = settings(speed: requested).modulation(reduceMotion: false)
        #expect(modulation.speed >= VisualModulation.speedBand.lowerBound)
        #expect(modulation.speed <= VisualModulation.speedBand.upperBound)
    }

    @Test("Amplitude always lands inside the safety band",
          arguments: [-99.0, -1.0, 0.0, 0.25, 0.5, 1.0, 2.0, 1_000.0])
    func amplitudeAlwaysInBand(requested: Double) {
        let modulation = settings(amplitude: requested).modulation(reduceMotion: false)
        #expect(modulation.amplitude >= VisualModulation.amplitudeBand.lowerBound)
        #expect(modulation.amplitude <= VisualModulation.amplitudeBand.upperBound)
    }

    @Test("A non-finite value degrades to the bottom of the band, not to NaN")
    func nonFiniteValuesDegrade() {
        for bad in [Double.nan, .infinity, -.infinity] {
            let modulation = settings(speed: bad, amplitude: bad)
                .modulation(reduceMotion: false)
            #expect(modulation.speed.isFinite)
            #expect(modulation.amplitude.isFinite)
            #expect(modulation.speed == VisualModulation.speedBand.lowerBound)
            #expect(modulation.amplitude == VisualModulation.amplitudeBand.lowerBound)
        }
    }

    @Test("Full speed is exactly the band ceiling — the same ceiling the reader's deepest phase reaches")
    func fullSpeedIsTheBandCeiling() {
        let modulation = settings(speed: 1.0).modulation(reduceMotion: false)
        #expect(modulation.speed == VisualModulation.speedBand.upperBound)
    }

    // MARK: - Reduce Motion

    @Test("Reduce Motion freezes the field but keeps its appearance")
    func reduceMotionFreezes() {
        let modulation = settings(speed: 1.0).modulation(reduceMotion: true)
        #expect(modulation.speed == 0)
        #expect(modulation.amplitude > 0)
        #expect(modulation.tint == VisualTint.violet.color)
    }

    // MARK: - Pass-through

    @Test("Tint and direction reach the modulation unchanged")
    func passThrough() {
        let modulation = settings(direction: .outward).modulation(reduceMotion: false)
        #expect(modulation.direction == .outward)
        #expect(modulation.tint == VisualTint.violet.color)
    }

    // MARK: - Defaults

    @Test("The default settings are a running, visible field")
    func defaultsAreVisible() {
        let modulation = VisualFieldSettings.standard.modulation(reduceMotion: false)
        #expect(VisualFieldSettings.standard.visual != .none)
        #expect(modulation.speed > 0)
        #expect(modulation.amplitude > 0)
        #expect(VisualFieldSettings.standard.duration == nil)
    }

    @Test("Opacity is clamped to the shared band")
    func opacityIsClamped() {
        var high = VisualFieldSettings.standard
        high.opacity = 9
        #expect(high.clampedOpacity == VisualModulation.opacityBand.upperBound)

        var low = VisualFieldSettings.standard
        low.opacity = -9
        #expect(low.clampedOpacity == VisualModulation.opacityBand.lowerBound)
    }

    // MARK: - Persistence

    @Test("Settings round-trip through Codable")
    func codableRoundTrip() throws {
        let original = settings(direction: .outward)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(VisualFieldSettings.self, from: data) == original)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Expected: compile failure — `cannot find 'VisualFieldSettings' in scope`.

- [ ] **Step 3: Create the type**

Create `Ilumionate/Visuals/VisualFieldSettings.swift`:

```swift
//  VisualFieldSettings.swift
//  Ilumionate
//
//  The wordless Visual Field's controls, and the second producer of
//  VisualModulation. The reader's producer is ReadingVisualModulator, which
//  derives the same struct from reading phase and pace instead.
//
//  SPEED AND AMPLITUDE ARE STORED NORMALISED, 0…1, and mapped into
//  VisualModulation's bands here. That is what makes the photosensitivity cap
//  unbypassable from the settings layer: "100% speed" resolves to
//  speedBand.upperBound — the same ceiling the reader's deepest phase reaches —
//  rather than to an unbounded number. Never store band-space values in this
//  struct, and never let a caller construct a VisualModulation directly.

import SwiftUI

struct VisualFieldSettings: Codable, Equatable, Sendable {
    var visual: TranceVisual
    var tint: VisualTint
    /// Normalised 0…1. Mapped into `VisualModulation.speedBand`.
    var speed: Double
    /// Normalised 0…1. Mapped into `VisualModulation.amplitudeBand`.
    var amplitude: Double
    var direction: VisualDirection
    /// Strength, in `VisualModulation.opacityBand` units.
    var opacity: Double
    /// nil runs open-ended.
    var duration: TimeInterval?

    static let standard = VisualFieldSettings(
        visual: .spiral,
        tint: .default,
        speed: 0.45,
        amplitude: 0.6,
        direction: .inward,
        opacity: 0.5,
        duration: nil
    )

    var clampedOpacity: Double {
        min(max(opacity, VisualModulation.opacityBand.lowerBound),
            VisualModulation.opacityBand.upperBound)
    }

    // MARK: - Modulation

    func modulation(reduceMotion: Bool) -> VisualModulation {
        let amplitude = Self.map(self.amplitude, into: VisualModulation.amplitudeBand)

        guard reduceMotion == false else {
            return VisualModulation(
                tint: tint.color, speed: 0, amplitude: amplitude, direction: direction
            )
        }

        return VisualModulation(
            tint: tint.color,
            speed: Self.map(speed, into: VisualModulation.speedBand),
            amplitude: amplitude,
            direction: direction
        )
    }

    /// Maps a normalised 0…1 value into a band. Non-finite input degrades to the
    /// bottom of the band rather than propagating NaN into a shader argument,
    /// where it would render as a blank frame with no diagnostic.
    private static func map(_ value: Double, into band: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return band.lowerBound }
        let normalised = min(max(value, 0), 1)
        return band.lowerBound + (band.upperBound - band.lowerBound) * normalised
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case visual, tint, speed, amplitude, direction, opacity, duration
    }

    init(visual: TranceVisual,
         tint: VisualTint,
         speed: Double,
         amplitude: Double,
         direction: VisualDirection,
         opacity: Double,
         duration: TimeInterval?) {
        self.visual = visual
        self.tint = tint
        self.speed = speed
        self.amplitude = amplitude
        self.direction = direction
        self.opacity = opacity
        self.duration = duration
    }

    /// Every field decodes optionally and falls back to its default, for the
    /// same reason `ReaderDisplayPreferences` does: one unreadable field must
    /// degrade to its default rather than discard every other setting with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.standard
        visual = try c.decodeIfPresent(TranceVisual.self, forKey: .visual) ?? d.visual
        tint = try c.decodeIfPresent(VisualTint.self, forKey: .tint) ?? d.tint
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed
        amplitude = try c.decodeIfPresent(Double.self, forKey: .amplitude) ?? d.amplitude
        direction = try c.decodeIfPresent(VisualDirection.self, forKey: .direction) ?? d.direction
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Run the full suite on both destinations**

- [ ] **Step 6: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(visuals): add VisualFieldSettings as the direct modulation producer"
```

---

**Phase 1 checkpoint.** The reader is unchanged, no user-visible feature has shipped, and the shared module can now describe a wordless field. Stop here and confirm the reader still renders all seven effects correctly before starting Phase 2.

---

# Phase 2 — The Create tab

---

### Task 7: Add CreateSessionKind

**Files:**
- Create: `Ilumionate/Create/CreateSessionKind.swift`
- Modify: `Ilumionate/Analytics/AnalyticsEvent.swift:231-241`
- Test: `IlumionateTests/CreateSessionKindTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/CreateSessionKindTests.swift`:

```swift
//
//  CreateSessionKindTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct CreateSessionKindTests {

    @Test("Every kind has a non-empty title and icon")
    func titlesAndIcons() {
        for kind in CreateSessionKind.allCases {
            #expect(kind.title.isEmpty == false)
            #expect(kind.systemImage.isEmpty == false)
        }
    }

    @Test("Raw values are stable for persistence")
    func rawValues() {
        #expect(CreateSessionKind.allCases.map(\.rawValue)
                == ["flash", "colourPulse", "bilateral", "visualField"])
    }

    @Test("Only the visual field is wordless; the rest drive the light engine")
    func lightEngineUse() {
        #expect(CreateSessionKind.visualField.usesLightEngine == false)
        for kind in [CreateSessionKind.flash, .colourPulse, .bilateral] {
            #expect(kind.usesLightEngine)
        }
    }

    @Test("Only light-engine kinds require the photosensitivity warning")
    func safetyWarning() {
        for kind in CreateSessionKind.allCases {
            #expect(kind.requiresSafetyWarning == kind.usesLightEngine)
        }
    }

    @Test("Every kind maps to a distinct analytics mode")
    func analyticsModesAreDistinct() {
        let modes = CreateSessionKind.allCases.map(\.analyticsMode)
        #expect(Set(modes.map(\.rawValue)).count == modes.count)
        #expect(CreateSessionKind.visualField.analyticsMode == .visualField)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Expected: compile failure — `cannot find 'CreateSessionKind' in scope`.

- [ ] **Step 3: Add the analytics cases**

In `Ilumionate/Analytics/AnalyticsEvent.swift`, extend both enums:

```swift
enum MindMachineMode: String, Sendable {
    case flash, colorPulse, bilateral, visualField
}
```

```swift
nonisolated enum CreateMode: String, Sendable {
    case flash, colorPulse, bilateral, audioSession, visualField
}
```

- [ ] **Step 4: Create the kind**

Create `Ilumionate/Create/CreateSessionKind.swift`:

```swift
//  CreateSessionKind.swift
//  Ilumionate
//
//  What the Create tab is making. This is the segmented row at the top of the
//  screen, and it decides which tiles the tray shows.
//
//  `visualField` is the odd one out and deliberately so: it never touches
//  LightEngine or FlashController, which is why it carries no photosensitivity
//  warning. Keeping that warning on the light path preserves its meaning —
//  showing it everywhere teaches people to dismiss it.

import Foundation

enum CreateSessionKind: String, CaseIterable, Identifiable, Sendable {
    case flash
    case colourPulse
    case bilateral
    case visualField

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flash:       return "Flash"
        case .colourPulse: return "Colour"
        case .bilateral:   return "Bilateral"
        case .visualField: return "Visuals"
        }
    }

    var systemImage: String {
        switch self {
        case .flash:       return "flashlight.on.fill"
        case .colourPulse: return "paintpalette.fill"
        case .bilateral:   return "circle.lefthalf.filled"
        case .visualField: return "circle.hexagonpath.fill"
        }
    }

    var summary: String {
        switch self {
        case .flash:       return "Full-screen entrainment flash"
        case .colourPulse: return "Slow colour breathing"
        case .bilateral:   return "Independent left and right fields"
        case .visualField: return "A wordless hypnotic field"
        }
    }

    /// Whether this kind drives LightEngine / FlashController.
    var usesLightEngine: Bool {
        self != .visualField
    }

    /// Only the light path flashes, so only the light path warns.
    var requiresSafetyWarning: Bool {
        usesLightEngine
    }

    var analyticsMode: CreateMode {
        switch self {
        case .flash:       return .flash
        case .colourPulse: return .colorPulse
        case .bilateral:   return .bilateral
        case .visualField: return .visualField
        }
    }

    var mindMachineMode: MindMachineMode {
        switch self {
        case .flash:       return .flash
        case .colourPulse: return .colorPulse
        case .bilateral:   return .bilateral
        case .visualField: return .visualField
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass, then the full suite on both destinations**

- [ ] **Step 6: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(create): add CreateSessionKind"
```

---

### Task 8: Add CreateControlSlot

**Files:**
- Create: `Ilumionate/Create/CreateControlSlot.swift`
- Test: `IlumionateTests/CreateControlSlotTests.swift`

Mirrors `PlayerControlSlot`, including the rule that matters: `slots(for:)` takes only the kind, so no value change can add or remove a tile and the tray cannot reflow mid-drag.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/CreateControlSlotTests.swift`:

```swift
//
//  CreateControlSlotTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct CreateControlSlotTests {

    @Test("Each kind's tray is pinned")
    func trays() {
        #expect(CreateControlSlot.slots(for: .visualField)
                == [.effect, .tint, .visualSpeed, .strength, .direction, .duration])
        #expect(CreateControlSlot.slots(for: .flash)
                == [.frequency, .intensity, .warmth, .waveform, .binaural, .duration])
        #expect(CreateControlSlot.slots(for: .bilateral)
                == [.frequency, .intensity, .warmth, .waveform, .binaural, .duration])
        #expect(CreateControlSlot.slots(for: .colourPulse)
                == [.frequency, .intensity, .duration])
    }

    @Test("A tray is the same list every time it is asked for")
    func traysAreStable() {
        for kind in CreateSessionKind.allCases {
            #expect(CreateControlSlot.slots(for: kind) == CreateControlSlot.slots(for: kind))
        }
    }

    @Test("No tray repeats a slot")
    func noDuplicateSlots() {
        for kind in CreateSessionKind.allCases {
            let slots = CreateControlSlot.slots(for: kind)
            #expect(Set(slots).count == slots.count)
        }
    }

    @Test("Every tray fits the two-rows-of-three layout")
    func traysFitTheLayout() {
        for kind in CreateSessionKind.allCases {
            let count = CreateControlSlot.slots(for: kind).count
            #expect(count >= 1)
            #expect(count <= 6)
        }
    }

    @Test("Every slot has a non-empty label and icon")
    func labelsAndIcons() {
        for slot in CreateControlSlot.allCases {
            #expect(slot.label.isEmpty == false)
            #expect(slot.systemImage.isEmpty == false)
        }
    }

    @Test("Continuous values drag; discrete ones tap")
    func draggability() {
        for slot in [CreateControlSlot.visualSpeed, .strength, .frequency, .intensity, .warmth] {
            #expect(slot.isDraggable)
        }
        for slot in [CreateControlSlot.effect, .tint, .direction, .duration, .waveform, .binaural] {
            #expect(slot.isDraggable == false)
        }
    }

    @Test("Every slot in every tray is reachable from allCases")
    func everySlotIsDeclared() {
        for kind in CreateSessionKind.allCases {
            for slot in CreateControlSlot.slots(for: kind) {
                #expect(CreateControlSlot.allCases.contains(slot))
            }
        }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Expected: compile failure — `cannot find 'CreateControlSlot' in scope`.

- [ ] **Step 3: Create the slot**

Create `Ilumionate/Create/CreateControlSlot.swift`:

```swift
//  CreateControlSlot.swift
//  Ilumionate
//
//  Which control tiles the Create tab shows for each session kind.
//
//  `slots(for:)` deliberately takes only a CreateSessionKind. It has no access
//  to any value, so changing a setting can never add or remove a tile — the tray
//  cannot reflow under the user's finger mid-drag. Same rule, same reason, as
//  PlayerControlSlot.slots(for:).

import Foundation

enum CreateControlSlot: String, Equatable, Hashable, CaseIterable, Sendable {
    // Visual field
    case effect
    case tint
    case visualSpeed
    case strength
    case direction
    // Light kinds
    case frequency
    case intensity
    case warmth
    case waveform
    case binaural
    // Shared
    case duration

    // MARK: - Composition

    static func slots(for kind: CreateSessionKind) -> [CreateControlSlot] {
        switch kind {
        case .visualField:
            return [.effect, .tint, .visualSpeed, .strength, .direction, .duration]
        case .flash, .bilateral:
            return [.frequency, .intensity, .warmth, .waveform, .binaural, .duration]
        case .colourPulse:
            return [.frequency, .intensity, .duration]
        }
    }

    // MARK: - Presentation

    /// Whether this tile is adjusted by dragging rather than tapping. A tile is
    /// one or the other, never both — see PlayerControlTile.
    var isDraggable: Bool {
        switch self {
        case .visualSpeed, .strength, .frequency, .intensity, .warmth:
            return true
        case .effect, .tint, .direction, .waveform, .binaural, .duration:
            return false
        }
    }

    /// Labels stay constant so the tray never reflows and muscle memory holds;
    /// the current value is carried by the tile's gauge and value text.
    var label: String {
        switch self {
        case .effect:      return "Effect"
        case .tint:        return "Colour"
        case .visualSpeed: return "Speed"
        case .strength:    return "Strength"
        case .direction:   return "Direction"
        case .frequency:   return "Frequency"
        case .intensity:   return "Intensity"
        case .warmth:      return "Warmth"
        case .waveform:    return "Waveform"
        case .binaural:    return "Binaural"
        case .duration:    return "Duration"
        }
    }

    var systemImage: String {
        switch self {
        case .effect:      return "circle.hexagonpath"
        case .tint:        return "paintpalette"
        case .visualSpeed: return "speedometer"
        case .strength:    return "circle.lefthalf.filled"
        case .direction:   return "arrow.down.right.and.arrow.up.left"
        case .frequency:   return "waveform.path"
        case .intensity:   return "sun.max"
        case .warmth:      return "thermometer.sun"
        case .waveform:    return "waveform"
        case .binaural:    return "headphones"
        case .duration:    return "timer"
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass, then the full suite on both destinations**

- [ ] **Step 5: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(create): add CreateControlSlot"
```

---

### Task 9: Add VisualFieldStore

**Files:**
- Create: `Ilumionate/Create/VisualFieldStore.swift`
- Test: `IlumionateTests/VisualFieldStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/VisualFieldStoreTests.swift`:

```swift
//
//  VisualFieldStoreTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct VisualFieldStoreTests {

    /// A defaults suite of its own per test, so tests never see each other's writes.
    private func freshDefaults() -> UserDefaults {
        let name = "VisualFieldStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("An empty store starts from the standard settings")
    func emptyStoreUsesDefaults() {
        let store = VisualFieldStore(defaults: freshDefaults())
        #expect(store.settings == VisualFieldSettings.standard)
    }

    @Test("Settings survive a round trip through the defaults")
    func settingsPersist() {
        let defaults = freshDefaults()
        let store = VisualFieldStore(defaults: defaults)

        var edited = VisualFieldSettings.standard
        edited.visual = .tunnel
        edited.direction = .outward
        edited.tint = .custom("FF8800")
        edited.duration = 600
        store.settings = edited

        #expect(VisualFieldStore(defaults: defaults).settings == edited)
    }

    @Test("Corrupt stored data degrades to the defaults instead of crashing")
    func corruptDataDegrades() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: VisualFieldStore.defaultsKey)
        #expect(VisualFieldStore(defaults: defaults).settings == VisualFieldSettings.standard)
    }

    @Test("A partial payload keeps the fields it has and defaults the rest")
    func partialPayloadFallsBackPerField() throws {
        let defaults = freshDefaults()
        defaults.set(Data(#"{"visual":"moire"}"#.utf8), forKey: VisualFieldStore.defaultsKey)

        let store = VisualFieldStore(defaults: defaults)
        #expect(store.settings.visual == .moire)
        #expect(store.settings.tint == VisualFieldSettings.standard.tint)
        #expect(store.settings.speed == VisualFieldSettings.standard.speed)
    }

    @Test("An unknown effect degrades to the default rather than losing every other field")
    func unknownEffectDegrades() {
        let defaults = freshDefaults()
        defaults.set(
            Data(#"{"visual":"kaleidoscope","direction":"outward"}"#.utf8),
            forKey: VisualFieldStore.defaultsKey
        )

        let store = VisualFieldStore(defaults: defaults)
        #expect(store.settings.visual == VisualFieldSettings.standard.visual)
        #expect(store.settings.direction == .outward)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Expected: compile failure — `cannot find 'VisualFieldStore' in scope`.

- [ ] **Step 3: Note the decode subtlety, then create the store**

`unknownEffectDegrades` will fail unless `VisualFieldSettings.init(from:)` tolerates an unknown enum raw value. `decodeIfPresent` **throws** on a present-but-unmatched raw value rather than returning nil, so the whole blob would be lost. Fix it in `Ilumionate/Visuals/VisualFieldSettings.swift` by decoding the three enum fields defensively:

```swift
        visual = (try? c.decodeIfPresent(TranceVisual.self, forKey: .visual)) ?? d.visual
        tint = (try? c.decodeIfPresent(VisualTint.self, forKey: .tint)) ?? d.tint
        direction = (try? c.decodeIfPresent(VisualDirection.self, forKey: .direction)) ?? d.direction
```

Then create `Ilumionate/Create/VisualFieldStore.swift`:

```swift
//  VisualFieldStore.swift
//  Ilumionate
//
//  The last-used Visual Field settings, so reopening Create restores what you
//  had rather than resetting to the defaults — which is what MindMachineModel
//  did as plain @State, and is why nobody's Create settings ever stuck.

import Foundation
import os

@MainActor
@Observable
final class VisualFieldStore {

    static let defaultsKey = "visualFieldSettings"

    static let shared = VisualFieldStore()

    private let defaults: UserDefaults

    var settings: VisualFieldSettings {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    private static func load(from defaults: UserDefaults) -> VisualFieldSettings {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return .standard
        }
        guard let decoded = try? JSONDecoder().decode(VisualFieldSettings.self, from: data) else {
            // Unreadable settings are not worth surfacing to the user, but they
            // are worth knowing about — the field-level fallbacks in
            // VisualFieldSettings.init(from:) mean reaching here at all implies
            // the payload was not even a JSON object.
            Log.ui.info("Visual field settings unreadable; starting from defaults")
            return .standard
        }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass, then the full suite on both destinations**

- [ ] **Step 5: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(create): persist the last-used visual field settings"
```

---

### Task 10: Add the duration options

**Files:**
- Create: `Ilumionate/Create/SessionDurationOption.swift`
- Test: `IlumionateTests/SessionDurationOptionTests.swift`

The Duration tile taps through a fixed list. Open-ended is first, because it is the default.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/SessionDurationOptionTests.swift`:

```swift
//
//  SessionDurationOptionTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct SessionDurationOptionTests {

    @Test("Open-ended is first, so it is what tapping lands on from the default")
    func openEndedIsFirst() {
        #expect(SessionDurationOption.allCases.first == .openEnded)
        #expect(SessionDurationOption.openEnded.seconds == nil)
    }

    @Test("Timed options are in ascending order")
    func ascendingOrder() {
        let seconds = SessionDurationOption.allCases.compactMap(\.seconds)
        #expect(seconds == seconds.sorted())
    }

    @Test("Every option has a non-empty label")
    func labels() {
        for option in SessionDurationOption.allCases {
            #expect(option.label.isEmpty == false)
        }
    }

    @Test("Advancing cycles through every option and wraps")
    func advanceWraps() {
        var option = SessionDurationOption.allCases[0]
        var seen: [SessionDurationOption] = [option]
        for _ in 1..<SessionDurationOption.allCases.count {
            option = option.next
            seen.append(option)
        }
        #expect(Set(seen).count == SessionDurationOption.allCases.count)
        #expect(option.next == SessionDurationOption.allCases[0])
    }

    @Test("An arbitrary stored duration resolves to the nearest option")
    func resolvesStoredDuration() {
        #expect(SessionDurationOption(seconds: nil) == .openEnded)
        #expect(SessionDurationOption(seconds: 600) == .tenMinutes)
        // A value that is not on the list picks the closest rather than falling
        // back to open-ended, which would silently drop a user's timer.
        #expect(SessionDurationOption(seconds: 605) == .tenMinutes)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Expected: compile failure — `cannot find 'SessionDurationOption' in scope`.

- [ ] **Step 3: Create the type**

Create `Ilumionate/Create/SessionDurationOption.swift`:

```swift
//  SessionDurationOption.swift
//  Ilumionate
//
//  What the Duration tile taps through. Open-ended is first and is the default:
//  a Visual Field session is something you might leave running like a fireplace,
//  so a timer is the opt-in, not the assumption.

import Foundation

enum SessionDurationOption: String, CaseIterable, Identifiable, Sendable {
    case openEnded
    case tenMinutes
    case twentyMinutes
    case thirtyMinutes
    case sixtyMinutes

    var id: String { rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .openEnded:      return nil
        case .tenMinutes:     return 600
        case .twentyMinutes:  return 1_200
        case .thirtyMinutes:  return 1_800
        case .sixtyMinutes:   return 3_600
        }
    }

    var label: String {
        switch self {
        case .openEnded: return "∞"
        case .tenMinutes, .twentyMinutes, .thirtyMinutes, .sixtyMinutes:
            return "\(Int((seconds ?? 0) / 60))m"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .openEnded: return "Open ended"
        case .tenMinutes, .twentyMinutes, .thirtyMinutes, .sixtyMinutes:
            return "\(Int((seconds ?? 0) / 60)) minutes"
        }
    }

    var next: SessionDurationOption {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return all[0] }
        return all[(index + 1) % all.count]
    }

    /// Resolves a stored duration to the nearest option. A value off the list
    /// picks the closest rather than falling back to open-ended, which would
    /// silently drop a user's timer.
    init(seconds: TimeInterval?) {
        guard let seconds else {
            self = .openEnded
            return
        }
        let timed = Self.allCases.filter { $0.seconds != nil }
        self = timed.min {
            abs(($0.seconds ?? 0) - seconds) < abs(($1.seconds ?? 0) - seconds)
        } ?? .openEnded
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass, then the full suite on both destinations**

- [ ] **Step 5: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(create): add session duration options"
```

---

### Task 11: Build the Create tile tray

**Files:**
- Create: `Ilumionate/Create/CreateControlTray.swift`
- Create: `Ilumionate/Create/CreateTintSheet.swift`

No new tests — the arithmetic is in `DragValueMapper` and the slot composition is in `CreateControlSlot`, both already covered. This task is view assembly.

- [ ] **Step 1: Create the tint sheet**

Create `Ilumionate/Create/CreateTintSheet.swift`:

```swift
//  CreateTintSheet.swift
//  Ilumionate
//
//  The Colour tile's swatch grid, with the custom picker behind the last chip.
//
//  A sheet rather than tap-to-cycle-plus-long-press: PlayerControlTile is
//  "either tappable or draggable, never both, which keeps gesture arbitration
//  out of the picture entirely", and a third gesture on one tile would put it
//  straight back in. The sheet also gives the custom picker somewhere to live.

import SwiftUI

struct CreateTintSheet: View {
    @Binding var tint: VisualTint
    @Environment(\.dismiss) private var dismiss

    @State private var customColor: Color = VisualTint.default.color

    private let columns = Array(repeating: GridItem(.flexible()), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TranceSpacing.cardMargin) {
                    LazyVGrid(columns: columns, spacing: TranceSpacing.cardMargin) {
                        ForEach(VisualTint.palette, id: \.self) { swatch in
                            swatchButton(swatch)
                        }
                    }

                    Divider().background(Color.glassBorder)

                    ColorPicker(
                        "Custom colour",
                        selection: $customColor,
                        supportsOpacity: false
                    )
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                    .onChange(of: customColor) { _, newValue in
                        guard let hex = newValue.hexString else { return }
                        tint = .custom(hex)
                        TranceHaptics.shared.selection()
                    }

                    Text("Very dark colours are lifted so the field stays visible.")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(TranceSpacing.screen)
            }
            .navigationTitle("Colour")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func swatchButton(_ swatch: VisualTint) -> some View {
        Button {
            tint = swatch
            TranceHaptics.shared.selection()
        } label: {
            VStack(spacing: TranceSpacing.micro) {
                Circle()
                    .fill(swatch.color)
                    .frame(height: 52)
                    .overlay {
                        Circle().stroke(
                            tint == swatch ? Color.textPrimary : Color.glassBorder,
                            lineWidth: tint == swatch ? 2 : 1
                        )
                    }
                Text(swatch.displayName)
                    .font(TranceTypography.caption)
                    .foregroundStyle(
                        tint == swatch ? Color.textPrimary : Color.textSecondary
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.displayName)
        .accessibilityAddTraits(tint == swatch ? [.isButton, .isSelected] : .isButton)
    }
}
```

- [ ] **Step 2: Add the Color → hex helper the sheet needs**

Append to `Ilumionate/Color+Extensions.swift`:

```swift
extension Color {
    /// `RRGGBB` for persistence. Nil when the colour cannot be resolved to
    /// concrete components — a dynamic or catalog colour, for instance.
    var hexString: String? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #else
        guard let converted = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = converted.redComponent, g = converted.greenComponent, b = converted.blueComponent
        #endif
        let clamp = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}
```

Check the file's existing imports first; add `import UIKit` / `import AppKit` under the matching `#if canImport` only if they are not already there.

- [ ] **Step 3: Create the tray**

Create `Ilumionate/Create/CreateControlTray.swift`:

```swift
//  CreateControlTray.swift
//  Ilumionate
//
//  Create's fixed control tray, in the same grammar as PlayerControlTray: 72pt
//  tiles, drag for continuous values with a haptic tick every 10%, tap for
//  everything else, and a slot list decided once from the session kind so
//  nothing reflows under the user's finger.

import SwiftUI

struct CreateControlTray: View {
    let kind: CreateSessionKind
    @Binding var visual: VisualFieldSettings
    @Bindable var light: MindMachineModel
    @Binding var showingTintSheet: Bool

    @State private var dragStart: [CreateControlSlot: Double] = [:]

    private static let unitMapper = DragValueMapper(range: 0...1)
    private static let frequencyMapper = DragValueMapper(range: 0.5...40.0)
    private static let strengthMapper =
        DragValueMapper(range: VisualModulation.opacityBand)

    private var slots: [CreateControlSlot] { CreateControlSlot.slots(for: kind) }

    private var rows: [[CreateControlSlot]] {
        stride(from: 0, to: slots.count, by: 3).map {
            Array(slots[$0..<min($0 + 3, slots.count)])
        }
    }

    var body: some View {
        VStack(spacing: TranceSpacing.small) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: TranceSpacing.small) {
                    ForEach(rows[row], id: \.self) { slot in
                        tile(for: slot)
                    }
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
    }

    @ViewBuilder
    private func tile(for slot: CreateControlSlot) -> some View {
        PlayerControlTile(
            systemImage: symbol(for: slot),
            label: slot.label,
            state: .normal,
            value: gauge(for: slot),
            accessibilityValueText: valueText(for: slot),
            onTap: slot.isDraggable ? nil : { tap(slot) },
            onDragChanged: slot.isDraggable ? { drag(slot, translation: $0) } : nil,
            onDragEnded: slot.isDraggable ? { dragStart[slot] = nil } : nil
        )
    }

    // MARK: - Presentation

    private func symbol(for slot: CreateControlSlot) -> String {
        switch slot {
        case .direction: return visual.direction.systemImage
        default:         return slot.systemImage
        }
    }

    /// 0…1 fill. Nil for tiles whose value is a name rather than a magnitude.
    private func gauge(for slot: CreateControlSlot) -> Double? {
        switch slot {
        case .visualSpeed: return visual.speed
        case .strength:
            let band = VisualModulation.opacityBand
            return (visual.clampedOpacity - band.lowerBound)
                / (band.upperBound - band.lowerBound)
        case .frequency:   return (light.frequency - 0.5) / 39.5
        case .intensity:   return light.intensity
        case .warmth:
            let options = light.temperatureOptions
            guard let index = options.firstIndex(of: light.colorTemperature),
                  options.count > 1 else { return nil }
            return Double(index) / Double(options.count - 1)
        default:           return nil
        }
    }

    private func valueText(for slot: CreateControlSlot) -> String {
        switch slot {
        case .effect:      return visual.visual.displayName
        case .tint:        return visual.tint.displayName
        case .direction:   return visual.direction.displayName
        case .duration:    return SessionDurationOption(seconds: visual.duration).accessibilityLabel
        case .visualSpeed: return percent(visual.speed)
        case .strength:    return percent(visual.clampedOpacity)
        case .frequency:
            return "\(light.frequency.formatted(.number.precision(.fractionLength(1)))) hertz"
        case .intensity:   return percent(light.intensity)
        case .warmth:      return "\(light.colorTemperature) kelvin"
        case .waveform:    return light.selectedPattern.rawValue
        case .binaural:    return light.binauralEnabled ? "On" : "Off"
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) percent"
    }

    // MARK: - Actions

    private func tap(_ slot: CreateControlSlot) {
        TranceHaptics.shared.selection()
        switch slot {
        case .effect:
            visual.visual = Self.nextEffect(after: visual.visual)
        case .tint:
            showingTintSheet = true
        case .direction:
            visual.direction = visual.direction == .inward ? .outward : .inward
        case .duration:
            visual.duration = SessionDurationOption(seconds: visual.duration).next.seconds
        case .waveform:
            let all = MindMachineModel.LightPattern.allCases
            let index = all.firstIndex(of: light.selectedPattern) ?? 0
            light.selectedPattern = all[(index + 1) % all.count]
        case .binaural:
            light.binauralEnabled.toggle()
        case .visualSpeed, .strength, .frequency, .intensity, .warmth:
            break
        }
    }

    /// `.none` is deliberately skipped: the Visual Field IS the effect here, so
    /// tapping through to "no effect" would tap through to a black screen. The
    /// reader keeps `.none` because there the effect is decoration.
    private static func nextEffect(after current: TranceVisual) -> TranceVisual {
        let selectable = TranceVisual.allCases.filter { $0 != .none && $0 != .breath }
        guard let index = selectable.firstIndex(of: current) else {
            return selectable[0]
        }
        return selectable[(index + 1) % selectable.count]
    }

    private func drag(_ slot: CreateControlSlot, translation: CGFloat) {
        switch slot {
        case .visualSpeed:
            let start = dragStart[slot] ?? visual.speed
            if dragStart[slot] == nil {
                dragStart[slot] = start
                TranceHaptics.shared.selection()
            }
            let new = Self.unitMapper.value(from: start, translation: translation)
            tick(from: visual.speed, to: new, in: 0...1)
            visual.speed = new

        case .strength:
            let start = dragStart[slot] ?? visual.clampedOpacity
            if dragStart[slot] == nil {
                dragStart[slot] = start
                TranceHaptics.shared.selection()
            }
            let new = Self.strengthMapper.value(from: start, translation: translation)
            tick(from: visual.opacity, to: new, in: VisualModulation.opacityBand)
            visual.opacity = new

        case .frequency:
            let start = dragStart[slot] ?? light.frequency
            if dragStart[slot] == nil {
                dragStart[slot] = start
                TranceHaptics.shared.selection()
            }
            let new = Self.frequencyMapper.value(from: start, translation: translation)
            tick(from: light.frequency, to: new, in: 0.5...40.0)
            light.frequency = new

        case .intensity:
            let start = dragStart[slot] ?? light.intensity
            if dragStart[slot] == nil {
                dragStart[slot] = start
                TranceHaptics.shared.selection()
            }
            let new = Self.unitMapper.value(from: start, translation: translation)
            tick(from: light.intensity, to: new, in: 0...1)
            light.intensity = new

        case .warmth:
            let options = light.temperatureOptions
            let startIndex = dragStart[slot]
                ?? Double(options.firstIndex(of: light.colorTemperature) ?? 0)
            if dragStart[slot] == nil {
                dragStart[slot] = startIndex
                TranceHaptics.shared.selection()
            }
            let mapper = DragValueMapper(range: 0...Double(options.count - 1))
            let new = mapper.value(from: startIndex, translation: translation)
            let index = Int(new.rounded())
            if options[index] != light.colorTemperature {
                light.colorTemperature = options[index]
                TranceHaptics.shared.selection()
            }

        case .effect, .tint, .direction, .waveform, .binaural, .duration:
            break
        }
    }

    /// A haptic tick on every 10% crossing, so a value is legible without looking.
    private func tick(from old: Double, to new: Double, in range: ClosedRange<Double>) {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return }
        let oldStep = Int(((old - range.lowerBound) / span) * 10)
        let newStep = Int(((new - range.lowerBound) / span) * 10)
        if oldStep != newStep { TranceHaptics.shared.selection() }
    }
}
```

- [ ] **Step 4: Build both destinations**

Expected: `** BUILD SUCCEEDED **`.

Two things the compiler is likely to object to, both with the same shape of fix:

`onTap: slot.isDraggable ? nil : { tap(slot) }` — a ternary between `nil` and a closure sometimes fails to infer. `onTap` is `(() -> Void)?` (see `Ilumionate/PlayerControlTile.swift:26`), so annotate the branch rather than changing the tile:

```swift
        let onTap: (() -> Void)? = slot.isDraggable ? nil : { tap(slot) }
```

`DragValueMapper(range: VisualModulation.opacityBand)` — `DragValueMapper.range` is `ClosedRange<Double>` and `opacityBand` already is one, so this compiles as written. If it does not, you have declared `opacityBand` as something other than `ClosedRange<Double>` in Task 2.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(create): add the Create control tray and tint sheet"
```

---

### Task 12: Build the live preview

**Files:**
- Create: `Ilumionate/Create/CreateFieldPreview.swift`

- [ ] **Step 1: Create the preview**

Create `Ilumionate/Create/CreateFieldPreview.swift`:

```swift
//  CreateFieldPreview.swift
//  Ilumionate
//
//  What the configured session will actually look like, rendered with the same
//  shader and the same modulation the session will run — not an illustration of
//  it. This replaces PhoneScreenOrb, which drew a picture of a phone.
//
//  Two constraints. It renders at the configured strength, so what you see is
//  what you get. And it obeys the same flicker budget as the session, because a
//  preview is a small light flashing at you for as long as you sit on this
//  screen — VisualFieldSettings.modulation is the only path in, so it cannot
//  exceed the bands.

import SwiftUI

struct CreateFieldPreview: View {
    let kind: CreateSessionKind
    let visual: VisualFieldSettings
    let light: MindMachineModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 200

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TranceRadius.card)
                .fill(Color.bgSecondary.opacity(0.55))

            content
                .clipShape(.rect(cornerRadius: TranceRadius.card))

            RoundedRectangle(cornerRadius: TranceRadius.card)
                .stroke(Color.glassBorder, lineWidth: 1)
        }
        .frame(height: Self.height)
        .overlay(alignment: .bottomLeading) { caption }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview")
        .accessibilityValue(captionText)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .visualField:
            // focus: 0 — there is no word to protect, and the compressed centre
            // is the point of an inward effect.
            VisualFieldLayer(
                visual: visual.visual,
                modulation: visual.modulation(reduceMotion: reduceMotion),
                opacity: visual.clampedOpacity,
                focus: 0
            )
        case .flash, .bilateral, .colourPulse:
            // LumeOrb takes only size and pulse — it derives its own breath
            // period from the frequency and clamps it to a calm range, which is
            // the behaviour we want in a preview. Intensity and warmth are
            // carried by the surrounding tint rather than by the orb.
            LumeOrb(size: .medium, pulse: light.frequency)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RadialGradient(
                        colors: [
                            Color.fromKelvin(light.colorTemperature)
                                .opacity(0.35 * light.intensity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: Self.height * 0.7
                    )
                }
        }
    }

    private var caption: some View {
        Text(captionText)
            .font(TranceTypography.caption)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, TranceSpacing.inner)
            .padding(.vertical, TranceSpacing.micro)
            .background(.ultraThinMaterial, in: .capsule)
            .padding(TranceSpacing.inner)
    }

    private var captionText: String {
        switch kind {
        case .visualField:
            let strength = visual.clampedOpacity
                .formatted(.percent.precision(.fractionLength(0)))
            return "\(visual.visual.displayName) · \(visual.direction.displayName) · \(strength)"
        case .flash, .bilateral, .colourPulse:
            let hertz = light.frequency.formatted(.number.precision(.fractionLength(1)))
            return "\(light.brainwaveZone) · \(hertz) Hz"
        }
    }
}
```

- [ ] **Step 2: Build both destinations**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(create): add the live session preview"
```

---

### Task 13: Assemble CreateView and retire the old screen

**Files:**
- Create: `Ilumionate/Create/CreateView.swift`
- Modify: `Ilumionate/MindMachineView.swift` (reduced to `MindMachineModel` only, then renamed)
- Modify: `Ilumionate/MindMachineStartBar.swift`
- Modify: `Ilumionate/ContentView.swift:185-189`
- Modify: `Ilumionate/LibraryView.swift` (receives `BrowseSessionsLink`)

- [ ] **Step 1: Extract the model, delete the old view**

`MindMachineView.swift` is 698 lines. Split it:

```bash
git mv Ilumionate/MindMachineView.swift Ilumionate/Create/MindMachineModel.swift
```

From `Ilumionate/Create/MindMachineModel.swift`, keep **only** `MindMachineModel` (lines 10–145 of the original) and update the header. Delete outright:

- `MindMachineView` — replaced by `CreateView`
- `LightVisualizationCard`, `FrequencyCard`, `ColorTemperatureCard`, `IntensityCard`, `PatternSelectionSection`, `VisualModeCard`, `AdvancedControlsSection` — every control they held now has a tile
- `PhoneScreenOrb` — replaced by `CreateFieldPreview`
- `CustomSlider` — nothing in the tray uses it
- `BrowseSessionsLink` — moves to Library in Step 5
- the `#Preview` block

Keep `VisualModeButton`, `PatternCard` and `CustomSlider` **only if** something outside this file still references them:

```bash
grep -rn "VisualModeButton\|PatternCard\|CustomSlider\|PhoneScreenOrb\|IntensityDial" Ilumionate --include="*.swift" | grep -v "Create/MindMachineModel.swift"
```

Delete any that show no other references; move any that do into their own file under `Ilumionate/Create/`.

Also delete `MindMachineModel.VisualMode` and its `selectedVisualMode` property — `CreateSessionKind` replaces it — along with `startSessionButtonTitle` and `startSessionIcon`, which switched on it. Step 3 puts the replacements on `CreateSessionKind`.

- [ ] **Step 2: Verify what you deleted is really unreferenced**

```bash
grep -rn "MindMachineView\|selectedVisualMode\|MindMachineModel.VisualMode" Ilumionate --include="*.swift"
```

Every hit must be one you are about to fix in Steps 3–5. Expect hits in `ContentView.swift`, `MindMachineStartBar.swift` and `PlayerMode.swift`.

- [ ] **Step 3: Move the start-bar copy onto the kind**

Add to `Ilumionate/Create/CreateSessionKind.swift`:

```swift
extension CreateSessionKind {
    func startTitle(binauralEnabled: Bool) -> String {
        switch self {
        case .visualField: return "Begin Visuals"
        case .colourPulse: return "Start Colour Pulse"
        case .bilateral:
            return binauralEnabled ? "Start Bilateral + Binaural" : "Start Bilateral Flash"
        case .flash:
            return binauralEnabled ? "Start Flash + Binaural" : "Start Flash Session"
        }
    }

    func startIcon(binauralEnabled: Bool) -> String {
        switch self {
        case .visualField: return "play.fill"
        case .colourPulse: return "paintpalette.fill"
        case .flash, .bilateral:
            return binauralEnabled ? "headphones" : "play.fill"
        }
    }
}
```

- [ ] **Step 4: Rewrite the start bar**

Replace the body of `Ilumionate/MindMachineStartBar.swift` (move it to `Ilumionate/Create/CreateStartBar.swift` with `git mv` and rename the struct to `CreateStartBar`) so it reads from the kind:

```swift
//  CreateStartBar.swift
//  Ilumionate
//

import SwiftUI

struct CreateStartBar: View {
    let kind: CreateSessionKind
    let visual: VisualFieldSettings
    @Bindable var light: MindMachineModel
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: TranceSpacing.inner) {
            HStack {
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text("Ready to begin")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(summary)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                }

                Spacer()

                Text(trailingValue)
                    .font(TranceTypography.dataReadout)
                    .foregroundStyle(trailingColor)
            }

            GlowButton(
                title: kind.startTitle(binauralEnabled: light.binauralEnabled),
                systemImage: kind.startIcon(binauralEnabled: light.binauralEnabled),
                kind: .primary,
                action: onStart
            )
            .accessibilityHint("Opens the full-screen player")
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.list)
        .padding(.bottom, TranceSpacing.tabBarClearance)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.bgPrimary.opacity(0.94), location: 0.24),
                    .init(color: Color.bgPrimary, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -TranceSpacing.content)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var summary: String {
        switch kind {
        case .visualField:
            return "\(visual.visual.displayName) · \(visual.direction.displayName)"
        case .flash, .bilateral, .colourPulse:
            let hertz = light.frequency.formatted(.number.precision(.fractionLength(1)))
            return "\(light.brainwaveZone) · \(hertz) Hz"
        }
    }

    private var trailingValue: String {
        switch kind {
        case .visualField:
            return visual.clampedOpacity.formatted(.percent.precision(.fractionLength(0)))
        case .flash, .bilateral, .colourPulse:
            return light.intensity.formatted(.percent.precision(.fractionLength(0)))
        }
    }

    private var trailingColor: Color {
        kind == .visualField ? visual.tint.color : light.brainwaveColor
    }
}
```

- [ ] **Step 5: Move BrowseSessionsLink to Library**

Create `Ilumionate/BrowseSessionsLink.swift` with the struct exactly as it was in `MindMachineView.swift:457-484`, then add it to `LibraryView`'s content alongside its other sections. `LibraryView` must own the `navigationDestination(for: String.self)` that resolves `"browseSessions"` to `BrowseSessionsView(sessions:engine:)` — copy it from `MindMachineView.swift:182-189`. Confirm `LibraryView` has the `sessions` and `engine` it needs; if it does not, thread them from `ContentView` the way it already threads `engine`.

- [ ] **Step 6: Create the screen**

Create `Ilumionate/Create/CreateView.swift`:

```swift
//  CreateView.swift
//  Ilumionate
//
//  The Create tab: pick what you are making, see it, tune it, start it.
//
//  Mode first and nothing buried. The previous screen hid the kind picker,
//  intensity, warmth, waveform and binaural inside one collapsed disclosure —
//  burial was the actual problem, so every control here has a tile.

import SwiftUI

struct CreateView: View {
    let engine: LightEngine
    let sessions: [LightSession]

    @State private var kind: CreateSessionKind = .visualField
    @State private var light = MindMachineModel()
    @State private var store = VisualFieldStore.shared
    @State private var showingTintSheet = false
    @State private var showingPlayer = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visualBinding: Binding<VisualFieldSettings> {
        Binding(get: { store.settings }, set: { store.settings = $0 })
    }

    var body: some View {
        ZStack {
            AuroraBackground(mood: light.moodCategory)

            ScrollView {
                VStack(spacing: TranceSpacing.cardMargin) {
                    kindPicker

                    CreateFieldPreview(
                        kind: kind,
                        visual: store.settings,
                        light: light
                    )
                    .padding(.horizontal, TranceSpacing.screen)

                    if reduceMotion && kind == .visualField {
                        reduceMotionNotice
                    }

                    CreateControlTray(
                        kind: kind,
                        visual: visualBinding,
                        light: light,
                        showingTintSheet: $showingTintSheet
                    )
                }
                .padding(.top, TranceSpacing.statusBar)
                .padding(.bottom, TranceSpacing.tabBarClearance)
            }
            .safeAreaInset(edge: .bottom) {
                CreateStartBar(
                    kind: kind,
                    visual: store.settings,
                    light: light,
                    onStart: start
                )
            }
        }
        .navigationTitle("Create")
        .platformLargeNavigationTitle()
        .sheet(isPresented: $showingTintSheet) {
            CreateTintSheet(tint: visualBinding.tint)
        }
        .platformFullScreenCover(isPresented: $showingPlayer) {
            UnifiedPlayerView(
                mode: playerMode,
                engine: engine,
                mindMachineEntryPoint: .create,
                mindMachineMode: kind.mindMachineMode
            )
        }
        .onChange(of: kind) { _, newKind in
            UsageAnalytics.shared.createModeSelected(newKind.analyticsMode)
            TranceHaptics.shared.selection()
        }
    }

    // MARK: - Kind picker

    private var kindPicker: some View {
        Picker("Session kind", selection: $kind) {
            ForEach(CreateSessionKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, TranceSpacing.screen)
    }

    /// Reduce Motion freezes the field. In the reader the visual is decoration,
    /// so a still frame needs no explanation; here it IS the content, and a
    /// Speed tile that does nothing needs one.
    private var reduceMotionNotice: some View {
        Text("Motion is reduced by a system setting, so the field will hold still.")
            .font(TranceTypography.caption)
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, TranceSpacing.screen)
    }

    // MARK: - Starting

    private var playerMode: PlayerMode {
        switch kind {
        case .visualField:
            return .visualField(
                settings: store.settings,
                audioFile: nil,
                binaural: light.binauralEnabled ? light.binauralSettings : nil
            )
        case .colourPulse:
            return .colorPulse(frequency: light.frequency, intensity: light.intensity)
        case .flash, .bilateral:
            return .flashMode(
                frequency: light.frequency,
                intensity: light.intensity,
                colorTemperature: light.colorTemperature,
                pattern: light.selectedPattern,
                binauralEnabled: light.binauralEnabled,
                binauralCarrier: light.binauralCarrierFrequency,
                binauralVolume: light.binauralVolume,
                goalDuration: store.settings.duration
            )
        }
    }

    private func start() {
        TranceHaptics.shared.heavy()
        UsageAnalytics.shared.mindMachineStartRequested(
            mode: kind.mindMachineMode,
            entryPoint: .create
        )
        showingPlayer = true
    }
}
```

Add the binaural bridge to `Ilumionate/Create/MindMachineModel.swift`:

```swift
extension MindMachineModel {
    var binauralSettings: BinauralSettings {
        BinauralSettings(
            enabled: binauralEnabled,
            carrier: binauralCarrierFrequency,
            volume: binauralVolume
        )
    }
}
```

`BinauralSettings` and `PlayerMode.visualField` do not exist yet — Task 14 adds both. `CreateView` will not compile until then; that is expected and is why the two tasks share a checkpoint.

- [ ] **Step 7: Point ContentView at the new screen**

In `Ilumionate/ContentView.swift:185-189`:

```swift
            } else if selectedTab == .create {
                NavigationStack {
                    CreateView(engine: engine, sessions: sessions)
                }
                .transition(.opacity)
            }
```

- [ ] **Step 8: Commit (build is expected to fail until Task 14)**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(create): rebuild the Create tab around session kinds and a tile tray"
```

---

# Phase 3 — The session runtime

---

### Task 14: Add PlayerMode.visualField

**Files:**
- Create: `Ilumionate/BinauralSettings.swift`
- Modify: `Ilumionate/PlayerMode.swift`
- Modify: `Ilumionate/PlayerControlSlot.swift:23-44`
- Test: `IlumionateTests/VisualFieldPlayerModeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/VisualFieldPlayerModeTests.swift`:

```swift
//
//  VisualFieldPlayerModeTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct VisualFieldPlayerModeTests {

    private func mode(
        audioFile: AudioFile? = nil,
        binaural: BinauralSettings? = nil,
        duration: TimeInterval? = nil
    ) -> PlayerMode {
        var settings = VisualFieldSettings.standard
        settings.duration = duration
        return .visualField(settings: settings, audioFile: audioFile, binaural: binaural)
    }

    @Test("A silent visual field offers no audio controls")
    func silentFieldHasNoAudioControls() {
        let mode = mode()
        #expect(mode.hasAudioScrubber == false)
        #expect(mode.hasVolumeControl == false)
    }

    @Test("Strength is the visual's own knob, so screen brightness is not offered")
    func noBrightnessControl() {
        #expect(mode().hasBrightnessControl == false)
    }

    @Test("The visual field never warns about flashing, because it never flashes")
    func noSafetyWarning() {
        #expect(mode().requiresSafetyWarning == false)
    }

    @Test("The field is dark chrome")
    func usesDarkChrome() {
        #expect(mode().usesDarkChrome)
    }

    @Test("Duration decides whether the session is finite")
    func finiteOnlyWhenTimed() {
        #expect(mode(duration: nil).hasFiniteDuration == false)
        #expect(mode(duration: 600).hasFiniteDuration)
        #expect(mode(duration: 600).goalDuration == 600)
        #expect(mode(duration: nil).goalDuration == nil)
    }

    @Test("The title names the session")
    func title() {
        #expect(mode().title == "Visual Field")
    }

    @Test("A silent field shows only its two visual tiles")
    func silentTray() {
        #expect(PlayerControlSlot.slots(for: mode()) == [.visualStrength, .visualSpeed])
    }

    @Test("Binaural adds the overflow tile")
    func binauralAddsMore() {
        let binaural = BinauralSettings(enabled: true, carrier: 200, volume: 0.5)
        #expect(PlayerControlSlot.slots(for: mode(binaural: binaural))
                == [.visualStrength, .visualSpeed, .more])
    }

    @Test("The visual tiles are dragged, not tapped")
    func visualTilesAreDraggable() {
        #expect(PlayerControlSlot.visualStrength.isDraggable)
        #expect(PlayerControlSlot.visualSpeed.isDraggable)
    }

    @Test("The tray for a given mode is the same list every time")
    func trayIsStable() {
        let mode = mode()
        #expect(PlayerControlSlot.slots(for: mode) == PlayerControlSlot.slots(for: mode))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Expected: compile failure — `cannot find 'BinauralSettings' in scope`.

- [ ] **Step 3: Create BinauralSettings**

Create `Ilumionate/BinauralSettings.swift`:

```swift
//  BinauralSettings.swift
//  Ilumionate
//
//  Binaural configuration for a mode that carries it.
//
//  `flashMode` still carries these three as loose parameters. Folding it in is a
//  tidy follow-on, but it touches every flashMode call site and none of that
//  work serves the Visual Field — so this starts as a type only the new mode uses.

import Foundation

struct BinauralSettings: Equatable, Codable, Sendable {
    var enabled: Bool
    var carrier: Double
    var volume: Double

    static let standard = BinauralSettings(enabled: false, carrier: 200, volume: 0.5)
}
```

- [ ] **Step 4: Add the case and update every exhaustive switch**

In `Ilumionate/PlayerMode.swift`, add the case:

```swift
    case visualField(
        settings: VisualFieldSettings,
        audioFile: AudioFile?,
        binaural: BinauralSettings?
    )
```

The compiler will now flag every non-`default` switch in this file. Update each:

```swift
    var id: String {
        // ...
        case .visualField:
            return "visualField-\(UUID())"
    }

    var title: String {
        // ...
        case .visualField:
            return "Visual Field"
    }

    var hasAudioScrubber: Bool {
        switch self {
        case .session, .audioLight, .playlist: return true
        case .visualField(_, let audioFile, _): return audioFile != nil
        case .flashMode, .colorPulse: return false
        }
    }

    var hasVolumeControl: Bool {
        switch self {
        case .audioLight, .playlist: return true
        case .session(_, let audioFile): return audioFile != nil
        case .visualField(_, let audioFile, _): return audioFile != nil
        case .flashMode, .colorPulse: return false
        }
    }

    var hasBrightnessControl: Bool {
        switch self {
        case .session, .playlist: return true
        case .audioLight: return true // shown when light sync enabled
        // Strength is the field's own knob, and the field does not drive the
        // light engine that screen brightness would scale.
        case .visualField: return false
        case .flashMode, .colorPulse: return false
        }
    }

    var hasSkipControls: Bool {
        switch self {
        case .audioLight: return true
        case .playlist: return true
        case .session, .flashMode, .colorPulse, .visualField: return false
        }
    }

    var usesDarkChrome: Bool {
        switch self {
        case .flashMode, .colorPulse, .playlist, .visualField: return true
        case .audioLight: return false
        case .session: return false
        }
    }

    var hasFiniteDuration: Bool {
        switch self {
        case .session, .audioLight, .playlist:
            return true
        case .flashMode(_, _, _, _, _, _, _, let goalDuration):
            return goalDuration != nil
        case .visualField(let settings, _, _):
            return settings.duration != nil
        case .colorPulse:
            return false
        }
    }
```

And extend `goalDuration`, which currently `guard case`s on `flashMode` only:

```swift
    /// Optional finish line. Open-ended sessions supply no goal.
    var goalDuration: TimeInterval? {
        switch self {
        case .flashMode(_, _, _, _, _, _, _, let goalDuration):
            return goalDuration
        case .visualField(let settings, _, _):
            return settings.duration
        default:
            return nil
        }
    }
```

`requiresSafetyWarning`, `hasBinauralToggle`, `hasBilateralToggle` and the rest already end in `default:` and need no edit — confirm each `default` gives `.visualField` the right answer. In particular `requiresSafetyWarning` must stay `false` for it, which the existing `default: return false` provides.

- [ ] **Step 5: Add the tray slots**

In `Ilumionate/PlayerControlSlot.swift`, add two cases and wire them:

```swift
enum PlayerControlSlot: Equatable, CaseIterable {
    case mindMachine
    case lightSync
    case volume
    case brightness
    case visualStrength
    case visualSpeed
    case more
```

```swift
        case .visualField(_, let audioFile, let binaural):
            var slots: [PlayerControlSlot] = [.visualStrength, .visualSpeed]
            if audioFile != nil { slots.append(.volume) }
            if binaural?.enabled == true { slots.append(.more) }
            return slots
```

```swift
    var isDraggable: Bool {
        self == .volume || self == .brightness
            || self == .visualStrength || self == .visualSpeed
    }
```

```swift
        case .visualStrength: return "Strength"
        case .visualSpeed:    return "Speed"
```

```swift
        case .visualStrength: return "circle.lefthalf.filled"
        case .visualSpeed:    return "speedometer"
```

and in `state(lightsAreOn:)`:

```swift
        case .volume, .more, .visualStrength, .visualSpeed:
            return .normal
```

- [ ] **Step 6: Run the tests to verify they pass**

Expected: `** TEST SUCCEEDED **` for `VisualFieldPlayerModeTests`, and the pre-existing `PlayerControlSlot` coverage still green.

- [ ] **Step 7: Build both destinations**

The compiler will now flag every remaining non-exhaustive switch outside `PlayerMode.swift`. Expect roughly twenty in `UnifiedPlayerViewModel.swift` and a handful in `UnifiedPlayerView.swift`, `PlayerTitleBlock.swift` and `PlayerSafetyWarningView.swift`. Task 15 handles them. If a switch already ends in `default:`, leave it alone and verify its answer is right for the new case.

- [ ] **Step 8: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(player): add PlayerMode.visualField and its tray slots"
```

---

### Task 15: Wire the visual field into the player

**Files:**
- Modify: `Ilumionate/UnifiedPlayerViewModel.swift`
- Modify: `Ilumionate/UnifiedPlayerView.swift:205-232`
- Modify: `Ilumionate/PlayerControlTray.swift`
- Create: `Ilumionate/VisualFieldStage.swift`

- [ ] **Step 1: Create the full-screen stage**

Create `Ilumionate/VisualFieldStage.swift`:

```swift
//  VisualFieldStage.swift
//  Ilumionate
//
//  The wordless field, full screen. focus: 0 — there is no word to protect, and
//  the compressed centre is the whole point of an inward effect.

import SwiftUI

struct VisualFieldStage: View {
    let settings: VisualFieldSettings
    /// Scales the configured strength. The timed ending rides this down to zero
    /// so a session recedes rather than cutting to black.
    var fade: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VisualFieldLayer(
                visual: settings.visual,
                modulation: settings.modulation(reduceMotion: reduceMotion),
                opacity: settings.clampedOpacity * min(max(fade, 0), 1),
                focus: 0
            )
        }
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: Give the view model its live settings**

In `Ilumionate/UnifiedPlayerViewModel.swift`, add a stored property near the other mode-derived state, and seed it in the initialiser where the other modes seed theirs (see the `if case .flashMode` block at line ~226):

```swift
    /// Live copy of the field's settings, so strength and speed can be tuned
    /// mid-session without ending it — the same affordance the reader's tray has.
    var visualFieldSettings: VisualFieldSettings = .standard
```

```swift
        if case .visualField(let settings, _, _) = mode {
            visualFieldSettings = settings
        }
```

- [ ] **Step 3: Work through the compiler errors**

Build, and for each non-exhaustive switch the compiler flags, group `.visualField` with the mode whose behaviour it shares. The rule for each:

- **Audio transport, scrubbing, track lists** — group with `.flashMode` (no audio timeline of its own).
- **Light engine start/stop, brightness, bilateral, drift, frequency display** — group with `.colorPulse`, and make the branch a no-op. The field must never call `FlashController` or `LightEngine`.
- **Chrome, backgrounds, "is this a light session"** — group with `.flashMode`.
- **Analytics mode mapping** (line ~1062, `case .colorPulse: .colorPulse`) — add `case .visualField: .visualField`.

Where a switch's existing `default:` already gives the right answer, leave it.

- [ ] **Step 4: Render the stage**

In `Ilumionate/UnifiedPlayerView.swift`, in the same switch that handles `.flashMode` and `.colorPulse` for the background (line ~205), add:

```swift
        case .visualField:
            VisualFieldStage(
                settings: viewModel.visualFieldSettings,
                fade: viewModel.visualFieldFade
            )
```

`visualFieldFade` arrives in Task 16; use `1` here and replace it there, or do the two tasks together.

- [ ] **Step 5: Drive the two new tiles**

In `Ilumionate/PlayerControlTray.swift`, add the mappers and the cases:

```swift
    private static let visualSpeedMapper = DragValueMapper(range: 0...1)
    private static let visualStrengthMapper =
        DragValueMapper(range: VisualModulation.opacityBand)
```

```swift
    @State private var visualSpeedDragStart: Double?
    @State private var visualStrengthDragStart: Double?
```

in `value(for:)`:

```swift
        case .visualSpeed:    return viewModel.visualFieldSettings.speed
        case .visualStrength:
            let band = VisualModulation.opacityBand
            return (viewModel.visualFieldSettings.clampedOpacity - band.lowerBound)
                / (band.upperBound - band.lowerBound)
```

in `drag(_:translation:)`:

```swift
        case .visualSpeed:
            let start = visualSpeedDragStart ?? viewModel.visualFieldSettings.speed
            if visualSpeedDragStart == nil {
                visualSpeedDragStart = start
                TranceHaptics.shared.selection()
            }
            let old = viewModel.visualFieldSettings.speed
            let new = Self.visualSpeedMapper.value(from: start, translation: translation)
            viewModel.visualFieldSettings.speed = new
            tick(from: old, to: new, in: 0...1)

        case .visualStrength:
            let band = VisualModulation.opacityBand
            let start = visualStrengthDragStart ?? viewModel.visualFieldSettings.clampedOpacity
            if visualStrengthDragStart == nil {
                visualStrengthDragStart = start
                TranceHaptics.shared.selection()
            }
            let old = viewModel.visualFieldSettings.opacity
            let new = Self.visualStrengthMapper.value(from: start, translation: translation)
            viewModel.visualFieldSettings.opacity = new
            tick(from: old, to: new, in: band)
```

and in `endDrag(_:)`:

```swift
        case .visualSpeed:    visualSpeedDragStart = nil
        case .visualStrength: visualStrengthDragStart = nil
```

- [ ] **Step 6: Build and test both destinations**

Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **` on both.

- [ ] **Step 7: Run the app and start a visual field session**

From Create, with Visuals selected, tap Begin Visuals. Verify: the field fills the screen with an unbroken centre, the tray shows exactly Strength and Speed, dragging either changes the field live with a haptic tick every 10%, and no photosensitivity warning appears.

- [ ] **Step 8: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(player): run the wordless visual field full screen"
```

---

### Task 16: Add the timed ending

**Files:**
- Create: `Ilumionate/Visuals/VisualFieldFade.swift`
- Modify: `Ilumionate/UnifiedPlayerViewModel.swift`
- Test: `IlumionateTests/VisualFieldFadeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/VisualFieldFadeTests.swift`:

```swift
//
//  VisualFieldFadeTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct VisualFieldFadeTests {

    @Test("An open-ended session never fades")
    func openEndedNeverFades() {
        for elapsed in [0.0, 60.0, 3_600.0, 86_400.0] {
            #expect(VisualFieldFade.multiplier(elapsed: elapsed, duration: nil) == 1)
        }
    }

    @Test("A timed session holds full strength until the fade window opens")
    func fullStrengthBeforeTheWindow() {
        #expect(VisualFieldFade.multiplier(elapsed: 0, duration: 600) == 1)
        #expect(VisualFieldFade.multiplier(elapsed: 300, duration: 600) == 1)
        // The window is the last 20 seconds, so 580 is exactly its start.
        #expect(VisualFieldFade.multiplier(elapsed: 579, duration: 600) == 1)
    }

    @Test("The fade runs to zero across the window")
    func fadesAcrossTheWindow() {
        let half = VisualFieldFade.multiplier(elapsed: 590, duration: 600)
        #expect(half > 0.4)
        #expect(half < 0.6)
        #expect(VisualFieldFade.multiplier(elapsed: 600, duration: 600) == 0)
    }

    @Test("Past the end it stays at zero rather than going negative")
    func clampsPastTheEnd() {
        #expect(VisualFieldFade.multiplier(elapsed: 900, duration: 600) == 0)
    }

    @Test("The fade decreases monotonically")
    func monotonic() {
        var previous = 1.0
        for elapsed in stride(from: 0.0, through: 600.0, by: 5.0) {
            let value = VisualFieldFade.multiplier(elapsed: elapsed, duration: 600)
            #expect(value <= previous + 0.0001)
            previous = value
        }
    }

    @Test("A duration shorter than the window still fades from the start")
    func shortSessionFadesFromTheStart() {
        #expect(VisualFieldFade.multiplier(elapsed: 0, duration: 10) == 1)
        #expect(VisualFieldFade.multiplier(elapsed: 10, duration: 10) == 0)
        let middle = VisualFieldFade.multiplier(elapsed: 5, duration: 10)
        #expect(middle > 0)
        #expect(middle < 1)
    }

    @Test("Nonsense input does not produce a NaN opacity")
    func hostileInput() {
        for value in [Double.nan, .infinity, -1] {
            #expect(VisualFieldFade.multiplier(elapsed: value, duration: 600).isFinite)
            #expect(VisualFieldFade.multiplier(elapsed: 100, duration: value).isFinite)
        }
    }

    @Test("The session is over exactly when its duration elapses")
    func completion() {
        #expect(VisualFieldFade.isComplete(elapsed: 599, duration: 600) == false)
        #expect(VisualFieldFade.isComplete(elapsed: 600, duration: 600))
        #expect(VisualFieldFade.isComplete(elapsed: 10_000, duration: nil) == false)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Expected: compile failure — `cannot find 'VisualFieldFade' in scope`.

- [ ] **Step 3: Create the type**

Create `Ilumionate/Visuals/VisualFieldFade.swift`:

```swift
//  VisualFieldFade.swift
//  Ilumionate
//
//  How a timed Visual Field session ends: by receding, not by cutting to black.
//
//  Pure arithmetic, kept out of the view for the same reason as
//  ReaderVisualStrength and DragValueMapper — the behaviour at the edges is
//  testable rather than something only a stopwatch and a device can tell you.

import Foundation

enum VisualFieldFade {

    /// How long the field takes to recede at the end of a timed session.
    static let window: TimeInterval = 20

    /// Strength multiplier, 1…0. Always 1 for an open-ended session.
    static func multiplier(elapsed: TimeInterval, duration: TimeInterval?) -> Double {
        guard let duration, duration > 0, duration.isFinite else { return 1 }
        guard elapsed.isFinite else { return 1 }

        let remaining = duration - max(elapsed, 0)
        guard remaining > 0 else { return 0 }

        // A session shorter than the window fades across its whole length rather
        // than starting below full strength.
        let window = min(Self.window, duration)
        guard remaining < window else { return 1 }
        return min(max(remaining / window, 0), 1)
    }

    static func isComplete(elapsed: TimeInterval, duration: TimeInterval?) -> Bool {
        guard let duration, duration > 0, duration.isFinite, elapsed.isFinite else {
            return false
        }
        return elapsed >= duration
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

If `shortSessionFadesFromTheStart` fails at `elapsed: 0`, the `remaining < window` comparison has become `<=`; at elapsed 0 the remaining time equals the window and must still read as full strength.

- [ ] **Step 5: Drive it from the view model**

In `Ilumionate/UnifiedPlayerViewModel.swift`, add the published fade and compute it wherever elapsed time already ticks (find the existing timer that updates `elapsed`/`currentTime` for `.flashMode` goal durations and extend it):

```swift
    /// Rides the field's strength down over the last seconds of a timed session.
    var visualFieldFade: Double = 1
```

```swift
        if case .visualField(let settings, _, _) = mode {
            visualFieldFade = VisualFieldFade.multiplier(
                elapsed: elapsed, duration: settings.duration
            )
            if VisualFieldFade.isComplete(elapsed: elapsed, duration: settings.duration) {
                finishSession()
            }
        }
```

Use whatever the file already calls its end-of-session path in place of `finishSession()` — find it by looking at how `.flashMode`'s `goalDuration` currently completes.

- [ ] **Step 6: Replace the placeholder in the view**

In `Ilumionate/UnifiedPlayerView.swift`, change `fade: 1` to `fade: viewModel.visualFieldFade` if you left a placeholder in Task 15.

- [ ] **Step 7: Build and test both destinations, then verify by hand**

Start a Visual Field session with a 10-minute duration. Confirm it is at full strength throughout, recedes smoothly over the last 20 seconds, and dismisses itself.

- [ ] **Step 8: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(player): fade a timed visual field out rather than cutting to black"
```

---

### Task 17: Let audio ride along

**Files:**
- Modify: `Ilumionate/Create/CreateView.swift`
- Modify: `Ilumionate/UnifiedPlayerViewModel.swift`
- Test: `IlumionateTests/VisualFieldAudioTests.swift`

Binaural and a library track are independently optional, and neither failing may take the field down — the field is the content.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/VisualFieldAudioTests.swift`:

```swift
//
//  VisualFieldAudioTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct VisualFieldAudioTests {

    @Test("Silence is a valid configuration, not an unconfigured one")
    func silenceIsValid() {
        let mode = PlayerMode.visualField(
            settings: .standard, audioFile: nil, binaural: nil
        )
        #expect(mode.hasVolumeControl == false)
        #expect(PlayerControlSlot.slots(for: mode) == [.visualStrength, .visualSpeed])
    }

    @Test("Binaural and a track are independent")
    func audioSourcesAreIndependent() {
        let binaural = BinauralSettings(enabled: true, carrier: 200, volume: 0.5)
        let withBinaural = PlayerMode.visualField(
            settings: .standard, audioFile: nil, binaural: binaural
        )
        #expect(withBinaural.hasVolumeControl == false)
        #expect(PlayerControlSlot.slots(for: withBinaural).contains(.more))
        #expect(PlayerControlSlot.slots(for: withBinaural).contains(.volume) == false)
    }

    @Test("Disabled binaural settings do not add the overflow tile")
    func disabledBinauralAddsNothing() {
        let off = BinauralSettings(enabled: false, carrier: 200, volume: 0.5)
        let mode = PlayerMode.visualField(
            settings: .standard, audioFile: nil, binaural: off
        )
        #expect(PlayerControlSlot.slots(for: mode) == [.visualStrength, .visualSpeed])
    }

    @Test("Audio failure never disables the field itself")
    func audioFailureLeavesTheFieldRunning() {
        // The field is the content; audio is decoration. This is the invariant
        // the view model must preserve when playback throws.
        #expect(VisualFieldAudioFailure.leavesFieldRunning)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Expected: compile failure — `cannot find 'VisualFieldAudioFailure' in scope`.

- [ ] **Step 3: State the invariant in code**

Add to `Ilumionate/VisualFieldStage.swift`:

```swift
/// The rule audio handling in a Visual Field session must obey.
///
/// A named constant rather than a comment because it is the one thing that
/// separates this mode from every other one in the player: elsewhere audio
/// failing means the session has failed, and here it does not.
enum VisualFieldAudioFailure {
    static let leavesFieldRunning = true
}
```

- [ ] **Step 4: Handle failure in the view model**

Find where `.audioLight` starts playback in `UnifiedPlayerViewModel.swift` and add the `.visualField` path beside it. The catch branch must not end the session:

```swift
        case .visualField(_, let audioFile, let binaural):
            if let binaural, binaural.enabled {
                binauralEngine.carrierFrequency = binaural.carrier
                binauralEngine.volume = binaural.volume
                binauralEngine.start()
            }
            if let audioFile {
                do {
                    try await audioManager.play(audioFile)
                } catch {
                    // The field is the content. Audio failing is a degraded
                    // session, not a failed one.
                    Log.ui.info("Visual field audio unavailable: \(error)")
                    audioUnavailable = true
                }
            }
```

Add the flag beside the other view-model state:

```swift
    /// Set when a Visual Field session's track could not play. Disables the
    /// volume tile and shows a non-blocking notice; the field keeps running.
    var audioUnavailable = false
```

Adapt `audioManager.play(_:)` to whatever the real playback entry point is — check how `.audioLight` does it and mirror that call exactly.

- [ ] **Step 5: Disable the volume tile when audio is gone**

In `Ilumionate/PlayerControlSlot.swift`, `state(lightsAreOn:)` cannot see the failure — it takes no view-model state, and that restriction is deliberate. Handle it at the tray instead, in `PlayerControlTray.tile(for:)`:

```swift
        let state: PlayerControlTile.State =
            (slot == .volume && viewModel.audioUnavailable)
                ? .disabled
                : slot.state(lightsAreOn: lightsAreOn)
```

The tile's presence is still decided only by the mode, so the tray does not reflow — only its state changes.

- [ ] **Step 6: Offer a track in Create**

In `Ilumionate/Create/CreateView.swift`, add the picker state and the sheet:

```swift
    @State private var accompanyingTrack: AudioFile?
    @State private var showingTrackPicker = false
```

Add a row under the tray, shown only for `.visualField`:

```swift
    @ViewBuilder
    private var trackRow: some View {
        if kind == .visualField {
            Button {
                showingTrackPicker = true
            } label: {
                HStack {
                    Image(systemName: accompanyingTrack == nil ? "speaker.slash" : "music.note")
                        .foregroundStyle(Color.roseGold)
                    Text(accompanyingTrack?.displayName ?? "No audio")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(TranceSpacing.inner)
                .liminalGlass(.roundedRect(cornerRadius: TranceRadius.card))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, TranceSpacing.screen)
        }
    }
```

and pass it into the mode:

```swift
        case .visualField:
            return .visualField(
                settings: store.settings,
                audioFile: accompanyingTrack,
                binaural: light.binauralEnabled ? light.binauralSettings : nil
            )
```

For the picker sheet, reuse whatever the app already uses to choose a library file — check `AudioLibraryView` for a selection-mode initialiser and use it; if there is none, present `AudioLibraryView(engine: engine)` and add an `onSelect` closure to it rather than building a second library screen.

- [ ] **Step 7: Run the tests and build both destinations, then verify by hand**

Start a Visual Field session with binaural on and no track; then with a track. Then start one pointing at a file you have deleted from disk — the field must keep running, the volume tile must be disabled, and the session must not end.

- [ ] **Step 8: Commit**

```bash
git add Ilumionate IlumionateTests
git commit -m "feat(player): let binaural and a library track ride along with the visual field"
```

---

### Task 18: Final verification

**Files:** none — this task only verifies.

- [ ] **Step 1: Confirm nothing was left behind**

```bash
grep -rn "MindMachineView\|PhoneScreenOrb\|AdvancedControlsSection\|CustomSlider\|visualOpacityRange\|\bReaderVisual\b" Ilumionate IlumionateTests --include="*.swift"
```

Expected: no output. Any hit is either a deletion you missed or a rename that did not land.

- [ ] **Step 2: Confirm the safety rules still hold**

```bash
grep -n "speedBand\|amplitudeBand" Ilumionate/Visuals/VisualModulation.swift
```

Expected: `speedBand` is `0.05...0.45` and `amplitudeBand` is `0.25...1.0` — unchanged from before this work.

```bash
git diff main -- IlumionateTests/TranceVisualTests.swift | grep -E "^[+-].*peakCrossingHz|^[+-].*3\.0|^[+-].*2\.7"
```

Expected: no output beyond the type rename. If the ceiling assertions changed, revert them.

- [ ] **Step 3: Run the full suite on both destinations**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests 2>&1 | tail -5
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **` on both.

- [ ] **Step 4: Build the Mac Catalyst compatibility destination**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. `CLAUDE.md` requires Catalyst keep compiling.

- [ ] **Step 5: Walk the definition of done**

On both iOS and macOS:

1. The reader behaves identically to before. Open a script, cycle all seven effects, change strength, force-quit and relaunch — the saved preference survives.
2. Create shows four kinds in a segmented row, each with a live preview and a fixed tray. There is no disclosure group anywhere on the screen.
3. A Visual Field session runs full-screen with effect, colour, speed, strength and direction all under direct control, open-ended or timed.
4. Binaural and a library track each ride along independently, and a broken track leaves the field running.
5. Turn on Reduce Motion: the preview and the session hold still, and the Create screen says why.

- [ ] **Step 6: Commit any fixes and update the plan**

```bash
git add Ilumionate IlumionateTests
git commit -m "chore: final verification for the Create tab visual field"
```

---

## Self-review notes

Checked against `docs/superpowers/specs/2026-08-05-create-tab-visual-field-design.md`:

| Spec section | Task |
|---|---|
| Promote the visual system | 1 |
| Opacity band moves to the shared module | 2 |
| Two producers, one modulation struct | 3, 6 |
| Direction | 3 |
| The focus well | 4 |
| Colour | 5, 11 |
| Create tab structure, tray, deletions, preview | 7, 8, 11, 12, 13 |
| Analytics | 7, 15 |
| Player mode and in-session tray | 14, 15 |
| Audio | 17 |
| Duration | 10, 16 |
| Screen sleep | inherited — `.visualField` uses the existing `keepScreenAwakeDuringSessions` gate, no code change |
| Safety | 7 (`requiresSafetyWarning`), 14, verified in 18 |
| Reduce Motion | 6 (modulation), 13 (notice) |
| Persistence | 9 |
| Failure behaviour | 5 (hex), 6 (decode), 9 (store), 17 (audio) |
| Testing | every task |

**Known deviation from the spec:** the spec says `VisualFieldSettings` decodes every field with `decodeIfPresent`. Task 9 Step 3 changes the three enum fields to `try?` as well, because `decodeIfPresent` throws on a present-but-unknown raw value and would discard the whole payload — exactly the failure the pattern exists to prevent.
