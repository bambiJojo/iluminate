# Focus Spots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional pair of opaque black focus spots rendered over the player's light fields, with position, diameter and horizontal spacing dialled in through a calibration screen reached from Session Defaults.

**Architecture:** A render-time display preference only — nothing enters `LightSession`, the session JSON schema, or `SessionGenerator`. Geometry persists as a JSON blob in `UserDefaults` (`focusSpots`) beside a plain Bool (`focusSpotsEnabled`), exactly mirroring how `FlashTint`/`FlashTintPreference` and `steadyLightEnabled` already work. Pure, view-free types hold the geometry and the visibility rule so both are unit-testable; a single overlay layer in `UnifiedPlayerView`'s ZStack renders them for every qualifying mode.

**Tech Stack:** Swift 6.2, SwiftUI, `@AppStorage`/`UserDefaults`, Swift Testing. iOS 26 / macOS 26. No new dependencies.

**Spec:** [`docs/superpowers/specs/2026-08-10-focus-spots-design.md`](../specs/2026-08-10-focus-spots-design.md)

---

## File Structure

**New — `Ilumionate/FocusSpots/`**

| File | Responsibility |
|---|---|
| `FocusSpotSettings.swift` | Geometry model, ranges, clamping, detent snapping, `FocusSpotPreference` persistence |
| `FocusSpotLayout.swift` | Pure size → two centre points resolver |
| `FocusSpotVisibility.swift` | Pure "should spots render?" rule + `PlayerMode.supportsFocusSpots` |
| `FocusSpotField.swift` | Draws two black circles for a given `FocusSpotSettings` |
| `FocusSpotOverlay.swift` | Reads stored preference + applies the gate, delegates drawing to `FocusSpotField` |
| `FocusSpotCalibrationView.swift` | Full-screen calibration surface |

> The spec listed one `FocusSpotOverlay.swift`. It is split into `FocusSpotField` (draws arbitrary settings — needed by the calibration preview) and `FocusSpotOverlay` (reads storage and gates), keeping one primary type per file as `CLAUDE.md` requires.

**New — `IlumionateTests/`:** `FocusSpotSettingsTests.swift`, `FocusSpotLayoutTests.swift`, `FocusSpotVisibilityTests.swift`

> The spec listed a fourth suite, `FocusSpotDetentTests`. Detent snapping is a static method on `FocusSpotSettings`, so its tests live in `FocusSpotSettingsTests` under a `// MARK: - Detent snapping` heading rather than in a suite of their own.

**Modified**

| File | Change |
|---|---|
| `Ilumionate/AppSettingsManager.swift` | Two keys + both in `resetPreferences` |
| `Ilumionate/UnifiedPlayerView.swift` | One overlay layer above `backgroundLayer` |
| `Ilumionate/ProfileSettingsView.swift` | Storage, calibration state, full-screen cover |
| `Ilumionate/ProfileSettingsView+Sections.swift` | Toggle + Calibrate row in Session Defaults |

`Ilumionate/` and `IlumionateTests/` are `PBXFileSystemSynchronizedRootGroup`s — new files join their targets automatically. **Do not edit `project.pbxproj`.**

## Commands you will use

Build (macOS):

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

Build (iOS Simulator):

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Run one test suite (fastest loop — macOS):

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/FocusSpotSettingsTests
```

---

## Task 1: Geometry model and persistence

**Files:**
- Create: `Ilumionate/FocusSpots/FocusSpotSettings.swift`
- Modify: `Ilumionate/AppSettingsManager.swift` (keys near line 22, reset near line 171)
- Test: `IlumionateTests/FocusSpotSettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `IlumionateTests/FocusSpotSettingsTests.swift`:

