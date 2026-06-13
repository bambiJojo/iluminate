# Liminal UI Overhaul — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the entire app in the Liminal identity (dark-only void + aurora), build the core component kit, and rebuild the two identity-defining surfaces — the Portal home and the Pure Void player.

**Architecture:** Token-swap-first. Replace the values behind the existing `TranceColors`/`TranceShadow` tokens with the Liminal palette so the whole app inherits the new look on commit one, while keeping the old semantic names (`bgPrimary`, `roseGold`, `glassBorder`, …) as working aliases. Then add new components (`AuroraBackground`, `LumeOrb`, `LiminalSurface`, `GlowButton`) under a new `DesignSystem/` group, and restructure `HomeView`, `UnifiedPlayerView`, `TranceTabBar`, and `MiniPlayerBar`. **Presentation only — `LightEngine`, `FlashController`, audio, analyzers, and session models are never touched.**

**Tech Stack:** SwiftUI (iOS 26), Swift 6.2, `@Observable`, Swift Testing (`import Testing`). Spec: [`docs/superpowers/specs/2026-06-13-liminal-ui-overhaul-design.md`](../specs/2026-06-13-liminal-ui-overhaul-design.md).

---

## Conventions used in this plan

**Build command** (use after view changes that have no unit test):
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

**Test command** (single test type or file):
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:IlumionateTests/<TestSuiteName> 2>&1 | tail -30
```

**New files** go in the app target's synchronized group, so simply creating the `.swift` file under `Ilumionate/` is enough — no `.pbxproj` editing. New `DesignSystem/` subfolder is created by writing files into `Ilumionate/DesignSystem/`.

**Commit after every task.** Attribution is disabled in this repo's git config — do not add co-author trailers.

---

## File Structure

**New files:**
- `Ilumionate/DesignSystem/LiminalPalette.swift` — raw Liminal hex constants (single source of truth)
- `Ilumionate/DesignSystem/LiminalMotion.swift` — motion tempo durations (Breath/Drift/Touch)
- `Ilumionate/DesignSystem/LiminalSurface.swift` — glass surface modifier + container
- `Ilumionate/DesignSystem/GlowButton.swift` — primary/secondary aurora button
- `Ilumionate/DesignSystem/AuroraBackground.swift` — animated void+aurora background
- `Ilumionate/DesignSystem/LumeOrb.swift` — the breathing orb centerpiece
- `Ilumionate/PortalRecommender.swift` — time-of-day → session selection logic
- `Ilumionate/PlayerControlsVisibility.swift` — auto-hide timer observable model
- `IlumionateTests/LiminalPaletteTests.swift`
- `IlumionateTests/PortalRecommenderTests.swift`
- `IlumionateTests/PlayerControlsVisibilityTests.swift`

**Modified files:**
- `Ilumionate/TranceDesignSystem.swift` — swap color values to Liminal; flip shadows to glow; keep aliases
- `Ilumionate/ContentView.swift` — enforce `.preferredColorScheme(.dark)`; remove appearance-derived scheme
- `Ilumionate/ProfileSettingsView.swift` + `ProfileSettingsView+Sections.swift` — remove the Appearance picker
- `Ilumionate/HomeView.swift` — Portal layout
- `Ilumionate/UnifiedPlayerView.swift` — Pure Void overlay + drawer
- `Ilumionate/TranceTabBar.swift` — Liminal restyle
- `Ilumionate/MiniPlayerBar.swift` — Liminal restyle

---

# GROUP A — Foundation (token swap + dark-only)

## Task 1: Liminal palette constants + tests

**Files:**
- Create: `Ilumionate/DesignSystem/LiminalPalette.swift`
- Test: `IlumionateTests/LiminalPaletteTests.swift`

- [ ] **Step 1: Write the palette source of truth**

```swift
//
//  LiminalPalette.swift
//  Ilumionate
//
//  Single source of truth for the Liminal identity's raw colors.
//  Semantic tokens in TranceDesignSystem.swift resolve to these.
//

import SwiftUI

/// Raw Liminal hex strings. Kept as strings so they can be unit-tested
/// without constructing UIColors on a background thread.
enum LiminalHex {
    // Void backgrounds
    static let voidDeep     = "03040C"
    static let voidPrimary  = "070D1F"
    static let voidElevated = "0D1428"

    // Aurora accents
    static let auroraTeal   = "7EE8D8"
    static let auroraBlue   = "7C9EFF"
    static let auroraViolet = "B07DC8"
    static let auroraPink   = "E87CB8"

    // Text
    static let textBright   = "E6EEFF"
    static let textDim      = "8FA3CC"
    static let textGhost    = "5A6A8A"
}

extension Color {
    static let voidDeep     = Color(hex: LiminalHex.voidDeep)
    static let voidPrimary  = Color(hex: LiminalHex.voidPrimary)
    static let voidElevated = Color(hex: LiminalHex.voidElevated)
    static let auroraTeal   = Color(hex: LiminalHex.auroraTeal)
    static let auroraBlue   = Color(hex: LiminalHex.auroraBlue)
    static let auroraViolet = Color(hex: LiminalHex.auroraViolet)
    static let auroraPink   = Color(hex: LiminalHex.auroraPink)
    static let textBright   = Color(hex: LiminalHex.textBright)
    static let textDim      = Color(hex: LiminalHex.textDim)
    static let textGhost    = Color(hex: LiminalHex.textGhost)
}

