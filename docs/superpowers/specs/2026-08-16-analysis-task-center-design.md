# Analysis Task Center — Design

**Date:** 2026-08-16
**Status:** Awaiting approval (revision 2)
**Surface:** New `AnalysisCenterView` (sheet) + `AnalysisStatusPill` (bottom chrome), replacing
`AnalyzerView`'s live-status role, `AnalysisStatusOverlay`, `AnalysisRecoveryStatusOverlay`, and
`LibraryAnalysisStatusSection`

## Problem

Analysis state is rendered by several surfaces that each read the underlying sources directly, with
different truncations. They disagree by construction.

| Surface | What it reads | File |
|---|---|---|
| Bottom chrome | `currentAnalysis` **or** `failedAnalyses.last` | `ContentView.swift:203` |
| Analysis Queue sheet | active, queue, failures, ready sessions | `AnalyzerView.swift` |
| Library shelf | active + `queue.prefix(2)` + `failed.suffix(2)` + `partial.prefix(2)` | `LibraryAnalysisStatusSection.swift` |
| Session Detail | one file's slice of active/queue/failure state | `SessionDetailView.swift:447` |
| System task card | iOS-owned, from `BGContinuedProcessingTaskRequest` — title, subtitle, progress only | `BackgroundAnalysisScheduler.swift` |
| `AnalysisStatusBar` | nothing — **dead code**, zero references outside its own `#Preview` | `AnalysisStatusBar.swift` |

The four live in-app surfaces read from six inputs:

1. `AnalysisStateManager.currentAnalysis`
2. `AnalysisStateManager.analysisQueue`
3. `AnalysisStateManager.failedAnalyses`
4. `AnalysisProgressStore` checkpoints (partials and manual recoveries)
5. `GeneratedSessionStore` (ready sessions)
6. The audio-library inventory (`AudioLibraryStore`) — required because `GeneratedSessionStore`
   cannot enumerate; every one of its accessors takes an `AudioFile`

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

**In:** the canonical model and projection; snapshot ownership and refresh; the pill; the center;
dismissal/removal persistence; the stall watchdog; model-download progress as a first-class state.

**Out:** Library Intelligence, deferred to its own task (`task_34b6360c`) — it is library-wide
statistics, not task state, and only shares a screen with the queue today.

## The model

All types are immutable value snapshots. The projection never vends live references, so a
published `[AnalysisTask]` is safe to diff, compare, and hold across actor boundaries.

```swift
nonisolated struct AnalysisTask: Identifiable, Equatable, Sendable {
    var id: UUID { audioFile.id }

    let audioFile: AudioFile
    let state: AnalysisTaskState
    /// Present whenever a failure has been recorded for this file, including
    /// when `state` has moved on to `.queued` for an automatic retry.
    let lastFailure: AnalysisFailureSnapshot?
    /// The most useful partial result saved on disk, independent of `state`.
    let recovery: AnalysisRecoveryStage
    /// Present whenever a generated session exists, including during re-analysis.
    let ready: AnalysisReadySnapshot?
}

nonisolated enum AnalysisTaskState: Equatable, Sendable {
    case queued(position: Int)          // one-based
    case preparing(ModelDownloadProgress)
    case running(stage: AnalysisStage, progress: Double, startedAt: Date)
    /// A durable checkpoint exists and nothing is scheduled. Named for what the
    /// user sees, not for what was saved: `recovery` may be `.none` when a
    /// cancellation left a checkpoint with no partial result yet.
    case paused
    case failed
    case ready
}

nonisolated struct ModelDownloadProgress: Equatable, Sendable {
    /// The file whose analysis this download is bootstrapping. A speculative
    /// prefetch downloads for the *next* file, not the active one.
    let audioFileID: UUID
    let attemptID: UUID
    let completedUnitCount: Int64
    let totalUnitCount: Int64
    let fractionCompleted: Double
}

nonisolated struct AnalysisFailureSnapshot: Equatable, Sendable {
    let reason: AnalyticsAnalysisFailureReason
    let failedStage: AnalyticsAnalysisStage
    let failedAt: Date
    let recoveryStage: AnalysisRecoveryStage
    let retryState: AnalysisRetryState
    let dismissedAt: Date?

    var presentation: AnalysisFailurePresentation {
        AnalysisFailurePresentation(
            reason: reason,
            failedStage: failedStage,
            recoveryStage: recoveryStage,
            retryState: retryState
        )
    }

    /// True when this failure needs a decision *regardless of queue state*.
    /// Tier-1 eligibility is broader — see `Failure assembly and tiers`, because
    /// an `.automatic` failure that is no longer queued is also stranded.
    var needsDecisionIntrinsically: Bool {
        dismissedAt == nil && (retryState == .manual || retryState == .unavailable)
    }
}

nonisolated struct AnalysisReadySnapshot: Equatable, Sendable {
    /// `LightSession.id` — decoded from the stored JSON, stable across loads.
    let sessionID: UUID
    let readyAt: Date
}
```