```swift
//
//  FocusSpotSettingsTests.swift
//  IlumionateTests
//
//  Focus spot geometry is a stored display preference. A corrupt or
//  hand-edited value must degrade to something renderable rather than
//  producing spots the size of the screen or off the edge of it.
//

import Foundation
import Testing

@testable import Ilumionate

@Suite("Focus spot settings")
struct FocusSpotSettingsTests {

    // MARK: - Defaults and clamping

    @Test("Defaults sit in the upper third")
    func defaultsToUpperThird() {
        #expect(FocusSpotSettings.default.verticalPosition == 1.0 / 3.0)
        #expect(FocusSpotSettings.default.horizontalSpacing == 180)
        #expect(FocusSpotSettings.default.diameter == 48)
    }

    @Test("Out-of-range values clamp into their ranges")
    func outOfRangeValuesClamp() {
        let wild = FocusSpotSettings(
            verticalPosition: 5,
            horizontalSpacing: -100,
            diameter: 9_000
        ).clamped

        #expect(wild.verticalPosition == FocusSpotSettings.verticalPositionRange.upperBound)
        #expect(wild.horizontalSpacing == FocusSpotSettings.horizontalSpacingRange.lowerBound)
        #expect(wild.diameter == FocusSpotSettings.diameterRange.upperBound)
    }

    @Test("Non-finite values fall back to the defaults")
    func nonFiniteValuesFallBack() {
        let broken = FocusSpotSettings(
            verticalPosition: .nan,
            horizontalSpacing: .infinity,
            diameter: .nan
        ).clamped

        #expect(broken.verticalPosition == FocusSpotSettings.default.verticalPosition)
        #expect(broken.diameter == FocusSpotSettings.default.diameter)
        #expect(broken.horizontalSpacing == FocusSpotSettings.horizontalSpacingRange.upperBound)
    }

    // MARK: - Detent snapping

    @Test("A value within tolerance snaps to its detent")
    func nearValuesSnap() {
        #expect(FocusSpotSettings.snappingVerticalPosition(0.34) == 1.0 / 3.0)
        #expect(FocusSpotSettings.snappingVerticalPosition(0.505) == 0.5)
        #expect(FocusSpotSettings.snappingVerticalPosition(0.655) == 2.0 / 3.0)
    }

    @Test("A value outside tolerance is left alone")
    func farValuesDoNotSnap() {
        #expect(FocusSpotSettings.snappingVerticalPosition(0.42) == 0.42)
        #expect(FocusSpotSettings.snappingVerticalPosition(0.6) == 0.6)
    }

    @Test("Snapping is idempotent on an exact detent")
    func snappingIsIdempotent() {
        for detent in FocusSpotSettings.verticalDetents {
            #expect(FocusSpotSettings.snappingVerticalPosition(detent) == detent)
        }
    }

    @Test("Snapping clamps before it snaps")
    func snappingClamps() {
        #expect(
            FocusSpotSettings.snappingVerticalPosition(-3)
                == FocusSpotSettings.verticalPositionRange.lowerBound
        )
    }

    // MARK: - Persistence

    @Test("Unset preference returns the defaults")
    func unsetReturnsDefaults() throws {
        let defaults = try makeDefaults()

        #expect(FocusSpotPreference.current(defaults: defaults) == .default)
        #expect(FocusSpotPreference.isEnabled(defaults: defaults) == false)
    }

    @Test("Geometry round-trips through UserDefaults")
    func geometryRoundTrips() throws {
        let defaults = try makeDefaults()
        let settings = FocusSpotSettings(
            verticalPosition: 0.5,
            horizontalSpacing: 220,
            diameter: 64
        )

        FocusSpotPreference.set(settings, defaults: defaults)

        #expect(FocusSpotPreference.current(defaults: defaults) == settings)
    }

    @Test("Enablement round-trips through UserDefaults")
    func enablementRoundTrips() throws {
        let defaults = try makeDefaults()

        FocusSpotPreference.setEnabled(true, defaults: defaults)
        #expect(FocusSpotPreference.isEnabled(defaults: defaults))

        FocusSpotPreference.setEnabled(false, defaults: defaults)
        #expect(FocusSpotPreference.isEnabled(defaults: defaults) == false)
    }

    @Test("Corrupt stored data falls back instead of crashing")
    func corruptDataFallsBack() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: AppSettingsManager.Key.focusSpots)

        #expect(FocusSpotPreference.current(defaults: defaults) == .default)
    }

    @Test("Stored out-of-range geometry is clamped on read")
    func storedValuesAreClampedOnRead() throws {
        let defaults = try makeDefaults()
        let json = #"{"verticalPosition":42,"horizontalSpacing":5,"diameter":900}"#
        defaults.set(Data(json.utf8), forKey: AppSettingsManager.Key.focusSpots)

        let read = FocusSpotPreference.current(defaults: defaults)

        #expect(read.verticalPosition == FocusSpotSettings.verticalPositionRange.upperBound)
        #expect(read.horizontalSpacing == FocusSpotSettings.horizontalSpacingRange.lowerBound)
        #expect(read.diameter == FocusSpotSettings.diameterRange.upperBound)
    }

    @Test("Preference reset turns the feature off and drops the geometry")
    @MainActor
    func resetClearsBothKeys() throws {
        let defaults = try makeDefaults()
        FocusSpotPreference.setEnabled(true, defaults: defaults)
        FocusSpotPreference.set(
            FocusSpotSettings(verticalPosition: 0.5, horizontalSpacing: 300, diameter: 100),
            defaults: defaults
        )

        AppSettingsManager.resetPreferences(
            defaults: defaults,
            resetAnalysisPreferences: false
        )

        #expect(FocusSpotPreference.isEnabled(defaults: defaults) == false)
        #expect(FocusSpotPreference.current(defaults: defaults) == .default)
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> UserDefaults {
        let name = "FocusSpotSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/FocusSpotSettingsTests
```

Expected: **BUILD FAILED** — `cannot find 'FocusSpotSettings' in scope`.

- [ ] **Step 3: Create the model and persistence**

Create `Ilumionate/FocusSpots/FocusSpotSettings.swift`:

