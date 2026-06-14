# In-App Reading Sources + Adult Directories — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Reading Source open inside the app (in-app Safari sheet) instead of external Safari, add eight free adult (18+) hypnosis-story directories to the catalog, and gate the adult ones behind a one-time confirmation.

**Architecture:** A pure `openAction(for:adultConfirmed:)` function decides whether a tapped source browses immediately or must clear an adult gate. `ReadingSourceDirectoryView` maps that decision to SwiftUI state: a `.sheet(item:)` presenting a new `SafariBrowserView` (an `SFSafariViewController` wrapper), and an `.alert` for the gate whose confirmation is persisted in `@AppStorage`. New sources are static curated entries.

**Tech Stack:** SwiftUI, SafariServices (`SFSafariViewController`), `@AppStorage`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-13-in-app-reading-sources-design.md`

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `Ilumionate/TextTrance/ReadingSource.swift` | Catalog data + `ReadingSourceOpenAction` enum + `openAction` gate function | Modify |
| `Ilumionate/TextTrance/SafariBrowserView.swift` | `SFSafariViewController` SwiftUI wrapper | **Create** |
| `Ilumionate/TextTrance/ReadingSourceDirectoryView.swift` | In-app sheet presentation, adult gate alert, "18+" badge | Modify |
| `IlumionateTests/TextTrance/ReadingSourceStoreTests.swift` | Fix the existing "no adultOnly" assertion | Modify |
| `IlumionateTests/TextTrance/ReadingSourceCatalogTests.swift` | New-source presence, rating/policy, URL validity, gate logic | **Create** |

**Build/test environment (from project memory — use exactly):**
- Scheme: `Ilumionate`
- Destination: `platform=iOS Simulator,name=iPhone 17` (iOS 26.2 — no iPhone 16 exists)
- New `.swift` files in `Ilumionate/TextTrance/` and `IlumionateTests/TextTrance/` are picked up automatically (synchronized groups). After creating a file, the first build confirms membership.

---

## Task 1: Adult-gate decision function

Pure logic first, fully unit-testable, no UI.

**Files:**
- Modify: `Ilumionate/TextTrance/ReadingSource.swift` (append at end of file)
- Create: `IlumionateTests/TextTrance/ReadingSourceCatalogTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/TextTrance/ReadingSourceCatalogTests.swift`:

```swift
//  ReadingSourceCatalogTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct ReadingSourceCatalogTests {

    // MARK: Gate logic

    private func makeSource(rating: ReadingSourceContentRating) -> ReadingSource {
        ReadingSource(
            id: "test-\(rating.rawValue)",
            title: "Test",
            url: URL(string: "https://example.com/")!,
            category: .scriptDirectory,
            summary: "",
            licenseKind: .thirdPartyTerms,
            licenseNote: "",
            contentNote: "",
            importPolicy: .linkOnly,
            contentRating: rating,
            isCurated: true,
            addedDate: nil
        )
    }

    @Test func adultSourceUnconfirmedRequestsConfirmation() {
        let source = makeSource(rating: .adultOnly)
        #expect(openAction(for: source, adultConfirmed: false) == .confirmAdult(source.url))
    }

    @Test func adultSourceConfirmedBrowsesDirectly() {
        let source = makeSource(rating: .adultOnly)
        #expect(openAction(for: source, adultConfirmed: true) == .browse(source.url))
    }

    @Test func generalSourceBrowsesRegardlessOfConfirmation() {
        let source = makeSource(rating: .general)
        #expect(openAction(for: source, adultConfirmed: false) == .browse(source.url))
        #expect(openAction(for: source, adultConfirmed: true) == .browse(source.url))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/ReadingSourceCatalogTests 2>&1 | tail -30
```
Expected: COMPILE FAILURE — `cannot find 'openAction' in scope` / `cannot find 'ReadingSourceOpenAction'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Ilumionate/TextTrance/ReadingSource.swift`:

```swift
/// What should happen when the user taps a reading source.
enum ReadingSourceOpenAction: Equatable {
    /// Open the URL in the in-app browser now.
    case browse(URL)
    /// Adult source not yet acknowledged — present the 18+ confirmation first.
    case confirmAdult(URL)
}

/// Decides whether a tapped source opens immediately or must clear the adult gate.
/// Pure so it can be unit-tested without any UI.
func openAction(for source: ReadingSource, adultConfirmed: Bool) -> ReadingSourceOpenAction {
    if source.contentRating == .adultOnly && !adultConfirmed {
        return .confirmAdult(source.url)
    }
    return .browse(source.url)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/ReadingSourceCatalogTests 2>&1 | tail -20
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/ReadingSource.swift IlumionateTests/TextTrance/ReadingSourceCatalogTests.swift
git commit -m "feat(text-trance): add reading-source adult-gate decision function"
```

---

## Task 2: Add the eight adult directories to the catalog

TDD: assert the new sources exist with the right shape, watch it fail, then add them. This task also fixes the pre-existing test that forbids `.adultOnly`.

**Files:**
- Modify: `IlumionateTests/TextTrance/ReadingSourceCatalogTests.swift`
- Modify: `IlumionateTests/TextTrance/ReadingSourceStoreTests.swift:11-30` (the `curatedSourcesHaveStableSafeShape` test)
- Modify: `Ilumionate/TextTrance/ReadingSource.swift:70-155` (the `curatedSources` array)

- [ ] **Step 1: Write the failing catalog tests**

Add these methods inside `struct ReadingSourceCatalogTests` in `ReadingSourceCatalogTests.swift`:

```swift
    // MARK: New adult directories

    private static let newAdultIDs = [
        "mc-stories",
        "spirals-nightclub",
        "nimja-hypno",
        "literotica-mc",
        "warpmymind",
        "hypnohub",
        "hypnotube-stories",
        "reddit-hypnautimagery"
    ]

    @Test func newAdultDirectoriesArePresent() {
        let ids = Set(ReadingSourceCatalog.curatedSources.map(\.id))
        for id in Self.newAdultIDs {
            #expect(ids.contains(id), "missing curated source: \(id)")
        }
    }

    @Test func newAdultDirectoriesAreAdultLinkOnly() {
        let byID = Dictionary(
            uniqueKeysWithValues: ReadingSourceCatalog.curatedSources.map { ($0.id, $0) }
        )
        for id in Self.newAdultIDs {
            let source = byID[id]
            #expect(source?.contentRating == .adultOnly, "\(id) should be adultOnly")
            #expect(source?.importPolicy == .linkOnly, "\(id) should be linkOnly")
        }
    }

    @Test func everyCuratedSourceHasWebURL() {
        for source in ReadingSourceCatalog.curatedSources {
            let scheme = source.url.scheme?.lowercased()
            #expect(scheme == "https" || scheme == "http", "\(source.id) has non-web URL")
            #expect(source.url.host?.isEmpty == false, "\(source.id) has empty host")
        }
    }
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
xcodebuild test -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/ReadingSourceCatalogTests/newAdultDirectoriesArePresent 2>&1 | tail -20
```
Expected: FAIL — `missing curated source: mc-stories`.

- [ ] **Step 3: Add the eight sources**

In `Ilumionate/TextTrance/ReadingSource.swift`, inside the `curatedSources` array literal, insert these eight elements after the existing `free-hypnosis-scripts-info` entry (before the closing `]` at line ~155). Keep the trailing comma rules valid (add a comma after the existing last element):

```swift
        ,
        ReadingSource(
            id: "mc-stories",
            title: "MC Stories",
            url: URL(string: "https://mcstories.com/")!,
            category: .scriptDirectory,
            summary: "The Erotic Mind-Control Story Archive — a large free hypnosis/mind-control story library.",
            licenseKind: .thirdPartyTerms,
            licenseNote: "Link-only. Stories are individually authored; review site terms before any reuse.",
            contentNote: "Adult (18+) erotic hypnosis fiction.",
            importPolicy: .linkOnly,
            contentRating: .adultOnly,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "spirals-nightclub",
            title: "Spirals Nightclub",
            url: URL(string: "http://www.spiralsnightclub.com/")!,
            category: .scriptDirectory,
            summary: "Erotic hypnosis community with free stories and scripts.",
            licenseKind: .thirdPartyTerms,
            licenseNote: "Link-only. Community-posted material; review site terms before reuse.",
            contentNote: "Adult (18+) erotic hypnosis content.",
            importPolicy: .linkOnly,
            contentRating: .adultOnly,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "nimja-hypno",
            title: "Nimja Hypno Scripts",
            url: URL(string: "https://hypno.nimja.com/script")!,
            category: .scriptDirectory,
            summary: "Free hypnosis induction script builder and library.",
            licenseKind: .thirdPartyTerms,
            licenseNote: "Link-only. Review site terms before reuse.",
            contentNote: "Adult (18+) erotic hypnosis material.",
            importPolicy: .linkOnly,
            contentRating: .adultOnly,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "literotica-mc",
            title: "Literotica – Mind Control",
            url: URL(string: "https://www.literotica.com/c/mind-control-stories")!,
            category: .scriptDirectory,
            summary: "Literotica's free Mind Control category — a large hypnosis/MC story collection.",
            licenseKind: .thirdPartyTerms,
            licenseNote: "Link-only. Stories are user-submitted; review site terms before reuse.",
            contentNote: "Adult (18+) erotic fiction.",
            importPolicy: .linkOnly,
            contentRating: .adultOnly,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "warpmymind",
            title: "Warp My Mind",
            url: URL(string: "https://www.warpmymind.com/")!,
            category: .scriptDirectory,
            summary: "Long-running free erotic hypnosis community (files, sessions, and text).",
            licenseKind: .thirdPartyTerms,
            licenseNote: "Link-only. Review site terms before reuse.",
            contentNote: "Adult (18+) erotic hypnosis content.",
            importPolicy: .linkOnly,
            contentRating: .adultOnly,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "hypnohub",
            title: "HypnoHub",
            url: URL(string: "https://hypnohub.net/")!,
            category: .scriptDirectory,
            summary: "Free hypnosis-themed imageboard with caption stories.",
            licenseKind: .thirdPartyTerms,
            licenseNote: "Link-only. User-submitted material; review site terms before reuse.",
            contentNote: "Adult (18+) erotic hypnosis imagery and captions.",
            importPolicy: .linkOnly,
            contentRating: .adultOnly,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "hypnotube-stories",
            title: "HypnoTube Stories",
            url: URL(string: "https://hypnotube.com/stories/")!,
            category: .scriptDirectory,
            summary: "The text-stories section of HypnoTube's free hypnosis community.",
            licenseKind: .thirdPartyTerms,
            licenseNote: "Link-only. User-submitted material; review site terms before reuse.",
            contentNote: "Adult (18+) erotic hypnosis content.",
            importPolicy: .linkOnly,
            contentRating: .adultOnly,
            isCurated: true,
            addedDate: nil
        ),
        ReadingSource(
            id: "reddit-hypnautimagery",
            title: "r/hypnautimagery",
            url: URL(string: "https://www.reddit.com/r/hypnautimagery/")!,
            category: .scriptDirectory,
            summary: "Reddit community for hypnosis stories and imagery.",
            licenseKind: .thirdPartyTerms,
            licenseNote: "Link-only. User-submitted material; review Reddit and author terms before reuse.",
            contentNote: "Adult (18+) erotic hypnosis content.",
            importPolicy: .linkOnly,
            contentRating: .adultOnly,
            isCurated: true,
            addedDate: nil
        )
```

- [ ] **Step 4: Fix the pre-existing "no adultOnly" assertion**

The current test in `IlumionateTests/TextTrance/ReadingSourceStoreTests.swift` forbids any `.adultOnly` source; that invariant no longer holds. Replace the body of `curatedSourcesHaveStableSafeShape` (lines ~11-30). Find:

```swift
    @Test func curatedSourcesHaveStableSafeShape() {
        let sources = ReadingSourceCatalog.curatedSources
        let allSourcesAreCurated = sources.allSatisfy { $0.isCurated }
        let allSourcesAvoidAdultOnlyRating = sources.allSatisfy { $0.contentRating != .adultOnly }
        let allSourcesUseWebURLs = sources.allSatisfy { source in
            let scheme = source.url.scheme?.lowercased()
            return scheme == "https" || scheme == "http"
        }

        #expect(sources.count >= 5)
        #expect(Set(sources.map(\.id)).count == sources.count)
        #expect(allSourcesAreCurated)
        #expect(allSourcesAvoidAdultOnlyRating)
        #expect(allSourcesUseWebURLs)
    }
```

Replace with (drops the adult-rating ban; adult sources are now allowed and gated at the UI):

```swift
    @Test func curatedSourcesHaveStableSafeShape() {
        let sources = ReadingSourceCatalog.curatedSources
        let allSourcesAreCurated = sources.allSatisfy { $0.isCurated }
        let allSourcesUseWebURLs = sources.allSatisfy { source in
            let scheme = source.url.scheme?.lowercased()
            return scheme == "https" || scheme == "http"
        }

        #expect(sources.count >= 5)
        #expect(Set(sources.map(\.id)).count == sources.count)
        #expect(allSourcesAreCurated)
        #expect(allSourcesUseWebURLs)
    }
```

- [ ] **Step 5: Run the catalog + store tests to verify they pass**

Run:
```bash
xcodebuild test -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/ReadingSourceCatalogTests \
  -only-testing:IlumionateTests/ReadingSourceStoreTests 2>&1 | tail -25
```
Expected: PASS (all catalog tests + all store tests green).

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/TextTrance/ReadingSource.swift \
        IlumionateTests/TextTrance/ReadingSourceCatalogTests.swift \
        IlumionateTests/TextTrance/ReadingSourceStoreTests.swift
git commit -m "feat(text-trance): add eight free adult hypnosis directories to catalog"
```

---

## Task 3: In-app Safari browser wrapper

**Files:**
- Create: `Ilumionate/TextTrance/SafariBrowserView.swift`

`SFSafariViewController`'s representable can't be exercised by a unit test (it needs a live `Context`), so verification here is a successful build. Keep the file tiny and correct.

- [ ] **Step 1: Create the wrapper**

Create `Ilumionate/TextTrance/SafariBrowserView.swift`:

```swift
//  SafariBrowserView.swift
//  Ilumionate
//
//  In-app browser for reading sources. Wraps SFSafariViewController so external
//  reading material opens inside the app instead of switching to Safari.

import SafariServices
import SwiftUI

struct SafariBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(.roseGold)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
```

- [ ] **Step 2: Build to verify it compiles and is in the target**

Run:
```bash
xcodebuild build -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`. (A build error of "cannot find type SafariBrowserView" in a later task would indicate the synchronized group didn't pick it up — but the file is in `Ilumionate/TextTrance/`, which is synchronized, so it will.)

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/TextTrance/SafariBrowserView.swift
git commit -m "feat(text-trance): add in-app SFSafariViewController browser wrapper"
```

---

## Task 4: Wire the directory to the in-app browser + adult gate + badge

Replaces external-Safari opening with the in-app sheet for all sources, adds the one-time adult confirmation, and marks adult cards with an "18+" badge.

**Files:**
- Modify: `Ilumionate/TextTrance/ReadingSourceDirectoryView.swift`

This is UI wiring; verification is a green build plus an on-simulator smoke test (the project's standing lesson: build-green ≠ UI-works).

- [ ] **Step 1: Add presentation state and remove `openURL`**

In `ReadingSourceDirectoryView`, replace the environment/state block. Find:

```swift
    @State private var store: ReadingSourceStore
    @State private var selectedCategory: ReadingSourceCategory?
    @State private var searchText = ""
    @State private var showingAddSource = false

    @Environment(\.openURL) private var openURL
```

Replace with:

```swift
    @State private var store: ReadingSourceStore
    @State private var selectedCategory: ReadingSourceCategory?
    @State private var searchText = ""
    @State private var showingAddSource = false
    @State private var browserDestination: BrowserDestination?
    @State private var pendingAdultURL: URL?

    @AppStorage("readingSourceAdultConfirmed") private var adultConfirmed = false
```

- [ ] **Step 2: Add the browser sheet and adult-gate alert**

In `ReadingSourceDirectoryView.body`, find the existing add-source sheet:

```swift
        .sheet(isPresented: $showingAddSource) {
            AddReadingSourceSheet(store: store)
        }
```

Add directly after it:

```swift
        .sheet(item: $browserDestination) { destination in
            SafariBrowserView(url: destination.url)
                .ignoresSafeArea()
        }
        .alert("Adult content", isPresented: adultGatePresented, presenting: pendingAdultURL) { url in
            Button("Continue", role: .destructive) {
                adultConfirmed = true
                pendingAdultURL = nil
                browserDestination = BrowserDestination(url: url)
            }
            Button("Cancel", role: .cancel) {
                pendingAdultURL = nil
            }
        } message: { _ in
            Text("This source links to adult (18+) material. Continue?")
        }
```

- [ ] **Step 3: Replace `openSource` and add the alert binding + destination type**

Find the existing `openSource`:

```swift
    private func openSource(_ source: ReadingSource) {
        TranceHaptics.shared.light()
        openURL(source.url)
    }
```

Replace with:

```swift
    private func openSource(_ source: ReadingSource) {
        TranceHaptics.shared.light()
        switch openAction(for: source, adultConfirmed: adultConfirmed) {
        case .browse(let url):
            browserDestination = BrowserDestination(url: url)
        case .confirmAdult(let url):
            pendingAdultURL = url
        }
    }

    private var adultGatePresented: Binding<Bool> {
        Binding(
            get: { pendingAdultURL != nil },
            set: { if !$0 { pendingAdultURL = nil } }
        )
    }
```

Add this private type at file scope (e.g. just below the `ReadingSourceDirectoryView` struct's closing brace, before `private struct SourceSection`):

```swift
private struct BrowserDestination: Identifiable {
    let id = UUID()
    let url: URL
}
```

- [ ] **Step 4: Add the "18+" badge to adult cards**

In `ReadingSourceCard.body`, find the header `HStack` that ends with the policy badge:

```swift
                    Spacer()

                    ImportPolicyBadge(policy: source.importPolicy)
                }
```

Replace with:

```swift
                    Spacer()

                    if source.contentRating == .adultOnly {
                        AdultBadge()
                    }
                    ImportPolicyBadge(policy: source.importPolicy)
                }