extension ShapeStyle where Self == Color {
    static var voidDeep: Color     { .voidDeep }
    static var voidPrimary: Color  { .voidPrimary }
    static var voidElevated: Color { .voidElevated }
    static var auroraTeal: Color   { .auroraTeal }
    static var auroraBlue: Color   { .auroraBlue }
    static var auroraViolet: Color { .auroraViolet }
    static var auroraPink: Color   { .auroraPink }
    static var textBright: Color   { .textBright }
    static var textDim: Color      { .textDim }
    static var textGhost: Color    { .textGhost }
}
```

- [ ] **Step 2: Write the failing test**

```swift
//
//  LiminalPaletteTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct LiminalPaletteTests {

    @Test("Void hex values are the approved Liminal palette")
    func voidHexValues() {
        #expect(LiminalHex.voidDeep == "03040C")
        #expect(LiminalHex.voidPrimary == "070D1F")
        #expect(LiminalHex.voidElevated == "0D1428")
    }

    @Test("Aurora accent hex values are the approved Liminal palette")
    func auroraHexValues() {
        #expect(LiminalHex.auroraTeal == "7EE8D8")
        #expect(LiminalHex.auroraBlue == "7C9EFF")
        #expect(LiminalHex.auroraViolet == "B07DC8")
        #expect(LiminalHex.auroraPink == "E87CB8")
    }

    @Test("voidPrimary is very dark — luminance well below mid-grey")
    func voidPrimaryIsDark() {
        let l = relativeLuminance(hex: LiminalHex.voidPrimary)
        #expect(l < 0.05)
    }

    @Test("textBright on voidPrimary meets WCAG AA for body text (>= 4.5:1)")
    func textBrightContrast() {
        let ratio = contrastRatio(LiminalHex.textBright, LiminalHex.voidPrimary)
        #expect(ratio >= 4.5)
    }

    @Test("textDim on voidPrimary meets WCAG AA for body text (>= 4.5:1)")
    func textDimContrast() {
        let ratio = contrastRatio(LiminalHex.textDim, LiminalHex.voidPrimary)
        #expect(ratio >= 4.5)
    }

    // MARK: - Helpers (sRGB relative luminance per WCAG 2.1)

    private func relativeLuminance(hex: String) -> Double {
        let (r, g, b) = rgb(hex)
        func lin(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private func contrastRatio(_ a: String, _ b: String) -> Double {
        let la = relativeLuminance(hex: a)
        let lb = relativeLuminance(hex: b)
        let hi = max(la, lb), lo = min(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }

    private func rgb(_ hex: String) -> (Double, Double, Double) {
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        return (Double(int >> 16) / 255.0,
                Double(int >> 8 & 0xFF) / 255.0,
                Double(int & 0xFF) / 255.0)
    }
}
```

- [ ] **Step 3: Run tests — they should pass immediately**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:IlumionateTests/LiminalPaletteTests 2>&1 | tail -30
```
Expected: all 5 tests PASS. If a contrast test fails, the palette is wrong — stop and report (do not weaken the threshold).

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/DesignSystem/LiminalPalette.swift IlumionateTests/LiminalPaletteTests.swift
git commit -m "feat(liminal): add Liminal palette tokens with contrast tests"
```

---

## Task 2: Motion tempo constants

**Files:**
- Create: `Ilumionate/DesignSystem/LiminalMotion.swift`

- [ ] **Step 1: Write the motion constants**

```swift
//
//  LiminalMotion.swift
//  Ilumionate
//
//  The three Liminal motion tempos. Centralizing them keeps every
//  surface breathing at the same rate.
//

import SwiftUI

enum LiminalMotion {
    /// Ambient, never-ending: orb breathing, aurora drift.
    static let breathDuration: Double = 5.0
    /// Conic orb-ring rotation period.
    static let orbSpinDuration: Double = 24.0

    /// Screen/sheet transitions.
    static let drift = Animation.spring(response: 0.7, dampingFraction: 0.85)
    /// Touch feedback (press, glow bloom).
    static let touch = Animation.easeInOut(duration: 0.22)
    /// Player controls fade.
    static let fade = Animation.easeInOut(duration: 0.3)

    /// Idle seconds before Pure Void controls auto-hide.
    static let controlsAutoHideDelay: Double = 4.0

    static var breath: Animation { .easeInOut(duration: breathDuration).repeatForever(autoreverses: true) }
    static var orbSpin: Animation { .linear(duration: orbSpinDuration).repeatForever(autoreverses: false) }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/DesignSystem/LiminalMotion.swift
git commit -m "feat(liminal): add motion tempo constants"
```

---

## Task 3: Swap semantic color tokens to Liminal

This is the keystone task: every existing screen inherits the void after this.

**Files:**
- Modify: `Ilumionate/TranceDesignSystem.swift:25-77` (the `TranceColors` struct)

- [ ] **Step 1: Replace the `TranceColors` background/accent/text/border values**

Replace the body of `struct TranceColors` (lines 25–77, from `// MARK: Backgrounds` through the `flashOff` declaration) with the following. **Keep the same property names** so all call sites keep compiling — only the values change. Brainwave/phase hues are re-tuned to sit on the void. Flash colors are unchanged except `flashOff` going to true void.

```swift
struct TranceColors {

    // MARK: Backgrounds (Liminal void — dark only)
    static let bgPrimary   = Color.voidPrimary
    static let bgSecondary = Color.voidElevated
    static let bgCard      = Color.voidElevated.opacity(0.65)

    // MARK: Accents (aurora)
    static let roseGold   = Color.auroraTeal     // primary action accent
    static let roseDeep   = Color.auroraBlue     // secondary action accent
    static let blush      = Color.auroraPink
    static let lavender   = Color.auroraViolet
    static let warmAccent = Color.auroraPink

    // MARK: Text
    static let textPrimary   = Color.textBright
    static let textSecondary = Color.textDim
    static let textLight     = Color.textGhost

    // MARK: Borders & Glass
    static let glassBorder = Color.auroraBlue.opacity(0.18)
    static let glassFill   = Color.white.opacity(0.06)

    // MARK: Brainwave Zone Colors (re-tuned for the void)
    static let bwDelta = Color(hex: "8B6BA8")
    static let bwTheta = Color(hex: "B07DC8")
    static let bwAlpha = Color(hex: "7C9EFF")
    static let bwBeta  = Color(hex: "7EE8D8")
    static let bwGamma = Color(hex: "E8B07A")

    // MARK: Hypnosis Phase Colors
    static let phaseIntro         = Color(hex: "7C9EFF")
    static let phaseInduction     = Color(hex: "7EE8D8")
    static let phaseDeepener      = Color(hex: "B07DC8")
    static let phaseFractionation = Color(hex: "E8B07A")
    static let phaseSuggestion    = Color(hex: "E87CB8")
    static let phaseAwakening     = Color(hex: "F5D08E")

    // MARK: Flash Mode Colors (light-therapy output — DO NOT restyle hues)
    // flashOn must stay bright/visible; flashOff goes to true void.
    static let flashOn  = Color(hex: "F8C8D4")
    static let flashOff = Color.voidDeep
}
```

> Note: `Color(light:dark:)` is no longer used here — the app is dark-only, so each token is a single color. The `Color(light:dark:)` helper at the top of the file stays (harmless, may be used elsewhere); do not delete it in this task.

- [ ] **Step 2: Flip shadow styles from drop-shadows to aurora glow**

In the same file, replace the `TranceShadow` `card`, `button`, and `elevated` definitions (lines ~182–211) with glow variants (light, not darkness):

```swift
struct TranceShadow {
    // Card glow (soft aurora bloom instead of a dark drop shadow)
    static let card = (
        color: Color.auroraBlue.opacity(0.10),
        radius: 16.0,
        x: 0.0,
        y: 0.0
    )

    // CTA button glow
    static let button = (
        color: Color.auroraTeal.opacity(0.35),
        radius: 18.0,
        x: 0.0,
        y: 6.0
    )

    // Category icon halo glow
    static func iconHalo(_ color: Color) -> (Color, CGFloat, CGFloat, CGFloat) {
        return (color.opacity(0.4), 14.0, 0.0, 0.0)
    }

    // Elevated card glow
    static let elevated = (
        color: Color.auroraBlue.opacity(0.18),
        radius: 20.0,
        x: 0.0,
        y: 0.0
    )

    // Phone frame (dev preview only)
    static let phoneFrame = (
        color: Color.black.opacity(0.5),
        radius: 40.0,
        x: 0.0,
        y: 25.0
    )
}
```

- [ ] **Step 3: Build to verify everything still compiles**

Run the build command. Expected: `** BUILD SUCCEEDED **`. If any call site broke, a token name was renamed by mistake — restore the exact original names.

- [ ] **Step 4: Re-run the palette tests (sanity)**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:IlumionateTests/LiminalPaletteTests 2>&1 | tail -15
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TranceDesignSystem.swift
git commit -m "feat(liminal): swap semantic tokens to Liminal void+aurora palette"
```

---

## Task 4: Enforce dark-only and remove the appearance picker

**Files:**
- Modify: `Ilumionate/ContentView.swift:27-39,134`
- Modify: `Ilumionate/ProfileSettingsView+Sections.swift:113-135` (the `appearanceSection`)
- Modify: `Ilumionate/ProfileSettingsView.swift` (remove now-unused appearance plumbing)

- [ ] **Step 1: Force dark scheme in ContentView**

In `ContentView.swift`, delete the appearance plumbing. Remove lines 27–39 (the `// Appearance` comment, `@AppStorage("appearanceMode")`, and the entire `preferredColorScheme` computed property):

```swift
    // Appearance — mirrors SettingsView's AppStorage key
    @AppStorage("appearanceMode") private var appearanceModeRaw = "system"

    // Synced to engine on appear and on change
    @AppStorage("userFrequencyMultiplier") private var userFrequencyMultiplierPref = 1.0

    private var preferredScheme: ColorScheme? {
        switch appearanceModeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
```
becomes:
```swift
    // Synced to engine on appear and on change
    @AppStorage("userFrequencyMultiplier") private var userFrequencyMultiplierPref = 1.0
```

- [ ] **Step 2: Replace the scheme modifier**

In `ContentView.swift`, change the final modifier on the body `ZStack` (line ~134):
```swift
        .preferredColorScheme(preferredScheme)
```
to:
```swift
        .preferredColorScheme(.dark)
```

- [ ] **Step 3: Remove the Appearance settings section**

In `ProfileSettingsView+Sections.swift`, delete the entire `appearanceSection` computed property (the block starting at line ~114 with `GlassCard(label: "Appearance")` through its closing — lines ~113–135). Then remove the reference to `appearanceSection` wherever it is composed into the settings body (search the file for `appearanceSection` and delete that line).

- [ ] **Step 4: Remove the now-unused appearance plumbing in ProfileSettingsView.swift**

In `ProfileSettingsView.swift`, delete:
- the `@AppStorage("appearanceMode") var appearanceModeRaw = "system"` line (~27)
- the `appearanceMode` binding computed property (~138–143)
- the computed property that returns `.colorScheme` from appearance (~145–147)
- the `enum AppearanceMode` (~118–136)

If any of these are referenced elsewhere after deletion, the build will flag it — handle by removing those references (they are all part of the removed picker).

- [ ] **Step 5: Build to verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Leave the stored default alone**

Do **not** change `AppSettingsManager.swift` — leaving the dormant `appearanceMode` key is harmless and avoids touching the settings-reset path. (Documented intentionally.)

- [ ] **Step 7: Commit**

```bash
git add Ilumionate/ContentView.swift Ilumionate/ProfileSettingsView.swift Ilumionate/ProfileSettingsView+Sections.swift
git commit -m "feat(liminal): enforce dark-only, remove appearance picker"
```

---

# GROUP B — Component Kit

## Task 5: LiminalSurface (glass container + modifier)

**Files:**
- Create: `Ilumionate/DesignSystem/LiminalSurface.swift`

- [ ] **Step 1: Write the surface**

```swift
//
//  LiminalSurface.swift
//  Ilumionate
//
//  The Liminal glass surface: ultraThinMaterial over the void with a
//  hairline aurora border and an aurora GLOW (not a dark drop shadow).
//

import SwiftUI

/// Applies the Liminal glass treatment to any view.
struct LiminalSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat = TranceRadius.glassCard
    var glow: Bool = true

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.voidElevated.opacity(0.6))
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
            .shadow(color: glow ? Color.auroraBlue.opacity(0.12) : .clear,
                    radius: 18, x: 0, y: 0)
    }
}

extension View {
    func liminalSurface(cornerRadius: CGFloat = TranceRadius.glassCard, glow: Bool = true) -> some View {
        modifier(LiminalSurfaceModifier(cornerRadius: cornerRadius, glow: glow))
    }
}

/// A labeled glass card built on the Liminal surface — drop-in companion to GlassCard.
struct LiminalCard<Content: View>: View {
    let label: String?
    @ViewBuilder let content: () -> Content

    init(label: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.small) {
            if let label {
                Text(label)
                    .font(TranceTypography.cardLabel)
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.textGhost)
            }
            content()
        }
        .padding(TranceSpacing.card)
        .liminalSurface()
    }
}

#Preview {
    ZStack {
        Color.voidPrimary.ignoresSafeArea()
        VStack(spacing: TranceSpacing.cardMargin) {
            LiminalCard(label: "Tonight") {
                Text("Hypnagogic Drift · 30 min")
                    .font(TranceTypography.body)
                    .foregroundStyle(.textBright)
            }
            LiminalCard {
                Text("No label")
                    .font(TranceTypography.body)
                    .foregroundStyle(.textDim)
            }
        }
        .padding(TranceSpacing.screen)
    }
}
```

- [ ] **Step 2: Build to verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/DesignSystem/LiminalSurface.swift
git commit -m "feat(liminal): add LiminalSurface glass container"
```

---

## Task 6: GlowButton

**Files:**
- Create: `Ilumionate/DesignSystem/GlowButton.swift`

- [ ] **Step 1: Write the button**

```swift
//
//  GlowButton.swift
//  Ilumionate
//
//  Liminal call-to-action button. Press = scale + glow bloom (never opacity dim).
//

import SwiftUI

struct GlowButton: View {
    enum Kind { case primary, secondary }

    let title: String
    var systemImage: String? = nil
    var kind: Kind = .primary
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            TranceHaptics.shared.medium()
            action()
        } label: {
            label
                .frame(maxWidth: .infinity)
                .padding(.vertical, TranceSpacing.card)
                .background(background)
                .clipShape(.rect(cornerRadius: TranceRadius.button))
                .overlay(
                    RoundedRectangle(cornerRadius: TranceRadius.button)
                        .stroke(kind == .secondary ? Color.glassBorder : .clear, lineWidth: 1)
                )
                .shadow(color: glowColor.opacity(isPressed ? 0.55 : 0.3),
                        radius: isPressed ? 26 : 18, x: 0, y: 6)
                .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(LiminalMotion.touch) { isPressed = pressing }
        }, perform: {})
    }

    @ViewBuilder
    private var label: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(kind == .primary ? Color.voidDeep : Color.textBright)
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            LinearGradient(colors: [.auroraTeal, .auroraBlue],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .secondary:
            Color.voidElevated.opacity(0.6)
        }
    }

    private var glowColor: Color { kind == .primary ? .auroraTeal : .auroraBlue }
}

