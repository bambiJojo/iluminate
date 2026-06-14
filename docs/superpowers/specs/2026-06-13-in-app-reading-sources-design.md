# In-App Reading Sources + Adult Hypnosis Directories — Design

**Date:** 2026-06-13
**Status:** Approved (brainstorming)
**Branch:** `feature/phase-eval-harness`
**Related:** `2026-06-10-text-trance-design.md`, `reading-sources-release-gates.md`

## Goal

Extend the Text Trance "Reading Sources" directory so that:

1. **Source content stays inside the app.** Today every source opens in external
   Safari via `@Environment(\.openURL)`. Replace that with an in-app browser sheet
   so the user never leaves Ilumionate.
2. **Add free hypnosis-story directories** the user requested, all of which are
   erotic / adult (18+). The original catalog deliberately excluded `.adultOnly`
   sources; this design intentionally reverses that, behind a content gate.

## Non-Goals (out of scope)

- No text scraping, caching, or import from these sites. They remain `linkOnly`.
  Web → RSVP text import is still the future, design-gated M4 milestone.
- No per-source gating, no new `ReadingSourceCategory`. A single global adult gate
  plus an "18+" badge is sufficient.
- No change to how bundled first-party scripts work.

## Decisions (from brainstorming)

| Question | Decision |
|----------|----------|
| How does "stay in app" render? | **`SFSafariViewController`** (in-app Safari sheet). Apple-maintained, full site functionality (login/cookies/JS), near-zero maintenance. Trade-off accepted: it's a black box, so it can never feed text to the RSVP reader — that path is deferred to M4. |
| Adult content handling | **One-time global confirmation gate** + a small "18+" badge on adult cards. Not a separate category. |
| Scope of in-app rendering | **All** sources (Gutenberg etc. included) open in the in-app sheet, for consistency. External Safari behavior is removed entirely. |

## New Sources

Eight curated entries appended to `ReadingSourceCatalog.curatedSources`
(`Ilumionate/TextTrance/ReadingSource.swift`). All share:
`category: .scriptDirectory`, `importPolicy: .linkOnly`,
`contentRating: .adultOnly`, `isCurated: true`, `addedDate: nil`.

| id | title | url |
|----|-------|-----|
| `mc-stories` | MC Stories | `https://mcstories.com/` |
| `spirals-nightclub` | Spirals Nightclub | `http://www.spiralsnightclub.com/` |
| `nimja-hypno` | Nimja Hypno Scripts | `https://hypno.nimja.com/script` |
| `literotica-mc` | Literotica – Mind Control | `https://www.literotica.com/c/mind-control-stories` |
| `warpmymind` | Warp My Mind | `https://www.warpmymind.com/` |
| `hypnohub` | HypnoHub | `https://hypnohub.net/` |
| `hypnotube-stories` | HypnoTube Stories | `https://hypnotube.com/stories/` |
| `reddit-hypnautimagery` | r/hypnautimagery | `https://www.reddit.com/r/hypnautimagery/` |

`licenseKind: .thirdPartyTerms`. `licenseNote`/`contentNote` follow the existing
pattern: link-only, review site terms before reuse, and an explicit adult-material
note in `contentNote`.

Note: `spirals-nightclub` is plain `http` (no TLS). `SFSafariViewController` loads
it fine; no ATS exception is needed because SafariViewController is out-of-process.

## Components

### 1. `SafariBrowserView` (new file)

`Ilumionate/TextTrance/SafariBrowserView.swift`

- A `UIViewControllerRepresentable` wrapping `SFSafariViewController`.
- Justified UIKit/SafariServices exception: it is the only API that provides the
  in-app Safari sheet, and it is the approach the user selected.
- Tinted to the Trance palette: `preferredControlTintColor = UIColor(.roseGold)`
  (and `preferredBarTintColor` to the background) via the controller, or set on the
  representable. Keep it minimal.
- Presented via `.sheet(item:)`.