```

Add the `AdultBadge` view just below the `ImportPolicyBadge` struct definition:

```swift
private struct AdultBadge: View {
    var body: some View {
        Text("18+")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.warmAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.warmAccent.opacity(0.16), in: Capsule())
            .accessibilityLabel("Adult content")
    }
}
```

> Note: `Color.warmAccent` is already used in this file (`SourceIcon.color` → `.warmAccent`), so it exists. If the build reports it missing, substitute `.roseGold`.

- [ ] **Step 5: Build to verify it compiles**

Run:
```bash
xcodebuild build -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run the full TextTrance test suite (no regressions)**

Run:
```bash
xcodebuild test -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/ReadingSourceCatalogTests \
  -only-testing:IlumionateTests/ReadingSourceStoreTests 2>&1 | tail -25
```
Expected: PASS.

- [ ] **Step 7: On-simulator smoke test (REQUIRED — build-green ≠ UI-works)**

Launch the app on the iPhone 17 simulator. Navigate: Read tab → Reading Sources (the "Find more scripts online" cross-link or Library row). Verify:
1. A **general** source (e.g. Project Gutenberg) → tapping "Open" presents the in-app Safari sheet (with a Done button), NOT external Safari.
2. A **new adult** source (e.g. MC Stories) shows the **18+** badge, and the first "Open" shows the "Adult content" alert.
3. Tapping **Continue** opens the in-app sheet; dismiss, reopen another adult source → it now opens **directly** (no alert) because `adultConfirmed` persisted.
4. Tapping **Cancel** on the alert opens nothing.