#Preview {
    ZStack {
        Color.voidPrimary.ignoresSafeArea()
        VStack(spacing: TranceSpacing.cardMargin) {
            GlowButton(title: "Begin", systemImage: "play.fill") {}
            GlowButton(title: "Browse Library", kind: .secondary) {}
        }
        .padding(TranceSpacing.screen)
    }
}
```

- [ ] **Step 2: Build to verify.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/DesignSystem/GlowButton.swift
git commit -m "feat(liminal): add GlowButton with press-glow bloom"
```

---

## Task 7: AuroraBackground

**Files:**
- Create: `Ilumionate/DesignSystem/AuroraBackground.swift`

- [ ] **Step 1: Write the background**

```swift
//
//  AuroraBackground.swift
//  Ilumionate
//
//  The signature Liminal surface: a void radial gradient with 2–3 large
//  blurred aurora blobs drifting at Breath tempo. Mood tints the aurora
//  toward a brainwave zone. Freezes under Reduce Motion. Pauses when an
//  active light session owns the screen.
//

import SwiftUI

struct AuroraBackground: View {
    /// Optional zone tint. nil = neutral teal/blue/violet mix.
    var mood: BrainwaveCategory? = nil
    /// When true, ambient drift halts (e.g. during an active flash session).
    var isPaused: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Void base
            RadialGradient(
                colors: [Color.voidPrimary, Color.voidDeep],
                center: .init(x: 0.5, y: 1.15),
                startRadius: 0, endRadius: 700
            )
            .ignoresSafeArea()

            if reduceMotion || isPaused {
                staticBlobs
            } else {
                animatedBlobs
            }
        }
        .background(Color.voidDeep.ignoresSafeArea())
    }

    private var blobColors: [Color] {
        if let mood {
            return [mood.haloColor, .auroraBlue, mood.haloColor.opacity(0.7)]
        }
        return [.auroraBlue, .auroraViolet, .auroraTeal]
    }

    private var staticBlobs: some View {
        ZStack {
            blob(blobColors[0]).offset(x: -120, y: -200)
            blob(blobColors[1]).offset(x: 130, y: 240)
            blob(blobColors[2]).opacity(0.5).offset(x: 60, y: 40)
        }
        .ignoresSafeArea()
    }

    private var animatedBlobs: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = t * (2 * .pi / LiminalMotion.breathDuration)
            ZStack {
                blob(blobColors[0])
                    .offset(x: -120 + CGFloat(sin(phase) * 40),
                            y: -200 + CGFloat(cos(phase * 0.8) * 30))
                blob(blobColors[1])
                    .offset(x: 130 + CGFloat(cos(phase) * 35),
                            y: 240 + CGFloat(sin(phase * 0.9) * 30))
                blob(blobColors[2])
                    .opacity(0.5)
                    .offset(x: 60 + CGFloat(sin(phase * 1.1) * 30),
                            y: 40 + CGFloat(cos(phase) * 40))
            }
            .ignoresSafeArea()
        }
    }

    private func blob(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 420, height: 420)
            .blur(radius: 90)
            .opacity(0.35)
    }
}

#Preview("Neutral") { AuroraBackground() }
#Preview("Sleep mood") { AuroraBackground(mood: .sleep) }
```

