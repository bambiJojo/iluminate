# Pink Aurora Light Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bright-pink "Pink Aurora" light mode alongside the existing dark Liminal theme, with a Light/Dark/System toggle, an always-dark session player, and a reader-level color-mode override.

**Architecture:** Adaptive semantic tokens — every semantic color in `TranceDesignSystem.swift` becomes `Color(light:dark:)` using the helper already defined there. Dark values stay byte-identical. Views using raw `void*`/`aurora*`/`text*` colors migrate to semantic tokens. Theme choice persists under the existing `appearanceMode` UserDefaults key.

**Tech Stack:** SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`), xcodebuild.

**Spec:** `docs/superpowers/specs/2026-07-18-pink-aurora-light-mode-design.md`

**Project facts the engineer needs:**
- The Xcode project uses synchronized folder groups — new `.swift` files under `Ilumionate/` and `IlumionateTests/` are picked up automatically; do NOT edit `project.pbxproj`.
- Build: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build`
- Test: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/<TestStruct>` (pre-existing failures exist in analyzer tests — only require green on the test structs named in this plan)
- Test style: Swift Testing structs; see `IlumionateTests/LiminalPaletteTests.swift` for the WCAG contrast helpers this plan reuses.
- Light-mode accent values were pre-verified against WCAG: text ≥ 4.5:1 and accents ≥ 3:1 on `FFF3F9`. Do not "improve" hex values; tests pin them.

---

### Task 1: Pink Aurora palette (raw hex layer)

**Files:**
- Create: `Ilumionate/DesignSystem/PinkAuroraPalette.swift`
- Test: `IlumionateTests/PinkAuroraPaletteTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/PinkAuroraPaletteTests.swift`:

```swift
//
//  PinkAuroraPaletteTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct PinkAuroraPaletteTests {

    @Test("Dawn background hex values are the approved Pink Aurora palette")
    func dawnHexValues() {
        #expect(PinkAuroraHex.dawnDeep == "FFE9F4")
        #expect(PinkAuroraHex.dawnPrimary == "FFF3F9")
        #expect(PinkAuroraHex.dawnElevated == "FFFFFF")
    }

    @Test("Accent hex values are the approved Pink Aurora palette")
    func accentHexValues() {
        #expect(PinkAuroraHex.accentTeal == "0B8A76")
        #expect(PinkAuroraHex.accentBlue == "4D6DF0")
        #expect(PinkAuroraHex.hotPink == "FF2D8F")
        #expect(PinkAuroraHex.violet == "9A4DC8")
        #expect(PinkAuroraHex.peach == "C4611A")
    }

    @Test("dawnPrimary is very light — luminance well above mid-grey")
    func dawnPrimaryIsLight() {
        let l = relativeLuminance(hex: PinkAuroraHex.dawnPrimary)
        #expect(l > 0.85)
    }

    @Test("Ink text on dawnPrimary meets WCAG AA for body text (>= 4.5:1)")
    func textInkContrast() {
        #expect(contrastRatio(PinkAuroraHex.textInk, PinkAuroraHex.dawnPrimary) >= 4.5)
    }

    @Test("Muted text on dawnPrimary meets WCAG AA for body text (>= 4.5:1)")
    func textMutedContrast() {
        #expect(contrastRatio(PinkAuroraHex.textMuted, PinkAuroraHex.dawnPrimary) >= 4.5)
    }

    @Test("All accents meet WCAG 3:1 for UI elements on dawnPrimary",
          arguments: [
              PinkAuroraHex.accentTeal, PinkAuroraHex.accentBlue,
              PinkAuroraHex.hotPink, PinkAuroraHex.violet, PinkAuroraHex.peach,
              PinkAuroraHex.bwDelta, PinkAuroraHex.bwTheta, PinkAuroraHex.bwAlpha,
              PinkAuroraHex.bwBeta, PinkAuroraHex.bwGamma,
              PinkAuroraHex.phaseIntro, PinkAuroraHex.phaseInduction,
              PinkAuroraHex.phaseDeepener, PinkAuroraHex.phaseFractionation,
              PinkAuroraHex.phaseSuggestion, PinkAuroraHex.phaseAwakening
          ])
    func accentContrast(hex: String) {
        #expect(contrastRatio(hex, PinkAuroraHex.dawnPrimary) >= 3.0)
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

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/PinkAuroraPaletteTests 2>&1 | tail -20`
Expected: build FAILS with "cannot find 'PinkAuroraHex' in scope"

- [ ] **Step 3: Write the palette**

Create `Ilumionate/DesignSystem/PinkAuroraPalette.swift`:

```swift
//
//  PinkAuroraPalette.swift
//  Ilumionate
//
//  Single source of truth for the Pink Aurora (light mode) raw colors.
//  Semantic tokens in TranceDesignSystem.swift resolve to these in light mode
//  and to LiminalPalette values in dark mode.
//

import SwiftUI

/// Raw Pink Aurora hex strings. Kept as strings so they can be unit-tested
/// without constructing UIColors on a background thread.
/// Accents are deepened relative to their Liminal counterparts so they meet
/// WCAG 3:1 on the blush dawnPrimary background (text colors meet 4.5:1).
enum PinkAuroraHex {
    // Dawn backgrounds
    static let dawnDeep     = "FFE9F4"
    static let dawnPrimary  = "FFF3F9"
    static let dawnElevated = "FFFFFF"

    // Aurora accents (deepened)
    static let accentTeal = "0B8A76"
    static let accentBlue = "4D6DF0"
    static let hotPink    = "FF2D8F"
    static let violet     = "9A4DC8"
    static let peach      = "C4611A"

    // Text
    static let textInk     = "231024"
    static let textMuted   = "7A5A80"
    static let textWhisper = "B08DB8"

    // Brainwave zones
    static let bwDelta = "6B4788"
    static let bwTheta = "9A4DC8"
    static let bwAlpha = "4D6DF0"
    static let bwBeta  = "0B8A76"
    static let bwGamma = "C4611A"

    // Hypnosis phases
    static let phaseIntro         = "4D6DF0"
    static let phaseInduction     = "0B8A76"
    static let phaseDeepener      = "9A4DC8"
    static let phaseFractionation = "C4611A"
    static let phaseSuggestion    = "FF2D8F"
    static let phaseAwakening     = "A87400"
}

extension Color {
    static let dawnDeep     = Color(hex: PinkAuroraHex.dawnDeep)
    static let dawnPrimary  = Color(hex: PinkAuroraHex.dawnPrimary)
    static let dawnElevated = Color(hex: PinkAuroraHex.dawnElevated)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/PinkAuroraPaletteTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, all PinkAuroraPaletteTests pass

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/DesignSystem/PinkAuroraPalette.swift IlumionateTests/PinkAuroraPaletteTests.swift
git commit -m "feat(theme): Pink Aurora raw palette with WCAG-pinned values"
```

---

### Task 2: Adaptive semantic tokens

**Files:**
- Modify: `Ilumionate/TranceDesignSystem.swift:25-98` (TranceColors + Color extension)
- Test: `IlumionateTests/AdaptiveTokenTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AdaptiveTokenTests.swift`. It resolves tokens through UIKit trait collections to prove they adapt (and that flash colors do NOT):

```swift
//
//  AdaptiveTokenTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
import UIKit
@testable import Ilumionate

@MainActor
struct AdaptiveTokenTests {

    private let lightTraits = UITraitCollection(userInterfaceStyle: .light)
    private let darkTraits  = UITraitCollection(userInterfaceStyle: .dark)

    private func resolvedHex(_ color: Color, _ traits: UITraitCollection) -> String {
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func h(_ c: CGFloat) -> String { String(format: "%02X", Int(round(c * 255))) }
        return h(r) + h(g) + h(b)
    }

    @Test("bgPrimary resolves to dawnPrimary in light and voidPrimary in dark")
    func bgPrimaryAdapts() {
        #expect(resolvedHex(.bgPrimary, lightTraits) == PinkAuroraHex.dawnPrimary)
        #expect(resolvedHex(.bgPrimary, darkTraits) == LiminalHex.voidPrimary)
    }

    @Test("bgDeep resolves to dawnDeep in light and voidDeep in dark")
    func bgDeepAdapts() {
        #expect(resolvedHex(.bgDeep, lightTraits) == PinkAuroraHex.dawnDeep)
        #expect(resolvedHex(.bgDeep, darkTraits) == LiminalHex.voidDeep)
    }

    @Test("Accent tokens adapt between palettes")
    func accentsAdapt() {
        #expect(resolvedHex(.roseGold, lightTraits) == PinkAuroraHex.accentTeal)
        #expect(resolvedHex(.roseGold, darkTraits) == LiminalHex.auroraTeal)
        #expect(resolvedHex(.blush, lightTraits) == PinkAuroraHex.hotPink)
        #expect(resolvedHex(.blush, darkTraits) == LiminalHex.auroraPink)
        #expect(resolvedHex(.textPrimary, lightTraits) == PinkAuroraHex.textInk)
        #expect(resolvedHex(.textPrimary, darkTraits) == LiminalHex.textBright)
    }

    @Test("Flash colors are hue-locked — identical in both modes")
    func flashColorsDoNotAdapt() {
        #expect(resolvedHex(.flashOn, lightTraits) == resolvedHex(.flashOn, darkTraits))
        #expect(resolvedHex(.flashOff, lightTraits) == resolvedHex(.flashOff, darkTraits))
        #expect(resolvedHex(.flashOff, darkTraits) == LiminalHex.voidDeep)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/AdaptiveTokenTests 2>&1 | tail -20`
Expected: build FAILS — `bgDeep` does not exist yet; after adding stubs the adapt assertions fail because tokens are static.

- [ ] **Step 3: Rewrite TranceColors as adaptive tokens**

In `Ilumionate/TranceDesignSystem.swift`, replace the entire `struct TranceColors { ... }` (currently lines 25-67) with:

```swift
struct TranceColors {

    // MARK: Backgrounds (dawn in light / Liminal void in dark)
    static let bgDeep      = Color(light: .dawnDeep, dark: .voidDeep)
    static let bgPrimary   = Color(light: .dawnPrimary, dark: .voidPrimary)
    static let bgSecondary = Color(light: .dawnElevated, dark: .voidElevated)
    static let bgCard      = Color(
        light: Color.white.opacity(0.72),
        dark: Color.voidElevated.opacity(0.65)
    )

    // MARK: Accents (aurora)
    static let roseGold   = Color(light: Color(hex: PinkAuroraHex.accentTeal), dark: .auroraTeal)
    static let roseDeep   = Color(light: Color(hex: PinkAuroraHex.accentBlue), dark: .auroraBlue)
    static let blush      = Color(light: Color(hex: PinkAuroraHex.hotPink), dark: .auroraPink)
    static let lavender   = Color(light: Color(hex: PinkAuroraHex.violet), dark: .auroraViolet)
    static let warmAccent = Color(light: Color(hex: PinkAuroraHex.peach), dark: Color(hex: "E8B07A"))

    // MARK: Text
    static let textPrimary   = Color(light: Color(hex: PinkAuroraHex.textInk), dark: .textBright)
    static let textSecondary = Color(light: Color(hex: PinkAuroraHex.textMuted), dark: .textDim)
    static let textLight     = Color(light: Color(hex: PinkAuroraHex.textWhisper), dark: .textGhost)

    // MARK: Borders & Glass
    static let glassBorder = Color(
        light: Color(hex: PinkAuroraHex.hotPink).opacity(0.18),
        dark: Color.auroraBlue.opacity(0.18)
    )
    static let glassFill = Color(
        light: Color.white.opacity(0.60),
        dark: Color.white.opacity(0.06)
    )

    // MARK: Brainwave Zone Colors
    static let bwDelta = Color(light: Color(hex: PinkAuroraHex.bwDelta), dark: Color(hex: "8B6BA8"))
    static let bwTheta = Color(light: Color(hex: PinkAuroraHex.bwTheta), dark: Color(hex: "B07DC8"))
    static let bwAlpha = Color(light: Color(hex: PinkAuroraHex.bwAlpha), dark: Color(hex: "7C9EFF"))
    static let bwBeta  = Color(light: Color(hex: PinkAuroraHex.bwBeta), dark: Color(hex: "7EE8D8"))
    static let bwGamma = Color(light: Color(hex: PinkAuroraHex.bwGamma), dark: Color(hex: "E8B07A"))

    // MARK: Hypnosis Phase Colors
    static let phaseIntro         = Color(light: Color(hex: PinkAuroraHex.phaseIntro), dark: Color(hex: "7C9EFF"))
    static let phaseInduction     = Color(light: Color(hex: PinkAuroraHex.phaseInduction), dark: Color(hex: "7EE8D8"))
    static let phaseDeepener      = Color(light: Color(hex: PinkAuroraHex.phaseDeepener), dark: Color(hex: "B07DC8"))
    static let phaseFractionation = Color(light: Color(hex: PinkAuroraHex.phaseFractionation), dark: Color(hex: "E8B07A"))
    static let phaseSuggestion    = Color(light: Color(hex: PinkAuroraHex.phaseSuggestion), dark: Color(hex: "E87CB8"))
    static let phaseAwakening     = Color(light: Color(hex: PinkAuroraHex.phaseAwakening), dark: Color(hex: "F5D08E"))

    // MARK: Flash Mode Colors (light-therapy output — hue-locked, NEVER adaptive)
    // flashOn must stay bright/visible; flashOff goes to true void.
    static let flashOn  = Color(hex: "F8C8D4")
    static let flashOff = Color.voidDeep
}
```

Then add `bgDeep` to BOTH accessor blocks in the same file:

In `extension Color` (after the `bgCard` line):
```swift
    static let bgDeep             = TranceColors.bgDeep
```

In `extension ShapeStyle where Self == Color` (after the `bgCard` line):
```swift
    static var bgDeep: Color             { .bgDeep }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/AdaptiveTokenTests -only-testing:IlumionateTests/LiminalPaletteTests -only-testing:IlumionateTests/PinkAuroraPaletteTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **` — adaptive tests AND the pre-existing Liminal tests both pass (dark values unchanged).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TranceDesignSystem.swift IlumionateTests/AdaptiveTokenTests.swift
git commit -m "feat(theme): semantic tokens adapt light/dark; flash colors hue-locked"
```

---

### Task 3: ThemeMode setting + Settings picker

**Files:**
- Create: `Ilumionate/ThemeMode.swift`
- Modify: `Ilumionate/ContentView.swift:142`
- Modify: `Ilumionate/ProfileSettingsView.swift:92` (remove forced dark) and add `@AppStorage`
- Modify: `Ilumionate/ProfileSettingsView+Sections.swift:114-131` (coreSettingsSection)
- Test: `IlumionateTests/ThemeModeTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/ThemeModeTests.swift`:

```swift
//
//  ThemeModeTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct ThemeModeTests {

    @Test("Raw values match the persisted appearanceMode strings")
    func rawValues() {
        #expect(ThemeMode.system.rawValue == "system")
        #expect(ThemeMode.light.rawValue == "light")
        #expect(ThemeMode.dark.rawValue == "dark")
    }

    @Test("system maps to nil colorScheme; light/dark map to their schemes")
    func colorSchemeMapping() {
        #expect(ThemeMode.system.colorScheme == nil)
        #expect(ThemeMode.light.colorScheme == .light)
        #expect(ThemeMode.dark.colorScheme == .dark)
    }

    @Test("Unknown persisted string falls back to system")
    func unknownFallsBackToSystem() {
        #expect(ThemeMode(persisted: "bogus") == .system)
        #expect(ThemeMode(persisted: nil) == .system)
        #expect(ThemeMode(persisted: "light") == .light)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/ThemeModeTests 2>&1 | tail -20`
Expected: build FAILS with "cannot find 'ThemeMode' in scope"

- [ ] **Step 3: Implement ThemeMode**

Create `Ilumionate/ThemeMode.swift`:

```swift
//
//  ThemeMode.swift
//  Ilumionate
//
//  App-wide appearance selection persisted under the existing
//  AppSettingsManager.Key.appearanceMode UserDefaults key.
//

import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// Tolerant of legacy/unknown persisted strings.
    init(persisted: String?) {
        self = persisted.flatMap(ThemeMode.init(rawValue:)) ?? .system
    }

    var displayName: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// nil means "follow the device setting".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/ThemeModeTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Wire the root**

In `Ilumionate/ContentView.swift`, add this property alongside the other `@AppStorage` properties near the top of `struct ContentView` (search for `userFrequencyMultiplierPref` to find them):

```swift
    @AppStorage("appearanceMode") private var appearanceModeRaw = ThemeMode.system.rawValue
```

Then change line 142 from:

```swift
        .preferredColorScheme(.dark)
```

to:

```swift
        .preferredColorScheme(ThemeMode(persisted: appearanceModeRaw).colorScheme)
```

- [ ] **Step 6: Settings UI**

In `Ilumionate/ProfileSettingsView.swift`:
1. Add below the other Core Settings `@AppStorage` properties (after line 28, `autoLockEnabled`):

```swift
    @AppStorage("appearanceMode") var appearanceModeRaw = ThemeMode.system.rawValue
```

2. Delete line 92: `.preferredColorScheme(.dark)`

In `Ilumionate/ProfileSettingsView+Sections.swift`, inside `coreSettingsSection`'s `VStack` (after the "Keep Screen Awake" `settingsToggle`, before the VStack closes at line 129), add:

```swift
                HStack(spacing: TranceSpacing.list) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.blush)
                        .frame(width: 24)
                    Text("Appearance")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Picker("Appearance", selection: $appearanceModeRaw) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .tint(.textSecondary)
                }
```

- [ ] **Step 7: Build**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add Ilumionate/ThemeMode.swift Ilumionate/ContentView.swift Ilumionate/ProfileSettingsView.swift Ilumionate/ProfileSettingsView+Sections.swift IlumionateTests/ThemeModeTests.swift
git commit -m "feat(theme): Light/Dark/System toggle wired to appearanceMode"
```

---

### Task 4: Session player always dark

**Files:**
- Modify: `Ilumionate/UnifiedPlayerView.swift:107`

- [ ] **Step 1: Force dark chrome on the player**

The spec requires the player to stay dark regardless of app theme (entrainment visuals need the void). Change line 107 from:

```swift
        .preferredColorScheme(viewModel.useDarkChrome ? .dark : .light)
```

to:

```swift
        // Player is always dark: entrainment visuals need the void backdrop,
        // regardless of the app-wide Pink Aurora theme.
        .preferredColorScheme(.dark)
```

Do NOT touch `useDarkChrome` in `UnifiedPlayerViewModel.swift` — it still styles text over bright flash content (`labelColor`/`secondaryLabelColor`/`accentColor` at lines 449-451) and that logic is unchanged.

- [ ] **Step 2: Build**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/UnifiedPlayerView.swift
git commit -m "feat(theme): session player chrome always dark"
```

---

### Task 5: AuroraBackground light variant + DesignSystem component migration

**Files:**
- Modify: `Ilumionate/DesignSystem/AuroraBackground.swift`
- Modify: `Ilumionate/DesignSystem/ContentTypeStyle.swift`, `GlowButton.swift`, `LiminalSurface.swift`, `LumeOrb.swift`, `PhaseTimeline.swift`, `WaveformShape.swift`
- Modify: `Ilumionate/TranceDesignSystem.swift:172-209` (TranceShadow)
- Modify: `Ilumionate/TranceTabBar.swift`

- [ ] **Step 1: AuroraBackground adapts**

Replace the `body` and `blob` pieces of `Ilumionate/DesignSystem/AuroraBackground.swift` so the void gradient uses adaptive tokens and blob opacity lightens in light mode. Full new file body (keep the header comment, add a line noting the light variant):

```swift
struct AuroraBackground: View {
    /// Optional zone tint. nil = neutral teal/blue/violet mix.
    var mood: BrainwaveCategory? = nil
    /// When true, ambient drift halts (e.g. during an active flash session).
    var isPaused: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Void base (dark) / dawn wash (light) via adaptive tokens
            RadialGradient(
                colors: [Color.bgPrimary, Color.bgDeep],
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
        .background(Color.bgDeep.ignoresSafeArea())
        .accessibilityHidden(true)
    }

    private var blobColors: [Color] {
        if let mood {
            return [mood.haloColor, .roseDeep, mood.haloColor.opacity(0.7)]
        }
        return [.roseDeep, .lavender, .roseGold]
    }

    /// Aurora blobs read heavier on the blush dawn wash; back them off in light mode.
    private var blobOpacity: Double {
        colorScheme == .light ? 0.18 : 0.35
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
            .opacity(blobOpacity)
    }
}

#Preview("Neutral") { AuroraBackground() }
#Preview("Sleep mood") { AuroraBackground(mood: .sleep) }
#Preview("Light") { AuroraBackground().environment(\.colorScheme, .light) }
```

- [ ] **Step 2: Migrate the other DesignSystem files with the mapping table**

Apply this exact substitution in `ContentTypeStyle.swift`, `GlowButton.swift`, `LiminalSurface.swift`, `LumeOrb.swift`, `PhaseTimeline.swift`, `WaveformShape.swift`, and `TranceTabBar.swift` (both `Color.x` and `.x` shorthand forms):

| Raw (Liminal) | Semantic replacement |
|---|---|
| `voidDeep` | `bgDeep` |
| `voidPrimary` | `bgPrimary` |
| `voidElevated` | `bgSecondary` |
| `auroraTeal` | `roseGold` |
| `auroraBlue` | `roseDeep` |
| `auroraViolet` | `lavender` |
| `auroraPink` | `blush` |
| `textBright` | `textPrimary` |
| `textDim` | `textSecondary` |
| `textGhost` | `textLight` |

In `Ilumionate/TranceDesignSystem.swift`, `TranceShadow` (lines 172-209): replace `Color.auroraBlue` with `Color.roseDeep` (card + elevated) and `Color.auroraTeal` with `Color.roseGold` (button).

**Exclusions — do NOT touch:** `LiminalPalette.swift` (definitions), `PinkAuroraPalette.swift`, the `flashOn`/`flashOff` lines in `TranceColors`, and `ReaderDisplayPreferences.swift` (handled in Task 7 — its `ReaderTheme.void` case intentionally keeps raw void colors).

After each file, spot-check with: `grep -n "aurora\|void\|textBright\|textDim\|textGhost" <file>` — remaining hits must be comments or the exclusions above.

- [ ] **Step 3: Build**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/DesignSystem Ilumionate/TranceDesignSystem.swift Ilumionate/TranceTabBar.swift
git commit -m "feat(theme): design-system components adapt via semantic tokens"
```

---

### Task 6: App screen migration

**Files (modify, same mapping table as Task 5):**
- `Ilumionate/HomeStreakPill.swift`, `HomeView.swift`
- `Ilumionate/LibraryAllFilesView.swift`, `LibraryShelves.swift`, `LibraryView.swift`
- `Ilumionate/MindMachineView.swift`, `MindMachineView+Binaural.swift`
- `Ilumionate/MiniPlayerBar.swift`, `OnboardingView.swift`
- `Ilumionate/PlaylistArtwork.swift`, `PlaylistGridTile.swift`, `PlaylistHeroCard.swift`
- `Ilumionate/SatelliteButton.swift`, `SessionCardViews.swift`, `SessionDetailView.swift`, `StreamingArtworkTile.swift`
- TextTrance (non-reader-screen surfaces): `ReaderSectionNavigatorSheet.swift`, `ReaderSettingsDrawer.swift`, `ReadingSourceDirectoryView.swift`, `ScriptTheme+Style.swift`, `TextTranceLibraryView.swift`, `TextTranceSetupView.swift`

**Exceptions (keep raw void/aurora colors — these render only inside the always-dark player):**
- `Ilumionate/PlayerHeroOrb.swift`
- `Ilumionate/ScrubWhisperLine.swift`

- [ ] **Step 1: Apply the Task 5 mapping table to every file listed above**

Mechanical substitution, file by file. Where a raw color is used inside a gradient or opacity chain (e.g. `Color.voidPrimary.opacity(0.88)` in `TextTranceSetupView.swift:103`), keep the modifier chain and swap only the base color (`Color.bgPrimary.opacity(0.88)`).

- [ ] **Step 2: Verify nothing outside the exceptions still references raw palette names**

Run:
```bash
grep -rln "voidDeep\|voidPrimary\|voidElevated\|auroraTeal\|auroraBlue\|auroraViolet\|auroraPink\|textBright\|textDim\|textGhost" Ilumionate --include="*.swift" | sort
```
Expected output is exactly:
```
Ilumionate/DesignSystem/LiminalPalette.swift
Ilumionate/DesignSystem/PinkAuroraPalette.swift
Ilumionate/PlayerHeroOrb.swift
Ilumionate/ScrubWhisperLine.swift
Ilumionate/TextTrance/ReaderDisplayPreferences.swift
Ilumionate/TranceDesignSystem.swift
```
(`TranceDesignSystem.swift` hits are the adaptive token definitions and `flashOff`; `ReaderDisplayPreferences.swift` is Task 7.)

- [ ] **Step 3: Build and run full non-analyzer test suite**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/ContentTypeStyleTests -only-testing:IlumionateTests/LiminalPaletteTests -only-testing:IlumionateTests/AdaptiveTokenTests 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add -A Ilumionate
git commit -m "feat(theme): migrate app screens to adaptive semantic tokens"
```

---

### Task 7: Reader color mode + Dawn theme

**Files:**
- Modify: `Ilumionate/TextTrance/ReaderDisplayPreferences.swift`
- Modify: `Ilumionate/TextTrance/ReaderSettingsDrawer.swift:207-238` (form section)
- Modify: `Ilumionate/TextTrance/TextTrancePlayerView.swift`
- Test: `IlumionateTests/ReaderColorModeTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/ReaderColorModeTests.swift`:

```swift
//
//  ReaderColorModeTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct ReaderColorModeTests {

    @Test("Default color mode is followApp")
    func defaultIsFollowApp() {
        #expect(ReaderDisplayPreferences.standard.colorMode == .followApp)
    }

    @Test("Legacy persisted JSON without colorMode decodes to followApp")
    func legacyDecoding() throws {
        let legacy = """
        {"theme":"void","font":"monospaced","fontScale":1.0,"lineSpacing":1.0,
         "orpColor":"teal","backgroundBrightness":0.5,"hideControls":false,
         "dyslexiaFriendly":false}
        """.data(using: .utf8)!
        let prefs = try JSONDecoder().decode(ReaderDisplayPreferences.self, from: legacy)
        #expect(prefs.colorMode == .followApp)
        #expect(prefs.theme == .void)
    }

    @Test("followApp + light app swaps dark themes to dawn")
    func followAppLightSwapsToDawn() {
        var prefs = ReaderDisplayPreferences.standard   // theme: .void
        prefs.colorMode = .followApp
        #expect(prefs.resolved(appColorScheme: .light).theme == .dawn)
        #expect(prefs.resolved(appColorScheme: .dark).theme == .void)
    }

    @Test("Explicit dark mode swaps light themes to void")
    func explicitDarkSwapsToVoid() {
        var prefs = ReaderDisplayPreferences.standard
        prefs.theme = .paper
        prefs.colorMode = .dark
        #expect(prefs.resolved(appColorScheme: .light).theme == .void)
    }

    @Test("Explicit light mode leaves light themes untouched")
    func explicitLightKeepsLightThemes() {
        var prefs = ReaderDisplayPreferences.standard
        prefs.theme = .sepia
        prefs.colorMode = .light
        #expect(prefs.resolved(appColorScheme: .dark).theme == .sepia)
    }

    @Test("Resolved scheme follows mode")
    func resolvedScheme() {
        var prefs = ReaderDisplayPreferences.standard
        prefs.colorMode = .light
        #expect(prefs.resolvedScheme(appColorScheme: .dark) == .light)
        prefs.colorMode = .followApp
        #expect(prefs.resolvedScheme(appColorScheme: .dark) == .dark)
    }

    @Test("Dawn theme is light with ink text and shows phase atmosphere")
    func dawnThemeProperties() {
        #expect(ReaderTheme.dawn.isDark == false)
        #expect(ReaderTheme.dawn.showsPhaseAtmosphere == true)
        #expect(ReaderTheme.void.isDark == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/ReaderColorModeTests 2>&1 | tail -20`
Expected: build FAILS — no `colorMode`, `.dawn`, `isDark`, `resolved`, or `resolvedScheme` yet.

- [ ] **Step 3: Implement in ReaderDisplayPreferences.swift**

Four edits:

**(a)** Add `.dawn` to `ReaderTheme` and an `isDark` property. In the enum, add the case after `case void`:

```swift
    case dawn
```

Add to `displayName`: `case .dawn: return "Dawn"`.
Add to `background`: `case .dawn: return .dawnPrimary`.
Add to `text`: change the first case line to `case .void, .dusk, .highContrast: return .textBright` (unchanged) and add `case .dawn: return Color(hex: PinkAuroraHex.textInk)`.
Add to `secondaryText`: `case .dawn: return Color(hex: PinkAuroraHex.textMuted)`.
In `showsPhaseAtmosphere`: change to `case .void, .dusk, .dawn: return true`.
Add after `showsPhaseAtmosphere`:

```swift
    var isDark: Bool {
        switch self {
        case .void, .dusk, .highContrast: return true
        case .paper, .sepia, .dawn: return false
        }
    }
```

**(b)** Add the color mode enum (top level, after `ReaderTheme`):

```swift
enum ReaderColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case followApp
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .followApp: return "Follow App"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
```

**(c)** Add the stored property with legacy-safe decoding. Add `var colorMode: ReaderColorMode` to the struct, add `colorMode: ReaderColorMode = .followApp` as the last parameter of `init(...)` (assign `self.colorMode = colorMode`), and add a custom decoder so old persisted prefs still load:

```swift
    private enum CodingKeys: String, CodingKey {
        case theme, font, fontScale, lineSpacing, orpColor
        case backgroundBrightness, hideControls, dyslexiaFriendly, colorMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decode(ReaderTheme.self, forKey: .theme)
        font = try c.decode(ReaderFont.self, forKey: .font)
        fontScale = try c.decode(Double.self, forKey: .fontScale)
        lineSpacing = try c.decode(Double.self, forKey: .lineSpacing)
        orpColor = try c.decode(ReaderORPColor.self, forKey: .orpColor)
        backgroundBrightness = try c.decode(Double.self, forKey: .backgroundBrightness)
        hideControls = try c.decode(Bool.self, forKey: .hideControls)
        dyslexiaFriendly = try c.decode(Bool.self, forKey: .dyslexiaFriendly)
        colorMode = try c.decodeIfPresent(ReaderColorMode.self, forKey: .colorMode) ?? .followApp
    }
```

**(d)** Migrate `ReaderORPColor.color` (same file, lines 138-146) to semantic tokens so the highlight color adapts with the reader's resolved scheme (the environment override in Step 6 makes these resolve per reader mode):

```swift
    var color: Color {
        switch self {
        case .teal: return .roseGold
        case .blue: return .roseDeep
        case .amber: return .warmAccent
        case .pink: return .blush
        case .white: return Color(light: Color(hex: PinkAuroraHex.textInk), dark: .white)
        }
    }
```

(The "White" option becomes ink in light mode — pure white on the Dawn background would be invisible. Its display name stays "White"; it means "match body text".)

**(e)** Add resolution helpers to the `extension ReaderDisplayPreferences` block (after `pivotColor`):

```swift
    /// The color scheme the reader should render in, honoring the override.
    func resolvedScheme(appColorScheme: ColorScheme) -> ColorScheme {
        switch colorMode {
        case .followApp: return appColorScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// A copy whose theme matches the resolved scheme: dark themes swap to
    /// .dawn under a light scheme; light themes swap to .void under dark.
    func resolved(appColorScheme: ColorScheme) -> ReaderDisplayPreferences {
        let scheme = resolvedScheme(appColorScheme: appColorScheme)
        var copy = self
        if scheme == .light && theme.isDark {
            copy.theme = .dawn
        } else if scheme == .dark && !theme.isDark {
            copy.theme = .void
        }
        return copy
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/ReaderColorModeTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Drawer UI**

In `Ilumionate/TextTrance/ReaderSettingsDrawer.swift`, inside the `Section("Reader display")` (line 208), add ABOVE the existing `Picker("Theme", ...)`:

```swift
            Picker("Reader mode", selection: $preferences.colorMode) {
                ForEach(ReaderColorMode.allCases) {
                    Text($0.displayName).tag($0)
                }
            }
```

- [ ] **Step 6: Apply resolution in the player view**

In `Ilumionate/TextTrance/TextTrancePlayerView.swift`:
1. Add to the main view struct's properties: `@Environment(\.colorScheme) private var appColorScheme`
2. Add a computed property:

```swift
    private var displayPrefs: ReaderDisplayPreferences {
        session.displayPreferences.resolved(appColorScheme: appColorScheme)
    }
```

3. Replace every read of `session.displayPreferences` used for RENDERING with `displayPrefs` (lines 47, 56, 180, 194, 209, 300 as of this writing — background, atmosphere flag, child-view `displayPreferences:`/`preferences:` arguments, text colors). Keep line 141's `.onChange(of: session.displayPreferences.hideControls)` reading the stored prefs (it observes the setting, not a rendered color).
4. On the player's root view (the top-level container that line 47's background belongs to), add:

```swift
        .environment(\.colorScheme, session.displayPreferences.resolvedScheme(appColorScheme: appColorScheme))
```

so adaptive tokens (ORP colors, phase atmosphere) inside the reader resolve to the reader's mode, not the app's.

Note: child views receiving a `ReaderDisplayPreferences` value (the `displayPreferences:`/`preferences:` call sites) get the resolved copy, so their internals need no changes.

- [ ] **Step 7: Build**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add Ilumionate/TextTrance IlumionateTests/ReaderColorModeTests.swift
git commit -m "feat(reader): Dawn theme + Follow App/Light/Dark reader color mode"
```

---

### Task 8: Full verification

- [ ] **Step 1: Run all plan test structs together**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IlumionateTests/PinkAuroraPaletteTests -only-testing:IlumionateTests/AdaptiveTokenTests -only-testing:IlumionateTests/ThemeModeTests -only-testing:IlumionateTests/ReaderColorModeTests -only-testing:IlumionateTests/LiminalPaletteTests -only-testing:IlumionateTests/AppSettingsManagerTests -only-testing:IlumionateTests/ContentTypeStyleTests 2>&1 | tail -10`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 2: Simulator smoke test — light mode**

Boot an iPhone 17 simulator, install and launch the app, then in Profile & Settings set Appearance to Light. Screenshot and visually verify: Home, Library, Profile & Settings, and the Text Trance library render on blush/dawn backgrounds with hot-pink accents and readable ink text.

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null; xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17' build
# install/launch via the usual app bundle id, then:
xcrun simctl io booted screenshot /tmp/light-home.png
```

- [ ] **Step 3: Verify always-dark surfaces in light mode**

With Appearance = Light: open a session in the player — chrome and backdrop must render void-dark. Start a flash segment — flash colors unchanged. Open the reader with mode Follow App — reader renders Dawn; switch reader mode to Dark — reader renders Void while the rest of the app stays light.

- [ ] **Step 4: Verify dark mode is unchanged**

Set Appearance to Dark: screenshot Home/Library and confirm the Liminal look is pixel-equivalent to before (spot-check against `git stash` of a pre-change build if in doubt — token dark values are byte-identical so any drift is a migration mistake).

- [ ] **Step 5: Final commit if fixups were needed**

```bash
git add -A && git commit -m "fix(theme): light-mode polish from simulator verification"
```
