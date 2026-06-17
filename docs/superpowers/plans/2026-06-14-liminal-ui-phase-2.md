# Liminal UI Phase 2 — Main Tabs Reskin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reskin the three main tabs — Library, Create (Mind Machine), and Read (TextTrance) — into the Liminal identity by composing the Phase-1 design kit, plus the few new shared components those screens require.

**Architecture:** Presentation-only. No engine, audio, analysis, or session-model changes. Phase 2 adds a small set of shared components to `Ilumionate/DesignSystem/` (a monospaced data-readout token, `WaveformSample`/`WaveformShape`, `ContentTypeStyle` + `SessionGlowDot`, `PhaseTimeline`), then migrates each screen's bespoke styling (`Color.bgPrimary` backgrounds, `GlassCard`, `.roseGold` accents) to the kit. Brainwave-zone colors (`bwDelta…bwGamma`) are kept per spec §2.1; only structural surfaces and primary accents move to aurora tokens.

**Tech Stack:** SwiftUI (iOS 26+), Swift 6.2, `@Observable`, Swift Testing (`import Testing`). Build target scheme `Ilumionate`; UI verification on the **iPhone 17** simulator.

---

## Conventions (apply to every reskin task)

These are the shared swap rules. Tasks reference "the Reskin Recipe" instead of repeating it.

**The Reskin Recipe — old → Liminal:**

| Old treatment (found in code) | Replace with |
|---|---|
| `Color.bgPrimary.ignoresSafeArea()` as a screen background | `AuroraBackground(mood:)` (mood chosen per screen; nil = neutral) |
| `GlassCard(label:) { … }` | `LiminalCard(label:) { … }` (same initializer shape) |
| Ad-hoc card: `.background(Color.bgCard)` + `RoundedRectangle(...).strokeBorder(Color.glassBorder)` | `.liminalSurface()` |
| `.roseGold` / `.roseDeep` as a **primary action / CTA accent** | `.auroraTeal` (and `.auroraBlue` as the gradient partner) |
| Primary CTA button with `LinearGradient([.roseGold,.roseDeep])` + `TranceShadow.button` | `GlowButton(title:systemImage:kind:.primary)` |
| Hz / data readout `Text(...).font(TranceTypography.frequency)` | `.font(TranceTypography.dataReadout)` (the new SF Mono token from Task 1) |
| `.foregroundStyle(.textPrimary/.textSecondary/.textLight)` | leave as-is — these are Phase-1 aliases already pointing at `textBright/textDim/textGhost` |
| Brainwave zone colors `.bwDelta…bwGamma`, `brainwaveColor` | **leave as-is** (kept per spec §2.1) |