```swift
//
//  FocusSpotSettings.swift
//  Ilumionate
//
//  Geometry for the optional pair of black focus spots drawn over the light
//  field — holes punched in the light for the eye to rest on.
//
//  Like `FlashTint`, this is a render-time display preference only. Nothing
//  here reaches `LightSession`, the session JSON schema, or `SessionGenerator`,
//  which is the whole point of keeping it in user preferences rather than in
//  the score.
//
//  Diameter and spacing are POINTS, not fractions of the screen: they are
//  aimed at a physical thing — your eyes — and should not rescale when the
//  window does. Vertical position is a FRACTION, because "upper third" is
//  inherently proportional and should hold across portrait, landscape, and a
//  resized Mac window.
//

import Foundation

struct FocusSpotSettings: Codable, Equatable, Sendable {
    /// Fraction of field height where the spot centres sit. 0 = top, 1 = bottom.
    var verticalPosition: Double
    /// Points between the two spot centres.
    var horizontalSpacing: Double
    /// Diameter of each spot, in points.
    var diameter: Double

    // MARK: - Ranges

    static let verticalPositionRange: ClosedRange<Double> = 0.1...0.9
    static let horizontalSpacingRange: ClosedRange<Double> = 40...400
    static let diameterRange: ClosedRange<Double> = 16...120

    /// The three vertical anchors the calibration slider snaps to: upper
    /// third, centre, lower third.
    static let verticalDetents: [Double] = [1.0 / 3.0, 0.5, 2.0 / 3.0]

    /// How close the slider must come to a detent before it snaps.
    static let detentTolerance: Double = 0.02

    static let `default` = FocusSpotSettings(
        verticalPosition: 1.0 / 3.0,
        horizontalSpacing: 180,
        diameter: 48
    )

    // MARK: - Clamping

    /// Every field forced into range, applied on read and on write so a
    /// hand-edited or partially-written value can never produce an
    /// unrenderable field.
    var clamped: FocusSpotSettings {
        FocusSpotSettings(
            verticalPosition: Self.clamp(
                verticalPosition,
                to: Self.verticalPositionRange,
                fallback: Self.default.verticalPosition
            ),
            horizontalSpacing: Self.clamp(
                horizontalSpacing,
                to: Self.horizontalSpacingRange,
                fallback: Self.default.horizontalSpacing
            ),
            diameter: Self.clamp(
                diameter,
                to: Self.diameterRange,
                fallback: Self.default.diameter
            )
        )
    }

    /// Snaps a vertical position onto the nearest detent when it is within
    /// tolerance, so upper third / centre / lower third stay one flick away
    /// while everything between them is still reachable.
    static func snappingVerticalPosition(_ value: Double) -> Double {
        let bounded = clamp(
            value,
            to: verticalPositionRange,
            fallback: Self.default.verticalPosition
        )
        guard
            let nearest = verticalDetents.min(by: {
                abs($0 - bounded) < abs($1 - bounded)
            })
        else {
            return bounded
        }
        return abs(nearest - bounded) <= detentTolerance ? nearest : bounded
    }

    /// `.nan` and `.infinity` survive `min`/`max` in ways that produce an
    /// unrenderable field, so they are rejected before clamping.
    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard !value.isNaN else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Persistence

/// Reads and writes the stored preference.
///
/// Falls back to `.default` for an unset key, an undecodable value, and an
/// out-of-range one — a bad write can never leave the field unrenderable.
enum FocusSpotPreference {

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: AppSettingsManager.Key.focusSpotsEnabled)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: AppSettingsManager.Key.focusSpotsEnabled)
    }

    static func current(defaults: UserDefaults = .standard) -> FocusSpotSettings {
        guard
            let data = defaults.data(forKey: AppSettingsManager.Key.focusSpots),
            let decoded = try? JSONDecoder().decode(FocusSpotSettings.self, from: data)
        else {
            return .default
        }
        return decoded.clamped
    }

    static func set(_ settings: FocusSpotSettings, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings.clamped) else { return }
        defaults.set(data, forKey: AppSettingsManager.Key.focusSpots)
    }
}
```

- [ ] **Step 4: Add the keys to `AppSettingsManager`**

In `Ilumionate/AppSettingsManager.swift`, add after the `flashTint` key (line 22):

```swift
        static let focusSpotsEnabled = "focusSpotsEnabled"
        static let focusSpots = "focusSpots"
```

And in `resetPreferences`, immediately after `defaults.removeObject(forKey: Key.flashTint)` (line 171):

```swift
        defaults.set(false, forKey: Key.focusSpotsEnabled)
        defaults.removeObject(forKey: Key.focusSpots)
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/FocusSpotSettingsTests
```

Expected: **TEST SUCCEEDED**, 13 tests passing.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/FocusSpots/FocusSpotSettings.swift Ilumionate/AppSettingsManager.swift IlumionateTests/FocusSpotSettingsTests.swift
git commit -m "feat(focus-spots): add geometry model and stored preference"
```

---

## Task 2: Geometry resolver

**Files:**
- Create: `Ilumionate/FocusSpots/FocusSpotLayout.swift`
- Test: `IlumionateTests/FocusSpotLayoutTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `IlumionateTests/FocusSpotLayoutTests.swift`:

