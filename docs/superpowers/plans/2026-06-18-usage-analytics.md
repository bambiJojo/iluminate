# Usage Analytics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add anonymous, opt-out, remote usage analytics (TelemetryDeck) behind a typed Swift facade, so the developer can see which features the ~100 TestFlight testers actually use.

**Architecture:** A single `@MainActor @Observable` `UsageAnalytics.shared` facade is the only thing that imports TelemetryDeck. Views/ViewModels call typed methods (`screen(.home)`, `sessionStarted(source:category:)`). The facade gates on an opt-out flag (default ON) and emits through an injectable `emit` closure so tests use a spy with no network. Parameter values are always enums or bucketed numbers — no free-form user content can leave the device by construction.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, TelemetryDeck SwiftSDK (SPM), Xcode synchronized file groups (new `.swift`/resource files in `Ilumionate/` and `IlumionateTests/` auto-join their targets).

**Spec:** `docs/superpowers/specs/2026-06-18-usage-analytics-design.md`

---

## File Structure

| File | Responsibility | New/Modify |
| --- | --- | --- |
| `Ilumionate/Analytics/AnalyticsEvent.swift` | Event value type, screen/param enums, completion bucketing. No SDK import. | New |
| `Ilumionate/Analytics/UsageAnalytics.swift` | Facade: opt-out gate, typed methods, SDK init, TelemetryDeck emit. Only SDK importer. | New |
| `IlumionateTests/UsageAnalyticsTests.swift` | Unit tests via injected defaults + spy emit. | New |
| `Ilumionate/PrivacyInfo.xcprivacy` | Privacy manifest: Product Interaction, not linked to identity, not tracking. | New |
| `Ilumionate/IlumionateApp.swift` | One-time `UsageAnalytics.configure()` at launch. | Modify |
| `Ilumionate/ProfileSettingsView.swift` | `@AppStorage("analyticsEnabled")` flag. | Modify |
| `Ilumionate/ProfileSettingsView+Sections.swift` | Opt-out toggle row in Privacy & Data section. | Modify |
| `Ilumionate/ContentView.swift` | Tab-change screen events. | Modify |
| Various feature views/VMs | Screen + action call sites. | Modify |
| `Ilumionate.xcodeproj/project.pbxproj` | TelemetryDeck SPM dependency. | Modify (via Xcode) |

---

## Task 1: Add the TelemetryDeck dependency