> `BrainwaveCategory` and its `haloColor` already exist in `HomeView.swift`. No new model needed.

- [ ] **Step 2: Build to verify.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/DesignSystem/AuroraBackground.swift
git commit -m "feat(liminal): add AuroraBackground with breath-tempo drift"
```

---

## Task 8: LumeOrb

**Files:**
- Create: `Ilumionate/DesignSystem/LumeOrb.swift`

- [ ] **Step 1: Write the orb**

```swift
//
//  LumeOrb.swift
//  Ilumionate
//
//  The Liminal centerpiece: a conic aurora ring slowly rotating around a
//  void core, with a breathing outer glow. Sizes: hero / medium / mini.
//  Optional `pulse` frequency drives the breath rate (target Hz preview).
//

import SwiftUI

struct LumeOrb: View {
    enum Size { case hero, medium, mini
        var diameter: CGFloat { switch self { case .hero: 200; case .medium: 120; case .mini: 40 } }
        var ringInset: CGFloat { switch self { case .hero: 7; case .medium: 5; case .mini: 2 } }
    }

    var size: Size = .hero
    /// Optional target frequency (Hz). When set, breath period = 1/pulse, clamped to a calm range.
    var pulse: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var breathPeriod: Double {
        guard let pulse, pulse > 0 else { return LiminalMotion.breathDuration }
        // Map entrainment Hz to a visible-but-calm breath (never seizure-fast).
        return min(6.0, max(2.0, 1.0 / pulse * 4.0))
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let spin = reduceMotion ? 0 : (t / LiminalMotion.orbSpinDuration)
                .truncatingRemainder(dividingBy: 1) * 360
            let breath = reduceMotion ? 0 : sin(t * (2 * .pi / breathPeriod))
            let glowScale = 1.0 + 0.10 * breath
            let glowOpacity = 0.6 + 0.25 * breath

            ZStack {
                // Outer breathing glow
                Circle()
                    .fill(RadialGradient(colors: [Color.auroraBlue.opacity(0.4), .clear],
                                         center: .center, startRadius: 0,
                                         endRadius: size.diameter * 0.9))
                    .scaleEffect(glowScale)
                    .opacity(glowOpacity)

                // Conic aurora ring
                Circle()
                    .fill(AngularGradient(colors: [.auroraTeal, .auroraBlue, .auroraViolet, .auroraPink, .auroraTeal],
                                          center: .center))
                    .rotationEffect(.degrees(spin))

                // Void core
                Circle()
                    .fill(Color.voidPrimary)
                    .padding(size.ringInset)
            }
            .frame(width: size.diameter, height: size.diameter)
            .shadow(color: .auroraBlue.opacity(0.4), radius: 40)
        }
    }
}