```swift
//
//  FocusSpotLayoutTests.swift
//  IlumionateTests
//
//  The resolver is the only thing standing between a stored preference and
//  spots drawn off the edge of a narrow Mac window, so its clamping is
//  tested harder than its happy path.
//

import CoreGraphics
import Foundation
import Testing

@testable import Ilumionate

@Suite("Focus spot layout")
struct FocusSpotLayoutTests {

    private let field = CGSize(width: 400, height: 900)

    private func settings(
        vertical: Double = 1.0 / 3.0,
        spacing: Double = 180,
        diameter: Double = 48
    ) -> FocusSpotSettings {
        FocusSpotSettings(
            verticalPosition: vertical,
            horizontalSpacing: spacing,
            diameter: diameter
        )
    }

    // MARK: - Anchors

    @Test("Each detent lands at its share of the height", arguments: [
        (1.0 / 3.0, 300.0),
        (0.5, 450.0),
        (2.0 / 3.0, 600.0)
    ])
    func detentsMapToExpectedHeight(vertical: Double, expectedY: Double) throws {
        let resolved = try #require(
            FocusSpotLayout.resolve(settings(vertical: vertical), in: field)
        )

        #expect(abs(resolved.left.y - expectedY) < 0.001)
        #expect(resolved.left.y == resolved.right.y)
    }

    // MARK: - Symmetry

    @Test("Centres are symmetric about the midline and ordered left then right")
    func centresAreSymmetric() throws {
        let resolved = try #require(FocusSpotLayout.resolve(settings(), in: field))

        #expect(resolved.left.x < resolved.right.x)
        #expect(abs((resolved.left.x + resolved.right.x) - field.width) < 0.001)
        #expect(abs((resolved.right.x - resolved.left.x) - 180) < 0.001)
    }

    // MARK: - Clamping

    @Test("A field narrower than the spacing keeps both spots fully inside")
    func narrowFieldClampsSpacing() throws {
        let narrow = CGSize(width: 300, height: 600)
        let resolved = try #require(
            FocusSpotLayout.resolve(settings(spacing: 400), in: narrow)
        )

        #expect(resolved.left.x - resolved.diameter / 2 >= 0)
        #expect(resolved.right.x + resolved.diameter / 2 <= narrow.width)
    }

    @Test("A diameter wider than half the field shrinks so two spots fit")
    func oversizedDiameterShrinks() throws {
        let narrow = CGSize(width: 200, height: 600)
        let resolved = try #require(
            FocusSpotLayout.resolve(settings(diameter: 120), in: narrow)
        )

        #expect(resolved.diameter == 100)
    }

    @Test("Extreme vertical positions keep the whole circle on screen", arguments: [0.1, 0.9])
    func extremeVerticalPositionsStayOnScreen(vertical: Double) throws {
        let short = CGSize(width: 400, height: 120)
        let resolved = try #require(
            FocusSpotLayout.resolve(settings(vertical: vertical), in: short)
        )

        #expect(resolved.left.y - resolved.diameter / 2 >= 0)
        #expect(resolved.left.y + resolved.diameter / 2 <= short.height)
    }

    @Test("A degenerate size resolves to nothing", arguments: [
        CGSize(width: 0, height: 0),
        CGSize(width: 400, height: 0),
        CGSize(width: 0, height: 900)
    ])
    func degenerateSizeReturnsNil(size: CGSize) {
        #expect(FocusSpotLayout.resolve(settings(), in: size) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/FocusSpotLayoutTests
```

Expected: **BUILD FAILED** — `cannot find 'FocusSpotLayout' in scope`.

- [ ] **Step 3: Write the resolver**

Create `Ilumionate/FocusSpots/FocusSpotLayout.swift`:

```swift
//
//  FocusSpotLayout.swift
//  Ilumionate
//
//  Turns a stored `FocusSpotSettings` and a field size into two centre
//  points. Pure and view-free so every clamping rule is unit-testable.
//
//  In bilateral flash mode the field is an HStack of two halves; symmetric
//  centres put exactly one spot in each half for any spacing above zero, so
//  bilateral needs no special case here.
//

import CoreGraphics

nonisolated enum FocusSpotLayout {

    struct Resolved: Equatable, Sendable {
        let diameter: CGFloat
        let left: CGPoint
        let right: CGPoint
    }

    /// Resolves the pair against a field, or `nil` when the field has no area
    /// to draw in (a view measured before its first layout pass).
    static func resolve(_ settings: FocusSpotSettings, in size: CGSize) -> Resolved? {
        guard size.width > 0, size.height > 0 else { return nil }

        let requested = settings.clamped

        // Two spots must fit side by side, and one must fit vertically.
        let diameter = min(CGFloat(requested.diameter), size.width / 2, size.height)
        // The outer edges stay inside the field: a Mac window narrowed to
        // 300pt must not push a spot off-screen.
        let spacing = min(CGFloat(requested.horizontalSpacing), size.width - diameter)
        let y = min(
            max(CGFloat(requested.verticalPosition) * size.height, diameter / 2),
            size.height - diameter / 2
        )
        let midX = size.width / 2

        return Resolved(
            diameter: diameter,
            left: CGPoint(x: midX - spacing / 2, y: y),
            right: CGPoint(x: midX + spacing / 2, y: y)
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/FocusSpotLayoutTests
```

Expected: **TEST SUCCEEDED**, 11 tests passing (the parameterised cases count individually).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/FocusSpots/FocusSpotLayout.swift IlumionateTests/FocusSpotLayoutTests.swift
git commit -m "feat(focus-spots): resolve spot geometry against the field size"
```

---

## Task 3: Visibility rule

**Files:**
- Create: `Ilumionate/FocusSpots/FocusSpotVisibility.swift`
- Test: `IlumionateTests/FocusSpotVisibilityTests.swift`

Spots only make sense over a **lit** field. With the mind machine off, `EntrainmentBackground` renders flat `Color.bgPrimary` (`PlayerBackgrounds.swift:113`) and black circles on it would read as a rendering bug.

- [ ] **Step 1: Write the failing tests**

Create `IlumionateTests/FocusSpotVisibilityTests.swift`:

```swift
//
//  FocusSpotVisibilityTests.swift
//  IlumionateTests
//
//  Focus spots must never appear over an unlit backdrop — black circles on
//  flat bgPrimary read as a rendering bug, not a feature.
//