```swift
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

To drive `.sheet(item:)`, wrap the URL in a small `Identifiable` value
(`struct BrowserDestination: Identifiable { let id = UUID(); let url: URL }`) or
make the presentation key the URL via an `Identifiable` conformance helper. Keep it
local to the directory view.

### 2. `ReadingSourceDirectoryView` changes

`Ilumionate/TextTrance/ReadingSourceDirectoryView.swift`

- Remove `@Environment(\.openURL)`.
- Add state: `@State private var browserDestination: BrowserDestination?` and
  `@State private var pendingAdultURL: URL?` (URL awaiting gate confirmation),
  `@AppStorage("readingSourceAdultConfirmed") private var adultConfirmed = false`.
- Rewrite `openSource(_:)`:
  - If `source.contentRating == .adultOnly && !adultConfirmed` →
    set `pendingAdultURL = source.url` (triggers the confirm dialog).
  - Else → `browserDestination = BrowserDestination(url: source.url)`.
- Add `.sheet(item: $browserDestination) { SafariBrowserView(url: $0.url) }`.
- Add `.confirmationDialog` (or `.alert`) bound to `pendingAdultURL != nil`:
  - Title: "Adult content"
  - Message: "This source links to adult (18+) material. Continue?"
  - Confirm button: sets `adultConfirmed = true`, opens
    `browserDestination = BrowserDestination(url: pendingAdultURL!)`, clears pending.
  - Cancel: clears `pendingAdultURL`.
- The card/contextMenu "Open" actions route through `openSource` unchanged; only the
  destination mechanism changes. Update the context-menu icon from `safari` to a
  neutral choice if desired (optional, cosmetic).

### 3. "18+" badge

In `ReadingSourceCard`, when `source.contentRating == .adultOnly`, render a small
capsule reading "18+" next to (or replacing position with) the `ImportPolicyBadge`.
Style: `.font(.system(size: 10, weight: .semibold))`, warm/red accent on a tinted
capsule, consistent with `ImportPolicyBadge`.

### 4. Gate decision as a pure function (testability)

Extract the branch into a free function so it can be unit-tested without UI:

```swift
enum ReadingSourceOpenAction: Equatable {
    case browse(URL)
    case confirmAdult(URL)
}

func openAction(for source: ReadingSource, adultConfirmed: Bool) -> ReadingSourceOpenAction {
    if source.contentRating == .adultOnly && !adultConfirmed {
        return .confirmAdult(source.url)
    }
    return .browse(source.url)
}
```

Place alongside the view or in `ReadingSource.swift`. The view calls this and maps
the result to state.

## Data Flow

```
tap "Open" on card
      │
      ▼
openAction(for: source, adultConfirmed:)
      │
      ├── .browse(url) ─────────────► browserDestination set ──► .sheet → SFSafariViewController
      │
      └── .confirmAdult(url) ──► pendingAdultURL set ──► confirmationDialog
                                          │
                            confirm ──► adultConfirmed = true,
                                        browserDestination = url ──► .sheet → SFSafariViewController
                            cancel  ──► pendingAdultURL = nil
```

## Error Handling

- URLs are compile-time literals via `URL(string:)!`. They are validated once by a
  test that decodes the catalog and asserts every URL is non-nil with an http/https
  scheme — so a typo fails a test, never ships a crash. (The force-unwrap pattern
  already exists in the catalog; the test is the guard.)
- `SFSafariViewController` handles network/load failures itself (its own error UI);
  no custom handling required.

## Testing

Target: the existing ReadingSource test file (`ReadingSourceStoreTests.swift` or a
new `ReadingSourceCatalogTests.swift` in the same target).

1. **Catalog presence:** each of the eight new ids exists in
   `ReadingSourceCatalog.curatedSources`.
2. **Adult rating + policy:** each new source is `.adultOnly` and `.linkOnly`.
3. **URL validity:** every curated source URL has an `http`/`https` scheme and a
   non-empty host (covers the whole catalog, old and new).
4. **Gate logic:** `openAction(for:adultConfirmed:)`
   - adult + `adultConfirmed == false` → `.confirmAdult(url)`
   - adult + `adultConfirmed == true` → `.browse(url)`
   - non-adult (e.g. Gutenberg) + either flag → `.browse(url)`

Use Swift Testing (`@Test`/`#expect`), per project convention.

## App Store / Compliance Note

Linking to this content raises the app's age rating to 17+ and is review-sensitive
(App Review Guideline 1.1, objectionable content). The one-time gate is a mitigation,
not a guarantee. This design is appropriate for personal/sideloaded use; revisit the
gating strength (and the App Store age-rating questionnaire) before any public
submission.

## Files Touched

- `Ilumionate/TextTrance/ReadingSource.swift` — +8 curated sources, + `openAction` (or new file)
- `Ilumionate/TextTrance/ReadingSourceDirectoryView.swift` — in-app sheet + gate + badge
- `Ilumionate/TextTrance/SafariBrowserView.swift` — **new**
- `IlumionateTests/.../ReadingSourceCatalogTests.swift` — **new** (or extend existing)

All new files need Xcode target membership; the TextTrance folder is a synchronized
group, so on-disk placement should suffice — verify the build picks them up.