**Prerequisite (manual, one-time):** Create an app in the TelemetryDeck dashboard (https://dashboard.telemetrydeck.com) and copy its **App ID** (a UUID). You'll paste it in Task 4.

**Files:**
- Modify: `Ilumionate.xcodeproj/project.pbxproj` (via Xcode UI — do NOT hand-edit)

- [ ] **Step 1: Verify the current SDK package URL, product name, and init API**

Use Xcode `DocumentationSearch` (or open https://github.com/TelemetryDeck/SwiftSDK) and confirm:
- Package URL: `https://github.com/TelemetryDeck/SwiftSDK`
- Library product name: `TelemetryDeck`
- v2 init API shape: `TelemetryDeck.initialize(config: TelemetryDeck.Config(appID:))` and `TelemetryDeck.signal(_ name: String, parameters: [String: String])`.

If the installed version's API differs from the above, note the real signatures — Tasks 2–3 reference them and must match.

- [ ] **Step 2: Add the package in Xcode**

Open `Ilumionate.xcodeproj`. File ▸ Add Package Dependencies… ▸ paste `https://github.com/TelemetryDeck/SwiftSDK` ▸ Dependency Rule: *Up to Next Major Version* from `2.0.0` ▸ Add Package ▸ add the **`TelemetryDeck`** product to the **Ilumionate** app target (only the app target, not test/tool targets).

- [ ] **Step 3: Verify it resolves and builds**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: BUILD SUCCEEDED, and `grep -c TelemetryDeck Ilumionate.xcodeproj/project.pbxproj` returns a non-zero count.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate.xcodeproj/project.pbxproj Ilumionate.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "chore: add TelemetryDeck SPM dependency"
```

---

## Task 2: Event catalog + bucketing (TDD)

**Files:**
- Create: `Ilumionate/Analytics/AnalyticsEvent.swift`
- Test: `IlumionateTests/UsageAnalyticsTests.swift` (created here, extended in Task 3)

- [ ] **Step 1: Write the failing test for completion bucketing**

Create `IlumionateTests/UsageAnalyticsTests.swift`:
```swift
import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct UsageAnalyticsTests {

    // MARK: - Completion bucketing

    @Test(arguments: [
        (0.0, CompletionBucket.under25),
        (0.24, CompletionBucket.under25),
        (0.25, CompletionBucket.b25_50),
        (0.49, CompletionBucket.b25_50),
        (0.50, CompletionBucket.b50_75),
        (0.74, CompletionBucket.b50_75),
        (0.75, CompletionBucket.b75_95),
        (0.94, CompletionBucket.b75_95),
        (0.95, CompletionBucket.complete),
        (1.0, CompletionBucket.complete),
    ])
    func bucketsFraction(_ pair: (fraction: Double, expected: CompletionBucket)) {
        #expect(CompletionBucket(fraction: pair.fraction) == pair.expected)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:IlumionateTests/UsageAnalyticsTests 2>&1 | tail -20
```
Expected: compile failure — `cannot find 'CompletionBucket' in scope`.

- [ ] **Step 3: Create the event catalog**

Create `Ilumionate/Analytics/AnalyticsEvent.swift`:
```swift
//
//  AnalyticsEvent.swift
//  Ilumionate
//
//  Typed catalog of usage-analytics events. No SDK import lives here.
//  Parameter values are always enum raw values or bucketed numbers, so
//  no free-form user content can ever be attached to an event.
//

import Foundation

/// A single analytics signal: a stable name plus string-keyed parameters.
struct AnalyticsEvent: Equatable, Sendable {
    let name: String
    let parameters: [String: String]

    init(_ name: String, _ parameters: [String: String] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

/// Major navigable surfaces. Raw value becomes the event-name suffix.
enum AnalyticsScreen: String, CaseIterable, Sendable {
    // Core surfaces
    case home, library, read, create, profile
    case audioLibrary, analysisQueue, sessionDetail, player, onboarding
    // Long-tail surfaces (cut-list candidates)
    case browseSessions, sessionLibrary, libraryCreators, libraryFolders
    case streamingBrowser, phraseLibrary, lightScoreEditor
}

enum SessionSource: String, Sendable {
    case preset, generated, textTrance, mindMachine
}

enum AudioSource: String, Sendable {
    case files, url, browser, recording
}

enum MindMachineMode: String, Sendable {
    case flash, colorPulse, bilateral
}

/// Bucketed completion fraction — exact playback time never leaves the device.
enum CompletionBucket: String, Sendable {
    case under25, b25_50, b50_75, b75_95, complete

    init(fraction: Double) {
        switch fraction {
        case ..<0.25: self = .under25
        case ..<0.50: self = .b25_50
        case ..<0.75: self = .b50_75
        case ..<0.95: self = .b75_95
        default:      self = .complete
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2.
Expected: the `bucketsFraction` cases PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/Analytics/AnalyticsEvent.swift IlumionateTests/UsageAnalyticsTests.swift
git commit -m "feat(analytics): typed event catalog with completion bucketing"
```

---

## Task 3: UsageAnalytics facade (TDD)

**Files:**
- Create: `Ilumionate/Analytics/UsageAnalytics.swift`
- Test: `IlumionateTests/UsageAnalyticsTests.swift` (extend)

- [ ] **Step 1: Add failing tests for the gate + typed methods**

Add these methods inside the existing `UsageAnalyticsTests` struct in `IlumionateTests/UsageAnalyticsTests.swift`:
```swift
    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suite = "UsageAnalyticsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Opt-out gate

    @Test
    func defaultsToEnabledWhenUnset() {
        let analytics = UsageAnalytics(defaults: makeDefaults(), emit: { _ in })
        #expect(analytics.isEnabled == true)
    }

    @Test
    func optOutSuppressesEmission() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: UsageAnalytics.optOutKey)
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: defaults, emit: { captured.append($0) })
        analytics.screen(.home)
        #expect(captured.isEmpty)
    }

    // MARK: - Typed emission

    @Test
    func enabledEmitsScreenEvent() {
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: makeDefaults(), emit: { captured.append($0) })
        analytics.screen(.lightScoreEditor)
        #expect(captured == [AnalyticsEvent("screen.lightScoreEditor")])
    }

    @Test
    func sessionStartedCarriesSourceAndCategory() {
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: makeDefaults(), emit: { captured.append($0) })
        analytics.sessionStarted(source: .generated, category: "Sleep")
        #expect(captured == [AnalyticsEvent("session.started",
                                            ["source": "generated", "category": "Sleep"])])
    }

    @Test
    func sessionCompletedEmitsBucket() {
        var captured: [AnalyticsEvent] = []
        let analytics = UsageAnalytics(defaults: makeDefaults(), emit: { captured.append($0) })
        analytics.sessionCompleted(fraction: 0.97)
        #expect(captured == [AnalyticsEvent("session.completed",
                                            ["completionBucket": "complete"])])
    }