import Foundation
import Testing

@testable import Ilumionate

@Suite("Focus spot visibility")
@MainActor
struct FocusSpotVisibilityTests {

    private func makeSession() -> LightSession {
        LightSession(
            session_name: "Visibility Test",
            duration_sec: 300,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)
            ]
        )
    }

    private func makeAudioFile() -> AudioFile {
        AudioFile(
            id: UUID(),
            filename: "track.m4a",
            duration: 300,
            fileSize: 2048,
            createdDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private var flashMode: PlayerMode {
        .flashMode(
            frequency: 10,
            intensity: 0.75,
            colorTemperature: 3000,
            pattern: .sine,
            binauralEnabled: false,
            binauralCarrier: 200,
            binauralVolume: 0.5
        )
    }

    private var visualField: PlayerMode {
        .visualField(settings: .standard, audioFile: nil, binaural: nil)
    }

    private func isVisible(
        _ mode: PlayerMode,
        isEnabled: Bool = true,
        mindMachineEnabled: Bool = true,
        lightSyncEnabled: Bool = true
    ) -> Bool {
        FocusSpotVisibility.isVisible(
            mode: mode,
            isEnabled: isEnabled,
            mindMachineEnabled: mindMachineEnabled,
            lightSyncEnabled: lightSyncEnabled
        )
    }

    // MARK: - Capability flag

    @Test("Every mode but the visual field supports focus spots")
    func capabilityFlag() {
        #expect(flashMode.supportsFocusSpots)
        #expect(PlayerMode.colorPulse(frequency: 10, intensity: 0.5).supportsFocusSpots)
        #expect(PlayerMode.session(session: makeSession(), audioFile: nil).supportsFocusSpots)
        #expect(PlayerMode.audioLight(audioFile: makeAudioFile()).supportsFocusSpots)
        #expect(PlayerMode.playlist(playlist: Playlist(name: "Evening")).supportsFocusSpots)
        #expect(visualField.supportsFocusSpots == false)
    }

    // MARK: - The gate

    @Test("Disabled means never visible")
    func disabledIsNeverVisible() {
        #expect(isVisible(flashMode, isEnabled: false) == false)
        #expect(
            isVisible(
                PlayerMode.colorPulse(frequency: 10, intensity: 0.5),
                isEnabled: false
            ) == false
        )
    }

    @Test("The raw entrainment fields always show spots when enabled")
    func rawFieldsAlwaysShow() {
        // Neither mode is gated by the mind machine or light sync toggles.
        #expect(isVisible(flashMode, mindMachineEnabled: false, lightSyncEnabled: false))
        #expect(
            isVisible(
                PlayerMode.colorPulse(frequency: 10, intensity: 0.5),
                mindMachineEnabled: false,
                lightSyncEnabled: false
            )
        )
    }

    @Test("Session and playlist follow the mind machine toggle")
    func sessionFollowsMindMachine() {
        let session = PlayerMode.session(session: makeSession(), audioFile: makeAudioFile())
        let playlist = PlayerMode.playlist(playlist: Playlist(name: "Evening"))

        #expect(isVisible(session, mindMachineEnabled: true))
        #expect(isVisible(session, mindMachineEnabled: false) == false)
        #expect(isVisible(playlist, mindMachineEnabled: true))
        #expect(isVisible(playlist, mindMachineEnabled: false) == false)
    }

    @Test("Audio mode follows its own light sync toggle")
    func audioFollowsLightSync() {
        let audio = PlayerMode.audioLight(audioFile: makeAudioFile())

        #expect(isVisible(audio, mindMachineEnabled: false, lightSyncEnabled: true))
        #expect(isVisible(audio, mindMachineEnabled: true, lightSyncEnabled: false) == false)
    }

    @Test("The visual field never shows spots, even when everything is on")
    func visualFieldNeverShows() {
        #expect(isVisible(visualField) == false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/FocusSpotVisibilityTests
```

Expected: **BUILD FAILED** — `cannot find 'FocusSpotVisibility' in scope`.

- [ ] **Step 3: Write the rule**

Create `Ilumionate/FocusSpots/FocusSpotVisibility.swift`:

```swift
//
//  FocusSpotVisibility.swift
//  Ilumionate
//
//  Whether the focus spots should be drawn for a given player mode.
//
//  Spots are holes in a lit field. With the lights off the backdrop is flat
//  `bgPrimary`, and two black circles on it read as a rendering bug — so the
//  gate follows the same "are the lights on?" question the control tray asks
//  (`PlayerControlTray.lightsAreOn`).
//

import Foundation

extension PlayerMode {
    /// Whether this mode renders a light field the spots can sit on.
    ///
    /// The visual field opts out: it is a composed shader scene rather than a
    /// driven light field, and two black holes would fight its composition.
    var supportsFocusSpots: Bool {
        switch self {
        case .visualField:
            return false
        case .session, .flashMode, .colorPulse, .audioLight, .playlist:
            return true
        }
    }
}

nonisolated enum FocusSpotVisibility {

    static func isVisible(
        mode: PlayerMode,
        isEnabled: Bool,
        mindMachineEnabled: Bool,
        lightSyncEnabled: Bool
    ) -> Bool {
        guard isEnabled, mode.supportsFocusSpots else { return false }

        switch mode {
        case .flashMode, .colorPulse: return true
        case .audioLight:             return lightSyncEnabled
        case .session, .playlist:     return mindMachineEnabled
        case .visualField:            return false
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/FocusSpotVisibilityTests
```

Expected: **TEST SUCCEEDED**, 6 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/FocusSpots/FocusSpotVisibility.swift IlumionateTests/FocusSpotVisibilityTests.swift
git commit -m "feat(focus-spots): gate spots on a lit field"
```

---

## Task 4: Render the spots in the player

**Files:**
- Create: `Ilumionate/FocusSpots/FocusSpotField.swift`
- Create: `Ilumionate/FocusSpots/FocusSpotOverlay.swift`
- Modify: `Ilumionate/UnifiedPlayerView.swift:52-55`

No unit test here — this is view composition over already-tested pure types, and the project reaches for UI tests only when a unit test cannot cover the behaviour. Verification is the build plus the manual smoke test in Task 7.

- [ ] **Step 1: Create the field view**

Create `Ilumionate/FocusSpots/FocusSpotField.swift`:

```swift
//
//  FocusSpotField.swift
//  Ilumionate
//
//  Draws the two focus spots for a given geometry.
//
//  Takes its settings as a parameter rather than reading storage, so the
//  calibration screen can render a working copy that has not been saved yet.
//

import SwiftUI

struct FocusSpotField: View {
    let settings: FocusSpotSettings

    @State private var size: CGSize = .zero

    var body: some View {
        ZStack {
            Color.clear

            if let resolved = FocusSpotLayout.resolve(settings, in: size) {
                spot(diameter: resolved.diameter, at: resolved.left)
                spot(diameter: resolved.diameter, at: resolved.right)
            }
        }
        // `onGeometryChange` rather than a GeometryReader: the reader would
        // impose its own layout on a view that must simply fill its parent.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }

    /// Genuinely opaque: the spot is a hole punched in the light, not a
    /// dimming. SwiftUI antialiases the edge; no feather is applied.
    private func spot(diameter: CGFloat, at centre: CGPoint) -> some View {
        Circle()
            .fill(.black)
            .frame(width: diameter, height: diameter)
            .position(centre)
    }
}

#Preview {
    ZStack {
        Color.orange
        FocusSpotField(settings: .default)
    }
    .ignoresSafeArea()
}
```

- [ ] **Step 2: Create the overlay**

Create `Ilumionate/FocusSpots/FocusSpotOverlay.swift`:

```swift
//
//  FocusSpotOverlay.swift
//  Ilumionate
//
//  The player's focus spot layer: reads the stored preference, applies the
//  lit-field gate, and hands the geometry to `FocusSpotField`.
//

import SwiftUI

struct FocusSpotOverlay: View {
    let mode: PlayerMode
    let mindMachineEnabled: Bool
    let lightSyncEnabled: Bool

    @AppStorage("focusSpotsEnabled") private var isEnabled = false
    /// Read as raw data so a change to the stored geometry re-renders a live
    /// session — the same trick `FlashGridBackground` uses for the tint.
    @AppStorage("focusSpots") private var settingsData: Data?

    private var settings: FocusSpotSettings {
        guard
            let settingsData,
            let decoded = try? JSONDecoder().decode(FocusSpotSettings.self, from: settingsData)
        else {
            return .default
        }
        return decoded.clamped
    }

    var body: some View {
        if FocusSpotVisibility.isVisible(
            mode: mode,
            isEnabled: isEnabled,
            mindMachineEnabled: mindMachineEnabled,
            lightSyncEnabled: lightSyncEnabled
        ) {
            FocusSpotField(settings: settings)
                .ignoresSafeArea()
                // Must never intercept the pull-to-reveal drag on the
                // minimal overlay above it.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
```

- [ ] **Step 3: Add the layer to the player**

In `Ilumionate/UnifiedPlayerView.swift`, inside the top-level `ZStack`, insert between `backgroundLayer` (line 54) and `SessionLockView` (line 57):

```swift
            // Layer 1: Background visual surface
            backgroundLayer

            // Layer 1.5: Optional focus spots — holes in the light for the
            // eye to rest on. Draws only over a lit field.
            FocusSpotOverlay(
                mode: viewModel.mode,
                mindMachineEnabled: viewModel.mindMachineEnabled,
                lightSyncEnabled: viewModel.lightSyncEnabled
            )

            // Layer 2: Session lock overlay
            SessionLockView {
```

- [ ] **Step 4: Build both platforms**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: **BUILD SUCCEEDED** for both.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/FocusSpots/FocusSpotField.swift Ilumionate/FocusSpots/FocusSpotOverlay.swift Ilumionate/UnifiedPlayerView.swift
git commit -m "feat(focus-spots): render focus spots over the player light field"
```

---

## Task 5: Calibration screen

**Files:**
- Create: `Ilumionate/FocusSpots/FocusSpotCalibrationView.swift`

The preview field is **steady**, never strobing: a settings screen should not flash, and a strobing preview would drag the photosensitivity warning into Settings.

- [ ] **Step 1: Create the calibration view**

Create `Ilumionate/FocusSpots/FocusSpotCalibrationView.swift`:

```swift
//
//  FocusSpotCalibrationView.swift
//  Ilumionate
//
//  Dial the focus spots in against a real field, at true size.
//
//  Spacing that matches your own eyes cannot be chosen from a number in a
//  settings list, so the sliders live here, on top of what they control.
//
//  The field is STEADY, never strobing. A settings screen should not flash,
//  and a strobing preview would drag the photosensitivity warning into
//  Settings.
//

import SwiftUI

struct FocusSpotCalibrationView: View {
    let initialSettings: FocusSpotSettings
    let onSave: (FocusSpotSettings) -> Void
    let onCancel: () -> Void

    @State private var working: FocusSpotSettings

    /// Well below full: tuning the spots should not be a face full of light.
    private static let fieldOpacity: Double = 0.6
    /// Mid-scale blackbody, matching the swatch shown in Session Defaults.
    private static let previewColorTemperature = 3000

    init(
        initialSettings: FocusSpotSettings,
        onSave: @escaping (FocusSpotSettings) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSettings = initialSettings
        self.onSave = onSave
        self.onCancel = onCancel
        _working = State(initialValue: initialSettings)
    }

    private var fieldColor: Color {
        FlashTintPreference.current().color(
            colorTemperature: Self.previewColorTemperature
        )
    }

    /// The tray gets out of the way of the spots rather than covering them.
    private var trayIsAtTop: Bool { working.verticalPosition > 0.5 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            fieldColor.opacity(Self.fieldOpacity).ignoresSafeArea()

            FocusSpotField(settings: working)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            controlTray
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: trayIsAtTop ? .top : .bottom
                )
                .animation(LiminalMotion.fade, value: trayIsAtTop)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Tray

    private var controlTray: some View {
        VStack(spacing: TranceSpacing.list) {
            header

            sliderRow(
                title: "Vertical Position",
                value: verticalPositionBinding,
                range: FocusSpotSettings.verticalPositionRange,
                step: 0.01,
                display: verticalPositionLabel(working.verticalPosition)
            )

            sliderRow(
                title: "Horizontal Spacing",
                value: $working.horizontalSpacing,
                range: FocusSpotSettings.horizontalSpacingRange,
                step: 4,
                display: pointsLabel(working.horizontalSpacing)
            )

            sliderRow(
                title: "Diameter",
                value: $working.diameter,
                range: FocusSpotSettings.diameterRange,
                step: 2,
                display: pointsLabel(working.diameter)
            )
        }
        .padding(TranceSpacing.card)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: TranceRadius.glassCard))
        .padding(TranceSpacing.screen)
    }

    private var header: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .foregroundStyle(Color.textSecondary)

            Spacer()

            Text("Focus Spots")
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Button("Save") {
                TranceHaptics.shared.light()
                onSave(working)
            }
            .foregroundStyle(Color.roseGold)
            .bold()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bindings

    /// Snaps onto upper third / centre / lower third, with a tick as it
    /// arrives so the anchor is findable without looking.
    private var verticalPositionBinding: Binding<Double> {
        Binding(
            get: { working.verticalPosition },
            set: { newValue in
                let snapped = FocusSpotSettings.snappingVerticalPosition(newValue)
                let wasOnDetent = FocusSpotSettings.verticalDetents
                    .contains(working.verticalPosition)
                let isOnDetent = FocusSpotSettings.verticalDetents.contains(snapped)
                if isOnDetent, !wasOnDetent {
                    TranceHaptics.shared.selection()
                }
                working.verticalPosition = snapped
            }
        )
    }

    // MARK: - Rows

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: TranceSpacing.micro) {
            HStack {
                Text(title)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(display)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            CustomSlider(
                value: value,
                range: range,
                trackColor: .glassBorder,
                thumbColor: .roseGold,
                activeColor: .roseGold
            )
            .frame(height: 24)
        }
        // CustomSlider is drag-driven and invisible to VoiceOver on its own,
        // so the row carries the label, the value, and the adjustment.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(display)
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? step : -step
            let updated = value.wrappedValue + delta
            value.wrappedValue = min(max(updated, range.lowerBound), range.upperBound)
        }
    }

    // MARK: - Labels

    private func verticalPositionLabel(_ value: Double) -> String {
        if value == FocusSpotSettings.verticalDetents[0] { return "Upper Third" }
        if value == FocusSpotSettings.verticalDetents[1] { return "Centre" }
        if value == FocusSpotSettings.verticalDetents[2] { return "Lower Third" }
        return (value * 100).formatted(.number.precision(.fractionLength(0))) + "% down"
    }

    private func pointsLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " pt"
    }
}

