# Home Screen Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the nine-section home screen with a launcher: a pinned settings gear, a greeting, four equal-weight door quadrants, and a resume pill.

**Architecture:** Home becomes a thin composition over two new testable value types (`HomeDoor` for routing, `HomeResumeState` for the pill) plus two new SwiftUI views. Resume reads the existing `PlaybackProgressStore` — no new persistence. The Visuals and Pulse doors deep-link into the Create tab with a preselected `CreateSessionKind`, which requires threading a requested-kind trigger through `ContentView` following the existing `readerQuickStartTrigger` pattern.

**Tech Stack:** SwiftUI, Swift 6.2 strict concurrency, `@Observable`, Swift Testing (`import Testing`), xcodebuild on macOS + iOS Simulator.

**Xcode project note:** this project uses Xcode 16 file-system synchronized groups (`objectVersion = 77`, `PBXFileSystemSynchronizedRootGroup`). Files added under `Ilumionate/` and `IlumionateTests/` join their target automatically — **never hand-edit `project.pbxproj`**, and never add it to a commit for a plain file add or delete.

**Spec:** `docs/superpowers/specs/2026-08-09-home-screen-launcher-design.md`

---

## File Structure

**Create:**

| File | Responsibility |
|---|---|
| `Ilumionate/HomeDoor.swift` | The four doors: title, subtitle, symbol, tint, analytics case, route. Pure value type. |
| `Ilumionate/HomeDoorsView.swift` | The 2×2 quadrant grid. Renders `HomeDoor.allCases`, reflows to one column at accessibility sizes. |
| `Ilumionate/HomeResumeState.swift` | Derives the pill's content from a `PlaybackProgressSnapshot`. Pure value type. |
| `Ilumionate/HomeResumePill.swift` | Renders `HomeResumeState`. |
| `IlumionateTests/HomeDoorTests.swift` | Route and metadata coverage. |
| `IlumionateTests/HomeResumeStateTests.swift` | Nil-when-empty, remaining-time, clamping. |

**Modify:**

| File | Change |
|---|---|
| `Ilumionate/HomeView.swift` | Rewritten. 838 lines → ~200. |
| `Ilumionate/Create/CreateView.swift:15` | Accept an initial kind and a re-apply trigger. |
| `Ilumionate/ContentView.swift:154-193` | Thread the requested Create kind; pass the door callback to `HomeView`. |
| `Ilumionate/Analytics/AnalyticsEvent.swift:94` | Extend `HomeCoreAction` from 2 cases to 4. |

**Delete:**

| File | Lines |
|---|---|
| `Ilumionate/HomeView+FeaturedSessions.swift` | 98 |
| `Ilumionate/HomeStreakPill.swift` | 98 |
| `Ilumionate/HomeCoreActionsView.swift` | 78 |
| `Ilumionate/HomeView+MySessions.swift` | 67 |

---

## Task 1: Confirm Library covers what home is losing

This is a gate, not a code change. The spec requires verifying Library already surfaces generated and featured sessions **before** home deletes those sections. If it does not, stop and report — the gap gets fixed in Library first.

**Files:**
- Read: `Ilumionate/LibraryView.swift`
- Read: `Ilumionate/HomeView+MySessions.swift`
- Read: `Ilumionate/HomeView+FeaturedSessions.swift`

- [ ] **Step 1: Find what the home sections show**

```bash
grep -n "GeneratedSessionStore\|loadMyGeneratedSessions\|MyGeneratedSessionItem" Ilumionate/HomeView+MySessions.swift
grep -n "sessions\|featured" Ilumionate/HomeView+FeaturedSessions.swift | head -20
```

- [ ] **Step 2: Check Library surfaces the same content**

```bash
grep -n "GeneratedSessionStore\|LightScoreReader\|sessions" Ilumionate/LibraryView.swift | head -30
```

- [ ] **Step 3: Record the verdict**

If Library shows both generated and bundled sessions, write one line in the commit message confirming it and continue to Task 2.

If it does not, **stop**. Report which content would become unreachable. Do not proceed to Task 8's deletions.

- [ ] **Step 4: Commit the finding**

```bash
git commit --allow-empty -m "chore: confirm Library covers home's session lists before removal"
```

---

## Task 2: Extend the home analytics enum