If any of these fail, fix before committing. (Tab-bar overlap caveat from project memory: the directory list already adds `TranceSpacing.tabBarClearance`; the Safari sheet is a full-screen `.sheet`, so the floating tab bar does not overlap it.)

- [ ] **Step 8: Commit**

```bash
git add Ilumionate/TextTrance/ReadingSourceDirectoryView.swift
git commit -m "feat(text-trance): open reading sources in-app with one-time adult gate"
```

---

## Self-Review Notes (addressed)

- **Spec coverage:** in-app rendering for all sources (Task 4) ✓; eight adult sources (Task 2) ✓; `SFSafariViewController` wrapper (Task 3) ✓; one-time global gate via `@AppStorage` (Task 4) ✓; "18+" badge (Task 4) ✓; `openAction` pure function + tests (Task 1) ✓; catalog/URL-validity tests (Task 2) ✓.
- **Pre-existing conflict resolved:** Task 2 Step 4 fixes `curatedSourcesHaveStableSafeShape`, which would otherwise fail the moment adult sources are added.
- **Type consistency:** `ReadingSourceOpenAction` (`.browse`/`.confirmAdult`), `openAction(for:adultConfirmed:)`, `BrowserDestination`, `SafariBrowserView(url:)`, `AdultBadge` are used with identical signatures across tasks.
- **Out of scope (unchanged):** no scraping/import, no per-source gate, no new category.
```
