# Analysis Task Center — Design

**Date:** 2026-08-16
**Status:** Awaiting approval
**Surface:** New `AnalysisCenterView` (sheet) + `AnalysisStatusPill` (bottom chrome), replacing
`AnalyzerView`'s live-status role, `AnalysisStatusOverlay`, `AnalysisRecoveryStatusOverlay`, and
`LibraryAnalysisStatusSection`

## Problem

Analysis state is rendered by six surfaces that each sample five sources independently, with
different truncations. They disagree by construction.

| Surface | What it samples | File |
|---|---|---|
| Bottom chrome | `currentAnalysis` **or** `failedAnalyses.last` | `ContentView.swift:203` |
| Analysis Queue sheet | all sources, three sections | `AnalyzerView.swift` |
| Library shelf | active + `queue.prefix(2)` + `failed.suffix(2)` + `partial.prefix(2)` | `LibraryAnalysisStatusSection.swift` |
| Session Detail | one file's slice | `SessionDetailView.swift:447` |
| System task card | iOS-owned, from `BGContinuedProcessingTaskRequest` | `BackgroundAnalysisScheduler.swift` |
| `AnalysisStatusBar` | — **dead code**, zero references outside its own `#Preview` | `AnalysisStatusBar.swift` |

The sources are `currentAnalysis`, `analysisQueue`, `failedAnalyses`, `AnalysisProgressStore`
checkpoints (partials), and `GeneratedSessionStore` (ready sessions).

Three user-visible consequences:

1. **Failures are invisible while anything is running.** The bottom chrome renders active work
   *or* the last failure, never both.
2. **Failures cannot be dismissed** (ERR-013), and `restoreManualRecoveries()` rebuilds them from
   durable checkpoints on every launch. Reported as "6 or 8 just sitting there even after quitting
   the app."
3. **Stalls are unobservable.** No timeout exists anywhere in the pipeline, so a hung analysis
   shows a frozen percentage indefinitely and emits no terminal event. This is the
   "13 starts / 1 completion / 0 errors" signature in `TELEMETRY_FINDINGS.md`.

### What this is not

Two premises in the originating recommendation were wrong and are recorded here so they are not
re-litigated:

- **There are no Live Activities to fix.** The repo contains no ActivityKit code. The Dynamic
  Island entries in ERR-014 came from `BGContinuedProcessingTaskRequest`, which iOS renders on the
  app's behalf. That was fixed on 2026-08-16.