`HomeCoreAction` currently has two cases because home had two core actions. Four doors need four.

**Files:**
- Modify: `Ilumionate/Analytics/AnalyticsEvent.swift:94-96`

- [ ] **Step 1: Replace the enum**

Replace lines 94-96 of `Ilumionate/Analytics/AnalyticsEvent.swift`:

```swift
nonisolated enum HomeCoreAction: String, Sendable {
    case audioLibrary, reader
}
```

with:

```swift
/// The four doors on the launcher home screen. Raw values are wire format for
/// TelemetryDeck — renaming a case would silently split a metric in two, so
/// `audioLibrary` keeps its original spelling even though the door is "Listen".
nonisolated enum HomeCoreAction: String, Sendable {
    case audioLibrary, reader, visuals, pulse
}
```

- [ ] **Step 2: Verify it still compiles**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/Analytics/AnalyticsEvent.swift
git commit -m "feat(analytics): add visuals and pulse to HomeCoreAction"
```

---

## Task 3: The `HomeDoor` model

A pure value type describing the four doors and where each one goes. This is the unit the grid renders and the tests cover.

**Files:**
- Create: `Ilumionate/HomeDoor.swift`
- Test: `IlumionateTests/HomeDoorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/HomeDoorTests.swift`:

```swift
import Testing
@testable import Ilumionate

struct HomeDoorTests {

    @Test
    func thereAreExactlyFourDoorsInFixedOrder() {
        #expect(HomeDoor.allCases == [.listen, .read, .visuals, .pulse])
    }

    @Test
    func eachDoorRoutesToItsSurface() {
        #expect(HomeDoor.listen.route == .audioLibrary)
        #expect(HomeDoor.read.route == .reader)
        #expect(HomeDoor.visuals.route == .create(.visualField))
        #expect(HomeDoor.pulse.route == .create(.flash))
    }

    @Test
    func lightPathDoorsRouteToCreateRatherThanStraightIntoAPlayer() {
        // Landing on Create preserves CreateSessionKind.requiresSafetyWarning.
        // A door that started a flash directly would bypass it.
        for door in [HomeDoor.visuals, .pulse] {
            guard case .create = door.route else {
                Issue.record("\(door) must route to Create, not a player")
                return
            }
        }
    }

    @Test
    func everyDoorCarriesADistinctAnalyticsCase() {
        let actions = HomeDoor.allCases.map(\.analyticsAction)
        #expect(Set(actions.map(\.rawValue)).count == HomeDoor.allCases.count)
    }