#Preview("Hero") {
    ZStack { Color.voidPrimary.ignoresSafeArea(); LumeOrb(size: .hero) }
}
#Preview("Mini") {
    ZStack { Color.voidPrimary.ignoresSafeArea(); LumeOrb(size: .mini) }
}
```

- [ ] **Step 2: Build to verify.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Verify previews render**

Open `LumeOrb.swift` in Xcode and resume the canvas. Confirm the hero orb shows the rotating ring + breathing glow, and the mini orb is a clean small disc. (Visual check; no assertion.)

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/DesignSystem/LumeOrb.swift
git commit -m "feat(liminal): add LumeOrb breathing centerpiece"
```

---

# GROUP C — The Portal (Home)

## Task 9: PortalRecommender — smart session selection (logic + tests)

**Files:**
- Create: `Ilumionate/PortalRecommender.swift`
- Test: `IlumionateTests/PortalRecommenderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//
//  PortalRecommenderTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

struct PortalRecommenderTests {

    @Test("Evening hours recommend a calming category")
    func eveningRecommendsCalm() {
        #expect(PortalRecommender.category(forHour: 22) == .sleep)
        #expect(PortalRecommender.category(forHour: 23) == .sleep)
    }

    @Test("Late night recommends sleep")
    func lateNightRecommendsSleep() {
        #expect(PortalRecommender.category(forHour: 1) == .sleep)
    }

    @Test("Morning recommends energy")
    func morningRecommendsEnergy() {
        #expect(PortalRecommender.category(forHour: 7) == .energy)
        #expect(PortalRecommender.category(forHour: 9) == .energy)
    }

    @Test("Midday recommends focus")
    func middayRecommendsFocus() {
        #expect(PortalRecommender.category(forHour: 13) == .focus)
    }

    @Test("Late afternoon/early evening recommends relax")
    func eveningRelax() {
        #expect(PortalRecommender.category(forHour: 18) == .relax)
    }

    @Test("Picks the first session whose first moment falls in the category range")
    func picksMatchingSession() {
        let sleepy = LightSession(
            session_name: "Delta Drift", duration_sec: 600,
            light_score: [LightMoment(time: 0, frequency: 2.0, intensity: 0.5, waveform: .sine)]
        )
        let focusy = LightSession(
            session_name: "Alpha Focus", duration_sec: 600,
            light_score: [LightMoment(time: 0, frequency: 10.0, intensity: 0.5, waveform: .sine)]
        )
        let pick = PortalRecommender.recommend(from: [focusy, sleepy], forHour: 23)
        #expect(pick?.session_name == "Delta Drift")
    }

    @Test("Falls back to the first session when none match the category")
    func fallsBackToFirst() {
        let only = LightSession(
            session_name: "Only One", duration_sec: 600,
            light_score: [LightMoment(time: 0, frequency: 10.0, intensity: 0.5, waveform: .sine)]
        )
        let pick = PortalRecommender.recommend(from: [only], forHour: 23)
        #expect(pick?.session_name == "Only One")
    }

    @Test("Returns nil for an empty library")
    func emptyLibraryReturnsNil() {
        #expect(PortalRecommender.recommend(from: [], forHour: 12) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:IlumionateTests/PortalRecommenderTests 2>&1 | tail -30
```
Expected: FAIL — `PortalRecommender` is undefined.

- [ ] **Step 3: Write the implementation**

```swift
//
//  PortalRecommender.swift
//  Ilumionate
//
//  Chooses the best-fit session for the Portal orb based on time of day,
//  reusing the existing BrainwaveCategory frequency ranges.
//

import Foundation

enum PortalRecommender {

    /// Maps an hour (0–23) to the brainwave category the Portal should offer.
    static func category(forHour hour: Int) -> BrainwaveCategory {
        switch hour {
        case 22...23, 0...4:  return .sleep    // night → wind down to sleep
        case 5...10:          return .energy   // morning → wake up
        case 11...15:         return .focus    // midday → focus
        default:              return .relax     // late afternoon/evening
        }
    }

    /// Picks the best session for the given hour: the first whose opening
    /// frequency lands in the time-appropriate category, else the first session.
    static func recommend(from sessions: [LightSession], forHour hour: Int) -> LightSession? {
        guard !sessions.isEmpty else { return nil }
        let category = category(forHour: hour)
        let range = category.frequencyRange
        let match = sessions.first { session in
            guard let first = session.light_score.sorted(by: { $0.time < $1.time }).first else { return false }
            return range.contains(first.frequency)
        }
        return match ?? sessions.first
    }

    /// Convenience using the current hour.
    static func recommend(from sessions: [LightSession], now: Date = .now) -> LightSession? {
        recommend(from: sessions, forHour: Calendar.current.component(.hour, from: now))
    }
}
```

> Verify before running: confirm `LightSession` has `session_name`, `duration_sec`, and `light_score` (array of `LightMoment` with `time`/`frequency`), and that `LightMoment` initializer matches the test. These are used in `UnifiedPlayerView.swift` previews, so they exist. If `BrainwaveCategory.frequencyRange` ranges overlap such that a sleep session (2 Hz) also matches focus, the per-hour category gate still selects correctly because `recommend` uses the hour's single category.