```

- [ ] **Step 2: Run to verify failure**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:IlumionateTests/UsageAnalyticsTests 2>&1 | tail -20
```
Expected: compile failure — `cannot find 'UsageAnalytics' in scope`.

- [ ] **Step 3: Create the facade**

Create `Ilumionate/Analytics/UsageAnalytics.swift`. If Task 1 Step 1 found different TelemetryDeck signatures, adjust `configure()` and `telemetryDeckEmit` accordingly — nothing else changes.
```swift
//
//  UsageAnalytics.swift
//  Ilumionate
//
//  The single entry point for usage analytics. Only file that imports the SDK.
//  Opt-out (default ON) is enforced here, and every event is built from the
//  typed catalog in AnalyticsEvent.swift.
//

import Foundation
import Observation
import TelemetryDeck

@MainActor
@Observable
final class UsageAnalytics {

    static let shared = UsageAnalytics()
    static let optOutKey = "analyticsEnabled"

    private let defaults: UserDefaults
    private let emit: (AnalyticsEvent) -> Void

    /// - Parameters:
    ///   - defaults: storage for the opt-out flag (injected in tests).
    ///   - emit: event sink (defaults to TelemetryDeck; a spy in tests).
    init(
        defaults: UserDefaults = .standard,
        emit: @escaping (AnalyticsEvent) -> Void = UsageAnalytics.telemetryDeckEmit
    ) {
        self.defaults = defaults
        self.emit = emit
        // Default-on: if the flag was never written, treat analytics as enabled.
        if defaults.object(forKey: Self.optOutKey) == nil {
            defaults.set(true, forKey: Self.optOutKey)
        }
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.optOutKey) }

    // MARK: - SDK lifecycle

    /// Call once at app launch.
    static func configure() {
        guard !appID.isEmpty else { return }
        TelemetryDeck.initialize(config: .init(appID: appID))
    }

    private static var appID: String {
        (Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String) ?? ""
    }

    private static func telemetryDeckEmit(_ event: AnalyticsEvent) {
        TelemetryDeck.signal(event.name, parameters: event.parameters)
    }

    // MARK: - Core send

    private func send(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        emit(event)
    }

    // MARK: - Screens

    func screen(_ screen: AnalyticsScreen) {
        send(AnalyticsEvent("screen.\(screen.rawValue)"))
    }

    // MARK: - Actions

    func sessionStarted(source: SessionSource, category: String) {
        send(AnalyticsEvent("session.started",
                            ["source": source.rawValue, "category": category]))
    }

    func sessionCompleted(fraction: Double) {
        send(AnalyticsEvent("session.completed",
                            ["completionBucket": CompletionBucket(fraction: fraction).rawValue]))
    }

    func audioImported(source: AudioSource) {
        send(AnalyticsEvent("audio.imported", ["source": source.rawValue]))
    }

    func audioAnalyzeStarted() { send(AnalyticsEvent("audio.analyzeStarted")) }
    func audioAnalyzeCompleted() { send(AnalyticsEvent("audio.analyzeCompleted")) }
    func sessionGenerated() { send(AnalyticsEvent("session.generated")) }

    func mindMachineStarted(mode: MindMachineMode) {
        send(AnalyticsEvent("mindMachine.started", ["mode": mode.rawValue]))
    }

    func textTranceStarted() { send(AnalyticsEvent("textTrance.started")) }
    func textTranceCompleted() { send(AnalyticsEvent("textTrance.completed")) }
    func readingSourceImported() { send(AnalyticsEvent("readingSource.imported")) }

    func onboardingStep(index: Int) {
        send(AnalyticsEvent("onboarding.step", ["index": String(index)]))
    }
    func onboardingCompleted() { send(AnalyticsEvent("onboarding.completed")) }

    func settingsToggled(key: String) {
        send(AnalyticsEvent("settings.toggled", ["key": key]))
    }
}
```