#Preview {
    FocusSpotCalibrationView(
        initialSettings: .default,
        onSave: { _ in },
        onCancel: {}
    )
}
```

- [ ] **Step 2: Build both platforms**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: **BUILD SUCCEEDED** for both.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/FocusSpots/FocusSpotCalibrationView.swift
git commit -m "feat(focus-spots): add the calibration screen"
```

---

## Task 6: Settings wiring

**Files:**
- Modify: `Ilumionate/ProfileSettingsView.swift:33-38` and `:106-112`
- Modify: `Ilumionate/ProfileSettingsView+Sections.swift:151-217`

- [ ] **Step 1: Add the state to `ProfileSettingsView`**

In `Ilumionate/ProfileSettingsView.swift`, in the `// Session Defaults` block (after line 38, below `showingFlashTintSheet`):

```swift
    @AppStorage("focusSpotsEnabled") var focusSpotsEnabled = false
    @State var showingFocusSpotCalibration = false
    /// True when calibration was opened by switching the toggle on, so
    /// cancelling has to switch it back off — backing out of the automatic
    /// screen must not leave the feature on with untuned defaults.
    @State var focusSpotCalibrationOpenedByToggle = false
```

- [ ] **Step 2: Present the calibration screen**

In the same file, after the `.sheet(isPresented: $showingFlashTintSheet)` block (line 106-108), add:

```swift
            .platformFullScreenCover(isPresented: $showingFocusSpotCalibration) {
                FocusSpotCalibrationView(
                    initialSettings: FocusSpotPreference.current(),
                    onSave: { settings in
                        FocusSpotPreference.set(settings)
                        showingFocusSpotCalibration = false
                    },
                    onCancel: {
                        if focusSpotCalibrationOpenedByToggle {
                            focusSpotsEnabled = false
                        }
                        showingFocusSpotCalibration = false
                    }
                )
            }
            .onChange(of: focusSpotsEnabled) { _, enabled in
                // Cancelling sets this false, which re-enters here; the guard
                // stops that from re-presenting the screen.
                guard enabled else { return }
                focusSpotCalibrationOpenedByToggle = true
                showingFocusSpotCalibration = true
            }
```

- [ ] **Step 3: Add the rows to Session Defaults**

In `Ilumionate/ProfileSettingsView+Sections.swift`, in `sessionDefaultsSection`, insert between the Flash Colour `Button` (ends line 189 with `.buttonStyle(.plain)`) and `settingsSlider(title: "Frequency Scale"...)` (line 190):

```swift
                settingsToggle(
                    title: "Focus Spots",
                    description: "Two dark spots to rest your eyes on, over the light field.",
                    binding: $focusSpotsEnabled,
                    icon: "circle.circle",
                    color: .bwTheta
                )
                if focusSpotsEnabled {
                    Button {
                        TranceHaptics.shared.light()
                        focusSpotCalibrationOpenedByToggle = false
                        showingFocusSpotCalibration = true
                    } label: {
                        HStack(spacing: TranceSpacing.list) {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.bwTheta)
                                .frame(width: 24)
                            Text("Calibrate…")
                                .font(TranceTypography.body)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textSecondary)
                        }
                        // Without this the Spacer is not hit-testable and most
                        // of the row reads dead.
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
```