- [ ] **Step 4: Run the test to verify it passes**

Re-run the test command from Step 2. Expected: all tests PASS. If `picksMatchingSession` fails because the `.sleep` range (`0.5...4.0`) doesn't contain 2.0 — it does; if it fails, inspect `BrainwaveCategory.frequencyRange` in `HomeView.swift:40-48` and align the test's frequencies to real ranges.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/PortalRecommender.swift IlumionateTests/PortalRecommenderTests.swift
git commit -m "feat(liminal): add PortalRecommender time-of-day session logic"
```

---

## Task 10: Rebuild HomeView as The Portal

This replaces the dashboard layout with the orb-centric Portal. The existing
session-launch plumbing (`selectedSession`, `continueSessionCard`, flash presets)
is reused — only the layout changes.

**Files:**
- Modify: `Ilumionate/HomeView.swift` (the `body` and `greetingSection`; add a `portalSection`)

- [ ] **Step 1: Add the AuroraBackground behind the scroll content**

In `HomeView.swift`, wrap the existing `ScrollView` (body starts ~line 102) in a `ZStack` with the aurora background. Change:
```swift
    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.content) {
```
to:
```swift
    var body: some View {
        ZStack {
            AuroraBackground(mood: PortalRecommender.category(forHour: Calendar.current.component(.hour, from: .now)))
            ScrollView {
                VStack(spacing: TranceSpacing.content) {
```
and add a matching closing brace for the `ZStack` at the end of the body (after the existing `ScrollView` modifiers, before the final `}` of `var body`). Build will tell you if the brace is misplaced.

- [ ] **Step 2: Insert the Portal section as the first element**

Immediately after the opening `VStack(spacing:)` and before `greetingSection`, add:
```swift
                    portalSection
                        .cardEntrance(visible: cardsVisible, delay: 0.00, reduceMotion: reduceMotion)
```
and change the existing `greetingSection`'s delay from `0.00` to `0.06` so it staggers after the orb.

- [ ] **Step 3: Add the `portalSection` view**

Add this computed property to `HomeView` (near `greetingSection`, ~line 169). It shows the time-aware greeting, the hero orb as the primary CTA (resume if a session is in progress, else the recommended one), and the StateChips row:

```swift
    private var portalSection: some View {
        let recommended = sessions.first(where: { $0.id.uuidString == lastSessionId && lastSessionProgress > 0 })
            ?? PortalRecommender.recommend(from: sessions)

        return VStack(spacing: TranceSpacing.content) {
            VStack(spacing: TranceSpacing.micro) {
                Text(currentGreeting)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.textDim)
                Text("Ready to descend?")
                    .font(.system(size: 26, weight: .ultraLight))
                    .foregroundStyle(.textBright)
            }
            .padding(.top, TranceSpacing.content)

            Button {
                TranceHaptics.shared.medium()
                if let recommended { selectedSession = recommended }
            } label: {
                ZStack {
                    LumeOrb(size: .hero, pulse: recommended?.light_score.first?.frequency)
                    VStack(spacing: 2) {
                        Text("Begin")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(.textBright)
                        if let recommended {
                            Text(recommended.session_name)
                                .font(.system(size: 11))
                                .foregroundStyle(.textGhost)
                                .lineLimit(1)
                                .frame(maxWidth: 140)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recommended.map { "Begin \($0.session_name)" } ?? "Begin a session")

            stateChipsRow
        }
    }

    private var stateChipsRow: some View {
        HStack(spacing: TranceSpacing.inner) {
            ForEach(BrainwaveCategory.allCases, id: \.self) { category in
                Button {
                    TranceHaptics.shared.selection()
                    showingSessionLibrary = true
                } label: {
                    Text("\(category.emoji) \(category.rawValue)")
                        .font(.system(size: 12))
                        .foregroundStyle(.textDim)
                        .padding(.horizontal, TranceSpacing.list)
                        .padding(.vertical, TranceSpacing.inner)
                        .background(category.haloColor.opacity(0.12))
                        .clipShape(.capsule)
                        .overlay(Capsule().stroke(category.haloColor.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
```

> This reuses existing state: `selectedSession`, `lastSessionId`, `lastSessionProgress`, `currentGreeting`, `showingSessionLibrary`, `BrainwaveCategory`. No new bindings.

- [ ] **Step 4: Simplify the old greeting (avoid duplication)**

Since `portalSection` now owns the greeting, the old `greetingSection` would double it up. Open `greetingSection` (~line 169) and reduce it to just the profile button row (keep the profile button + `showingProfile` plumbing, remove the greeting text). If `greetingSection` is mostly greeting text, replace its body with the profile button only. Build to confirm `showingProfile`/profile sheet still wire up.

- [ ] **Step 5: Build and visually verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`. Then open `HomeView.swift` preview (the `#Preview` at file end ~line 681) and confirm: aurora background, greeting, hero orb labeled "Begin", a row of state chips, and the existing continue/featured sections below.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/HomeView.swift
git commit -m "feat(liminal): rebuild Home as the Portal (hero LumeOrb)"
```

---

# GROUP D — Pure Void Player

## Task 11: PlayerControlsVisibility — auto-hide timer model (logic + tests)

Extract the controls-visibility/auto-hide behavior into a testable observable so
the player view stays thin and the timer logic is unit-tested.

**Files:**
- Create: `Ilumionate/PlayerControlsVisibility.swift`
- Test: `IlumionateTests/PlayerControlsVisibilityTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//
//  PlayerControlsVisibilityTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

@MainActor
struct PlayerControlsVisibilityTests {

    @Test("Starts visible")
    func startsVisible() {
        let v = PlayerControlsVisibility()
        #expect(v.isVisible == true)
    }

    @Test("Interaction shows controls")
    func interactionShows() {
        let v = PlayerControlsVisibility()
        v.hideNow()
        #expect(v.isVisible == false)
        v.registerInteraction()
        #expect(v.isVisible == true)
    }

    @Test("Auto-hide is suppressed while the drawer is open")
    func drawerSuppressesHide() {
        let v = PlayerControlsVisibility()
        v.isDrawerOpen = true
        v.hideNow()
        #expect(v.isVisible == true)   // refuses to hide while drawer is open
    }

    @Test("Auto-hide is suppressed under VoiceOver")
    func voiceOverSuppressesHide() {
        let v = PlayerControlsVisibility(voiceOverActive: { true })
        v.hideNow()
        #expect(v.isVisible == true)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:IlumionateTests/PlayerControlsVisibilityTests 2>&1 | tail -30
```
Expected: FAIL — `PlayerControlsVisibility` undefined.

- [ ] **Step 3: Write the implementation**

```swift
//
//  PlayerControlsVisibility.swift
//  Ilumionate
//
//  Observable model for Pure Void controls auto-hide. Controls fade after
//  an idle delay, but never while the drawer is open or VoiceOver is running.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class PlayerControlsVisibility {
    var isVisible: Bool = true
    var isDrawerOpen: Bool = false

    private let voiceOverActive: () -> Bool
    private var hideTask: Task<Void, Never>?

    init(voiceOverActive: @escaping () -> Bool = { UIAccessibility.isVoiceOverRunning }) {
        self.voiceOverActive = voiceOverActive
    }

    /// Whether auto-hide is currently allowed.
    var canAutoHide: Bool { !isDrawerOpen && !voiceOverActive() }

    /// User touched the screen: show controls and restart the idle timer.
    func registerInteraction() {
        withAnimation(LiminalMotion.fade) { isVisible = true }
        scheduleAutoHide()
    }

    /// Force-hide now (respects suppression rules).
    func hideNow() {
        guard canAutoHide else { return }
        withAnimation(LiminalMotion.fade) { isVisible = false }
    }

    /// Begin/refresh the idle countdown.
    func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LiminalMotion.controlsAutoHideDelay))
            guard let self, !Task.isCancelled else { return }
            self.hideNow()
        }
    }

    func cancel() { hideTask?.cancel() }
}
```

- [ ] **Step 4: Run the test to verify it passes.** Re-run Step 2's command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/PlayerControlsVisibility.swift IlumionateTests/PlayerControlsVisibilityTests.swift
git commit -m "feat(liminal): add PlayerControlsVisibility auto-hide model"
```

---

## Task 12: Pure Void player overlay

Restyle the player's minimal overlay into the whisper-thin Pure Void overlay
and move the controls into a swipe-up drawer. **The `backgroundLayer` and all
engine/flash rendering stay byte-identical — only chrome changes.**

**Files:**
- Modify: `Ilumionate/UnifiedPlayerView.swift` (`minimalOverlay` ~157, controls presentation ~49-55, add drawer)

- [ ] **Step 1: Replace `minimalOverlay` with the Pure Void whisper**

Replace the `minimalOverlay` computed property (lines ~159–203) with:

```swift
    // MARK: - Minimal Overlay (Pure Void whisper — auto-fades)

    private var minimalOverlay: some View {
        VStack {
            // Whisper header: session name + frequency readout
            VStack(spacing: TranceSpacing.micro) {
                if viewModel.mode.hasFrequencyDisplay || viewModel.mode.hasAudioScrubber {
                    Text(viewModel.formatTime(viewModel.currentTime))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(viewModel.secondaryLabelColor.opacity(0.6))
                }
            }
            .padding(.top, TranceSpacing.statusBar)

            Spacer()

            if viewModel.mode.hasMandalaVisualizer {
                MandalaVisualizer(size: 250, brightness: viewModel.engine.brightness, isPlaying: viewModel.isPlaying)
                Spacer()
            }

            Text("Tap to show controls · swipe up for settings")
                .font(TranceTypography.caption)
                .foregroundStyle(viewModel.secondaryLabelColor.opacity(0.5))
                .padding(.bottom, TranceSpacing.statusBar)
        }
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(LiminalMotion.fade) { viewModel.showingControls = true }
        }
        .accessibilityLabel("Show controls")
    }
```

> This keeps using `viewModel.showingControls` (the existing flag) so we do not rewire the viewModel. The `PlayerControlsVisibility` model from Task 11 is wired in a follow-up integration step below to drive auto-hide; for this task the existing tap-to-show behavior is preserved and restyled.

- [ ] **Step 2: Wire auto-hide via the new model**

Add a state object to `UnifiedPlayerView` (near the top, after `@State private var viewModel`):
```swift
    @State private var controlsVisibility = PlayerControlsVisibility()
```
Then bridge it to the existing flag. In `body`, add after `.onAppear { viewModel.onAppear() }`:
```swift
        .onAppear { controlsVisibility.registerInteraction() }
        .onChange(of: controlsVisibility.isVisible) { _, visible in
            withAnimation(LiminalMotion.fade) { viewModel.showingControls = visible }
        }
        .onChange(of: viewModel.showingControls) { _, showing in
            if showing { controlsVisibility.registerInteraction() }
        }
```
And in the `minimalOverlay` tap handler, replace the body with:
```swift
        .onTapGesture { controlsVisibility.registerInteraction() }
```

> Net effect: tapping shows controls and starts the 4 s idle timer; after 4 s of no interaction the controls fade — unless the drawer is open or VoiceOver is running (enforced inside the model).

- [ ] **Step 3: Add the swipe-up drawer gesture to the background**

In `body`, on the root `ZStack` (after `.statusBarHidden(...)`), add a drag gesture that opens the controls (the drawer = the existing `controlsOverlay`, which already holds every control):
```swift
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height < -40 {   // swipe up
                        controlsVisibility.registerInteraction()
                    } else if value.translation.height > 40 { // swipe down
                        controlsVisibility.hideNow()
                    }
                }
        )
```

- [ ] **Step 4: Tie drawer-open suppression to controls visibility**

So auto-hide pauses while controls (the "drawer") are shown, set `isDrawerOpen` from the visibility change. Update the `onChange(of: controlsVisibility.isVisible)` added in Step 2 to also keep the model's drawer flag in sync is unnecessary; instead, treat "controls showing" as the drawer being open. Add to `body`:
```swift
        .onChange(of: viewModel.showingControls) { _, showing in
            controlsVisibility.isDrawerOpen = showing
        }
```
(If two `.onChange(of: viewModel.showingControls)` modifiers are awkward, merge them into one closure that both calls `registerInteraction()` when showing and sets `isDrawerOpen = showing`.)

- [ ] **Step 5: Build and verify**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run the visibility tests again (still green)**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:IlumionateTests/PlayerControlsVisibilityTests 2>&1 | tail -15
```
Expected: PASS.

- [ ] **Step 7: Manual smoke test in the simulator**

Launch the app, start a session, and confirm: controls fade after ~4 s; a tap brings them back; a swipe-up brings them back; the safety/photosensitivity warning still appears for flash modes (unchanged). If anything in the engine/flash rendering changed visually, revert — this task is chrome-only.

- [ ] **Step 8: Commit**

```bash
git add Ilumionate/UnifiedPlayerView.swift
git commit -m "feat(liminal): Pure Void player overlay with auto-hide + swipe drawer"
```

---

# GROUP E — Tab Bar + Mini-Player Restyle

## Task 13: Restyle TranceTabBar for Liminal

**Files:**
- Modify: `Ilumionate/TranceTabBar.swift:101-102` (and capsule fills if needed)

- [ ] **Step 1: Point the accent at aurora teal and add a glow dot**

In `TranceTabBar.swift`, the accent already resolves through `.roseGold` (now aurora teal after Task 3), so the capsule indicator is already correct. Enhance the active item with a glow. In `tabItem(_:)`, change the selected-state foreground/background block. Replace the `.background { if isSelected { Capsule()... } }` (lines ~90–96) with:
```swift
            .background {
                if isSelected {
                    Capsule()
                        .fill(tabAccentColor.opacity(0.18))
                        .matchedGeometryEffect(id: "TAB_INDICATOR", in: tabAnimation)
                        .shadow(color: tabAccentColor.opacity(0.4), radius: 10)
                }
            }
```
And ensure inactive items use `.textGhost`: change line ~85
```swift
            .foregroundStyle(isSelected ? tabAccentColor : Color.textSecondary)
```
to
```swift
            .foregroundStyle(isSelected ? tabAccentColor : Color.textGhost)
```

- [ ] **Step 2: Make the bar background read as void glass**

The bar uses `.regularMaterial` (line ~54). Add a void tint behind it. Replace the `.background { Capsule().fill(.regularMaterial)... }` block (lines ~52–56) with:
```swift
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .background(Capsule().fill(Color.voidElevated.opacity(0.7)))
                .shadow(color: Color.auroraBlue.opacity(0.15), radius: 16, x: 0, y: 8)
        }
```

- [ ] **Step 3: Build and verify.** Expected: `** BUILD SUCCEEDED **`. Open the `#Preview` (file end) and confirm the active tab glows teal on void glass.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/TranceTabBar.swift
git commit -m "feat(liminal): restyle tab bar for void glass + aurora glow"
```

---

## Task 14: Restyle MiniPlayerBar for Liminal

**Files:**
- Modify: `Ilumionate/MiniPlayerBar.swift`

- [ ] **Step 1: Read the file first**

Open `Ilumionate/MiniPlayerBar.swift` and identify: the artwork view, the background material, and the accent colors. (It already uses Trance tokens, so it inherited the void palette in Task 3.)

- [ ] **Step 2: Swap the artwork thumbnail for a mini LumeOrb**

Find the artwork element (a thumbnail rectangle or image). Replace it with:
```swift
            LumeOrb(size: .mini)
                .frame(width: 40, height: 40)
```
(Keep any surrounding `frame`/`padding`.) If the mini-player shows real session art and you prefer to keep it, instead overlay a subtle aurora ring around it — but the default is the mini orb for identity consistency.

- [ ] **Step 3: Ensure the bar uses the void glass treatment**

Apply the shared surface to the bar's container (the outer `HStack`/capsule). If it currently uses `.ultraThinMaterial` directly, add `.background(Color.voidElevated.opacity(0.7))` behind it and a `.shadow(color: .auroraBlue.opacity(0.15), radius: 14)` so it visually matches the tab bar from Task 13.

- [ ] **Step 4: Build and verify.** Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Smoke test stacking**

Launch the app, start a session, return to Home: confirm the mini-player sits above the tab bar with correct clearance (`TranceSpacing.tabBarClearance` unchanged) and the mini orb animates.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/MiniPlayerBar.swift
git commit -m "feat(liminal): restyle mini-player with mini LumeOrb + void glass"
```

---

# GROUP F — Phase 1 Verification

## Task 15: Full regression pass

**Files:** none (verification only)

- [ ] **Step 1: Full build**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Run the new Liminal test suites**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:IlumionateTests/LiminalPaletteTests \
       -only-testing:IlumionateTests/PortalRecommenderTests \
       -only-testing:IlumionateTests/PlayerControlsVisibilityTests 2>&1 | tail -30
```
Expected: all PASS.

- [ ] **Step 3: Run the existing engine/analysis suites to confirm no regressions**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:IlumionateTests/LightActionTests \
       -only-testing:IlumionateTests/SessionArcTests 2>&1 | tail -30
```
Expected: PASS (engine untouched ⇒ green). If any fail, the engine boundary was crossed — investigate before proceeding.

- [ ] **Step 4: Manual device/simulator walkthrough**

Confirm each surface reads as Liminal and nothing is broken:
- Home: aurora bg, hero orb "Begin", state chips, continue/featured below.
- Tap orb → player launches → Pure Void overlay → controls auto-hide after 4 s → tap/swipe recall.
- Tab bar: active tab glows teal on void glass; all four tabs navigate.
- Start a session, minimize → mini-player with mini orb above the tab bar.
- Settings: no Appearance picker; app is dark regardless of system setting.
- Library / Create / Read: inherited the void palette (may look imperfect — that's expected; Phase 2 restyles them).

- [ ] **Step 5: Final commit (if any cleanup)**

```bash
git add -A
git commit -m "chore(liminal): Phase 1 verification cleanup" || echo "nothing to commit"
```

---

## Phase 1 Done — Definition of Done

- [ ] Whole app renders in the Liminal void palette, dark-only, appearance picker gone.
- [ ] `AuroraBackground`, `LumeOrb`, `LiminalSurface`, `GlowButton` exist with previews.
- [ ] Home is the Portal (hero orb as primary CTA, time-aware, state chips).
- [ ] Player is Pure Void (whisper overlay, 4 s auto-hide, swipe-up drawer, safety flow intact).
- [ ] Tab bar + mini-player restyled and stack correctly.
- [ ] New unit tests pass; existing engine/analysis tests still green.
- [ ] Engine, flash, audio, analyzers, session models untouched.

Phase 2 (Library, Create/Mind Machine, Read) and Phase 3 (secondary surfaces, onboarding, token rename + delete Trance system) follow in their own plans.