### Why not the obvious types

- **`SyncPlayerItem` must not appear in the model.** It is `Identifiable` only — not `Equatable`,
  not `Sendable` — and its `let id = UUID()` (`SyncPlayerItem.swift:10`) generates a fresh value
  per instance, so two projections of identical state would compare unequal. `AnalysisReadySnapshot`
  carries `LightSession.id` instead, which is a decoded `UUID` (`LightSession.swift:15`) and
  therefore stable. **The player item is resolved when Play is tapped**, not held in the snapshot.
- **`FailedAnalysis` must not appear in the model.** It is `Identifiable, Sendable` but not
  `Equatable` (`FailedAnalysis.swift:96`), which would block `AnalysisTask`'s synthesised
  conformance. `AnalysisFailureSnapshot` mirrors the fields the UI needs and keeps
  `AnalysisFailurePresentation` reachable as a computed property.
- **`AudioFile` is safe to hold**: `Identifiable, Codable, Sendable` (`AudioFile.swift:32`) with an
  explicit `Equatable` conformance (`:145`) and `Hashable` (`:172`).
- **`dismissedAt` is not pipeline state.** It lives on the failure snapshot, mirroring where it is
  persisted, so `state` stays a description of what the pipeline is doing.
- **Foundation `Progress` never crosses an actor.** It is a non-`Sendable` reference type; the
  download callback converts it to `ModelDownloadProgress` at the call site.

### Projection

`AnalysisTaskProjection.tasks(from:)` is a **pure `nonisolated` function** taking one plain-value
input and returning `[AnalysisTask]`:

```swift
nonisolated struct AnalysisTaskProjectionInput: Equatable, Sendable {
    let libraryFiles: [AudioFile]
    let activeAnalysis: ActiveAnalysisSnapshot?
    let modelDownload: ModelDownloadProgress?
    /// Audio file ids in queue order. Duplicates are not permitted; the
    /// assembler enforces uniqueness and the projection uses first occurrence.
    let queue: [UUID]
    let failures: [UUID: AnalysisFailureSnapshot]
    let checkpoints: [UUID: AnalysisCheckpointSnapshot]
    let ready: [UUID: AnalysisReadySnapshot]
}

nonisolated struct ActiveAnalysisSnapshot: Equatable, Sendable {
    let audioFileID: UUID
    let attemptID: UUID
    let stage: AnalysisStage
    let progress: Double
    let startedAt: Date

    /// `.complete` and `.failed` are terminal: the pipeline leaves
    /// `currentAnalysis` populated after it has stopped working on the file.
    var isTerminal: Bool { stage == .complete || stage == .failed }
}

nonisolated struct AnalysisCheckpointSnapshot: Equatable, Sendable {
    let recoveryStage: AnalysisRecoveryStage
    let startedAt: Date
    /// Drives tier-4 ordering and the staleness comparison against `readyAt`.
    let lastUpdated: Date
}
```