- **Give-up telemetry already exists.** `UsageAnalytics.audioAnalysisFailed` is emitted at
  `AnalysisStateManager.swift:1319` with reason, stage, and processing time, on both the retry and
  terminal branches. `plan.md`'s open item to add it is stale. The real gap is that a *hang* never
  reaches that handler — an absence, not a failure. See [Stall watchdog](#stall-watchdog).

## Goal

One canonical task model shared by every analysis surface. The new screen is a consequence of that
model, not the deliverable.

### Acceptance criteria

1. One stable `AnalysisTask` per audio file, identified by `audioFile.id`.
2. One shared published `[AnalysisTask]` snapshot.
3. A pure, unit-tested projection function.
4. Explicit per-file collapse precedence.
5. Explicit cross-file sorting rules.
6. Action-required failures outrank active work.
7. Automatic retries do not hide active progress.
8. Recovery information survives failed/paused states.
9. Old ready sessions remain addressable but age out of activity views.
10. Pill, Task Center, Library, and Session Detail only filter the shared list — none
    independently reconstruct state.

## Scope

**In:** the canonical model and projection; the pill; the center; dismissal/removal persistence;
the stall watchdog; model-download progress as a first-class state.

**Out:** Library Intelligence, deferred to its own task (`task_34b6360c`) — it is library-wide
statistics, not task state, and only shares a screen with the queue today.

### Build order

The model and projection land first and are independently testable. The watchdog and the
model-download callback are **additional producers feeding that model**, not architectural
foundations, and are wired in afterwards. `.preparing` ships in the enum from day one with nothing
producing it, so wiring the callback later is additive rather than a model change.

## The model

```swift
nonisolated enum AnalysisTaskState: Equatable, Sendable {
    case queued(position: Int)
    case preparing(ModelDownloadProgress)
    case running(stage: AnalysisStage, progress: Double)
    case partial(recovery: AnalysisRecoveryStage)
    case failed(FailedAnalysis, dismissedAt: Date?)
    case ready(SyncPlayerItem)
}
```

`AnalysisTaskProjection.tasks(...)` is a **pure `nonisolated` function** over plain values
returning `[AnalysisTask]`.

It is not a property on `AnalysisStateManager`: that file is already 1,406 lines against
CLAUDE.md's 800-line cap, and a property there would only be testable by standing up a
`@MainActor` singleton. As a free function the ordering and collapse rules get unit tests with no
actor, no async, and no I/O — which is what makes criterion 10 enforceable rather than
aspirational.

A thin `@MainActor @Observable AnalysisCenterModel` reads `AnalysisStateManager` and publishes the
snapshot.

### Per-file collapse precedence

One task per `audioFile.id`. A file may appear in several sources simultaneously; highest match
wins.

| Precedence | State | Condition |
|---|---|---|
| 1 | `.preparing` / `.running` | file is `currentAnalysis` |
| 2 | `.queued(position:)` | present in `analysisQueue`, **including auto-retry re-queues** |
| 3 | `.failed` | in `failedAnalyses`, not queued, not active |
| 4 | `.partial` | durable checkpoint exists, nothing scheduled |
| 5 | `.ready` | generated session exists, no live work |

Precedence 2 above 3 is the load-bearing rule. A failure with `retryState == .automatic` is
re-appended to the queue at `AnalysisStateManager.swift:1330`, so the file is *simultaneously*
failed and queued. Collapsing it to `.queued` is what satisfies criterion 7.

### Attributes, not states

The task carries `lastFailure`, `recovery: AnalysisRecoveryStage`, and `readyItem` alongside its
one `state`. State answers *what is happening now*; attributes answer *what has been salvaged*.
This satisfies criterion 8: a `.failed` task still renders "Transcript saved", and a `.queued`
auto-retry still knows what it resumes from.

### Cross-file sort

1. Action-required failures — undismissed, `retryState` of `.manual` or `.unavailable`
2. `.preparing` / `.running`
3. `.queued`, by queue position
4. `.partial`
5. Dismissed failures
6. `.ready`, most recent first

Only tier 1 outranks active work, and auto-retries cannot reach tier 1 because they collapsed to
`.queued`. Criteria 6 and 7 both fall out of the structure with no special cases.

`.ready` items remain in the canonical list permanently. Ageing out is a **view filter**, not a
model deletion, satisfying criterion 9.

## Surfaces

All four filter the shared snapshot.

| Surface | Slice |
|---|---|
| Pill | `preparing`/`running`/`queued` + undismissed action-required failures |
| Task Center | Everything, grouped by sort tier |
| Library | One entry row summarising counts |
| Session Detail | `tasks.first { $0.id == audioFile.id }` |

**Deleted:** `AnalysisStatusBar.swift` (dead), `LibraryAnalysisStatusSection.swift` (duplicate),
`AnalysisRecoveryStatusOverlay` (folded into the pill).

### Pill composition

The pill shows **active progress as the headline plus a persistent attention chip** for
action-required failures — both visible simultaneously.

This is a deliberate divergence from the tier order. Applied literally to the pill, tier 1 would
give a failure the headline and hide live progress; because a `.manual` failure can sit
indefinitely, the pill would stop showing progress for as long as it exists. That reintroduces the
defect being removed. The two states answer different questions: progress is transient and
self-resolving, a failure is a standing decision. The sort order still governs the Task Center,
which leads with the failure when opened.

## Dismissal and persistence

`restoreManualRecoveries()` (`AnalysisStateManager.swift:254`) rebuilds `failedAnalyses` from
durable checkpoints on every launch, so dismissal held only in memory is resurrected on relaunch.

### Storage

`dismissedAt` lives on the **failure occurrence**, not the checkpoint root:

```swift
nonisolated struct AnalysisManualRecovery: Codable, Sendable {
    let reason: AnalyticsAnalysisFailureReason
    let failedStage: AnalyticsAnalysisStage
    let failedAt: Date
    var dismissedAt: Date?
}
```

Dismissal invalidation then falls out of existing code with no added bookkeeping:

- `saveQueued` already nils `manualRecovery` when re-queueing a manual retry
  (`AnalysisProgressStore.swift:120-129`), so retry clears dismissal.
- `markRequiresManualRetry` constructs a *fresh* `AnalysisManualRecovery` on each failure
  (`:212`), so a new occurrence starts undismissed.

`Optional` with a default decodes cleanly from existing on-disk checkpoints.

### Operations

- **`dismiss(fileID:expecting failedAt:)`** — writes `dismissedAt`, **leaves the checkpoint
  intact**. The task stays in the canonical list at sort tier 5, leaves the pill, and retry still
  resumes from the saved transcript. The `failedAt` guard prevents a delayed action from an old row
  dismissing a newer failure for the same file.
- **`remove(fileID:)`** — clears the dismissal record *and* the checkpoint, *and* the in-memory
  projected task. Clearing only `progressStore` leaves the row visible until relaunch.

Both report success. The published snapshot updates only after the atomic write lands; a failed
write restores the prior in-memory value.

### Write-failure handling

`persist()` currently swallows both encoding and disk-write errors
(`AnalysisProgressStore.swift:236-242`):

```swift
guard let data = try? JSONEncoder().encode(stringKeyed) else { return }
try? data.write(to: storeURL, options: .atomic)
```

If the UI marks something dismissed and the write silently fails, ERR-013 returns on relaunch. This
is the same defect class as ERR-005, where the audio library dropped writes while announcing
success; that fix made every mutator return `Bool` with `@discardableResult` on the save. Follow
that shape rather than inventing a convention.

### The `.unavailable` exception

`.unavailable` failures clear their checkpoint at `AnalysisStateManager.swift:1305` *before*
entering `failedAnalyses`, and `restoreManualRecoveries()` rebuilds only from
`manualRecoveryCheckpoints()` (filtered on `manualRecovery != nil`). Therefore:

| Failure kind | Dismissal behaviour |
|---|---|
| `.manual` | persisted in the recovery; checkpoint survives; task restores as dismissed |
| `.unavailable` | no checkpoint to annotate; dismissal removes the in-memory failure and it stays gone after relaunch |

Persisting `.unavailable` failure history would require a separate durable failure-history store.
Out of scope.

> **ERRORS.md correction applied 2026-08-16.** ERR-013 was filed under "Resolved" with
> `Status: completed` while its own resolution line read "Not yet fixed"; no `dismissFailure`
> exists in the code. Its reproduction step 5 also claimed `.unavailable` failures are restored
> after relaunch, which the code contradicts. Both corrected.

## Stall watchdog

No timeout exists in the pipeline today; the only `Task.sleep` in `AnalysisStateManager` is a 250ms
poll at `:1109`.

### Why inactivity, not total elapsed

A total-elapsed limit would kill healthy work on long-form content — precisely what this app is
for. The watchdog times out on **absence of a heartbeat**.

```swift
static let noProgressTimeout: Duration = .minutes(5)
```

Five minutes is conservative for the current emitters:

- the observed first model download took roughly 100 seconds;
- WhisperKit reports progress per ~28-second audio window
  (`Double(transcriptionProgress.windowId) * 28.0`, `AudioAnalyzer.swift:547`);
- content analysis reports at phase-chunk completion boundaries.

**This is an initial policy, not an empirically tuned value.** No distribution of maximum heartbeat
gaps across real devices exists yet.

### Heartbeat definition

Any of: a stage transition; a meaningful progress increase; explicit producer activity such as
downloaded bytes.

Use a **monotonic clock, injected for tests**. **Disarm the watchdog during ordinary cancellation
and background expiration** — a lifecycle pause must never become `.stalled`.

### Coverage of speculative transcription

The watchdog must cover the prefetch path. `awaitPrefetchedTranscriptionForNextFile()` awaits
`prefetch.task.value` unbounded before promoting the next file
(`AnalysisStateManager.swift:855`). A watchdog observing only `currentAnalysis.progress` would miss
that hang entirely.

The hazard exists on both branches: the reordering branch calls `prefetch.task.cancel()` and
`audioAnalyzer.cancelTranscription()` (`:851-852`) but still falls through to the same unbounded
await, and `Task<Void, Never>` cannot throw, so an uncooperative child wedges the queue either way.

### Exactly-once terminal result

Completion, cancellation, and timeout need a single winner. `TaskGroup.cancelAll()` is insufficient
— a structured group can still wait forever on an uncooperative child. Use an **attempt/generation
identity** so a late operation cannot emit completion after the watchdog has already emitted
failure.

### Retry posture

`.stalled` flows through the existing automatic-retry budget
(`reason.supportsAutomaticRetry && failedAttemptNumber < 2`, `:1288`), giving one automatic retry
before falling to `.manual` with the checkpoint preserved.

**One exception.** Cancellation is cooperative; if WhisperKit or Foundation Models ignores it,
launching a retry immediately would create two operations competing for the same model. Therefore:

- record the `.stalled` failure exactly once;
- invalidate the old attempt so late callbacks and results are ignored;
- preserve the checkpoint;
- **do not launch the automatic retry until teardown completes**;
- if teardown cannot be confirmed, leave it recoverable as `.manual`.

### `.stalled` reason

Add `case stalled` to `AnalyticsAnalysisFailureReason` — a `String`-raw `Codable` enum
(`AnalyticsEvent.swift:162`), so existing checkpoints still decode. Map a typed
`AnalysisStalledError` in `AnalyticsAnalysisFailureReason.init(error:stage:)` **before** the
stage-based fallback, or a stall will be misattributed to whatever stage it died in.

The exhaustive switches in `AnalysisFailurePresentation` will require dedicated user-facing copy at
compile time rather than silently falling through to `.unknown`.

## Model download

`.preparing` is driven by `WhisperKit.download`'s `progressCallback: ((Progress) -> Void)?`
(`WhisperKit.swift:241` in the pinned checkout). `AudioAnalyzer.swift:454` currently passes
nothing — the 100-second silence is a callback the app declines to wire up, not a missing
capability.

**Failure handling is unchanged.** A download failure uses the existing `.modelInitialization`
presentation and retry behaviour. Note that `WhisperModelBootstrap.actionableFailureMessage` is
stored only in `FailedAnalysis.technicalMessage`, which the UI deliberately does not render
("Retained for local logs and debugging; UI uses `presentation`",
`FailedAnalysis.swift:104`). Surfacing that message is **not** part of this work.

## Testing

Swift Testing (`import Testing`), macOS and iOS Simulator. Run via `Scripts/run-tests.sh` so a
filter matching nothing fails rather than reporting success (ERR-002).

**Projection** — pure, no actor, no async:

- per-file collapse precedence
- cross-file sort
- auto-retry collapses to `.queued` and sorts below active work
- recovery attributes survive a `.failed` collapse
- `.ready` persists in the list while filtered out of activity views

**Persistence:**

- dismissed manual recovery round-trips through a new store and manager
- restored task retains `dismissedAt` and is excluded from pill candidates
- retry after dismissal reuses the transcript and clears the old dismissal
- a new failure occurrence for the same file starts undismissed
- `remove` deletes a manual checkpoint and leaves nothing restorable
- a stale dismissal cannot dismiss a newer failure occurrence
- dismissing `.unavailable` succeeds without requiring a checkpoint
- persistence failure leaves both durable state and the published snapshot unchanged

**Pill candidates:**

- dismissed failures excluded
- active progress and an action-required failure render simultaneously

**Watchdog:**

- no-progress heartbeat trips at the threshold
- slow-but-advancing progress does not trip
- stage transition resets the watchdog
- background expiration and ordinary cancellation never produce `.stalled`
- timeout versus completion emits exactly one terminal result
- retry does not begin before timed-out resource teardown
- late progress from a timed-out attempt cannot mutate its replacement
- a stalled transcription prefetch cannot wedge the queue

## Risks

- **Watchdog false positives.** Five minutes is a policy guess. If real devices show heartbeat gaps
  approaching it — a very long content-analysis chunk on a cold model — healthy work will be
  killed and retried. The threshold is a named constant so it can move without a redesign.
- **Uncooperative teardown.** The retry guard depends on observing teardown. If neither WhisperKit
  nor Foundation Models exposes a reliable completion signal after cancellation, tasks will settle
  at `.manual` more often than intended. That is the safe direction, but it means some stalls need
  a manual tap that the design intends to handle automatically.
- **`AnalysisStateManager` size.** This work adds a watchdog and generation identity to a file
  already 1,406 lines over a 800-line cap. The projection is extracted deliberately; the watchdog
  should be too, or the file gets worse.
- **Ordering divergence between pill and center** is intentional but is the kind of thing a future
  reader will "fix". The rationale is recorded above.