- [ ] **Step 4: Run to verify all tests pass**

Run the Step 2 command. Expected: all `UsageAnalyticsTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/Analytics/UsageAnalytics.swift IlumionateTests/UsageAnalyticsTests.swift
git commit -m "feat(analytics): UsageAnalytics facade with opt-out gate"
```

---

## Task 4: Initialize the SDK + add the App ID

**Files:**
- Modify: `Ilumionate/IlumionateApp.swift`
- Modify: target Info properties (Xcode UI)

- [ ] **Step 1: Add the App ID to Info properties**

In Xcode, select the **Ilumionate** target ▸ Info tab ▸ add a Custom iOS Target Property:
key `TelemetryDeckAppID` (type String) = the App ID UUID from Task 1's prerequisite. (This is not a secret — App IDs are write-only ingest keys — but keeping it out of source keeps the Info plist the single source of truth.)

- [ ] **Step 2: Call configure() at launch**

Edit `Ilumionate/IlumionateApp.swift`. Replace the `IlumionateApp` struct body with:
```swift
@main
struct IlumionateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        UsageAnalytics.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/IlumionateApp.swift Ilumionate.xcodeproj/project.pbxproj
git commit -m "feat(analytics): initialize TelemetryDeck at launch"
```

---

## Task 5: Opt-out toggle in Settings

**Files:**
- Modify: `Ilumionate/ProfileSettingsView.swift:35` (the `@AppStorage` "Privacy" block)
- Modify: `Ilumionate/ProfileSettingsView+Sections.swift` (the `privacyDataSection`, ~line 318)

- [ ] **Step 1: Add the @AppStorage flag**

In `Ilumionate/ProfileSettingsView.swift`, find:
```swift
    // Privacy
    @AppStorage("listeningHistoryEnabled") var listeningHistoryEnabled = false
```
Add directly below it:
```swift
    @AppStorage("analyticsEnabled") var analyticsEnabled = true
```

- [ ] **Step 2: Add the toggle row**

In `Ilumionate/ProfileSettingsView+Sections.swift`, inside `privacyDataSection`'s `VStack`, immediately after the existing `settingsToggle(title: "Track Session History", ...)` call, add:
```swift
                settingsToggle(
                    title: "Anonymous Usage Analytics",
                    binding: $analyticsEnabled,
                    icon: "chart.bar.xaxis",
                    color: .bwAlpha
                )
```

- [ ] **Step 3: Emit settings.toggled when it changes**