`AnalysisCheckpointSnapshot` carries `lastUpdated` rather than a bare
`AnalysisRecoveryStage` for three reasons: tier-4 ordering needs it; a checkpoint whose
`recoveryStage` is `.none` must still produce a task (see rule 5); and it is the only way to detect
a checkpoint that has been overtaken by a completed session.

It is not a property on `AnalysisStateManager`: that file is 1,406 lines, well past the
200–400-line norm and the 800-line ceiling in the global coding-style rules, and putting the
projection there makes it harder to reach in isolation. (`AnalysisStateManager` *does* have an
injectable initialiser at `:105` accepting `transcriber`, `analyzer`, `progressStore`,
`preferences`, and `cacheURL`, so it is testable without the singleton — the argument here is
about file size and separation, not testability.) As a free function over plain values, the
ordering and collapse rules get unit tests with no actor, no async, and no I/O — which is what
makes criterion 10 enforceable rather than aspirational.

### Per-file collapse precedence

One task per `audioFile.id`. A file may appear in several inputs simultaneously; the first
matching rule wins.

| # | Condition | Result |
|---|---|---|
| 1 | active, non-terminal, **and** `modelDownload` matches both `audioFileID` and `attemptID` | `.preparing(progress)` |
| 2 | active, non-terminal | `.running(stage:progress:startedAt:)` |
| 3 | present in `queue` | `.queued(position:)`, one-based, first occurrence |
| 4 | a failure snapshot exists | `.failed` |
| 5 | a checkpoint exists **and** is not overtaken by a ready session | `.paused` |
| 6 | a ready snapshot exists | `.ready` |
| — | otherwise | no task emitted |

**Terminal active analysis does not win.** `currentAnalysis` is left in place with
`stage == .failed` during failure handling (`AnalysisStateManager.swift:1325`) while the file is
simultaneously re-appended to the queue (`:1330`) and added to `failedAnalyses`. Under a naive
"any active analysis wins" rule the task would collapse to `.running(stage: .failed)` and defeat
criterion 7 entirely. Non-terminal means the stage is one of `.starting`, `.transcribing`,
`.analyzing`, `.generatingSession`; `.failed` and `.complete` both fall through to rule 3 and
below.

**`.complete` does not synthesise a ready snapshot.** A terminal `.complete` active analysis falls
through like any other terminal stage. It reaches `.ready` only if the `ready` map actually
contains an entry for the file, which happens once the generated session is on disk and the
assembler has seen it. Between those two moments the task legitimately collapses to `.paused` (the
checkpoint still exists) or emits nothing.

**Rule 3 above rule 4 is load-bearing.** A failure with `retryState == .automatic` is re-queued, so
the file is both failed and queued; collapsing to `.queued` is what satisfies criterion 7. The
failure is not lost — it is carried as `lastFailure`.

**Rule 5's staleness comparison.** A session saved immediately before a crash can coexist with a
checkpoint that was never cleared. Rule 5 applies only when there is no ready snapshot, or when
`checkpoint.lastUpdated > ready.readyAt`. Otherwise the checkpoint is stale progress that has
already been superseded by completed work, and the task falls to rule 6. Without this, a crashed
run would permanently outrank a session the user can actually play.

**Rule 5 does not require a partial result.** Cancelling after `saveQueued` leaves a checkpoint
whose `recoveryStage` is `.none`. That file has durable state and nothing scheduled, so it must
still appear — as paused, with `recovery == .none` telling the UI that nothing was salvaged. Gating
rule 5 on a non-`.none` recovery stage would make cancelled work vanish from every surface while
still occupying disk.

