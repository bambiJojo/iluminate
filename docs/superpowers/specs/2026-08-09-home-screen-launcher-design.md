# Home Screen — Launcher Redesign

**Date:** 2026-08-09
**Branch:** `feature/reader-hypnotic-visuals`
**Status:** Design approved, not implemented

---

## Problem

`HomeView.swift` is 838 lines rendering nine stacked sections that offer six distinct
ways to start something:

| Affordance | Source | Starts |
|---|---|---|
| Begin orb | `portalSection` | a bundled light session |
| State chips | `stateChipsRow` | a filtered list sheet |
| Audio / Reader | `HomeCoreActionsView` | two of four modalities |
| Continue card | `continueSessionCard` | last session or audio |
| Session lists | `mySessions`, `featuredSessions` | a specific session |
| Quick presets | `quickStartSection` | a flash session |

Three concrete defects behind that sprawl:

1. **The chips lie.** `CategorySessionSheet` filters by the frequency of a session's
   first moment, then falls back to *all sessions* when the filter is empty
   (`HomeView.swift:746`). `.trance` returns everything by design. Tapping "Sleep"
   and tapping "Focus" can present identical lists.
2. **Two vocabularies for one concept.** `stateChipsRow` names brainwave bands by
   intent (Sleep / Relax / Focus / Energy); `quickStartSection` names the same bands
   by Greek letter (Delta / Theta / Alpha). They map one-to-one and behave
   incompatibly — one shows a list, the other launches a session.
3. **The recommender only sees canned content.** `PortalRecommender.recommend`
   draws exclusively from the bundled `sessions` array
   (`PortalRecommender.swift:25`). It never considers imported audio or generated
   sessions, so home's primary action is a shortcut to shipped content.

The root cause is navigational. The tab bar's four slots do not match the four things
the product actually is:

| Product surface | Front door today | Depth |
|---|---|---|
| Reader | `.read` tab | tab |
| Audio analyzer | `AudioLibraryView`, a sheet off home | sheet, no tab |
| Hypnotic visuals | 4th segment of Create's picker (`CreateSessionKind.swift:18`) | tab → segment |
| Synced audio | tap an analyzed file in the audio library | sheet → row → player |

Meanwhile `Library` — browsing light sessions — holds a whole tab. Home has been
compensating for that mismatch by growing a new entry point per modality.

## Decisions

| # | Question | Choice |
|---|---|---|
| 1 | What is home for? | **Launcher.** One tap in, then get out of the way. Lists move to Library. |
| 2 | What does it launch? | **No default modality.** Reader, audio analysis, hypnotic visuals and synced audio are equal citizens. Home exposes all four; the user settles. |
| 3 | Does home adapt? | **Fixed doors, adaptive resume.** The four doors never move. One row above them reflects the last activity. |
| 4 | Settings route | **Pinned gear in the home toolbar.** `HomeView` already sits in a `NavigationStack`. |
| 5 | Chips and presets | **Delete both rows.** Intent and frequency selection belong in Create and Library. |
| 6 | Tab bar | **Leave it alone this round.** Home compensates via deep links. Revisit once the four nouns prove out. |
| 7 | Visual direction | **D — quadrant field.** |

### On decision 2

Stated by the user: *"I don't want to pick the feature that the user wants. I want
them to explore them all and then facilitate them using whatever part(s) of the app
they enjoy."* Every downstream choice follows from this — notably the rejection of
direction C (bento), whose asymmetric tile sizes encode a ranking the product does
not want to assert.

### On decision 7

Four directions were mocked. D was chosen because it is the only one where all four
doors are equal in size and none can be scrolled past, which is what "explore them
all" requires. A (orb ritual) makes resume the hero and quietly biases toward
repeating the last session. B (utility stack) is the accessibility fallback if the
quadrants read as too bold on glass.

**The quadrants are translucent, not flat fills.** Solid colour blocks would fight
`AuroraBackground` and `Color.bgPrimary`. Each quadrant is a `LiminalCard`-style
glass surface tinted with its modality colour, letting the aurora through.

## Target composition

Top to bottom:

1. **Toolbar** — gear, trailing, pinned. Opens `ProfileSettingsView`.
2. **Greeting** — time-aware line plus name, from `portalSection`. Streak folds in as
   one muted line rather than `HomeStreakPill`'s own card.
3. **Door quadrants** — 2×2, equal weight, fixed order, filling the bulk of the screen.
4. **Resume pill** — full width, below the quadrants. Present only when there is
   something to resume.

`HomeView.swift` drops from 838 lines to roughly 200, with the quadrants extracted
to their own file.

### The four doors

| Door | Subtitle | Routes to |
|---|---|---|
| Listen | your audio, light-synced | `showingAudioLibrary = true` |
| Read | scripts, paced | `onOpenReader()` → `selectedTab = .read` |
| Visuals | a wordless field | `selectedTab = .create`, kind `.visualField` |
| Pulse | flash entrainment | `selectedTab = .create`, kind `.flash` |

Audio analysis and synced playback are deliberately **one door**, not two. They are a
single pipeline — import, analyze, then play synced — and as two doors the user would
have to guess which to tap. Analysis is what happens inside Listen.

The Visuals and Pulse doors land on the Create screen with the segment preselected,
**not** straight into a running session. This preserves
`CreateSessionKind.requiresSafetyWarning` on the light path and keeps the deliberate
photosensitivity-warning exemption for `.visualField` intact.

## Deletions

Removed from `HomeView.swift`:

| Item | Lines (approx) |
|---|---|
| `WordmarkView` | 100 |
| `recentAudioSection` + `audioFileRow` | 110 |
| `CategorySessionSheet` | 65 |
| `quickStartSection` + `quickStartMiniCard` | 50 |
| `greetingSection` | 35 |
| `stateChipsRow` | 20 |

Files deleted outright:

| File | Lines | Note |
|---|---|---|
| `HomeView+FeaturedSessions.swift` | 98 | Library's job |
| `HomeStreakPill.swift` | 98 | becomes one line in the greeting |
| `HomeCoreActionsView.swift` | 78 | superseded by `HomeDoorsView` |
| `HomeView+MySessions.swift` | 67 | Library's job |

`BrainwaveCategory` itself **stays** — `PortalRecommender`, `AuroraBackground`,
`ThresholdView`, `MindMachineModel` and `LightSession+Metadata` all depend on it.
Only its use as a home chip row goes away.

Before deleting `HomeView+MySessions.swift` and `HomeView+FeaturedSessions.swift`,
confirm Library already covers both. If it does not, that gap is fixed in Library
before home drops the sections — not after.

## Additions

### Resume reads the store that already exists

An earlier draft of this spec proposed a new `LastActivity` record. That was wrong —
`PlaybackProgressStore` (`PlaybackProgressStore.swift`) already persists everything
the pill needs:

```swift
struct PlaybackProgressSnapshot: Codable, Identifiable, Equatable, Sendable {
    let contentID: String
    let kind: ResumablePlaybackKind   // .session | .audio
    let title: String
    let progress: Double
    let duration: TimeInterval
    let updatedAt: Date
}
```

It keeps up to 20 snapshots ordered most-recent-first, is already consumed by
`LibraryView:44`, and already has coverage in `PlaybackProgressStoreTests.swift`.

**The resume pill reads `PlaybackProgressStore.shared.snapshots.first`.** No new type,
no new `UserDefaults` key, no migration. `kind` distinguishes session from audio,
which is all the routing needs; `title`, `progress` and `duration` render the pill.

Home stops reading `lastSessionId` / `lastSessionProgress` entirely.
`UnifiedPlayerViewModel` keeps writing them — they still back
`storedResumeID` / `storedResumeProgress` as a legacy fallback
(`UnifiedPlayerViewModel.swift:1379`) — so nothing is removed from the player and
there is no migration risk.

#### Reader is not resumable, and that is not a regression

`ResumablePlaybackKind` has only `.session` and `.audio`, and TextTrance never writes
to the store. `resumableContentID` returns `nil` for flash, colour pulse, visual field
and playlist (`UnifiedPlayerViewModel.swift:1402`), so those were never resumable
either. The pill therefore covers sessions and audio — exactly what
`continueSessionCard` and `ContinueAudioCard` cover today. Making the reader resumable
means teaching TextTrance to write snapshots and adding a `.reader` case; that is its
own piece of work, tracked separately.

### `CreateView` initial kind

`CreateView.kind` is private `@State` defaulting to `.visualField`
(`Create/CreateView.swift:15`). It needs to accept a requested kind from outside,
following the `readerQuickStartTrigger` pattern already in `ContentView` so a repeat
tap re-applies rather than being swallowed as a no-op.

### New files

- `HomeDoorsView.swift` — the 2×2 quadrant grid
- `HomeDoor.swift` — the door enum: title, subtitle, symbol, tint, route
- `HomeResumePill.swift` — the resume affordance

## Out of scope

- Reworking `TranceTabBar` to match the four modalities (decision 6 — follow-up)
- Reviving `ProfileView`, which is dead code: nothing constructs it but its own
  `#Preview`, so its stats, weekly chart and history are unreachable. `plan.md:113`
  claims this as done, which is true of the code and false of the product. Track
  separately: either give it a door or delete it.
- Collapsing `SettingsView`, a one-line wrapper returning `ProfileSettingsView()`
  (`SettingsView.swift:17`)
- Extending `PortalRecommender` to consider imported and generated content. The orb
  it fed is gone; if a first-run starter suggestion is wanted later, fix the
  recommender then.

## Risks

| Risk | Mitigation |
|---|---|
| Quadrants read as too bold over the aurora | Glass tint, not flat fill. B (utility stack) is the pre-agreed fallback. |
| Home and tab bar tell different stories | Accepted for this round; decision 6 revisits it. |
| Deleting home's lists orphans content | Verify Library covers my-sessions and featured before deleting. |
| Dynamic Type breaks the 2×2 grid | Quadrants must reflow to a single column at accessibility sizes. |

## Testing

Swift Testing (`import Testing`), matching the existing suite.

- The resume pill renders the most recent `PlaybackProgressSnapshot`, and is absent
  when the store is empty.
- Each `HomeDoor` case maps to its expected route.
- The resume pill is absent when there is no last activity, and present with the
  correct title and remaining time when there is.
- `CreateView` honours an injected initial kind, and re-applies it on a repeat
  trigger with the same value.
- A snapshot with `kind == .audio` routes to the audio player; `kind == .session`
  routes to the session player.

Run on both destinations:

```
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests
```

## Definition of done

- Home renders greeting, 2×2 quadrants and a conditional resume pill — nothing else.
- The settings gear is reachable without scrolling, on both iOS and macOS.
- All four doors route correctly, with safety warnings intact on the light path.
- No reference to `WordmarkView`, `CategorySessionSheet`, `stateChipsRow` or
  `quickStartSection` remains.
- Quadrants reflow to one column at accessibility text sizes.
- Tests pass on macOS and iOS Simulator.