- [ ] **Step 4: Build both platforms**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: **BUILD SUCCEEDED** for both.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/ProfileSettingsView.swift Ilumionate/ProfileSettingsView+Sections.swift
git commit -m "feat(focus-spots): add the toggle and calibrate row to Session Defaults"
```

---

## Task 7: Full verification

**Files:** none — verification only.

- [ ] **Step 1: Run the whole shared suite on macOS**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

Expected: **TEST SUCCEEDED**, no new failures against the pre-change baseline.

- [ ] **Step 2: Run the whole shared suite on iOS Simulator**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests
```

Expected: **TEST SUCCEEDED**.

- [ ] **Step 3: Keep Mac Catalyst compiling**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' build
```

Expected: **BUILD SUCCEEDED**.

- [ ] **Step 4: Manual smoke test on the iPhone 17 Pro simulator**

Run the app and walk this list, which covers the behaviours no unit test reaches:

1. Settings → Session Defaults: **Focus Spots** is off, and no Calibrate row is shown.
2. Switch it on → the calibration screen appears immediately over a steady lit field with two black spots in the upper third.
3. Drag **Vertical Position** slowly through the middle — it snaps at upper third, centre, and lower third, and the label changes to match. The control tray jumps to the top of the screen once the spots pass the midline.
4. Drag **Diameter** to its maximum and **Horizontal Spacing** to its maximum — both spots stay fully on screen.
5. **Cancel** → the screen closes and the Focus Spots toggle is back **off**.
6. Switch it on again, adjust, **Save** → the screen closes, the toggle stays on, and a **Calibrate…** row is now shown.
7. Start a Mind Machine session → the spots render over the flashing field, and swiping up still reveals the controls (the overlay must not swallow the gesture).
8. Turn bilateral mode on → one spot sits in each half.
9. Open a session with audio and turn the mind machine **off** → the spots disappear with the light field; turn it back on → they return.
10. Open a Visual Field session → **no spots**.
11. Re-open Settings, tap **Calibrate…**, then **Cancel** → the toggle stays **on** (cancel only reverts the toggle when calibration was opened by it).

- [ ] **Step 5: Verify on macOS**

Run the macOS app, enable Focus Spots, and resize the window narrow (under ~400pt wide) during a Mind Machine session. Both spots must stay fully inside the window.

- [ ] **Step 6: Update `plan.md`**

Add to the **Mind Machine (MindMachineView)** section of `plan.md`:

```markdown
- ✅ Focus Spots — optional black fixation spots over the light field, with a
      calibration screen for vertical position, spacing, and diameter
```

- [ ] **Step 7: Commit**

```bash
git add plan.md
git commit -m "docs: mark focus spots complete in plan.md"
```