**Mood mapping (for `AuroraBackground(mood:)`):**
- Library: `mood: nil` (neutral — it's a browse surface).
- Create / Mind Machine: `mood:` derived from the live frequency's zone — add `MindMachineModel.moodCategory` in Task 10.
- Read player: `mood: nil` on `voidDeep` (the RSVP word owns the screen).
- Read setup/library/sources: `mood: nil`.

**Verification commands (used verbatim in tasks):**
- Build: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Test (single suite): `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:IlumionateTests/<SuiteName>`
- "Preview check" means: open the file's `#Preview` in Xcode (or `RenderPreview` via Xcode MCP) and confirm void background + aurora glow, no light-mode/`bgPrimary` flatness.

**File-membership rule:** new files under `Ilumionate/DesignSystem/` and `IlumionateTests/` land in the existing synchronized groups — no `project.pbxproj` surgery (see memory `xcode-target-membership`). After creating a new file, build once to confirm it compiled into the target.

---

## File Structure

**New files:**
- `Ilumionate/DesignSystem/WaveformShape.swift` — `WaveformSample` (pure sampler) + `WaveformShape: Shape` (one glowing cycle).
- `Ilumionate/DesignSystem/ContentTypeStyle.swift` — pure `ContentType → (color, icon)` mapping + `SessionGlowDot` view.
- `Ilumionate/DesignSystem/PhaseTimeline.swift` — slim glowing segmented phase strip.
- `IlumionateTests/WaveformSampleTests.swift`
- `IlumionateTests/ContentTypeStyleTests.swift`

**Modified files:**
- `Ilumionate/TranceDesignSystem.swift` — add `TranceTypography.dataReadout`.
- `Ilumionate/LibraryView.swift` — background, category card, rows (→ `SessionGlowDot`), recents, sort capsule, toolbar, Favorites subview.
- `Ilumionate/SessionDetailView.swift` — aurora treatment + `PhaseTimeline` preview.
- `Ilumionate/MindMachineView.swift` — background, `GlassCard`→`LiminalCard`, readouts, slider, waveform picker, start button, live-preview, `moodCategory`.
- `Ilumionate/MindMachineView+Binaural.swift` — binaural deck → kit.
- `Ilumionate/TextTrance/TextTrancePlayerView.swift` — `voidDeep` + `auroraTeal` pivot.
- `Ilumionate/TextTrance/TextTranceSetupView.swift`, `TextTranceLibraryView.swift`, `TextTranceRootView.swift`, `ReadingSourceDirectoryView.swift` — kit composition.

---

# Task Group 0 — Shared kit additions

### Task 1: SF Mono data-readout typography token

**Files:**
- Modify: `Ilumionate/TranceDesignSystem.swift:234`

- [ ] **Step 1: Add the monospaced token**

In `TranceTypography`, immediately after the existing `frequency` line (`Ilumionate/TranceDesignSystem.swift:234`), add:

```swift
    // Monospaced data readout (frequency / Hz / counts) — the instrument showing through (spec §2.2)
    static let dataReadout = Font.system(size: 18, weight: .semibold, design: .monospaced)
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED (token unused so far).

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/TranceDesignSystem.swift
git commit -m "feat(liminal): add SF Mono dataReadout typography token"
```

---

### Task 2: WaveformSample + WaveformShape (the glowing waveform picker shapes)

Spec §4 (Create): the waveform picker should show "actual glowing waveform shapes," not gradient boxes. The drawing is driven by a pure sampler so it is unit-testable.

**Files:**
- Create: `Ilumionate/DesignSystem/WaveformShape.swift`
- Test: `IlumionateTests/WaveformSampleTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/WaveformSampleTests.swift`:

```swift
import Testing
import Foundation
@testable import Ilumionate

struct WaveformSampleTests {
    // Sampler returns a normalized amplitude in 0...1 for phase in 0...1.

    @Test("Sine starts at mid, peaks at quarter")
    func sine() {
        #expect(abs(WaveformSample.value(.sine, phase: 0.0) - 0.5) < 0.001)
        #expect(abs(WaveformSample.value(.sine, phase: 0.25) - 1.0) < 0.001)
        #expect(abs(WaveformSample.value(.sine, phase: 0.75) - 0.0) < 0.001)
    }

    @Test("Square is high in first half, low in second")
    func square() {
        #expect(WaveformSample.value(.square, phase: 0.1) == 1.0)
        #expect(WaveformSample.value(.square, phase: 0.6) == 0.0)
    }

    @Test("Triangle peaks at the midpoint")
    func triangle() {
        #expect(abs(WaveformSample.value(.triangle, phase: 0.0) - 0.0) < 0.001)
        #expect(abs(WaveformSample.value(.triangle, phase: 0.5) - 1.0) < 0.001)
        #expect(abs(WaveformSample.value(.triangle, phase: 1.0) - 0.0) < 0.001)
    }

    @Test("Sawtooth ramps linearly 0→1")
    func sawtooth() {
        #expect(abs(WaveformSample.value(.sawtooth, phase: 0.0) - 0.0) < 0.001)
        #expect(abs(WaveformSample.value(.sawtooth, phase: 0.5) - 0.5) < 0.001)
    }

    @Test("Pulse is a brief spike near the start")
    func pulse() {
        #expect(WaveformSample.value(.pulse, phase: 0.02) == 1.0)
        #expect(WaveformSample.value(.pulse, phase: 0.5) == 0.0)
    }

    @Test("All samples stay within 0...1 across the cycle")
    func bounded() {
        for pattern in MindMachineModel.LightPattern.allCases {
            for i in 0...20 {
                let v = WaveformSample.value(pattern, phase: Double(i) / 20.0)
                #expect(v >= 0.0 && v <= 1.0)
            }
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:IlumionateTests/WaveformSampleTests`
Expected: FAIL — `WaveformSample` is not defined.

- [ ] **Step 3: Write the sampler + shape**

Create `Ilumionate/DesignSystem/WaveformShape.swift`:

```swift
//
//  WaveformShape.swift
//  Ilumionate
//
//  Pure waveform sampler + a Shape that traces one glowing cycle. Used by the
//  Create tab's waveform picker so each pattern shows its real shape (spec §4).
//

import SwiftUI

/// Normalized waveform sampler. `phase` 0...1 maps one full cycle to amplitude 0...1
/// (0.5 = baseline for sine; shapes are framed for legible picker thumbnails, not DSP).
enum WaveformSample {
    static func value(_ pattern: MindMachineModel.LightPattern, phase: Double) -> Double {
        let p = phase - phase.rounded(.down) // wrap into 0..<1
        switch pattern {
        case .sine:
            return 0.5 + 0.5 * sin(p * 2 * .pi)
        case .square:
            return p < 0.5 ? 1.0 : 0.0
        case .triangle:
            return p < 0.5 ? (p / 0.5) : (1.0 - (p - 0.5) / 0.5)
        case .sawtooth:
            return p
        case .pulse:
            return p < 0.05 ? 1.0 : 0.0
        }
    }
}

/// Traces one cycle of `pattern` across the rect, y inverted so amplitude 1 is the top.
struct WaveformShape: Shape {
    let pattern: MindMachineModel.LightPattern
    var samples: Int = 64

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0...samples {
            let phase = Double(i) / Double(samples)
            let amp = WaveformSample.value(pattern, phase: phase)
            let x = rect.minX + CGFloat(phase) * rect.width
            let y = rect.maxY - CGFloat(amp) * rect.height
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

#Preview {
    ZStack {
        Color.voidPrimary.ignoresSafeArea()
        VStack(spacing: TranceSpacing.cardMargin) {
            ForEach(MindMachineModel.LightPattern.allCases, id: \.rawValue) { pattern in
                WaveformShape(pattern: pattern)
                    .stroke(
                        LinearGradient(colors: [.auroraTeal, .auroraBlue],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .frame(height: 44)
                    .shadow(color: .auroraTeal.opacity(0.5), radius: 8)
                    .padding(.horizontal, TranceSpacing.screen)
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:IlumionateTests/WaveformSampleTests`
Expected: PASS (all `@Test` green).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/DesignSystem/WaveformShape.swift IlumionateTests/WaveformSampleTests.swift
git commit -m "feat(liminal): add WaveformSample sampler + glowing WaveformShape"
```

---

### Task 3: ContentTypeStyle mapping + SessionGlowDot

`contentTypeColor` and `contentTypeIcon` are currently duplicated in three places in `LibraryView.swift` (`SessionMiniCard`, `LibrarySessionRow`, `LibrarySessionRowLabel`). Extract the mapping into one tested helper and a reusable zone-tinted glow dot (spec §4: "zone-tinted glow dots replacing thumbnail boxes").

**Files:**
- Create: `Ilumionate/DesignSystem/ContentTypeStyle.swift`
- Test: `IlumionateTests/ContentTypeStyleTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/ContentTypeStyleTests.swift`:

```swift
import Testing
import SwiftUI
@testable import Ilumionate

struct ContentTypeStyleTests {
    @Test("Known content types map to their zone color and a non-empty SF Symbol")
    func knownTypes() {
        #expect(ContentTypeStyle.color(for: .hypnosis) == .bwDelta)
        #expect(ContentTypeStyle.color(for: .meditation) == .bwAlpha)
        #expect(ContentTypeStyle.color(for: .brainwave) == .bwGamma)
        #expect(ContentTypeStyle.icon(for: .hypnosis) == "brain.head.profile")
        #expect(!ContentTypeStyle.icon(for: .music).isEmpty)
    }

    @Test("nil content type falls back to a neutral aurora color and waveform icon")
    func nilFallback() {
        #expect(ContentTypeStyle.color(for: nil) == .auroraTeal)
        #expect(ContentTypeStyle.icon(for: nil) == "waveform")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:IlumionateTests/ContentTypeStyleTests`
Expected: FAIL — `ContentTypeStyle` is not defined.

- [ ] **Step 3: Write the mapping + glow dot**

Create `Ilumionate/DesignSystem/ContentTypeStyle.swift`. (The mapping is lifted verbatim from the three duplicated copies in `LibraryView.swift`, with the `default`/`roseGold` fallback retuned to `.auroraTeal`.)

```swift
//
//  ContentTypeStyle.swift
//  Ilumionate
//
//  Single source of truth for a session's content-type color + icon, plus the
//  zone-tinted glow dot that replaces the old thumbnail boxes (spec §4).
//

import SwiftUI

enum ContentTypeStyle {
    static func color(for type: ContentType?) -> Color {
        switch type {
        case .hypnosis:       return .bwDelta
        case .eroticHypnosis: return .roseDeep
        case .sleepHypnosis:  return .bwDelta
        case .meditation:     return .bwAlpha
        case .brainwave:      return .bwGamma
        case .asmr:           return .warmAccent
        case .music:          return .bwBeta
        case .guidedImagery:  return .bwTheta
        case .affirmations:   return .warmAccent
        default:              return .auroraTeal
        }
    }

    static func icon(for type: ContentType?) -> String {
        switch type {
        case .hypnosis:       return "brain.head.profile"
        case .eroticHypnosis: return "flame"
        case .sleepHypnosis:  return "moon.zzz"
        case .meditation:     return "leaf"
        case .brainwave:      return "waveform.path.ecg"
        case .asmr:           return "ear"
        case .music:          return "music.note"
        case .guidedImagery:  return "figure.mind.and.body"
        case .affirmations:   return "quote.bubble"
        default:              return "waveform"
        }
    }
}

/// A zone-tinted glowing dot with the content-type icon — the Liminal replacement
/// for the old `RoundedRectangle().fill(color.opacity(0.18))` badge.
struct SessionGlowDot: View {
    let contentType: ContentType?
    var size: CGFloat = 40

    private var color: Color { ContentTypeStyle.color(for: contentType) }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 1))
            Image(systemName: ContentTypeStyle.icon(for: contentType))
                .font(.system(size: size * 0.42, weight: .regular))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 0)
    }
}

#Preview {
    ZStack {
        Color.voidPrimary.ignoresSafeArea()
        HStack(spacing: TranceSpacing.card) {
            SessionGlowDot(contentType: .hypnosis)
            SessionGlowDot(contentType: .meditation)
            SessionGlowDot(contentType: .music)
            SessionGlowDot(contentType: nil)
        }
    }
}
```

> Note: confirm `ContentType` is the exact enum name on `AudioFile.analysisResult?.contentType` (it is the type switched over in `LibraryView.swift`). If the compiler reports a different name, match it.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:IlumionateTests/ContentTypeStyleTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/DesignSystem/ContentTypeStyle.swift IlumionateTests/ContentTypeStyleTests.swift
git commit -m "feat(liminal): extract ContentTypeStyle mapping + SessionGlowDot"
```

---

### Task 4: PhaseTimeline component (slim glowing phase strip)

Spec §3 + §4 (Library session detail): a slim glowing segmented strip across the canonical session arc, current stage pulsing. Phase 2 uses it as a static preview in session detail (`current: nil`). **Design note:** there is no `HypnosisPhase` type — the analysis model is `HypnosisMetadata.Phase` (11 cases). A design-system component should NOT import the analysis domain model; instead it carries its own self-contained `Stage` enum matching the spec's named 5-stage arc (intro→induction→deepener→suggestion→awakening). The Breath-tempo pulse mirrors `AuroraBackground`'s reduce-motion branching pattern.

**Files:**
- Create: `Ilumionate/DesignSystem/PhaseTimeline.swift`

- [ ] **Step 1: Write the component**

Create `Ilumionate/DesignSystem/PhaseTimeline.swift`:

```swift
//
//  PhaseTimeline.swift
//  Ilumionate
//
//  Slim glowing segmented strip across the canonical session arc. The active
//  stage glows brighter and pulses at Breath tempo (frozen under Reduce Motion).
//  Self-contained Stage enum — decoupled from the analysis model (spec §3/§4).
//

import SwiftUI

struct PhaseTimeline: View {
    /// The canonical session arc shown as a glowing strip.
    enum Stage: String, CaseIterable, Identifiable {
        case intro, induction, deepener, suggestion, awakening
        var id: String { rawValue }
    }

    /// The stage currently highlighted, or nil for a neutral preview (all dim).
    var current: Stage? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || current == nil {
                strip(pulse: 1.0)
            } else {
                TimelineView(.animation) { context in
                    strip(pulse: pulseOpacity(at: context.date))
                }
            }
        }
        .frame(height: 6)
    }

    private func strip(pulse: Double) -> some View {
        HStack(spacing: TranceSpacing.micro) {
            ForEach(Stage.allCases) { stage in
                let isActive = stage == current
                Capsule()
                    .fill(isActive ? Color.auroraTeal : Color.auroraBlue.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .opacity(isActive ? pulse : 1.0)
                    .shadow(color: isActive ? Color.auroraTeal.opacity(0.6 * pulse) : .clear, radius: 6)
            }
        }
    }

    private func pulseOpacity(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let phase = t * (2 * .pi / LiminalMotion.breathDuration)
        return 0.7 + 0.3 * (0.5 + 0.5 * sin(phase))
    }
}

#Preview {
    ZStack {
        Color.voidPrimary.ignoresSafeArea()
        VStack(spacing: TranceSpacing.cardMargin) {
            PhaseTimeline(current: .deepener)
            PhaseTimeline(current: nil)
        }
        .padding(TranceSpacing.screen)
    }
}
```

- [ ] **Step 3: Build + preview check**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED. Preview check: five segments on the void, the active one glowing teal.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/DesignSystem/PhaseTimeline.swift
git commit -m "feat(liminal): add PhaseTimeline glowing phase strip"
```

---

# Task Group A — Library reskin

### Task 5: Library screen background + category card

**Files:**
- Modify: `Ilumionate/LibraryView.swift:46-47` (background), `:231-301` (`LibraryCategoryRows`)

- [ ] **Step 1: Swap the screen background**

In `LibraryView.body`, replace `Color.bgPrimary.ignoresSafeArea()` (`LibraryView.swift:47`) with `AuroraBackground()` (neutral mood — see Conventions). Replace the two `divider`/`bottomSpacer` `Color.bgPrimary` fills (`:199`, lines using `Color.bgPrimary`) with `Color.clear`.

- [ ] **Step 2: Reskin the category card container**

In `LibraryCategoryRows.body` (`:290-300`), remove the bespoke card chrome — delete the `.background(Color.bgCard)` + `.clipShape(RoundedRectangle…)` + `.overlay(RoundedRectangle…strokeBorder)` block and replace with a single `.liminalSurface()` after the existing horizontal/top padding. Keep the inner `LibraryRowDivider` rows unchanged.

- [ ] **Step 3: Build + preview check**

Run the Build command. Preview check: Library opens on the aurora void; the category list sits on void-glass.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/LibraryView.swift
git commit -m "feat(liminal): Library aurora background + void-glass category card"
```

---

### Task 6: Library rows → SessionGlowDot (and DRY the duplicated helpers)

**Files:**
- Modify: `Ilumionate/LibraryView.swift` — `SessionMiniCard` (`:522-591`), `LibrarySessionRow` (`:595-687`), `LibrarySessionRowLabel` (`:691-772`)

- [ ] **Step 1: Replace the three badge ZStacks with `SessionGlowDot`**

In each of the three row structs, replace the icon-badge `ZStack { RoundedRectangle…; Image(systemName: contentTypeIcon)… }` with `SessionGlowDot(contentType: file.analysisResult?.contentType, size: 40)` (use `size: 110` shaped differently for `SessionMiniCard` — there the artwork is a 110×110 tile; replace its `RoundedRectangle().fill(contentTypeGradient)` + icon with a larger `SessionGlowDot(contentType: file.analysisResult?.contentType, size: 110)`).

- [ ] **Step 2: Delete the now-dead duplicated helpers**

Remove the `contentTypeColor`, `contentTypeIcon`, and `contentTypeGradient` computed properties from `SessionMiniCard`, `LibrarySessionRow`, and `LibrarySessionRowLabel` (they are now centralized in `ContentTypeStyle`). Any remaining call site (e.g. a row's `.tint(.roseGold)` swipe action) uses `ContentTypeStyle.color(...)` or `.auroraTeal` as appropriate.

- [ ] **Step 3: Build to verify nothing references the deleted helpers**

Run the Build command.
Expected: BUILD SUCCEEDED. If the compiler flags a remaining reference to `contentTypeColor`/`contentTypeIcon`, replace it with the `ContentTypeStyle` call.

- [ ] **Step 4: Preview check + commit**

Preview check: rows show glowing zone-tinted dots instead of flat boxes.

```bash
git add Ilumionate/LibraryView.swift
git commit -m "refactor(liminal): Library rows use SessionGlowDot; drop duplicated style helpers"
```

---

### Task 7: Recents strip, sort capsule, toolbar accent, Favorites subview

**Files:**
- Modify: `Ilumionate/LibraryView.swift` — `RecentsStrip` (`:304-327`), `LibrarySessionsList` sort menu (`:343-363`) + list container (`:418-427`), `toolbarContent` (`:128-141`), `LibraryFavoritesView` (`:776-848`)

- [ ] **Step 1: Sort capsule + toolbar accent**

In the sort `Menu` label (`:360-362`), swap `Color.glassBorder.opacity(0.1)` background for `.liminalGlass(.capsule, glow: false)` (drop the manual `.background`/`.clipShape`/`.overlay`). In `toolbarContent` (`:137`), change the `LinearGradient(colors: [.roseGold, .blush]…)` to `LinearGradient(colors: [.auroraTeal, .auroraBlue]…)`.

- [ ] **Step 2: Sessions list container + Favorites subview**

In `LibrarySessionsList` (`:420-425`) replace the `.background(Color.bgCard)` + clip + strokeBorder block with `.liminalSurface()`. In `LibraryFavoritesView` (`:785`) replace `Color.bgPrimary.ignoresSafeArea()` with `AuroraBackground()`; change the empty-state icon gradient (`:790`) `[.roseGold, .roseDeep]` → `[.auroraTeal, .auroraBlue]`.

- [ ] **Step 3: Build + preview check + commit**

Run the Build command. Preview check: sort pill is void-glass; toolbar `+` glows teal; Favorites empty state on aurora void.

```bash
git add Ilumionate/LibraryView.swift
git commit -m "feat(liminal): Library recents/sort/toolbar/favorites adopt aurora kit"
```

---

### Task 8: Session detail — aurora treatment + PhaseTimeline preview

**Files:**
- Modify: `Ilumionate/SessionDetailView.swift`

- [ ] **Step 1: Read the file and locate background + header**

Run: `sed -n '1,60p' Ilumionate/SessionDetailView.swift` (or Read it). Identify the screen background (`Color.bgPrimary` or similar) and where the session metadata header renders.

- [ ] **Step 2: Apply aurora background + insert PhaseTimeline**

Replace the screen background with `AuroraBackground(mood:)` where mood is the session's zone if available (else nil). Below the title/metadata header, insert a labeled phase preview:

```swift
LiminalCard(label: "Phases") {
    PhaseTimeline(current: nil)
}
```

Migrate any `GlassCard` in this file to `LiminalCard` and any `.roseGold` CTA to `GlowButton`/`.auroraTeal` per the Reskin Recipe.

- [ ] **Step 3: Build + preview check + commit**

Run the Build command. Preview check: detail screen on aurora void with a glowing phase strip.

```bash
git add Ilumionate/SessionDetailView.swift
git commit -m "feat(liminal): session detail aurora treatment + PhaseTimeline preview"
```

---

# Task Group B — Create (Mind Machine) reskin

### Task 9: Mind Machine background, card migration, mono readouts, mood

**Files:**
- Modify: `Ilumionate/MindMachineView.swift` — `MindMachineModel` (add `moodCategory`, `:79-100`), `body` background (`:180`), `LightVisualizationCard`/`FrequencyCard`/`ColorTemperatureCard`/`IntensityCard`/`StartSessionCard`/`AdvancedControlsSection`/`BrowseSessionsLink` (all use `GlassCard`)

- [ ] **Step 1: Add `moodCategory` to the model**

In `MindMachineModel`, after `brainwaveColor` (`:100`), add a mapping from the live frequency to a `BrainwaveCategory` for `AuroraBackground(mood:)`:

```swift
    /// Maps the live frequency to a brainwave category for AuroraBackground mood.
    /// Bands match BrainwaveCategory's own frequencyRange/haloColor so the aurora
    /// tint agrees with the model's brainwaveColor.
    var moodCategory: BrainwaveCategory {
        switch frequency {
        case 0.5..<4:   return .sleep   // delta  → bwDelta
        case 4..<8:     return .relax   // theta  → bwTheta
        case 8..<14:    return .focus   // alpha  → bwAlpha
        case 14..<30:   return .energy  // beta   → bwBeta
        default:        return .trance  // gamma  → bwGamma
        }
    }
```

> `BrainwaveCategory` (in `HomeView.swift`) has cases `.sleep/.focus/.energy/.relax/.trance` (confirmed).

- [ ] **Step 2: Swap background + migrate `GlassCard` → `LiminalCard`**

In `MindMachineView.body` (`:159-180`), wrap the `ScrollView` in a `ZStack` with `AuroraBackground(mood: model.moodCategory)` behind it and delete `.background(Color.bgPrimary)`. Replace every `GlassCard(label:)`/`GlassCard {` in this file with `LiminalCard(label:)`/`LiminalCard {` (same initializer).

- [ ] **Step 3: Mono readouts**

In `LightVisualizationCard` (`:243`) and `FrequencyCard` (`:273`), change the Hz `Text(...).font(TranceTypography.frequency)` to `.font(TranceTypography.dataReadout)`. Do the same for the `\(Int(model.intensity*100))%` readout (`:254`) and `\(model.colorTemperature)K` (`:306`).

- [ ] **Step 4: Build + preview check + commit**

Run the Build command. Preview check: Create tab breathes the zone-tinted aurora; cards are void-glass; Hz reads in SF Mono.

```bash
git add Ilumionate/MindMachineView.swift
git commit -m "feat(liminal): Create tab aurora background, void-glass cards, mono readouts"
```

---

### Task 10: Luminous frequency slider + start button → GlowButton

**Files:**
- Modify: `Ilumionate/MindMachineView.swift` — `CustomSlider` (`:570-616`), `StartSessionCard` (`:347-391`)

- [ ] **Step 1: Make the slider luminous**

In `CustomSlider.body`, add a glow to the active track and thumb: on the active-track `RoundedRectangle` (`:590-592`) add `.shadow(color: activeColor.opacity(0.6), radius: 6)`; on the thumb `Circle` (`:595-599`) add `.shadow(color: thumbColor.opacity(0.7), radius: isDragging ? 12 : 8)`. No behavioral change.

- [ ] **Step 2: Replace the start button with GlowButton**

In `StartSessionCard.body` (`:352-388`), replace the hand-rolled `Button { … }` (the one with the `[.roseGold,.roseDeep]` gradient + `TranceShadow.button`) with:

```swift
GlowButton(title: model.startSessionButtonTitle, systemImage: model.startSessionIcon, kind: .primary) {
    showingFlashMode = true
    TranceHaptics.shared.heavy()
}
```

Keep the description `Text` below it. (`GlowButton` already fires `TranceHaptics.medium()`; the explicit `.heavy()` here is intentional for the session-start thump per spec §2.4.)

- [ ] **Step 3: Build + preview check + commit**

Run the Build command. Preview check: slider thumb glows; Begin button is the aurora gradient with a press bloom.

```bash
git add Ilumionate/MindMachineView.swift
git commit -m "feat(liminal): luminous frequency slider + GlowButton session start"
```

---

### Task 11: Waveform picker → glowing WaveformShape

**Files:**
- Modify: `Ilumionate/MindMachineView.swift` — `PatternCard` (`:531-566`)

- [ ] **Step 1: Replace the gradient box with the real waveform**

In `PatternCard.body` (`:539-548`), replace the `RoundedRectangle(cornerRadius: TranceRadius.pattern).fill(pattern.gradient)` thumbnail with the actual waveform on a glass tile:

```swift
ZStack {
    RoundedRectangle(cornerRadius: TranceRadius.pattern)
        .fill(Color.voidElevated.opacity(0.6))
        .frame(width: 80, height: 50)
    WaveformShape(pattern: pattern)
        .stroke(
            LinearGradient(colors: [.auroraTeal, .auroraBlue], startPoint: .leading, endPoint: .trailing),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 64, height: 30)
        .shadow(color: .auroraTeal.opacity(isSelected ? 0.7 : 0.4), radius: isSelected ? 10 : 6)
}
.overlay {
    RoundedRectangle(cornerRadius: TranceRadius.pattern)
        .stroke(isSelected ? Color.auroraTeal : Color.clear, lineWidth: 2)
        .frame(width: 80, height: 50)
}
```

The `pattern.gradient` property in `MindMachineModel.LightPattern` is now unused by the picker — leave it (it may be referenced elsewhere; removing it is Phase 3 cleanup). Confirm with `grep -rn "\.gradient" Ilumionate/MindMachineView.swift` and only delete it if this was the sole use.

- [ ] **Step 2: Build + preview check + commit**

Run the Build command. Preview check: each waveform card shows its real glowing shape; selected one glows brighter with a teal ring.

```bash
git add Ilumionate/MindMachineView.swift
git commit -m "feat(liminal): waveform picker shows real glowing WaveformShape"
```

---

### Task 12: Binaural deck → kit

**Files:**
- Modify: `Ilumionate/MindMachineView+Binaural.swift`

- [ ] **Step 1: Read the file**

Run: `cat Ilumionate/MindMachineView+Binaural.swift` (179 lines).

- [ ] **Step 2: Apply the Reskin Recipe**

Migrate `GlassCard` → `LiminalCard`, `.roseGold` accents → `.auroraTeal`, any Hz/carrier readout `.font(TranceTypography.frequency)` → `.font(TranceTypography.dataReadout)`, and reuse `CustomSlider` (already restyled in Task 10) for the carrier/volume sliders.

- [ ] **Step 3: Build + preview check + commit**

Run the Build command. Preview check: binaural section reads as a void-glass deck.

```bash
git add Ilumionate/MindMachineView+Binaural.swift
git commit -m "feat(liminal): binaural deck adopts aurora kit"
```

---

### Task 13: Live light-field preview strip

Spec §4 (Create): "Live preview: mini light-field strip pulsing at chosen settings." The existing `PhoneScreenOrb` (`MindMachineView.swift:621-697`) already breathes at the frequency. Phase 2 keeps it but reskins its frame onto the void and reaffirms the spec's "strip" by verifying it pulses with the live frequency/intensity.

**Files:**
- Modify: `Ilumionate/MindMachineView.swift` — `PhoneScreenOrb` (`:621-697`)

- [ ] **Step 1: Reskin the phone-frame onto the void**

In `PhoneScreenOrb.body`, change the phone-body `LinearGradient` start color `Color.bgSecondary` (`:648`) to `Color.voidElevated`, and keep the `brainwaveColor` glow. The screen-glow fill (`:660-673`) already reads kelvin + intensity — leave the breathing math (engine boundary: presentation only, no timing change).

- [ ] **Step 2: Build + preview check + commit**

Run the Build command. Preview check: the live visualizer sits on void and brightens/dims with frequency + intensity changes.

```bash
git add Ilumionate/MindMachineView.swift
git commit -m "feat(liminal): live preview visualizer reskinned onto the void"
```

---

# Task Group C — Read (TextTrance) reskin

> Spec §4 + §8: restyle only, **no functional changes** to TextTrance. RSVP words in light type on `voidDeep`.

### Task 14: RSVP player → voidDeep + auroraTeal pivot

**Files:**
- Modify: `Ilumionate/TextTrance/TextTrancePlayerView.swift:22` (background), `:27` (pulse color), `:76` (pivot color)

- [ ] **Step 1: Move the player to the deepest void**

Replace `Color.bgPrimary.ignoresSafeArea()` (`:22`) with `Color.voidDeep.ignoresSafeArea()` (the RSVP word owns the screen; no aurora blobs competing). In the decorative `RadialGradient` (`:27`), change `Color.roseGold` → `Color.auroraTeal`.

- [ ] **Step 2: Tint the pivot letter aurora**

In `AnchoredWord.body` (`:76`), change the pivot highlight `Color.roseGold` → `Color.auroraTeal`; non-pivot letters stay `Color.textPrimary` (alias → `textBright`). Do not touch the monospaced font / `anchorOffset` math (pivot alignment is functional).

- [ ] **Step 3: Build + preview check + commit**

Run the Build command. Preview check (`#Preview` at `:93`): word renders in bright type on near-black void, pivot letter glows teal.

```bash
git add Ilumionate/TextTrance/TextTrancePlayerView.swift
git commit -m "feat(liminal): RSVP player on voidDeep with aurora pivot"
```

---

### Task 15: TextTrance setup screen → kit

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceSetupView.swift` (background `:32`, `.tint` `:38`/`:99`, `GlassCard` `:72`/`:87`/`:108`)

- [ ] **Step 1: Read the file**

Run: `cat Ilumionate/TextTrance/TextTranceSetupView.swift`.

- [ ] **Step 2: Apply the Reskin Recipe**

Replace `Color.bgPrimary.ignoresSafeArea()` (`:32`) with `AuroraBackground()`. Migrate `GlassCard(label:)` (`:72`, `:87`, `:108`) → `LiminalCard(label:)`. Change `.tint(Color.roseGold)` (`:38`, `:99`) → `.tint(Color.auroraTeal)`. If a "Begin" CTA exists, convert it to `GlowButton`.

- [ ] **Step 3: Build + preview check + commit**

Run the Build command. Preview check: setup on aurora void, controls tinted teal.

```bash
git add Ilumionate/TextTrance/TextTranceSetupView.swift
git commit -m "feat(liminal): TextTrance setup adopts aurora kit"
```

---

### Task 16: TextTrance library, root, and reading-source directory → kit

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceLibraryView.swift` (`:40`, `:86`/`:108`/`:129`, `:132`/`:157`/`:158`/`:171`/`:174`), `Ilumionate/TextTrance/TextTranceRootView.swift`, `Ilumionate/TextTrance/ReadingSourceDirectoryView.swift`

- [ ] **Step 1: Reskin TextTranceLibraryView**

Replace `Color.bgPrimary.ignoresSafeArea()` (`:40`) with `AuroraBackground()`. Migrate the three `GlassCard(label: nil)` (`:86`, `:108`, `:129`) → `LiminalCard()`. Replace `.roseGold` accents (`:132`, `:157`, `:158`, `:171`, `:174`) with `.auroraTeal`, keeping the selected/unselected logic (`isOn ? .auroraTeal.opacity(0.22) : Color.glassBorder.opacity(0.4)`).

- [ ] **Step 2: Reskin RootView + ReadingSourceDirectoryView**

Read both (`cat Ilumionate/TextTrance/TextTranceRootView.swift Ilumionate/TextTrance/ReadingSourceDirectoryView.swift`). Apply the Reskin Recipe: background → `AuroraBackground()`, `GlassCard` → `LiminalCard`, `.roseGold` → `.auroraTeal`, any CTA → `GlowButton`. Leave the adult-gate flow and reading-source behavior untouched (functional / safety-critical — see memory `text-trance-feature`).

- [ ] **Step 3: Build + preview check + commit**

Run the Build command. Preview check: all Read surfaces on aurora void with teal accents.

```bash
git add Ilumionate/TextTrance/TextTranceLibraryView.swift Ilumionate/TextTrance/TextTranceRootView.swift Ilumionate/TextTrance/ReadingSourceDirectoryView.swift
git commit -m "feat(liminal): TextTrance library/root/sources adopt aurora kit"
```

---

# Final Verification

### Task 17: Full build + test sweep + manual walkthrough

- [ ] **Step 1: Full build**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Full test run (engine + new suites must stay green)**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: all suites pass, including `WaveformSampleTests`, `ContentTypeStyleTests`, and the Phase-1 suites (`LiminalPaletteTests`, `PortalRecommenderTests`, `PlayerControlsVisibilityTests`).

- [ ] **Step 3: Manual simulator walkthrough**

Launch the app on the iPhone 17 simulator and confirm: Library (aurora void, glowing zone dots, void-glass cards, teal `+`), session detail (PhaseTimeline strip), Create (zone-tinted aurora, mono Hz, real glowing waveforms, GlowButton start, binaural deck), Read (RSVP on voidDeep with teal pivot, setup/library/sources on aurora). No flat `bgPrimary` surfaces remain on these three tabs. Engine output (flash sessions) unchanged.

- [ ] **Step 4: Note residuals for Phase 3**

Confirm the broader `GlassBackground` deletion + token rename are still deferred to Phase 3 (the consolidation follow-up chip `task_8e6f4de2` and `MindMachineModel.LightPattern.gradient` removal belong there, not here).

---

## Self-Review (run after the plan is written)

**Spec §4 Phase 2 coverage:**
- Library reskin (ghost-tracked headers, LiminalSurface rows, zone-tinted glow dots, glass-capsule search, session detail aurora + PhaseTimeline) → Tasks 4–8 ✓
- Create (luminous frequency dial, waveform picker with real shapes, binaural glass deck, live preview strip) → Tasks 2, 9–13 ✓
- Read (RSVP light type on voidDeep, sources/setup reskinned, functionality untouched) → Tasks 14–16 ✓
- Spec §2.2 SF Mono data readouts → Task 1 ✓

**Type consistency:** `WaveformSample.value(_:phase:)` used identically in Task 2 (def), the `WaveformShape` path, and Task 11. `ContentTypeStyle.color(for:)`/`icon(for:)` + `SessionGlowDot(contentType:size:)` defined in Task 3, consumed in Task 6. `TranceTypography.dataReadout` defined in Task 1, used in Tasks 9 & 12. `MindMachineModel.moodCategory` defined in Task 9, used in Task 9's background. `PhaseTimeline(current:)` defined in Task 4, used in Task 8.

**Verify-before-coding flags (do not assume):** `ContentType` enum name (Task 3), `HypnosisPhase` cases/order (Task 4), `BrainwaveCategory` cases (Task 9). Each task's first step greps for the real name and substitutes if different.

**Honest testing note:** A visual reskin's primary verification is build + Xcode preview + simulator walkthrough; only the two pure units (`WaveformSample`, `ContentTypeStyle`) carry unit tests. This matches spec §7 (engine untouched ⇒ existing suites stay green; new tests are narrow).