    @Test
    func everyDoorHasCopy() {
        for door in HomeDoor.allCases {
            #expect(!door.title.isEmpty)
            #expect(!door.subtitle.isEmpty)
            #expect(!door.systemImage.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run it and verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/HomeDoorTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'HomeDoor' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Ilumionate/HomeDoor.swift`:

```swift
//
//  HomeDoor.swift
//  Ilumionate
//
//  The four doors on the launcher home screen.
//
//  Fixed order, equal weight, never reordered by usage. The app has four parts
//  people care about — reader, audio, hypnotic visuals, light entrainment — and
//  home's job is to show all four rather than guess which one someone wants.
//  Audio analysis and synced playback are one door, not two: they are a single
//  pipeline, and splitting them would only make people guess which to tap.
//

import SwiftUI

/// Where a door sends you. `create` carries the segment to preselect.
enum HomeDoorRoute: Equatable, Sendable {
    case audioLibrary
    case reader
    case create(CreateSessionKind)
}

enum HomeDoor: String, CaseIterable, Identifiable, Sendable {
    case listen
    case read
    case visuals
    case pulse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listen:  "Listen"
        case .read:    "Read"
        case .visuals: "Visuals"
        case .pulse:   "Pulse"
        }
    }

    var subtitle: String {
        switch self {
        case .listen:  "Your audio, light-synced"
        case .read:    "Scripts, paced"
        case .visuals: "A wordless field"
        case .pulse:   "Flash entrainment"
        }
    }

    var systemImage: String {
        switch self {
        case .listen:  "waveform"
        case .read:    "text.aligncenter"
        case .visuals: "circle.hexagonpath.fill"
        case .pulse:   "lightbulb.fill"
        }
    }

    var tint: Color {
        switch self {
        case .listen:  .bwAlpha
        case .read:    .roseGold
        case .visuals: .bwGamma
        case .pulse:   .bwBeta
        }
    }

    /// The light path lands on Create with its segment selected rather than
    /// starting a session, so `CreateSessionKind.requiresSafetyWarning` still
    /// gates the flash.
    var route: HomeDoorRoute {
        switch self {
        case .listen:  .audioLibrary
        case .read:    .reader
        case .visuals: .create(.visualField)
        case .pulse:   .create(.flash)
        }
    }

    var analyticsAction: HomeCoreAction {
        switch self {
        case .listen:  .audioLibrary
        case .read:    .reader
        case .visuals: .visuals
        case .pulse:   .pulse
        }
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/HomeDoorTests 2>&1 | tail -20
```

Expected: all five tests pass.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/HomeDoor.swift IlumionateTests/HomeDoorTests.swift
git commit -m "feat(home): add the HomeDoor model and its routes"
```

---

## Task 4: The `HomeResumeState` value type

The pill's content, derived from the store that already exists. No new persistence.

**Files:**
- Create: `Ilumionate/HomeResumeState.swift`
- Test: `IlumionateTests/HomeResumeStateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/HomeResumeStateTests.swift`:

```swift
import Foundation
import Testing
@testable import Ilumionate

struct HomeResumeStateTests {

    private func snapshot(
        contentID: String = "abc",
        kind: ResumablePlaybackKind = .session,
        title: String = "Deep Descent",
        progress: Double = 0.5,
        duration: TimeInterval = 600
    ) -> PlaybackProgressSnapshot {
        PlaybackProgressSnapshot(
            contentID: contentID,
            kind: kind,
            title: title,
            progress: progress,
            duration: duration,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    @Test
    func absentWhenThereIsNothingToResume() {
        #expect(HomeResumeState(snapshot: nil) == nil)
    }

    @Test
    func carriesTitleAndRemainingTime() throws {
        let state = try #require(HomeResumeState(snapshot: snapshot()))
        #expect(state.title == "Deep Descent")
        #expect(state.remaining == 300)
        #expect(state.progress == 0.5)
    }

    @Test
    func remainingNeverGoesNegative() throws {
        let state = try #require(HomeResumeState(snapshot: snapshot(progress: 1.5)))
        #expect(state.remaining == 0)
        #expect(state.progress == 1)
    }

    @Test
    func absentWhenTheContentHasNoDuration() {
        #expect(HomeResumeState(snapshot: snapshot(duration: 0)) == nil)
    }

    @Test
    func keepsTheKindSoTheTapCanRouteToTheRightPlayer() throws {
        let audio = try #require(HomeResumeState(snapshot: snapshot(kind: .audio)))
        #expect(audio.kind == .audio)
        let session = try #require(HomeResumeState(snapshot: snapshot(kind: .session)))
        #expect(session.kind == .session)
    }
}
```

- [ ] **Step 2: Run it and verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/HomeResumeStateTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'HomeResumeState' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Ilumionate/HomeResumeState.swift`:

```swift
//
//  HomeResumeState.swift
//  Ilumionate
//
//  What the home resume pill shows.
//
//  Derived from PlaybackProgressStore rather than from its own record: that
//  store already persists contentID, kind, title, progress and duration, keeps
//  the twenty most recent entries newest-first, and is already what LibraryView
//  reads. A second source of truth would only be a second thing to keep in sync.
//

import Foundation

struct HomeResumeState: Equatable, Sendable {
    let contentID: String
    let kind: ResumablePlaybackKind
    let title: String
    /// Clamped to 0...1.
    let progress: Double
    /// Seconds left, never negative.
    let remaining: TimeInterval

    init?(snapshot: PlaybackProgressSnapshot?) {
        guard let snapshot, snapshot.duration > 0 else { return nil }
        let clamped = min(max(snapshot.progress, 0), 1)
        self.contentID = snapshot.contentID
        self.kind = snapshot.kind
        self.title = snapshot.title
        self.progress = clamped
        self.remaining = max(0, snapshot.duration - snapshot.duration * clamped)
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/HomeResumeStateTests 2>&1 | tail -20
```

Expected: all five tests pass.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/HomeResumeState.swift IlumionateTests/HomeResumeStateTests.swift
git commit -m "feat(home): derive resume state from PlaybackProgressStore"
```

---

## Task 5: `CreateView` accepts a requested kind

The Visuals and Pulse doors need Create to open on a specific segment. `kind` is currently private `@State` with a hardcoded default.

**Files:**
- Modify: `Ilumionate/Create/CreateView.swift:12-22`

- [ ] **Step 1: Add the initialiser and trigger**

In `Ilumionate/Create/CreateView.swift`, replace:

```swift
struct CreateView: View {
    let engine: LightEngine

    @State private var kind: CreateSessionKind = .visualField
```

with:

```swift
struct CreateView: View {
    let engine: LightEngine

    /// Bumped by the caller to re-apply `requestedKind`. A plain value would be
    /// swallowed when someone taps the same home door twice, because the state
    /// is already equal — the same reason `readerQuickStartTrigger` exists.
    let kindRequestToken: Int
    let requestedKind: CreateSessionKind?

    @State private var kind: CreateSessionKind

    init(
        engine: LightEngine,
        kindRequestToken: Int = 0,
        requestedKind: CreateSessionKind? = nil
    ) {
        self.engine = engine
        self.kindRequestToken = kindRequestToken
        self.requestedKind = requestedKind
        self._kind = State(initialValue: requestedKind ?? .visualField)
    }
```

- [ ] **Step 2: Re-apply on a repeat request**

Find the `.onAppear` or the end of the `body`'s outermost `ZStack` in `CreateView` and attach:

```swift
.onChange(of: kindRequestToken) { _, _ in
    guard let requestedKind else { return }
    kind = requestedKind
}
```

Use the two-parameter `onChange` — the project forbids the one-parameter form.

- [ ] **Step 3: Verify the build**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. The existing `CreateView(engine:)` call site in `ContentView.swift:187` still compiles because both new parameters have defaults.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/Create/CreateView.swift
git commit -m "feat(create): accept a requested session kind from callers"
```

---

## Task 6: The quadrant grid

**Files:**
- Create: `Ilumionate/HomeDoorsView.swift`

- [ ] **Step 1: Write the view**

Create `Ilumionate/HomeDoorsView.swift`:

```swift
//
//  HomeDoorsView.swift
//  Ilumionate
//
//  The four doors, as equal-weight quadrants.
//
//  Equal size is the point: these are four things people can like, and sizing
//  one larger would assert a favourite the product does not have. Glass rather
//  than flat fill so the aurora behind stays visible.
//

import SwiftUI

struct HomeDoorsView: View {
    let onSelect: (HomeDoor) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: TranceSpacing.list), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: TranceSpacing.list) {
            ForEach(HomeDoor.allCases) { door in
                HomeDoorTile(door: door) { onSelect(door) }
            }
        }
    }
}

private struct HomeDoorTile: View {
    let door: HomeDoor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                Image(systemName: door.systemImage)
                    .font(.title2)
                    .foregroundStyle(door.tint)

                Spacer(minLength: TranceSpacing.content)

                Text(door.title)
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(Color.textPrimary)

                Text(door.subtitle)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .padding(TranceSpacing.card)
            .background(door.tint.opacity(0.10), in: .rect(cornerRadius: TranceRadius.glassCard))
            .liminalGlass(.roundedRect(cornerRadius: TranceRadius.glassCard))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(door.title)
        .accessibilityHint(door.subtitle)
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        HomeDoorsView { _ in }
            .padding(TranceSpacing.screen)
    }
}
```

- [ ] **Step 2: Verify the build and the preview**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/HomeDoorsView.swift
git commit -m "feat(home): add the four-door quadrant grid"
```

---

## Task 7: The resume pill

**Files:**
- Create: `Ilumionate/HomeResumePill.swift`

- [ ] **Step 1: Write the view**

Create `Ilumionate/HomeResumePill.swift`:

```swift
//
//  HomeResumePill.swift
//  Ilumionate
//
//  Pick up where you left off.
//
//  Subordinate to the doors on purpose: making resume the hero would quietly
//  bias every launch toward repeating the last session, which is the opposite
//  of letting someone find the part of the app they like.
//

import SwiftUI

struct HomeResumePill: View {
    let state: HomeResumeState
    let action: () -> Void

    private var remainingText: String {
        Duration.seconds(state.remaining).formatted(.time(pattern: .minuteSecond))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.roseGold)

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(state.title)
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text("\(remainingText) remaining")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 0)

                ProgressRingView(progress: state.progress)
            }
            .padding(TranceSpacing.card)
            .liminalGlass(.roundedRect(cornerRadius: TranceRadius.glassCard))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resume \(state.title)")
        .accessibilityValue("\(remainingText) remaining")
    }
}
```

`ProgressRingView` already exists — it is used by the current `continueSessionCard` at `HomeView.swift:365`. If the build cannot find it, run `grep -rn "struct ProgressRingView" Ilumionate` and import nothing extra; it is in the same target.

- [ ] **Step 2: Verify the build**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/HomeResumePill.swift
git commit -m "feat(home): add the resume pill"
```

---

## Task 8: Rewrite `HomeView`

The big one. Everything before this was additive; this is where the old home comes out.

**Files:**
- Modify: `Ilumionate/HomeView.swift` (full rewrite)

- [ ] **Step 1: Replace the whole file**

Replace the entire contents of `Ilumionate/HomeView.swift` with:

```swift
//
//  HomeView.swift
//  Ilumionate
//
//  The launcher. Greeting, four doors, and a way back into whatever you were
//  last doing — nothing else.
//
//  This screen used to carry nine sections and six competing ways to start
//  something, because it was compensating for a tab bar whose four slots do not
//  match the four things the app actually is. The doors below are that
//  compensation, made explicit and made equal.
//

import SwiftUI

// MARK: - Brainwave Category

enum BrainwaveCategory: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case sleep  = "Sleep"
    case focus  = "Focus"
    case energy = "Energy"
    case relax  = "Relax"
    case trance = "Trance"

    var emoji: String {
        switch self {
        case .sleep:  return "🌙"
        case .focus:  return "🎯"
        case .energy: return "⚡"
        case .relax:  return "🧘"
        case .trance: return "🌀"
        }
    }

    var haloColor: Color {
        switch self {
        case .sleep:  return .bwDelta
        case .focus:  return .bwAlpha
        case .energy: return .bwBeta
        case .relax:  return .bwTheta
        case .trance: return .bwGamma
        }
    }

    /// Average frequency of the first moment that determines which category a session belongs to
    var frequencyRange: ClosedRange<Double> {
        switch self {
        case .sleep:  return 0.5...4.0    // Delta
        case .relax:  return 4.0...8.0    // Theta
        case .focus:  return 8.0...14.0   // Alpha
        case .energy: return 14.0...30.0  // Beta
        case .trance: return 0.5...40.0   // All
        }
    }
}

// MARK: - HomeView

struct HomeView: View {
    @Binding var showingAudioLibrary: Bool
    @Binding var selectedSession: LightSession?

    let sessions: [LightSession]
    let audioFiles: [AudioFile]
    let engine: LightEngine
    let onRefresh: (() -> Void)?
    let onOpenReader: () -> Void
    let onOpenCreate: (CreateSessionKind) -> Void

    @State private var showingProfile = false
    @State private var playerFile: AudioFile?
    @State private var cardsVisible = false
    @State private var progressStore = PlaybackProgressStore.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("profileName") private var userName = ""
    @AppStorage("listeningHistoryEnabled") private var historyEnabled = true

    private let history = SessionHistoryManager.shared

    var body: some View {
        ZStack {
            AuroraBackground(
                mood: PortalRecommender.category(
                    forHour: Calendar.current.component(.hour, from: .now)
                )
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: TranceSpacing.content) {
                    greeting
                        .cardEntrance(visible: cardsVisible, delay: 0.00, reduceMotion: reduceMotion)

                    HomeDoorsView(onSelect: open)
                        .cardEntrance(visible: cardsVisible, delay: 0.06, reduceMotion: reduceMotion)

                    if let resume {
                        HomeResumePill(state: resume) { open(resume) }
                            .cardEntrance(visible: cardsVisible, delay: 0.12, reduceMotion: reduceMotion)
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.bottom, TranceSpacing.tabBarClearance)
            }
            .refreshable { await handleRefresh() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Settings", systemImage: "gearshape") {
                    TranceHaptics.shared.light()
                    showingProfile = true
                }
                .foregroundStyle(Color.roseGold)
            }
        }
        .onAppear {
            cardsVisible = false
            Task {
                try? await Task.sleep(for: .milliseconds(30))
                cardsVisible = true
            }
        }
        .onDisappear { cardsVisible = false }
        .sheet(isPresented: $showingProfile) {
            ProfileSettingsView()
        }
        .platformFullScreenCover(item: $playerFile) { file in
            UnifiedPlayerView(mode: .audioLight(audioFile: file), engine: engine)
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(spacing: TranceSpacing.micro) {
            Text(portalGreeting)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color.textSecondary)

            Text("Ready to descend?")
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(Color.textPrimary)

            if let streakText {
                Text(streakText)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textLight)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TranceSpacing.statusBar)
    }

    /// Only shown once there is momentum worth protecting — a "0 day streak"
    /// is a discouragement, not a metric.
    private var streakText: String? {
        guard historyEnabled else { return nil }
        let streak = history.currentStreak
        guard streak > 0 else { return nil }
        return streak == 1 ? "1 day streak" : "\(streak) day streak"
    }

    private var currentGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Good morning,"
        case 12..<17: return "Good afternoon,"
        case 17..<21: return "Good evening,"
        default:      return "Good night,"
        }
    }

    private var portalGreeting: String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            return currentGreeting.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        }
        return "\(currentGreeting) \(name)"
    }

    // MARK: - Resume

    private var resume: HomeResumeState? {
        HomeResumeState(snapshot: progressStore.snapshots.first)
    }

    // MARK: - Actions

    private func open(_ door: HomeDoor) {
        TranceHaptics.shared.light()
        UsageAnalytics.shared.homeCoreActionSelected(door.analyticsAction)
        switch door.route {
        case .audioLibrary:
            showingAudioLibrary = true
        case .reader:
            onOpenReader()
        case .create(let kind):
            onOpenCreate(kind)
        }
    }

    private func open(_ state: HomeResumeState) {
        TranceHaptics.shared.medium()
        switch state.kind {
        case .audio:
            playerFile = audioFiles.first { $0.id.uuidString == state.contentID }
        case .session:
            selectedSession = sessions.first { $0.id.uuidString == state.contentID }
        }
    }

    private func handleRefresh() async {
        TranceHaptics.shared.light()
        try? await Task.sleep(for: .seconds(0.8))
        onRefresh?()
    }
}

// MARK: - Card Entrance Modifier

private extension View {
    /// Slides the view up from a 20-pt offset while fading in.
    /// When `reduceMotion` is true the slide is suppressed and a quick fade
    /// is used instead, honoring the user's accessibility preference.
    func cardEntrance(visible: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: (visible || reduceMotion) ? 0 : 20)
            .animation(
                reduceMotion
                    ? .easeIn(duration: 0.15).delay(delay)
                    : .spring(response: 0.55, dampingFraction: 0.82).delay(delay),
                value: visible
            )
    }
}

// MARK: - Preview

#Preview {
    struct HomeViewPreview: View {
        @State private var showingAudioLibrary = false
        @State private var selectedSession: LightSession?
        @State private var engine = LightEngine()

        var body: some View {
            NavigationStack {
                HomeView(
                    showingAudioLibrary: $showingAudioLibrary,
                    selectedSession: $selectedSession,
                    sessions: [],
                    audioFiles: [],
                    onRefresh: nil,
                    onOpenReader: {},
                    onOpenCreate: { _ in },
                    engine: engine
                )
            }
        }
    }

    return HomeViewPreview()
}
```

- [ ] **Step 2: Build and expect failures at the call site**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build 2>&1 | grep -E "error:" | head -20
```

Expected: errors in `ContentView.swift` — `HomeView` no longer takes `showingSessionPlayer`, and now requires `onOpenCreate`. Task 9 fixes them.

- [ ] **Step 3: Do not commit yet**

The tree does not build. Continue to Task 9 and commit both together.

---

## Task 9: Wire `ContentView`

**Files:**
- Modify: `Ilumionate/ContentView.swift:22-45`, `:154-193`

- [ ] **Step 1: Add the Create request state**

In `Ilumionate/ContentView.swift`, alongside `readerQuickStartTrigger` (line 35), add:

```swift
    @State private var createKindRequestToken = 0
    @State private var createRequestedKind: CreateSessionKind?
```

- [ ] **Step 2: Update the `HomeView` call site**

Replace the `.home` branch of `featureContent` (lines 156-169):

```swift
            if selectedTab == .home {
                NavigationStack {
                    HomeView(
                        showingAudioLibrary: $showingAudioLibrary,
                        selectedSession: $selectedSession,
                        sessions: sessions,
                        audioFiles: audioFiles,
                        onRefresh: loadSessions,
                        onOpenReader: { selectedTab = .read },
                        onOpenCreate: openCreate,
                        engine: engine
                    )
                }
                .transition(.opacity)
            }
```

- [ ] **Step 3: Update the `CreateView` call site**

Replace the `.create` branch (lines 185-190):

```swift
            } else if selectedTab == .create {
                NavigationStack {
                    CreateView(
                        engine: engine,
                        kindRequestToken: createKindRequestToken,
                        requestedKind: createRequestedKind
                    )
                }
                .transition(.opacity)
            }
```

- [ ] **Step 4: Add the routing helper**

Next to `handleDeepLink` (line 295), add:

```swift
    /// Sends the user to Create with a segment preselected. The token is bumped
    /// so tapping the same home door twice re-applies the kind instead of being
    /// swallowed as a no-op.
    private func openCreate(_ kind: CreateSessionKind) {
        createRequestedKind = kind
        createKindRequestToken += 1
        selectedTab = .create
    }
```

- [ ] **Step 5: Remove the now-unused state**

`showingSessionPlayer` was only ever passed to `HomeView`. Confirm and remove:

```bash
grep -n "showingSessionPlayer" Ilumionate/ContentView.swift
```

If the only remaining hits are its `@State` declaration at line 28, delete that line. If anything else references it, leave it alone and note why.

- [ ] **Step 6: Build**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit the rewrite and the wiring together**

```bash
git add Ilumionate/HomeView.swift Ilumionate/ContentView.swift
git commit -m "feat(home): rewrite home as a launcher with four doors and a resume pill"
```

---

## Task 10: Delete what home no longer uses

Only after Task 1's gate passed.

**Files:**
- Delete: `Ilumionate/HomeView+FeaturedSessions.swift`, `Ilumionate/HomeStreakPill.swift`, `Ilumionate/HomeCoreActionsView.swift`, `Ilumionate/HomeView+MySessions.swift`

- [ ] **Step 1: Confirm nothing else references them**

```bash
grep -rn "HomeStreakPill\|HomeCoreActionsView\|mySessionsSection\|featuredSessionsSection\|MyGeneratedSessionItem\|loadMyGeneratedSessions" Ilumionate IlumionateTests --include="*.swift"
```

Expected: no hits outside the four files being deleted. Any hit elsewhere must be resolved before deleting.

- [ ] **Step 2: Delete the files**

```bash
git rm Ilumionate/HomeView+FeaturedSessions.swift \
       Ilumionate/HomeStreakPill.swift \
       Ilumionate/HomeCoreActionsView.swift \
       Ilumionate/HomeView+MySessions.swift
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(home): delete the sections the launcher replaces"
```

---

## Task 11: Check `CategorySessionSheet`'s other consumers

The rewrite dropped `CategorySessionSheet` and `WordmarkView` with the old file. Confirm nothing else wanted them.

**Files:**
- Read: whole target

- [ ] **Step 1: Search**

```bash
grep -rn "CategorySessionSheet\|WordmarkView\|stateChipsRow\|quickStartSection\|ContinueAudioCard" Ilumionate IlumionateTests --include="*.swift"
```

- [ ] **Step 2: Delete `ContinueAudioCard`**

Expected: the only hit is `Ilumionate/ContinueAudioCard.swift` defining itself. Its sole caller was `HomeView.swift:135`, which the rewrite removed, and the resume pill replaced it.

```bash
git rm Ilumionate/ContinueAudioCard.swift
```

`WordmarkView` and `CategorySessionSheet` were both defined and used only inside the old `HomeView.swift`, so the rewrite already removed them — this search should return nothing for either. If it unexpectedly returns a hit elsewhere, stop and restore that type to its own file rather than deleting a live caller's dependency.

- [ ] **Step 3: Build and commit**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -5
git add -A
git commit -m "refactor(home): remove views orphaned by the launcher rewrite"
```

---

## Task 12: Full verification on both platforms

**Files:** none

- [ ] **Step 1: Run the whole suite on macOS**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests 2>&1 | tail -30
```

Expected: all tests pass, including the new `HomeDoorTests` and `HomeResumeStateTests`.

`UsageAnalyticsTests.homeCoreActionTracksDestination` (line 268) exercises `.reader` only, so adding the two new cases in Task 2 does not affect it. If it fails anyway, the raw values changed — revert that, they are wire format.

- [ ] **Step 2: Run the whole suite on iOS Simulator**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests 2>&1 | tail -30
```

Expected: all tests pass.

- [ ] **Step 3: Build Mac Catalyst**

Catalyst is a compatibility destination and must keep compiling.

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Launch on the simulator and check the four things the spec calls done**

Build and run on iPhone 17 Pro, then confirm by looking:

1. Home shows a greeting, four equal quadrants, and — if something is in progress — a resume pill. Nothing else.
2. The settings gear is visible without scrolling and opens `ProfileSettingsView`.
3. Each door lands on the right surface. Visuals and Pulse land **on** the Create screen with the correct segment, not in a running session.
4. Set text size to the largest accessibility size in Settings → Accessibility → Display & Text Size. The quadrants reflow to one column with no clipped text.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix(home): address issues found in device verification"
```

---

## Task 13: Update `plan.md`

**Files:**
- Modify: `plan.md:76-80`

- [ ] **Step 1: Replace the Home Dashboard section**

Replace lines 76-80 of `plan.md`:

```markdown
### Home Dashboard
- ✅ Greeting section (dynamic time-based messages)
- ✅ Category icon grid (Sleep, Focus, Energy, Relax, Trance)
- ✅ Continue Session card, Quick Start section, Library scroll
- ✅ Staggered entrance animations
```

with:

```markdown
### Home Dashboard
- ✅ Launcher layout: greeting, four equal door quadrants, resume pill
- ✅ Settings reachable from a pinned toolbar gear (iOS); macOS uses the sidebar `SettingsLink`
- ✅ Staggered entrance animations, reduce-motion aware
- ✅ Quadrants reflow to one column at accessibility text sizes
- ❌ Reader is not resumable — TextTrance does not write `PlaybackProgressStore` snapshots
- ❌ Tab bar still maps to Home/Library/Read/Create rather than the four product surfaces
```

- [ ] **Step 2: Correct the stale Profile claim**

`plan.md:113` claims the profile screen with its weekly activity chart is done. `ProfileView` is dead code — nothing constructs it but its own `#Preview`. Replace that line:

```markdown
- ✅ Profile with weekly activity chart, session history
```

with:

```markdown
- ❌ Profile with weekly activity chart, session history — `ProfileView` exists but is unreachable (no caller); either give it an entry point or delete it
```

- [ ] **Step 3: Commit**

```bash
git add plan.md
git commit -m "docs: record the home launcher rewrite in plan.md"
```

---

## Self-Review Notes

**Spec coverage.** Every spec section maps to a task: composition → 8, doors → 3/6, routing → 5/9, resume → 4/7, deletions → 10/11, Dynamic Type risk → 6 and 12.4, testing → 3/4/12, definition of done → 12.4 and 13. The spec's "verify Library covers home's lists" precondition is Task 1, gating Task 10.

**Known non-coverage, deliberate.** `CreateView`'s initial-kind behaviour has no unit test — the state is private to a SwiftUI view and any test would assert on a test double rather than the view. It is verified by build plus the manual check in Task 12.4. Do not add a hollow test to close this gap.

**Type consistency.** `HomeDoor.analyticsAction` returns `HomeCoreAction` (Task 2 defines all four cases before Task 3 uses them). `HomeDoorRoute.create` carries `CreateSessionKind`, matching `CreateView.requestedKind` in Task 5 and `openCreate(_:)` in Task 9. `HomeResumeState.kind` is `ResumablePlaybackKind`, matching `PlaybackProgressSnapshot.kind`.

**Ordering constraint.** Tasks 8 and 9 leave the tree un-buildable between them and commit together. Every other task ends green.