**`.preparing` versus `.running`.** The model download is **not** a property of the active
analysis. `onTranscriptionReady()` starts the lookahead prefetch as soon as content analysis is
checkpointed and before the current file enters `.generatingSession`
(`AnalysisStateManager.swift:1186-1189`, whose comment states the overlap explicitly), so a
speculative Whisper bootstrap for file N+1 can run while file N is generating. A global download
flag would relabel the actively-generating file as `.preparing`.

`.preparing` is therefore selected only when the download snapshot's `audioFileID` **and**
`attemptID` both match the active analysis. A speculative download changes nothing the user sees:
its file stays `.queued`, because showing bootstrap progress for a file that may never be promoted
would imply the queue is processing two files at once.

**Speculative transcription stays `.queued`** for the same reason. The prefetch
(`startPrefetchingNextTranscription`) transcribes the next queued file opportunistically and may be
discarded if the queue is reordered. The watchdog still covers it internally — see
[Coverage of speculative transcription](#coverage-of-speculative-transcription).

### Attributes, not states

`lastFailure`, `recovery`, and `ready` are populated independently of `state`. State answers *what
is happening now*; attributes answer *what has been salvaged*. This satisfies criterion 8: a
`.failed` task still renders "Transcript saved", a `.queued` auto-retry still knows what it resumes
from, and a file being re-analysed still knows it has a playable session from last time.

### Failure assembly and tiers

**Two sources hold failures** and must be merged before projection:

- **Durable manual recoveries** — `AnalysisProgressStore.manualRecoveryCheckpoints()`, which carry
  `dismissedAt` and survive relaunch. These exist only for `.manual` failures.
- **Runtime `failedAnalyses`** — holds `.automatic` and `.unavailable` entries too, but loses them
  on termination.

**Merge rule:** the durable record is authoritative when both exist for a file and their `failedAt`
values are equal. When they differ, the **later `failedAt` wins**, because a newer occurrence has
genuinely superseded the older one and `markRequiresManualRetry` writes a fresh recovery per
occurrence. A durable record with no runtime counterpart is included (this is the post-relaunch
case); a runtime record with no durable counterpart is included (this is the `.automatic` and
`.unavailable` case). The merge is a total function over the union of both key sets.

**Tier-1 eligibility** is computed by the projection, not by the snapshot, because it depends on
queue membership:

```
needsDecision(task) =
    lastFailure != nil
    && lastFailure.dismissedAt == nil
    && (lastFailure.needsDecisionIntrinsically || !queue.contains(task.id))
```

The second clause closes a real hole. An `.automatic` failure is only harmless because something
will retry it; once the queue is cleared — `clearQueue()` is a user-facing toolbar action — nothing
will. Under the narrower rule that file sat in no tier at all: not tier 1 (`.automatic`), not
tier 3 (no longer queued), not tier 5 (not dismissed). It would have been invisible, which is the
exact defect class this design exists to remove.

### Cross-file sort

Tiers, then a deterministic order within each tier, then a stable tie-breaker on `audioFile.id`
so equal timestamps never reorder between projections:

| Tier | Contents | Within-tier order |
|---|---|---|
| 1 | `needsDecision(task) == true` | `failedAt` descending |
| 2 | `.preparing`, `.running` | `startedAt` descending |
| 3 | `.queued` | queue position ascending |
| 4 | `.paused` | checkpoint `lastUpdated` descending |
| 5 | `.failed` with `dismissedAt != nil` | `failedAt` descending |
| 6 | `.ready` | `readyAt` descending |

Every task lands in exactly one tier: tier 1 is evaluated first and overrides the state-derived
tier, so a `.queued` task whose failure needs a decision sorts to tier 1 while still *rendering* as
queued. Criteria 6 and 7 both fall out of the structure — automatic retries that are still queued
fail the `needsDecision` test and stay in tier 3.

### Ready semantics

- **`readyAt`** is the modification date of the generated-session file, obtained from
  `GeneratedSessionStore.sessionURL(forAudioFileID:)` (`:51`). It survives relaunch and adds no new
  persistence format. For a bundled gold session, which has no generated file, fall back to the
  audio file's import date.
- **Activity policy:** activity-oriented views show the **three most recent** ready tasks,
  preserving today's `AnalysisReadySessionsCard` behaviour (`.prefix(3)`). There is no TTL. The
  Task Center's full list shows all of them. Ageing out is a **view filter**, never a model
  deletion, satisfying criterion 9.
- **Deleted or corrupt:** if the audio file is gone from the library inventory, no task is emitted
  at all — the library is the spine of the projection. If the session file is missing or fails to
  decode, **the assembler omits the file from the `ready` map**, so the projection simply never sees
  it and the task falls through to a lower rule. A task therefore never advertises a session that
  cannot be loaded. This is an input-assembly responsibility, not a projection one: the projection
  receives an already-built map and does no disk access, so its tests cannot and should not cover
  decode failure. That belongs to the assembler's tests.

## Snapshot ownership and refresh

The projection is pure, so something must own its input and decide when to recompute it.

**Ownership.** A single `AnalysisCenterModel` (`@MainActor @Observable`) is created at the app root
and injected into all four surfaces through the environment. There is exactly one instance; no
surface constructs its own.

**Two refresh paths**, because the inputs have very different frequencies:

- **Structural refresh** rebuilds the disk- and store-backed fields of
  `AnalysisTaskProjectionInput`: `libraryFiles`, `queue`, `failures`, `checkpoints`, `ready`.
- **Progress refresh** replaces only `activeAnalysis` and `modelDownload` and re-runs the
  projection. It **never touches disk**. This is the high-frequency path — WhisperKit reports per
  ~28s audio window, the download callback more often.

**Structural triggers.** Any mutation of a structural field, which means all of:

| Source | Events |
|---|---|
| Queue | enqueue, dequeue, promotion to active, cancellation, reorder, `clearQueue` |
| Failures | failure recorded, retry started, dismissal, removal, `restoreManualRecoveries()` |
| Checkpoints | `saveQueued`, `saveTranscription`, `saveAnalysis`, `markRequiresManualRetry`, `clear` |
| Sessions | generated-session save, delete |
| Library | audio file added, renamed, deleted |

Queue mutations matter as much as the rest: queue position is projection input, so a reorder that
does not trigger a refresh leaves every position stale.

**Notification.** `AnalysisProgressStore` is a `private` actor on the manager and
`GeneratedSessionStore` publishes nothing, so neither can be observed directly. Rather than making
them observable, the manager exposes one `nonisolated` accessor returning the structural fields as
plain values, and every mutating path above calls a single `invalidateStructure()` on the model
after its write completes. One funnel, called from the places that already exist, instead of five
observation mechanisms.

### The refresh loop

Structural refresh is asynchronous (disk reads, actor hops) and progress refresh is synchronous and
frequent, so an in-flight structural read can complete *after* a newer progress tick and clobber it.
A single coalesced, generation-guarded loop prevents that:

1. **Observers are installed before bootstrap starts.** Any invalidation racing the first load is
   recorded rather than lost.
2. **Invalidations during an in-flight pass set a dirty flag** rather than starting a second pass.
   When the pass commits and the flag is set, exactly one more pass runs. Bursts — importing forty
   files — coalesce into two passes, not forty.
3. **Each structural pass carries a monotonically increasing generation.** A pass whose generation
   is older than the last committed one is discarded at commit time, so a slow read can never
   overwrite a newer one.
4. **A structural commit merges the live `activeAnalysis` and `modelDownload`** held by the model
   at commit time, never the values captured when the pass began. This is what stops a structural
   refresh from rewinding progress.
5. **Disk-backed reads happen off the main actor.** Only the commit — assembling the input and
   publishing the projected snapshot — is main-actor work.

**Startup ordering** is fixed and observable:

1. Install observers.
2. Load the audio-library inventory.
3. Restore manual recoveries and read checkpoints.
4. Enumerate ready sessions for the loaded inventory.
5. Publish the first snapshot.

The published snapshot is `nil` (distinct from empty) until step 5, so surfaces can distinguish
"still loading" from "nothing to show" and neither the pill nor the Library row flashes an empty
state on launch. If anything invalidated during steps 2–4, another pass runs immediately after
step 5 per rule 2.

**Invalidation.** Deleting an audio file or its generated session triggers a structural refresh;
the projection then omits the task or clears `ready` respectively. Because tasks are keyed on
`audioFile.id`, a re-imported file with a new identifier is a new task and inherits nothing.

## Surfaces

All four filter the shared snapshot.

| Surface | Slice |
|---|---|
| Pill | `preparing`/`running`/`queued` + tasks where `needsDecision(task)` |
| Task Center | Everything, grouped by sort tier |
| Library | One entry row summarising counts |
| Session Detail | `tasks.first { $0.id == audioFile.id }` |

**Deleted:**

- `AnalysisStatusBar.swift` — dead code, no references.
- `LibraryAnalysisStatusSection.swift` — duplicate summary, replaced by the Library entry row.
- `AnalysisStatusOverlay.swift` — the whole file. It holds **both** `AnalysisStatusOverlay` (active
  progress) and `AnalysisRecoveryStatusOverlay` (last failure), and the pill replaces both. Deleting
  one and keeping the other would leave the either/or split that this design exists to remove.

**`AnalyzerView`'s fate.** Its Live Status and Ready Sessions sections are replaced by the Task
Center. Its third section, `AnalyzerLibraryIntelligenceSection`, is out of scope and has no other
entry point once the queue's callers move. It is therefore **left in place inside `AnalyzerView`,
and `AnalyzerView` remains reachable from a single entry — the Task Center's overflow — until
`task_34b6360c` relocates it to Library.** This avoids orphaning a working feature to satisfy a
boundary, and the follow-up task deletes both together.

### Pill composition

The pill shows **active progress as the headline plus a persistent attention chip** for
action-required failures — both visible simultaneously.

This is a deliberate divergence from the tier order. Applied literally to the pill, tier 1 would
give a failure the headline and hide live progress; because a `.manual` failure can sit
indefinitely, the pill would stop showing progress for as long as it exists. That reintroduces the
defect being removed. The two states answer different questions: progress is transient and
self-resolving, a failure is a standing decision. The sort order still governs the Task Center,
which leads with the failure when opened.

## Dismissal and removal

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

Both are **occurrence-guarded**: the caller passes the `failedAt` it is acting on, so a
confirmation raised for one failure cannot act on a newer failure for the same file.

```swift
func dismiss(fileID: UUID, expectingFailedAt: Date) async -> Bool
func remove(fileID: UUID, expectingFailedAt: Date) async -> Bool
```

- **`dismiss`** writes `dismissedAt` and **leaves the checkpoint intact**. The task stays in the
  canonical list at tier 5, leaves the pill, and retry still resumes from the saved transcript.
- **`remove`** clears the manual recovery *and* the checkpoint, **and removes the entry from
  `failedAnalyses`** — the authoritative in-memory source. Mutating only the projected row is
  insufficient: the next structural refresh would recreate it.

**Return value:**

- `true` — the requested postcondition holds: for `dismiss`, the occurrence is recorded dismissed
  and durably written; for `remove`, the occurrence and its checkpoint are gone and
  `failedAnalyses` no longer contains it.
- `false` — the occurrence is stale (a different `failedAt` is on record), no matching entry
  exists, or persistence failed.

**Removal is destructive and requires confirmation.** The confirmation must say that it deletes
*saved analysis progress* — the transcript or analysis a retry would have resumed from — and that
it does **not** delete the audio file.

**Ordering:** the durable write happens first; the published snapshot updates only after it
succeeds. A failed write leaves both durable state and the in-memory value untouched, so the UI
never shows a dismissal that disk does not agree with.

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
| `.manual` | persisted in the recovery; checkpoint survives; task restores as dismissed at tier 5 |
| `.unavailable` | no checkpoint exists to annotate; `dismiss` succeeds immediately with **no disk write**, removes the entry from `failedAnalyses`, and the task does not join tier 5. It does not return after relaunch because nothing durable ever referenced it. |

Dismissing an `.unavailable` failure removes the *failure*, not the file. If the audio file still
has a generated session from an earlier successful analysis, its task falls through to `.ready` at
tier 6 rather than disappearing; only a file with no failure, no checkpoint, and no session emits
no task at all.

Persisting `.unavailable` failure history would require a separate durable failure-history store.
Out of scope.

> **ERRORS.md correction applied 2026-08-16.** ERR-013 was filed under "Resolved" with
> `Status: completed` while its own resolution line read "Not yet fixed"; no `dismissFailure`
> exists in the code. Its reproduction step 5 also claimed `.unavailable` failures are restored
> after relaunch, which the code contradicts. Both corrected, and the entry moved to Open issues.

## Stall watchdog

No timeout exists in the pipeline today; the only `Task.sleep` in `AnalysisStateManager` is a 250ms
poll at `:1109`.

**This section is decided policy with conditional implementation.** The mechanism depends on
questions the spike in Phase 2a must answer first.

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

### Exactly-once terminalisation

Attempt identity suppresses stale results; it does **not** unblock an uncooperative await, and the
distinction matters here. `AudioAnalyzer.cancelTranscription()` (`:266`) itself awaits the task it
is cancelling — `_ = try? await task?.value` (`:270`) — so cancellation can hang for the same
reason the work can. A hung operation also never reaches the existing `catch`, so the watchdog
needs an **independently callable terminalisation path** that records the failure without waiting
for the runaway child, plus an attempt/generation identity so a late completion cannot overwrite
the recorded failure. `TaskGroup.cancelAll()` is insufficient — a structured group still waits for
its children.

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
- if teardown cannot be confirmed within a bounded grace period, leave it recoverable as
  `.manual`.

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
capability. The callback converts `Progress` to `ModelDownloadProgress` before it crosses any actor
boundary.

**Failure handling is unchanged.** A download failure uses the existing `.modelInitialization`
presentation and retry behaviour. `WhisperModelBootstrap.actionableFailureMessage` is stored only
in `FailedAnalysis.technicalMessage`, which the UI deliberately does not render ("Retained for
local logs and debugging; UI uses `presentation`", `FailedAnalysis.swift:104`). Surfacing that
message is **not** part of this work.

## Build phases

**Phase 1 — the canonical model.** Exact model and snapshot types; projection and selectors;
shared publication owner and refresh mechanics; dismissal and removal persistence; the four
surfaces; then deletion of the legacy views. Independently shippable and independently testable.

**Phase 2a — teardown/cancellation spike.** A time-boxed investigation, not a feature. Exit
criteria:

- Can WhisperKit and Foundation Models confirm teardown after cancellation?
- What bounded grace period defines "teardown not confirmed"?
- Can the queue resolve the attempt without awaiting the runaway child?
- How is shared model ownership quarantined from a replacement attempt?
- Does a speculative prefetch stall consume retry budget, fall back to normal processing, or pause
  the queue?
- What happens to the remaining queue when teardown never confirms?

**Phase 2b — watchdog and `.stalled`.** Conditional on 2a's answers. If teardown cannot be
confirmed, the watchdog still records the failure and preserves the checkpoint, but automatic retry
is disabled and every stall settles at `.manual`.

**Phase 2c — model-download callback and `.preparing`.** Independent of the watchdog result and of
2a; can land any time after Phase 1.

## Testing

Swift Testing (`import Testing`), macOS and iOS Simulator. Run via `Scripts/run-tests.sh` so a
filter matching nothing fails rather than reporting success (ERR-002).

**Projection** — pure, no actor, no async:

- per-file collapse precedence, rule by rule
- terminal `currentAnalysis` (`.failed`) collapses to `.queued`, not `.running`
- terminal `currentAnalysis` (`.complete`) collapses to `.ready` **only when a ready snapshot
  exists**, and to `.paused` when only a checkpoint does
- auto-retry collapses to `.queued` and sorts below active work
- `lastFailure`, `recovery`, and `ready` survive a `.queued` or `.failed` collapse
- queue positions are one-based, follow queue order, and use first occurrence on a duplicate id
- `.preparing` requires both `audioFileID` and `attemptID` to match the active analysis
- a speculative download for the next file leaves the active file `.running`, not `.preparing`,
  and leaves the downloading file `.queued`
- a checkpoint with `recoveryStage == .none` still produces a `.paused` task
- a checkpoint older than `readyAt` yields `.ready`, not `.paused`
- an `.automatic` failure that is no longer queued lands in tier 1
- an `.automatic` failure that is still queued stays in tier 3
- failure merge: durable wins on equal `failedAt`, later `failedAt` wins when they differ, and
  records present in only one source are retained
- within-tier ordering and the `audioFile.id` tie-breaker are deterministic
- identical inputs produce equal snapshots (guards the `SyncPlayerItem` identity trap)
- a file absent from the library inventory emits no task

**Input assembly** — disk-backed, not part of the pure projection:

- a session file that is missing or fails to decode is omitted from the `ready` map
- `readyAt` comes from the session file's modification date, with import-date fallback for a
  bundled gold session
- the queue is de-duplicated before it reaches the projection

**Ownership and refresh:**

- progress refresh performs no disk reads
- an invalidation raised during an in-flight structural pass causes exactly one further pass,
  not one per invalidation
- a structural pass with a stale generation is discarded at commit
- a structural commit preserves progress values newer than the pass's own start
- an invalidation raised during bootstrap is not lost
- first publication happens only after library, recoveries, and ready enumeration complete
- the snapshot is `nil` rather than empty before first publication
- queue reorder, cancellation, and `clearQueue` each trigger a structural refresh
- session delete and audio delete invalidate correctly

**Persistence:**

- dismissed manual recovery round-trips through a new store and manager
- restored task retains `dismissedAt` and is excluded from pill candidates
- retry after dismissal reuses the transcript and clears the old dismissal
- a new failure occurrence for the same file starts undismissed
- `remove` deletes a manual checkpoint, clears `failedAnalyses`, and leaves nothing restorable
- a stale `failedAt` cannot dismiss or remove a newer occurrence
- dismissing `.unavailable` succeeds without a disk write and leaves no tier-5 entry
- persistence failure leaves both durable state and the published snapshot unchanged

**Pill candidates:**

- dismissed failures excluded
- active progress and an action-required failure render simultaneously

**Watchdog** (Phase 2b):

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
- **Uncooperative teardown.** The retry guard depends on observing teardown, and
  `cancelTranscription()` already awaits the task it cancels. If neither WhisperKit nor Foundation
  Models exposes a reliable post-cancellation signal, Phase 2b ships with automatic retry disabled
  and every stall settling at `.manual`. That is the safe direction, but it reduces what the
  watchdog buys.
- **`AnalysisStateManager` size.** The file is 1,406 lines. This work adds recovery-snapshot
  accessors, and Phase 2b adds a watchdog and generation identity. The projection is extracted
  deliberately; the watchdog should be extracted too, or the file gets worse.
- **Ordering divergence between pill and center** is intentional but is the kind of thing a future
  reader will "fix". The rationale is recorded above.
- **`AnalyzerView` lingers through Phase 1** carrying Library Intelligence behind one entry point.
  If `task_34b6360c` is not picked up, that is a half-migrated screen left in the app.