Still in `privacyDataSection`, attach a change handler to the analytics toggle by adding this modifier to the `GlassCard(label: "Privacy & Data")` closure's outer container. Add after the `VStack { ... }` closing brace inside the `GlassCard`:
```swift
            .onChange(of: analyticsEnabled) { _, _ in
                UsageAnalytics.shared.settingsToggled(key: "analyticsEnabled")
            }
```
(Note: when the user turns analytics OFF, this final event is still emitted because the gate is read at send time and the flag flips after the binding writes; that's acceptable — it records the opt-out itself. If the version's ordering suppresses it, that's fine too.)

- [ ] **Step 4: Build**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/ProfileSettingsView.swift Ilumionate/ProfileSettingsView+Sections.swift
git commit -m "feat(analytics): opt-out toggle in Privacy settings"
```

---

## Task 6: Privacy manifest

**Files:**
- Create: `Ilumionate/PrivacyInfo.xcprivacy`

- [ ] **Step 1: Create the manifest**

Create `Ilumionate/PrivacyInfo.xcprivacy`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeProductInteraction</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array/>
</dict>
</plist>
```

- [ ] **Step 2: Verify target membership**

The `Ilumionate/` folder is a synchronized group, so the manifest should auto-join the app target. Confirm in Xcode (select the file ▸ File Inspector ▸ Target Membership shows **Ilumionate** checked). If it does not appear, add it to the target manually.

- [ ] **Step 3: Build and confirm it bundles**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED. (Optional: locate `PrivacyInfo.xcprivacy` inside the built `.app` to confirm bundling.)

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/PrivacyInfo.xcprivacy
git commit -m "feat(analytics): privacy manifest for product-interaction analytics"
```

---

## Task 7: Screen events — tabs

**Files:**
- Modify: `Ilumionate/ContentView.swift` (the `.onAppear` at line ~93, plus a new `.onChange`)

The four tabs render via `if selectedTab == ...` rather than separate appearances, so track them from `selectedTab`.

- [ ] **Step 1: Add a helper that maps a tab to a screen, and fire it**

In `Ilumionate/ContentView.swift`, find the existing `.onAppear { loadSessions(); ... }` block (line ~93). Add a screen call for the initial tab at the end of that closure:
```swift
            UsageAnalytics.shared.screen(screen(for: selectedTab))
```
Then, immediately after the existing `.onChange(of: userFrequencyMultiplierPref)` modifier, add:
```swift
        .onChange(of: selectedTab) { _, newTab in
            UsageAnalytics.shared.screen(screen(for: newTab))
        }
```
Finally, add this private helper inside `ContentView` (after the `checkForFirstLaunch()` method):
```swift
    private func screen(for tab: TranceTab) -> AnalyticsScreen {
        switch tab {
        case .home:    .home
        case .library: .library
        case .read:    .read
        case .create:  .create
        }
    }
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/ContentView.swift
git commit -m "feat(analytics): screen events for main tabs"
```

---

## Task 8: Screen events — covers, sheets, and long-tail surfaces

Each step adds `.onAppear { UsageAnalytics.shared.screen(.<case>) }` to the root view's `body` of one surface. For each file: locate `var body: some View {` and attach the modifier to the outermost view it returns. Build + commit once at the end.

**Files / mapping:**
- `Ilumionate/OnboardingView.swift` → `.onboarding`
- `Ilumionate/ProfileView.swift` → `.profile`
- `Ilumionate/AudioLibraryView.swift` → `.audioLibrary`
- `Ilumionate/AnalyzerView.swift` → `.analysisQueue`
- `Ilumionate/SessionDetailView.swift` → `.sessionDetail`
- `Ilumionate/UnifiedPlayerView.swift` → `.player`
- `Ilumionate/BrowseSessionsView.swift` → `.browseSessions`
- `Ilumionate/SessionLibraryView.swift` → `.sessionLibrary`
- `Ilumionate/LibraryCreatorsView.swift` → `.libraryCreators`
- `Ilumionate/LibraryFoldersView.swift` → `.libraryFolders`
- `Ilumionate/StreamingBrowserView.swift` → `.streamingBrowser`
- `Ilumionate/PhraseLibraryView.swift` → `.phraseLibrary`
- `Ilumionate/LightScoreEditorView.swift` → `.lightScoreEditor`

- [ ] **Step 1: Add `.onAppear` to each view above**

Example for `AudioLibraryView.swift` — find the outermost view returned by `var body` and append:
```swift
        .onAppear { UsageAnalytics.shared.screen(.audioLibrary) }
```
Repeat for every file in the mapping, substituting the matching `AnalyticsScreen` case. If a view already has an `.onAppear`, add the line inside the existing closure instead of a second modifier.

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/OnboardingView.swift Ilumionate/ProfileView.swift Ilumionate/AudioLibraryView.swift Ilumionate/AnalyzerView.swift Ilumionate/SessionDetailView.swift Ilumionate/UnifiedPlayerView.swift Ilumionate/BrowseSessionsView.swift Ilumionate/SessionLibraryView.swift Ilumionate/LibraryCreatorsView.swift Ilumionate/LibraryFoldersView.swift Ilumionate/StreamingBrowserView.swift Ilumionate/PhraseLibraryView.swift Ilumionate/LightScoreEditorView.swift
git commit -m "feat(analytics): screen events for covers, sheets, and long-tail surfaces"
```

---

## Task 9: Action events — session playback

**Files:**
- Modify: `Ilumionate/UnifiedPlayerViewModel.swift` (`startCountdownAndPlay()` ~line 487; `saveProgress()` ~line 738)

- [ ] **Step 1: Emit `session.started` when playback begins**

In `Ilumionate/UnifiedPlayerViewModel.swift`, find `private func startCountdownAndPlay() {` (~line 487). At the start of the method body add:
```swift
        UsageAnalytics.shared.sessionStarted(source: sessionSource, category: sessionCategory)
```

- [ ] **Step 2: Add the `sessionSource` helper**

`mode` is a `PlayerMode` (defined in `Ilumionate/PlayerMode.swift`) with five cases: `.session(session:audioFile:)`, `.flashMode(...)`, `.colorPulse(...)`, `.audioLight(audioFile:)`, `.playlist(playlist:)`. Directly below the existing `sessionCategory` computed property (~line 749), add:
```swift
    private var sessionSource: SessionSource {
        switch mode {
        case .session(_, let audioFile): audioFile == nil ? .preset : .generated
        case .audioLight:                .generated
        case .flashMode, .colorPulse:    .mindMachine
        case .playlist:                  .preset
        }
    }
```

- [ ] **Step 3: Emit `session.completed` alongside the existing history record**

In `saveProgress()`, find the existing `sessionHistory.record(...)` call (~line 738). Immediately after the closing `)` of that call, add:
```swift
        UsageAnalytics.shared.sessionCompleted(fraction: prog)
```
(`prog` is already computed in scope as `listenedDuration / session.duration_sec`.)

- [ ] **Step 4: Build**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/UnifiedPlayerViewModel.swift
git commit -m "feat(analytics): session started/completed events"
```

---

## Task 10: Action events — audio pipeline

**Files:**
- Modify: `Ilumionate/AudioManager.swift` (`importAudio(from:)` ~line 143)
- Modify: `Ilumionate/AnalysisStateManager.swift` (`startAnalysis(for audioFile:...)` ~line 186)
- Modify: `Ilumionate/SessionGenerationView.swift` (`generateSession()` ~line 262)

- [ ] **Step 1: Emit `audio.imported`**

In `Ilumionate/AudioManager.swift`, find `func importAudio(from url: URL) async -> AudioFile? {` (~line 143). On the success path, just before the function `return`s a non-nil `AudioFile`, add:
```swift
            await UsageAnalytics.shared.audioImported(source: .files)
```
(If `importAudio` is already `@MainActor`, drop the `await`. The `.files` source matches Files-app import; recording/url/browser sources can be added at their own call sites later — out of scope for this pass beyond `.files`.)

- [ ] **Step 2: Emit `audio.analyzeStarted` / `audio.analyzeCompleted`**

In `Ilumionate/AnalysisStateManager.swift`, find `func startAnalysis(for audioFile: AudioFile, priority:...) async {` (~line 186). Add at the top of the body:
```swift
        UsageAnalytics.shared.audioAnalyzeStarted()
```
Then find where a single-file analysis finishes successfully (the point where the result is stored / status set to completed) and add:
```swift
        UsageAnalytics.shared.audioAnalyzeCompleted()
```
If completion is signalled in a `defer` or a separate callback, place the call there so it fires once per finished analysis.

- [ ] **Step 3: Emit `session.generated`**

In `Ilumionate/SessionGenerationView.swift`, find `private func generateSession() {` (~line 262). After the generated `LightSession` is successfully produced/persisted, add:
```swift
        UsageAnalytics.shared.sessionGenerated()
```

- [ ] **Step 4: Build**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AudioManager.swift Ilumionate/AnalysisStateManager.swift Ilumionate/SessionGenerationView.swift
git commit -m "feat(analytics): audio import/analyze/generate events"
```

---

## Task 11: Action events — mind machine, text trance, reading source, onboarding

**Files:**
- Modify: `Ilumionate/MindMachineView.swift` (`fullScreenCover(isPresented: $showingFlashMode)` ~line 211)
- Modify: `Ilumionate/TextTrance/TextTrancePlayerView.swift` (`var body` ~line 21; completion at `session.isComplete` ~line 55)
- Modify: `Ilumionate/TextTrance/ReadingSourceStore.swift` (`customSources.append(source)` ~line 80)
- Modify: `Ilumionate/OnboardingView.swift` (`nextPhase()` ~line 374)

- [ ] **Step 1: Emit `mindMachine.started`**

The selected mode lives on the model as `model.selectedVisualMode`, of type `MindMachineModel.VisualMode` with cases `.fullScreenFlash`, `.colorPulse`, `.bilateralFlash`. In `Ilumionate/MindMachineView.swift`, find the `.fullScreenCover(isPresented: $showingFlashMode) {` (~line 211). Add `.onAppear` to the cover's content root:
```swift
            .onAppear {
                UsageAnalytics.shared.mindMachineStarted(mode: analyticsMode(model.selectedVisualMode))
            }
```
Add this mapping helper inside `MindMachineView`:
```swift
    private func analyticsMode(_ mode: MindMachineModel.VisualMode) -> MindMachineMode {
        switch mode {
        case .fullScreenFlash: .flash
        case .colorPulse:      .colorPulse
        case .bilateralFlash:  .bilateral
        }
    }
```

- [ ] **Step 2: Emit `textTrance.started` / `textTrance.completed`**

In `Ilumionate/TextTrance/TextTrancePlayerView.swift`, find `var body: some View {` (~line 21). Add to the body root:
```swift
        .onAppear { UsageAnalytics.shared.textTranceStarted() }
```
Then find the existing completion check `if session.isComplete { dismiss() }` (~line 55). Change it to:
```swift
            if session.isComplete {
                UsageAnalytics.shared.textTranceCompleted()
                dismiss()
            }
```

- [ ] **Step 3: Emit `readingSource.imported`**

In `Ilumionate/TextTrance/ReadingSourceStore.swift`, find `customSources.append(source)` (~line 80). Add immediately after it:
```swift
        UsageAnalytics.shared.readingSourceImported()
```
If `ReadingSourceStore` is not `@MainActor`, wrap the call: `Task { @MainActor in UsageAnalytics.shared.readingSourceImported() }`.

- [ ] **Step 4: Emit onboarding step + completion**

Onboarding progress is held by `@State private var currentPhase: OnboardingPhase` (~line 18). `OnboardingPhase` is `Int, CaseIterable` (`welcome = 0, questionnaire, personalizedResponse, warning, completed`), so `currentPhase.rawValue` is the step index. Add a single `.onChange` to the view body (attach it to the same root view that gets the `backgroundForPhase(currentPhase)` at ~line 45) so every phase transition is captured without touching the navigation logic:
```swift
        .onChange(of: currentPhase) { _, newPhase in
            UsageAnalytics.shared.onboardingStep(index: newPhase.rawValue)
            if newPhase == .completed {
                UsageAnalytics.shared.onboardingCompleted()
            }
        }
```

- [ ] **Step 5: Build**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/MindMachineView.swift Ilumionate/TextTrance/TextTrancePlayerView.swift Ilumionate/TextTrance/ReadingSourceStore.swift Ilumionate/OnboardingView.swift
git commit -m "feat(analytics): mind machine, text trance, reading source, onboarding events"
```

---

## Task 12: Full verification + TestFlight note

**Files:**
- Modify: `BETA_RELEASE_NOTES.md` (add the analytics line for "What to Test")

- [ ] **Step 1: Run the full test suite**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -25
```
Expected: TEST SUCCEEDED, including all `UsageAnalyticsTests`.

- [ ] **Step 2: Manual smoke (simulator)**

Build/run on the simulator. With analytics ON (default), navigate each tab, start a session, open Settings. Confirm no crashes. Toggle "Anonymous Usage Analytics" OFF in Settings and confirm the app still behaves normally. (TelemetryDeck has no debug console in-app; trust the unit tests for emission correctness — this step only verifies no runtime regressions.)

- [ ] **Step 3: Add the TestFlight disclosure**

In `BETA_RELEASE_NOTES.md`, add under the current build's notes:
```markdown
- This build includes anonymous, opt-out usage analytics (no personal data, no content, no tracking) to help us learn which features are useful. You can turn it off in Settings ▸ Privacy & Data ▸ Anonymous Usage Analytics.
```

- [ ] **Step 4: Commit**

```bash
git add BETA_RELEASE_NOTES.md
git commit -m "docs: disclose anonymous usage analytics in beta notes"
```

---

## Notes for the implementer

- **Anchors are approximate line numbers** from 2026-06-18; if a line has moved, locate by the quoted symbol/string rather than the number.
- **`@MainActor` calls:** `UsageAnalytics.shared` is `@MainActor`. Most call sites are already on the main actor (SwiftUI views, `@MainActor` view models). Where a call site is not, wrap it in `Task { @MainActor in ... }` or `await`.
- **Privacy invariant:** never add an event parameter sourced from a file name, title, transcript, URL, or query. If a new event needs a discriminator, add a new enum case to `AnalyticsEvent.swift` instead of passing a string.
- **The `category` parameter** on `session.started` comes from the fixed `sessionCategory` set (Sleep/Relax/Focus/Energy/Trance) — keep it that way.
