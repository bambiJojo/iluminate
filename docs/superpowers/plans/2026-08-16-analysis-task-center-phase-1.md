# Analysis Task Center — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace six independent readers of analysis state with one canonical `[AnalysisTask]` snapshot, produced by a pure projection and consumed by four surfaces, and make failure dismissal durable.

**Architecture:** A pure `nonisolated` function maps a plain-value input struct to an ordered `[AnalysisTask]`. A single `@MainActor @Observable AnalysisCenterModel`, owned at the app root, assembles that input (off the main actor), publishes the snapshot, and coalesces refreshes behind a generation guard. Pill, Task Center, Library row, and Session Detail all filter the same published array. Dismissal state persists inside `AnalysisManualRecovery` so it survives relaunch without discarding resumable checkpoints.

**Tech Stack:** Swift 6.2 strict concurrency, SwiftUI, `@Observable`, Swift Testing, actor-isolated `AnalysisProgressStore`.

**Spec:** `docs/superpowers/specs/2026-08-16-analysis-task-center-design.md` (revision 3, commit `e940af8`).

**Out of scope:** Phase 2a (teardown spike), 2b (watchdog / `.stalled`), 2c (model-download callback). `ModelDownloadProgress` and `AnalysisTaskState.preparing` are *defined* here so the model is stable, but nothing produces them until 2c.

---

## Build and test commands

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/<SuiteName>
```

Always use `Scripts/run-tests.sh` rather than raw `xcodebuild test`. A `-only-testing:` filter that matches nothing makes `xcodebuild` print `** TEST SUCCEEDED **` having run zero tests (ERR-002). The wrapper fails when zero cases ran.

Filter at **suite** level (`-only-testing:IlumionateTests/AnalysisTaskProjectionTests`), not individual test level. Swift Testing identifiers end in `()`; omitting them matches nothing.

Before the final commit, run the full suite on both platforms:

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests
```

```bash
Scripts/run-tests.sh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IlumionateTests
```

## Xcode project note

`Ilumionate.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup`. **New `.swift` files under `Ilumionate/` are picked up automatically** — there is no "add to target" step. Do not edit `project.pbxproj`.

---

## File structure

### Created

| File | Responsibility |
|---|---|
| `Ilumionate/AnalysisCenter/AnalysisTask.swift` | `AnalysisTask`, `AnalysisTaskState` |
| `Ilumionate/AnalysisCenter/AnalysisTaskSnapshots.swift` | The five immutable input snapshots |
| `Ilumionate/AnalysisCenter/AnalysisFailureMerge.swift` | Durable + runtime failure merge |
| `Ilumionate/AnalysisCenter/AnalysisTaskProjection.swift` | Pure input → `[AnalysisTask]`, collapse + sort |
| `Ilumionate/AnalysisCenter/AnalysisTaskInputAssembler.swift` | Disk/store reads → `AnalysisTaskProjectionInput` |
| `Ilumionate/AnalysisCenter/AnalysisCenterModel.swift` | Ownership, refresh loop, publication |
| `Ilumionate/AnalysisCenter/AnalysisStatusPill.swift` | Bottom-chrome ambient signal |
| `Ilumionate/AnalysisCenter/AnalysisCenterView.swift` | The sheet |
| `Ilumionate/AnalysisCenter/AnalysisTaskRow.swift` | One row, all six states |
| `Ilumionate/AnalysisCenter/LibraryAnalysisEntryRow.swift` | Library summary row |

### Modified

| File | Change |
|---|---|
| `Ilumionate/AnalysisProgressStore.swift` | `dismissedAt`, `persist()` returns `Bool`, `dismiss`/`remove` |
| `Ilumionate/AnalysisStateManager.swift` | `attemptID`, structural-invalidation hook, snapshot accessors |
| `Ilumionate/ContentView.swift:197-235` | Pill replaces the two overlays |
| `Ilumionate/LibraryView.swift:261` | Entry row replaces `LibraryAnalysisStatusSection` |
| `Ilumionate/SessionDetailView.swift:447-495` | Read from the task, not the manager |

### Deleted (Task 13, last)

- `Ilumionate/AnalysisStatusBar.swift`
- `Ilumionate/AnalysisStatusOverlay.swift`
- `Ilumionate/LibraryAnalysisStatusSection.swift`

---

## Task 1: Snapshot value types

**Files:**
- Create: `Ilumionate/AnalysisCenter/AnalysisTaskSnapshots.swift`
- Test: `IlumionateTests/AnalysisTaskSnapshotTests.swift`

Background: `ActiveAnalysis` is an `@Observable final class` (`AnalysisStateManager.swift:1367`) — a non-`Sendable` reference type. `SyncPlayerItem` has `let id = UUID()` which regenerates per instance, and `FailedAnalysis` is not `Equatable`. None of them can appear in the published model. These snapshots are the value-type replacements.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AnalysisTaskSnapshotTests.swift`:

```swift
//
//  AnalysisTaskSnapshotTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

struct AnalysisTaskSnapshotTests {

    @Test func manualUndismissedFailureNeedsDecisionIntrinsically() {
        let failure = AnalysisFailureSnapshot(
            reason: .transcription,
            failedStage: .transcription,
            failedAt: Date(timeIntervalSince1970: 100),
            recoveryStage: .transcription,
            retryState: .manual,
            dismissedAt: nil
        )
        #expect(failure.needsDecisionIntrinsically)
    }

    @Test func dismissedFailureDoesNotNeedDecision() {
        let failure = AnalysisFailureSnapshot(
            reason: .transcription,
            failedStage: .transcription,
            failedAt: Date(timeIntervalSince1970: 100),
            recoveryStage: .transcription,
            retryState: .manual,
            dismissedAt: Date(timeIntervalSince1970: 200)
        )
        #expect(failure.needsDecisionIntrinsically == false)
    }

    @Test func automaticFailureDoesNotNeedDecisionIntrinsically() {
        let failure = AnalysisFailureSnapshot(
            reason: .transcription,
            failedStage: .transcription,
            failedAt: Date(timeIntervalSince1970: 100),
            recoveryStage: .none,
            retryState: .automatic,
            dismissedAt: nil
        )
        #expect(failure.needsDecisionIntrinsically == false)
    }

    @Test func activeSnapshotTerminalStages() {
        func snapshot(_ stage: AnalysisStage) -> ActiveAnalysisSnapshot {
            ActiveAnalysisSnapshot(
                audioFileID: UUID(),
                attemptID: UUID(),
                stage: stage,
                progress: 0.5,
                startedAt: Date(timeIntervalSince1970: 0)
            )
        }
        #expect(snapshot(.complete).isTerminal)
        #expect(snapshot(.failed).isTerminal)
        #expect(snapshot(.transcribing).isTerminal == false)
        #expect(snapshot(.starting).isTerminal == false)
        #expect(snapshot(.analyzing).isTerminal == false)
        #expect(snapshot(.generatingSession).isTerminal == false)
    }

    @Test func identicalSnapshotsAreEqual() {
        let id = UUID()
        let attempt = UUID()
        let date = Date(timeIntervalSince1970: 42)
        let a = ActiveAnalysisSnapshot(
            audioFileID: id, attemptID: attempt, stage: .transcribing, progress: 0.25, startedAt: date
        )
        let b = ActiveAnalysisSnapshot(
            audioFileID: id, attemptID: attempt, stage: .transcribing, progress: 0.25, startedAt: date
        )
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisTaskSnapshotTests`

Expected: **build failure**, `cannot find 'AnalysisFailureSnapshot' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Ilumionate/AnalysisCenter/AnalysisTaskSnapshots.swift`:

```swift
//
//  AnalysisTaskSnapshots.swift
//  Ilumionate
//
//  Immutable value snapshots of everything the Analysis Task Center projects.
//  The live types cannot be used: ActiveAnalysis is a non-Sendable @Observable
//  class, SyncPlayerItem regenerates its id per instance, and FailedAnalysis is
//  not Equatable.
//

import Foundation

/// The active analysis, flattened to values.
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

/// Progress of a WhisperKit model download. Produced in Phase 2c; defined here
/// so the model does not change when that lands.
nonisolated struct ModelDownloadProgress: Equatable, Sendable {
    /// The file whose analysis this download is bootstrapping. A speculative
    /// prefetch downloads for the *next* file, not the active one.
    let audioFileID: UUID
    let attemptID: UUID
    let completedUnitCount: Int64
    let totalUnitCount: Int64
    let fractionCompleted: Double
}

/// A recorded failure, merged from the durable recovery and the runtime list.
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
    /// Tier-1 eligibility is broader — an `.automatic` failure that is no
    /// longer queued is also stranded. See `AnalysisTaskProjection`.
    var needsDecisionIntrinsically: Bool {
        dismissedAt == nil && (retryState == .manual || retryState == .unavailable)
    }
}

/// A durable checkpoint, flattened. Carries `lastUpdated` because tier-4
/// ordering needs it and because it is the only way to detect a checkpoint
/// overtaken by a completed session.
nonisolated struct AnalysisCheckpointSnapshot: Equatable, Sendable {
    let recoveryStage: AnalysisRecoveryStage
    let startedAt: Date
    let lastUpdated: Date
}

/// A generated session that is ready to play.
nonisolated struct AnalysisReadySnapshot: Equatable, Sendable {
    /// `LightSession.id` — decoded from stored JSON, stable across loads.
    /// Deliberately not `SyncPlayerItem.id`, which regenerates per instance.
    let sessionID: UUID
    let readyAt: Date
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisTaskSnapshotTests`

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AnalysisCenter/AnalysisTaskSnapshots.swift IlumionateTests/AnalysisTaskSnapshotTests.swift
git commit -m "feat: add immutable snapshot types for the analysis task model"
```

---

## Task 2: The task and its state

**Files:**
- Create: `Ilumionate/AnalysisCenter/AnalysisTask.swift`
- Test: `IlumionateTests/AnalysisTaskTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AnalysisTaskTests.swift`:

```swift
//
//  AnalysisTaskTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

private func makeAudioFile(id: UUID = UUID()) -> AudioFile {
    AudioFile(
        id: id,
        filename: "test_\(id.uuidString).m4a",
        duration: 300,
        fileSize: 1_024_000,
        createdDate: Date(timeIntervalSince1970: 0)
    )
}

struct AnalysisTaskTests {

    @Test func taskIdentityComesFromAudioFile() {
        let id = UUID()
        let task = AnalysisTask(
            audioFile: makeAudioFile(id: id),
            state: .queued(position: 1),
            lastFailure: nil,
            recovery: .none,
            ready: nil
        )
        #expect(task.id == id)
    }

    /// Guards the SyncPlayerItem trap: two projections of identical state must
    /// compare equal, or every progress tick looks like a full list change.
    @Test func identicalTasksAreEqual() {
        let file = makeAudioFile()
        let ready = AnalysisReadySnapshot(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!,
            readyAt: Date(timeIntervalSince1970: 10)
        )
        let a = AnalysisTask(audioFile: file, state: .ready, lastFailure: nil, recovery: .none, ready: ready)
        let b = AnalysisTask(audioFile: file, state: .ready, lastFailure: nil, recovery: .none, ready: ready)
        #expect(a == b)
    }

    @Test func differingStateBreaksEquality() {
        let file = makeAudioFile()
        let a = AnalysisTask(audioFile: file, state: .queued(position: 1), lastFailure: nil, recovery: .none, ready: nil)
        let b = AnalysisTask(audioFile: file, state: .queued(position: 2), lastFailure: nil, recovery: .none, ready: nil)
        #expect(a != b)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisTaskTests`

Expected: **build failure**, `cannot find 'AnalysisTask' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Ilumionate/AnalysisCenter/AnalysisTask.swift`:

```swift
//
//  AnalysisTask.swift
//  Ilumionate
//
//  One task per audio file. `state` is what the pipeline is doing right now;
//  `lastFailure`, `recovery`, and `ready` are what has been salvaged, and are
//  populated independently of `state`.
//

import Foundation

nonisolated struct AnalysisTask: Identifiable, Equatable, Sendable {
    var id: UUID { audioFile.id }

    let audioFile: AudioFile
    let state: AnalysisTaskState
    /// Present whenever a failure has been recorded, including when `state` has
    /// moved on to `.queued` for an automatic retry.
    let lastFailure: AnalysisFailureSnapshot?
    /// The most useful partial result on disk, independent of `state`.
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisTaskTests`

Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AnalysisCenter/AnalysisTask.swift IlumionateTests/AnalysisTaskTests.swift
git commit -m "feat: add AnalysisTask and AnalysisTaskState"
```

---

## Task 3: Failure merge

**Files:**
- Create: `Ilumionate/AnalysisCenter/AnalysisFailureMerge.swift`
- Test: `IlumionateTests/AnalysisFailureMergeTests.swift`

Background: failures live in two places. Durable manual recoveries (`AnalysisProgressStore.manualRecoveryCheckpoints()`) carry `dismissedAt` and survive relaunch, but exist only for `.manual` failures. Runtime `failedAnalyses` also holds `.automatic` and `.unavailable`, but is lost on termination. The merge must be total over the union of both key sets.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AnalysisFailureMergeTests.swift`:

```swift
//
//  AnalysisFailureMergeTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

private func snapshot(
    failedAt: TimeInterval,
    retryState: AnalysisRetryState = .manual,
    dismissedAt: Date? = nil,
    recoveryStage: AnalysisRecoveryStage = .transcription
) -> AnalysisFailureSnapshot {
    AnalysisFailureSnapshot(
        reason: .transcription,
        failedStage: .transcription,
        failedAt: Date(timeIntervalSince1970: failedAt),
        recoveryStage: recoveryStage,
        retryState: retryState,
        dismissedAt: dismissedAt
    )
}

struct AnalysisFailureMergeTests {

    @Test func durableWinsOnEqualFailedAt() {
        let id = UUID()
        let durable = snapshot(failedAt: 100, dismissedAt: Date(timeIntervalSince1970: 150))
        let runtime = snapshot(failedAt: 100, dismissedAt: nil)
        let merged = AnalysisFailureMerge.merge(durable: [id: durable], runtime: [id: runtime])
        #expect(merged[id]?.dismissedAt == Date(timeIntervalSince1970: 150))
    }

    @Test func laterFailedAtWins() {
        let id = UUID()
        let durable = snapshot(failedAt: 100, dismissedAt: Date(timeIntervalSince1970: 150))
        let runtime = snapshot(failedAt: 300, dismissedAt: nil)
        let merged = AnalysisFailureMerge.merge(durable: [id: durable], runtime: [id: runtime])
        #expect(merged[id]?.failedAt == Date(timeIntervalSince1970: 300))
        #expect(merged[id]?.dismissedAt == nil)
    }

    @Test func durableOnlyIsRetained() {
        let id = UUID()
        let durable = snapshot(failedAt: 100)
        let merged = AnalysisFailureMerge.merge(durable: [id: durable], runtime: [:])
        #expect(merged[id]?.failedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func runtimeOnlyIsRetained() {
        let id = UUID()
        let runtime = snapshot(failedAt: 100, retryState: .unavailable, recoveryStage: .none)
        let merged = AnalysisFailureMerge.merge(durable: [:], runtime: [id: runtime])
        #expect(merged[id]?.retryState == .unavailable)
    }

    @Test func mergeCoversUnionOfBothKeySets() {
        let a = UUID(), b = UUID()
        let merged = AnalysisFailureMerge.merge(
            durable: [a: snapshot(failedAt: 1)],
            runtime: [b: snapshot(failedAt: 2)]
        )
        #expect(merged.count == 2)
        #expect(merged[a] != nil)
        #expect(merged[b] != nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisFailureMergeTests`

Expected: **build failure**, `cannot find 'AnalysisFailureMerge' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Ilumionate/AnalysisCenter/AnalysisFailureMerge.swift`:

```swift
//
//  AnalysisFailureMerge.swift
//  Ilumionate
//
//  Failures live in two places with different lifetimes. The durable manual
//  recovery survives relaunch and carries `dismissedAt`, but only exists for
//  `.manual` failures. The runtime list also holds `.automatic` and
//  `.unavailable`, but is lost on termination.
//

import Foundation

nonisolated enum AnalysisFailureMerge {

    /// Total over the union of both key sets. The durable record is
    /// authoritative on an equal `failedAt`; otherwise the later occurrence
    /// wins, because `markRequiresManualRetry` writes a fresh recovery per
    /// occurrence and a newer failure genuinely supersedes an older one.
    static func merge(
        durable: [UUID: AnalysisFailureSnapshot],
        runtime: [UUID: AnalysisFailureSnapshot]
    ) -> [UUID: AnalysisFailureSnapshot] {
        var merged = durable
        for (id, runtimeFailure) in runtime {
            guard let durableFailure = merged[id] else {
                merged[id] = runtimeFailure
                continue
            }
            if runtimeFailure.failedAt > durableFailure.failedAt {
                merged[id] = runtimeFailure
            }
        }
        return merged
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisFailureMergeTests`

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AnalysisCenter/AnalysisFailureMerge.swift IlumionateTests/AnalysisFailureMergeTests.swift
git commit -m "feat: merge durable and runtime analysis failures"
```

---

## Task 4: The projection — collapse precedence

**Files:**
- Create: `Ilumionate/AnalysisCenter/AnalysisTaskProjection.swift`
- Test: `IlumionateTests/AnalysisTaskProjectionTests.swift`

This is the correctness core. Read the spec's "Per-file collapse precedence" section before starting.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AnalysisTaskProjectionTests.swift`:

```swift
//
//  AnalysisTaskProjectionTests.swift
//  IlumionateTests
//
//  Pure projection: no actor, no async, no disk.
//

import Testing
import Foundation
@testable import Ilumionate

private func makeAudioFile(id: UUID = UUID()) -> AudioFile {
    AudioFile(
        id: id,
        filename: "test_\(id.uuidString).m4a",
        duration: 300,
        fileSize: 1_024_000,
        createdDate: Date(timeIntervalSince1970: 0)
    )
}

private func input(
    files: [AudioFile],
    active: ActiveAnalysisSnapshot? = nil,
    download: ModelDownloadProgress? = nil,
    queue: [UUID] = [],
    failures: [UUID: AnalysisFailureSnapshot] = [:],
    checkpoints: [UUID: AnalysisCheckpointSnapshot] = [:],
    ready: [UUID: AnalysisReadySnapshot] = [:]
) -> AnalysisTaskProjectionInput {
    AnalysisTaskProjectionInput(
        libraryFiles: files,
        activeAnalysis: active,
        modelDownload: download,
        queue: queue,
        failures: failures,
        checkpoints: checkpoints,
        ready: ready
    )
}

private func failure(
    failedAt: TimeInterval = 100,
    retryState: AnalysisRetryState = .manual,
    dismissedAt: Date? = nil,
    recoveryStage: AnalysisRecoveryStage = .transcription
) -> AnalysisFailureSnapshot {
    AnalysisFailureSnapshot(
        reason: .transcription,
        failedStage: .transcription,
        failedAt: Date(timeIntervalSince1970: failedAt),
        recoveryStage: recoveryStage,
        retryState: retryState,
        dismissedAt: dismissedAt
    )
}

private func checkpoint(
    recoveryStage: AnalysisRecoveryStage = .transcription,
    lastUpdated: TimeInterval = 100
) -> AnalysisCheckpointSnapshot {
    AnalysisCheckpointSnapshot(
        recoveryStage: recoveryStage,
        startedAt: Date(timeIntervalSince1970: 0),
        lastUpdated: Date(timeIntervalSince1970: lastUpdated)
    )
}

private func ready(readyAt: TimeInterval = 100) -> AnalysisReadySnapshot {
    AnalysisReadySnapshot(sessionID: UUID(), readyAt: Date(timeIntervalSince1970: readyAt))
}

private func active(
    _ fileID: UUID,
    stage: AnalysisStage = .transcribing,
    attemptID: UUID = UUID(),
    progress: Double = 0.4
) -> ActiveAnalysisSnapshot {
    ActiveAnalysisSnapshot(
        audioFileID: fileID,
        attemptID: attemptID,
        stage: stage,
        progress: progress,
        startedAt: Date(timeIntervalSince1970: 50)
    )
}

struct AnalysisTaskProjectionTests {

    // MARK: Rule 1 / 2 — active

    @Test func nonTerminalActiveCollapsesToRunning() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(files: [file], active: active(file.id)))
        #expect(tasks.first?.state == .running(stage: .transcribing, progress: 0.4, startedAt: Date(timeIntervalSince1970: 50)))
    }

    @Test func preparingRequiresMatchingFileAndAttempt() {
        let file = makeAudioFile()
        let attempt = UUID()
        let download = ModelDownloadProgress(
            audioFileID: file.id, attemptID: attempt,
            completedUnitCount: 5, totalUnitCount: 10, fractionCompleted: 0.5
        )
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            active: active(file.id, attemptID: attempt),
            download: download
        ))
        #expect(tasks.first?.state == .preparing(download))
    }

    /// The lookahead prefetch downloads for the *next* file while the current
    /// file is generating. A global download flag would mislabel the active file.
    @Test func speculativeDownloadDoesNotRelabelActiveFile() {
        let current = makeAudioFile()
        let next = makeAudioFile()
        let download = ModelDownloadProgress(
            audioFileID: next.id, attemptID: UUID(),
            completedUnitCount: 5, totalUnitCount: 10, fractionCompleted: 0.5
        )
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [current, next],
            active: active(current.id, stage: .generatingSession),
            download: download,
            queue: [next.id]
        ))
        let currentTask = tasks.first { $0.id == current.id }
        let nextTask = tasks.first { $0.id == next.id }
        #expect(currentTask?.state == .running(stage: .generatingSession, progress: 0.4, startedAt: Date(timeIntervalSince1970: 50)))
        #expect(nextTask?.state == .queued(position: 1))
    }

    // MARK: Terminal active falls through

    @Test func terminalFailedActiveCollapsesToQueuedNotRunning() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            active: active(file.id, stage: .failed),
            queue: [file.id],
            failures: [file.id: failure(retryState: .automatic)]
        ))
        #expect(tasks.first?.state == .queued(position: 1))
    }

    @Test func terminalCompleteActiveCollapsesToReadyWhenReadyExists() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            active: active(file.id, stage: .complete),
            ready: [file.id: ready()]
        ))
        #expect(tasks.first?.state == .ready)
    }

    @Test func terminalCompleteWithoutReadySnapshotDoesNotSynthesiseReady() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            active: active(file.id, stage: .complete),
            checkpoints: [file.id: checkpoint()]
        ))
        #expect(tasks.first?.state == .paused)
    }

    // MARK: Rule 3 above rule 4

    @Test func automaticRetryCollapsesToQueuedAndKeepsFailureAsAttribute() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            queue: [file.id],
            failures: [file.id: failure(retryState: .automatic)]
        ))
        #expect(tasks.first?.state == .queued(position: 1))
        #expect(tasks.first?.lastFailure != nil)
    }

    @Test func queuePositionsAreOneBased() {
        let a = makeAudioFile(), b = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(files: [a, b], queue: [a.id, b.id]))
        #expect(tasks.first { $0.id == a.id }?.state == .queued(position: 1))
        #expect(tasks.first { $0.id == b.id }?.state == .queued(position: 2))
    }

    @Test func duplicateQueueEntriesUseFirstOccurrence() {
        let file = makeAudioFile()
        let other = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file, other],
            queue: [file.id, other.id, file.id]
        ))
        #expect(tasks.first { $0.id == file.id }?.state == .queued(position: 1))
    }

    // MARK: Rule 5 — paused

    @Test func checkpointWithNoRecoveryStageStillProducesPausedTask() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            checkpoints: [file.id: checkpoint(recoveryStage: .none)]
        ))
        #expect(tasks.first?.state == .paused)
        #expect(tasks.first?.recovery == AnalysisRecoveryStage.none)
    }

    @Test func checkpointOlderThanReadyYieldsReady() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            checkpoints: [file.id: checkpoint(lastUpdated: 50)],
            ready: [file.id: ready(readyAt: 100)]
        ))
        #expect(tasks.first?.state == .ready)
    }

    @Test func checkpointNewerThanReadyYieldsPaused() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            checkpoints: [file.id: checkpoint(lastUpdated: 150)],
            ready: [file.id: ready(readyAt: 100)]
        ))
        #expect(tasks.first?.state == .paused)
    }

    // MARK: Library is the spine

    @Test func fileAbsentFromLibraryEmitsNoTask() {
        let orphan = UUID()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [],
            queue: [orphan],
            failures: [orphan: failure()]
        ))
        #expect(tasks.isEmpty)
    }

    @Test func fileWithNoStateAtAllEmitsNoTask() {
        let file = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(files: [file]))
        #expect(tasks.isEmpty)
    }

    // MARK: Attributes survive collapse

    @Test func attributesSurviveQueuedCollapse() {
        let file = makeAudioFile()
        let readySnapshot = ready()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [file],
            queue: [file.id],
            failures: [file.id: failure(retryState: .automatic)],
            checkpoints: [file.id: checkpoint(recoveryStage: .analysis)],
            ready: [file.id: readySnapshot]
        ))
        let task = tasks.first
        #expect(task?.state == .queued(position: 1))
        #expect(task?.lastFailure?.retryState == .automatic)
        #expect(task?.recovery == AnalysisRecoveryStage.analysis)
        #expect(task?.ready == readySnapshot)
    }

    // MARK: Determinism

    @Test func identicalInputsProduceEqualSnapshots() {
        let file = makeAudioFile()
        let shared = input(files: [file], queue: [file.id])
        #expect(AnalysisTaskProjection.tasks(from: shared) == AnalysisTaskProjection.tasks(from: shared))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisTaskProjectionTests`

Expected: **build failure**, `cannot find 'AnalysisTaskProjection' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Ilumionate/AnalysisCenter/AnalysisTaskProjection.swift`:

```swift
//
//  AnalysisTaskProjection.swift
//  Ilumionate
//
//  Pure input -> ordered [AnalysisTask]. No actor, no async, no disk access.
//  Every analysis surface renders this one list; none re-derives state.
//

import Foundation

nonisolated struct AnalysisTaskProjectionInput: Equatable, Sendable {
    let libraryFiles: [AudioFile]
    let activeAnalysis: ActiveAnalysisSnapshot?
    let modelDownload: ModelDownloadProgress?
    /// Audio file ids in queue order. The assembler enforces uniqueness; the
    /// projection uses first occurrence if a duplicate slips through.
    let queue: [UUID]
    let failures: [UUID: AnalysisFailureSnapshot]
    let checkpoints: [UUID: AnalysisCheckpointSnapshot]
    let ready: [UUID: AnalysisReadySnapshot]
}

nonisolated enum AnalysisTaskProjection {

    static func tasks(from input: AnalysisTaskProjectionInput) -> [AnalysisTask] {
        var positions: [UUID: Int] = [:]
        for (index, id) in input.queue.enumerated() where positions[id] == nil {
            positions[id] = index + 1          // one-based, first occurrence
        }

        let tasks = input.libraryFiles.compactMap { file -> AnalysisTask? in
            guard let state = state(for: file.id, in: input, queuePosition: positions[file.id]) else {
                return nil
            }
            return AnalysisTask(
                audioFile: file,
                state: state,
                lastFailure: input.failures[file.id],
                recovery: input.checkpoints[file.id]?.recoveryStage ?? .none,
                ready: input.ready[file.id]
            )
        }

        return sorted(tasks, queuePositions: positions)
    }

    // MARK: Collapse

    private static func state(
        for fileID: UUID,
        in input: AnalysisTaskProjectionInput,
        queuePosition: Int?
    ) -> AnalysisTaskState? {
        // Rules 1 and 2 — an active, non-terminal analysis. Terminal stages fall
        // through: the pipeline leaves `currentAnalysis` populated with
        // `.failed` while re-queueing the file, and collapsing that to
        // `.running(.failed)` would defeat the automatic-retry rule.
        if let active = input.activeAnalysis, active.audioFileID == fileID, !active.isTerminal {
            if let download = input.modelDownload,
               download.audioFileID == fileID,
               download.attemptID == active.attemptID {
                return .preparing(download)
            }
            return .running(stage: active.stage, progress: active.progress, startedAt: active.startedAt)
        }

        // Rule 3 — above rule 4 so an automatic retry reads as queued.
        if let position = queuePosition {
            return .queued(position: position)
        }

        // Rule 4
        if input.failures[fileID] != nil {
            return .failed
        }

        // Rule 5 — a checkpoint counts even with `.none` recovery, but not when
        // a completed session has already superseded it.
        if let checkpoint = input.checkpoints[fileID] {
            let overtaken = input.ready[fileID].map { checkpoint.lastUpdated <= $0.readyAt } ?? false
            if !overtaken {
                return .paused
            }
        }

        // Rule 6
        if input.ready[fileID] != nil {
            return .ready
        }

        return nil
    }

    // MARK: Sort

    /// Tier 1 is computed here rather than on the failure snapshot because it
    /// depends on queue membership: an `.automatic` failure is only harmless
    /// while something is going to retry it.
    static func needsDecision(_ task: AnalysisTask, queuePositions: [UUID: Int]) -> Bool {
        guard let failure = task.lastFailure, failure.dismissedAt == nil else { return false }
        return failure.needsDecisionIntrinsically || queuePositions[task.id] == nil
    }

    private static func tier(_ task: AnalysisTask, queuePositions: [UUID: Int]) -> Int {
        if needsDecision(task, queuePositions: queuePositions) { return 1 }
        switch task.state {
        case .preparing, .running: return 2
        case .queued:              return 3
        case .paused:              return 4
        case .failed:              return 5
        case .ready:               return 6
        }
    }

    private static func sorted(_ tasks: [AnalysisTask], queuePositions: [UUID: Int]) -> [AnalysisTask] {
        tasks.sorted { lhs, rhs in
            let lhsTier = tier(lhs, queuePositions: queuePositions)
            let rhsTier = tier(rhs, queuePositions: queuePositions)
            if lhsTier != rhsTier { return lhsTier < rhsTier }
            if let ordering = withinTier(lhsTier, lhs, rhs, queuePositions: queuePositions) { return ordering }
            return lhs.id.uuidString < rhs.id.uuidString      // stable tie-breaker
        }
    }

    private static func withinTier(
        _ tier: Int,
        _ lhs: AnalysisTask,
        _ rhs: AnalysisTask,
        queuePositions: [UUID: Int]
    ) -> Bool? {
        switch tier {
        case 1, 5:
            guard let l = lhs.lastFailure?.failedAt, let r = rhs.lastFailure?.failedAt, l != r else { return nil }
            return l > r
        case 2:
            guard case .running(_, _, let l) = lhs.state, case .running(_, _, let r) = rhs.state, l != r else { return nil }
            return l > r
        case 3:
            guard let l = queuePositions[lhs.id], let r = queuePositions[rhs.id], l != r else { return nil }
            return l < r
        case 6:
            guard let l = lhs.ready?.readyAt, let r = rhs.ready?.readyAt, l != r else { return nil }
            return l > r
        default:
            return nil
        }
    }
}
```

Note: tier 4 (`.paused`) ordering by checkpoint `lastUpdated` is added in Task 5, which is where the sorting tests live. The projection carries `recovery` but not `lastUpdated`, so tier 4 currently falls to the id tie-breaker.

- [ ] **Step 4: Run test to verify it passes**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisTaskProjectionTests`

Expected: PASS, 16 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AnalysisCenter/AnalysisTaskProjection.swift IlumionateTests/AnalysisTaskProjectionTests.swift
git commit -m "feat: project analysis state into one ordered task list"
```

---

## Task 5: Tier ordering and the stranded automatic failure

**Files:**
- Modify: `Ilumionate/AnalysisCenter/AnalysisTask.swift`
- Modify: `Ilumionate/AnalysisCenter/AnalysisTaskProjection.swift`
- Test: `IlumionateTests/AnalysisTaskSortingTests.swift`

Tier 4 needs the checkpoint's `lastUpdated`, which the task does not currently carry. Add it to `AnalysisTask` so sorting is total without re-reading the input.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AnalysisTaskSortingTests.swift`:

```swift
//
//  AnalysisTaskSortingTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

private func makeAudioFile(id: UUID = UUID()) -> AudioFile {
    AudioFile(
        id: id,
        filename: "test_\(id.uuidString).m4a",
        duration: 300,
        fileSize: 1_024_000,
        createdDate: Date(timeIntervalSince1970: 0)
    )
}

private func failure(
    failedAt: TimeInterval,
    retryState: AnalysisRetryState = .manual,
    dismissedAt: Date? = nil
) -> AnalysisFailureSnapshot {
    AnalysisFailureSnapshot(
        reason: .transcription,
        failedStage: .transcription,
        failedAt: Date(timeIntervalSince1970: failedAt),
        recoveryStage: .transcription,
        retryState: retryState,
        dismissedAt: dismissedAt
    )
}

private func input(
    files: [AudioFile],
    active: ActiveAnalysisSnapshot? = nil,
    queue: [UUID] = [],
    failures: [UUID: AnalysisFailureSnapshot] = [:],
    checkpoints: [UUID: AnalysisCheckpointSnapshot] = [:],
    ready: [UUID: AnalysisReadySnapshot] = [:]
) -> AnalysisTaskProjectionInput {
    AnalysisTaskProjectionInput(
        libraryFiles: files, activeAnalysis: active, modelDownload: nil,
        queue: queue, failures: failures, checkpoints: checkpoints, ready: ready
    )
}

struct AnalysisTaskSortingTests {

    @Test func actionRequiredFailureOutranksActiveWork() {
        let failed = makeAudioFile()
        let running = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [running, failed],
            active: ActiveAnalysisSnapshot(
                audioFileID: running.id, attemptID: UUID(), stage: .transcribing,
                progress: 0.5, startedAt: Date(timeIntervalSince1970: 10)
            ),
            failures: [failed.id: failure(failedAt: 100)]
        ))
        #expect(tasks.first?.id == failed.id)
    }

    /// Criterion 7: an automatic retry is still queued, so it must not
    /// masquerade as something needing a decision.
    @Test func queuedAutomaticRetryStaysBelowActiveWork() {
        let retrying = makeAudioFile()
        let running = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [retrying, running],
            active: ActiveAnalysisSnapshot(
                audioFileID: running.id, attemptID: UUID(), stage: .transcribing,
                progress: 0.5, startedAt: Date(timeIntervalSince1970: 10)
            ),
            queue: [retrying.id],
            failures: [retrying.id: failure(failedAt: 100, retryState: .automatic)]
        ))
        #expect(tasks.first?.id == running.id)
    }

    /// The hole: clearQueue() strands an automatic failure. Nothing will retry
    /// it, so it must surface rather than sitting in no tier at all.
    @Test func strandedAutomaticFailureReachesTierOne() {
        let stranded = makeAudioFile()
        let running = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [stranded, running],
            active: ActiveAnalysisSnapshot(
                audioFileID: running.id, attemptID: UUID(), stage: .transcribing,
                progress: 0.5, startedAt: Date(timeIntervalSince1970: 10)
            ),
            queue: [],
            failures: [stranded.id: failure(failedAt: 100, retryState: .automatic)]
        ))
        #expect(tasks.first?.id == stranded.id)
    }

    @Test func dismissedFailuresSortBelowPaused() {
        let dismissed = makeAudioFile()
        let paused = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [dismissed, paused],
            failures: [dismissed.id: failure(failedAt: 100, dismissedAt: Date(timeIntervalSince1970: 200))],
            checkpoints: [paused.id: AnalysisCheckpointSnapshot(
                recoveryStage: .transcription,
                startedAt: Date(timeIntervalSince1970: 0),
                lastUpdated: Date(timeIntervalSince1970: 10)
            )]
        ))
        #expect(tasks.first?.id == paused.id)
    }

    @Test func pausedTasksOrderByCheckpointLastUpdatedDescending() {
        let older = makeAudioFile()
        let newer = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [older, newer],
            checkpoints: [
                older.id: AnalysisCheckpointSnapshot(
                    recoveryStage: .transcription,
                    startedAt: Date(timeIntervalSince1970: 0),
                    lastUpdated: Date(timeIntervalSince1970: 10)
                ),
                newer.id: AnalysisCheckpointSnapshot(
                    recoveryStage: .transcription,
                    startedAt: Date(timeIntervalSince1970: 0),
                    lastUpdated: Date(timeIntervalSince1970: 99)
                )
            ]
        ))
        #expect(tasks.first?.id == newer.id)
    }

    @Test func readyTasksOrderByReadyAtDescending() {
        let older = makeAudioFile()
        let newer = makeAudioFile()
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [older, newer],
            ready: [
                older.id: AnalysisReadySnapshot(sessionID: UUID(), readyAt: Date(timeIntervalSince1970: 10)),
                newer.id: AnalysisReadySnapshot(sessionID: UUID(), readyAt: Date(timeIntervalSince1970: 99))
            ]
        ))
        #expect(tasks.first?.id == newer.id)
    }

    @Test func equalTimestampsFallBackToStableIDOrder() {
        let a = makeAudioFile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
        let b = makeAudioFile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!)
        let sameReady = Date(timeIntervalSince1970: 50)
        let tasks = AnalysisTaskProjection.tasks(from: input(
            files: [b, a],
            ready: [
                a.id: AnalysisReadySnapshot(sessionID: UUID(), readyAt: sameReady),
                b.id: AnalysisReadySnapshot(sessionID: UUID(), readyAt: sameReady)
            ]
        ))
        #expect(tasks.map(\.id) == [a.id, b.id])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisTaskSortingTests`

Expected: FAIL on `pausedTasksOrderByCheckpointLastUpdatedDescending` — tier 4 currently falls to the id tie-breaker, so the order is by UUID rather than recency.

- [ ] **Step 3: Write minimal implementation**

In `Ilumionate/AnalysisCenter/AnalysisTask.swift`, add the field after `recovery`:

```swift
    /// The most useful partial result on disk, independent of `state`.
    let recovery: AnalysisRecoveryStage
    /// Checkpoint recency, carried so tier-4 ordering is total without
    /// re-reading the projection input. `nil` when no checkpoint exists.
    let checkpointLastUpdated: Date?
```

In `AnalysisTaskProjection.tasks(from:)`, populate it:

```swift
            return AnalysisTask(
                audioFile: file,
                state: state,
                lastFailure: input.failures[file.id],
                recovery: input.checkpoints[file.id]?.recoveryStage ?? .none,
                checkpointLastUpdated: input.checkpoints[file.id]?.lastUpdated,
                ready: input.ready[file.id]
            )
```

In `withinTier`, add the tier-4 case before `default`:

```swift
        case 4:
            guard let l = lhs.checkpointLastUpdated, let r = rhs.checkpointLastUpdated, l != r else { return nil }
            return l > r
```

Then update the three existing `AnalysisTask(...)` literals in `IlumionateTests/AnalysisTaskTests.swift` to pass `checkpointLastUpdated: nil` after `recovery:`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisTaskSortingTests`

Expected: PASS, 7 tests.

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisTaskTests`

Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AnalysisCenter IlumionateTests/AnalysisTaskSortingTests.swift IlumionateTests/AnalysisTaskTests.swift
git commit -m "feat: order analysis tasks by tier with deterministic tie-breaking"
```

---

## Task 6: Persist dismissal on the failure occurrence

**Files:**
- Modify: `Ilumionate/AnalysisProgressStore.swift:58-62` (struct), `:236-242` (`persist`)
- Test: `IlumionateTests/AnalysisDismissalTests.swift`

`restoreManualRecoveries()` rebuilds `failedAnalyses` from durable checkpoints on every launch, so dismissal held only in memory is resurrected — this is ERR-013. Storing `dismissedAt` inside `AnalysisManualRecovery` means `saveQueued` (which already nils `manualRecovery` at `:120-129`) and `markRequiresManualRetry` (which builds a fresh recovery at `:212`) invalidate it for free.

`persist()` currently swallows both encoding and write errors. Same defect class as ERR-005.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AnalysisDismissalTests.swift`:

```swift
//
//  AnalysisDismissalTests.swift
//  IlumionateTests
//
//  ERR-013: dismissal must survive relaunch without discarding resumable work.
//

import Testing
import Foundation
@testable import Ilumionate

private func makeAudioFile(id: UUID = UUID()) -> AudioFile {
    AudioFile(
        id: id,
        filename: "test_\(id.uuidString).m4a",
        duration: 300,
        fileSize: 1_024_000,
        createdDate: Date(timeIntervalSince1970: 0)
    )
}

private func temporaryStoreURL() -> URL {
    URL.temporaryDirectory.appending(path: "AnalysisProgress-\(UUID().uuidString).json")
}

struct AnalysisDismissalTests {

    @Test func dismissedRecoveryRoundTripsThroughANewStore() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let failedAt = Date(timeIntervalSince1970: 100)

        let store = AnalysisProgressStore(storeURL: url)
        await store.saveTranscription(.empty, for: file)
        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription, failedAt: failedAt
        )
        let dismissed = await store.dismiss(fileID: file.id, expectingFailedAt: failedAt)
        #expect(dismissed)

        let reloaded = AnalysisProgressStore(storeURL: url)
        let checkpoint = await reloaded.checkpoint(for: file)
        #expect(checkpoint?.manualRecovery?.dismissedAt != nil)
        // The whole point: dismissal must not discard resumable work.
        #expect(checkpoint?.transcription != nil)
    }

    @Test func staleFailedAtCannotDismissANewerOccurrence() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)

        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription,
            failedAt: Date(timeIntervalSince1970: 300)
        )
        let dismissed = await store.dismiss(
            fileID: file.id, expectingFailedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(dismissed == false)
        let checkpoint = await store.checkpoint(for: file)
        #expect(checkpoint?.manualRecovery?.dismissedAt == nil)
    }

    @Test func newFailureOccurrenceStartsUndismissed() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)
        let first = Date(timeIntervalSince1970: 100)

        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription, failedAt: first
        )
        _ = await store.dismiss(fileID: file.id, expectingFailedAt: first)

        let second = Date(timeIntervalSince1970: 500)
        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription, failedAt: second
        )
        let checkpoint = await store.checkpoint(for: file)
        #expect(checkpoint?.manualRecovery?.dismissedAt == nil)
        #expect(checkpoint?.manualRecovery?.failedAt == second)
    }

    @Test func retryClearsDismissal() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)
        let failedAt = Date(timeIntervalSince1970: 100)

        await store.saveTranscription(.empty, for: file)
        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription, failedAt: failedAt
        )
        _ = await store.dismiss(fileID: file.id, expectingFailedAt: failedAt)

        await store.saveQueued(file)          // this is what a retry does
        let checkpoint = await store.checkpoint(for: file)
        #expect(checkpoint?.manualRecovery == nil)
        // Retry resumes from the saved transcript rather than transcribing again.
        #expect(checkpoint?.transcription != nil)
    }

    @Test func removeDeletesTheCheckpointEntirely() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)
        let failedAt = Date(timeIntervalSince1970: 100)

        await store.saveTranscription(.empty, for: file)
        await store.markRequiresManualRetry(
            for: file, reason: .transcription, failedStage: .transcription, failedAt: failedAt
        )
        let removed = await store.remove(fileID: file.id, expectingFailedAt: failedAt)
        #expect(removed)

        let reloaded = AnalysisProgressStore(storeURL: url)
        #expect(await reloaded.checkpoint(for: file) == nil)
        #expect(await reloaded.manualRecoveryCheckpoints().isEmpty)
    }

    @Test func dismissReturnsFalseWhenNoRecoveryExists() async throws {
        let url = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = makeAudioFile()
        let store = AnalysisProgressStore(storeURL: url)
        let dismissed = await store.dismiss(
            fileID: file.id, expectingFailedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(dismissed == false)
    }
}
```

If `AudioTranscriptionResult` has no `.empty` static, replace `.empty` with a minimal literal matching its initialiser — check `Ilumionate/AudioAnalyzer.swift` for the declaration and use the same shape the existing `AnalysisCacheTests.swift` fixtures use.

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisDismissalTests`

Expected: **build failure**, `value of type 'AnalysisProgressStore' has no member 'dismiss'`.

- [ ] **Step 3: Write minimal implementation**

In `Ilumionate/AnalysisProgressStore.swift`, change the recovery struct:

```swift
nonisolated struct AnalysisManualRecovery: Codable, Sendable {
    let reason: AnalyticsAnalysisFailureReason
    let failedStage: AnalyticsAnalysisStage
    let failedAt: Date
    /// Set when the user dismisses this specific occurrence. Optional with a
    /// default so existing on-disk checkpoints decode unchanged. Living on the
    /// occurrence means `saveQueued` and `markRequiresManualRetry` invalidate
    /// it for free.
    var dismissedAt: Date? = nil
}
```

Replace `persist()` and add the two operations:

```swift
    func dismiss(fileID: UUID, expectingFailedAt: Date) -> Bool {
        guard var checkpoint = checkpoints[fileID],
              var recovery = checkpoint.manualRecovery,
              recovery.failedAt == expectingFailedAt else { return false }

        let previous = checkpoints[fileID]
        recovery.dismissedAt = Date()
        checkpoint.manualRecovery = recovery
        checkpoints[fileID] = checkpoint

        guard persist() else {
            checkpoints[fileID] = previous          // never report a write that did not land
            return false
        }
        Log.analysis.info("🙈 Checkpoint: dismissed failure for \(checkpoint.audioFile.filename)")
        return true
    }

    func remove(fileID: UUID, expectingFailedAt: Date) -> Bool {
        guard let checkpoint = checkpoints[fileID],
              let recovery = checkpoint.manualRecovery,
              recovery.failedAt == expectingFailedAt else { return false }

        checkpoints.removeValue(forKey: fileID)
        guard persist() else {
            checkpoints[fileID] = checkpoint
            return false
        }
        Log.analysis.info("🗑️ Checkpoint: removed \(checkpoint.audioFile.filename)")
        return true
    }

    // MARK: Private

    /// Reports whether the write landed. Previously swallowed both failures,
    /// which is how a dismissal could appear to stick and then return on the
    /// next launch (ERR-013), and the same defect class as ERR-005.
    @discardableResult
    private func persist() -> Bool {
        let stringKeyed = Dictionary(
            uniqueKeysWithValues: checkpoints.map { ($0.key.uuidString, $0.value) }
        )
        do {
            let data = try JSONEncoder().encode(stringKeyed)
            try data.write(to: storeURL, options: .atomic)
            return true
        } catch {
            Log.analysis.error("❌ Checkpoint store write failed: \(error)")
            return false
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisDismissalTests`

Expected: PASS, 6 tests.

Then confirm nothing else broke:

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisCacheTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AnalysisProgressStore.swift IlumionateTests/AnalysisDismissalTests.swift
git commit -m "fix: persist failure dismissal on the occurrence (ERR-013)"
```

---

## Task 7: Attempt identity on the active analysis

**Files:**
- Modify: `Ilumionate/AnalysisStateManager.swift:1367-1396`
- Test: `IlumionateTests/AnalysisAttemptIdentityTests.swift`

`ActiveAnalysis` has no attempt identity. `ActiveAnalysisSnapshot.attemptID` needs a source, and Phase 2b's exactly-once terminalisation will need the same field. Adding it now keeps Phase 2 additive.

Note `ActiveAnalysis.==` deliberately excludes `startedAt` so elapsed time does not cause spurious UI diffs. `attemptID` is likewise excluded — it is constant for the lifetime of the instance, so comparing it adds nothing.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AnalysisAttemptIdentityTests.swift`:

```swift
//
//  AnalysisAttemptIdentityTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

private func makeAudioFile(id: UUID = UUID()) -> AudioFile {
    AudioFile(
        id: id,
        filename: "test_\(id.uuidString).m4a",
        duration: 300,
        fileSize: 1_024_000,
        createdDate: Date(timeIntervalSince1970: 0)
    )
}

@MainActor
struct AnalysisAttemptIdentityTests {

    @Test func eachActiveAnalysisGetsADistinctAttemptID() {
        let file = makeAudioFile()
        let first = ActiveAnalysis(audioFile: file, stage: .starting, progress: 0)
        let second = ActiveAnalysis(audioFile: file, stage: .starting, progress: 0)
        #expect(first.attemptID != second.attemptID)
    }

    @Test func attemptIDIsStableForTheLifetimeOfTheInstance() {
        let analysis = ActiveAnalysis(audioFile: makeAudioFile(), stage: .starting, progress: 0)
        let captured = analysis.attemptID
        analysis.stage = .transcribing
        analysis.progress = 0.5
        #expect(analysis.attemptID == captured)
    }

    @Test func snapshotCarriesAttemptID() {
        let analysis = ActiveAnalysis(audioFile: makeAudioFile(), stage: .transcribing, progress: 0.5)
        let snapshot = analysis.snapshot
        #expect(snapshot.attemptID == analysis.attemptID)
        #expect(snapshot.audioFileID == analysis.audioFile.id)
        #expect(snapshot.stage == .transcribing)
        #expect(snapshot.progress == 0.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisAttemptIdentityTests`

Expected: **build failure**, `value of type 'ActiveAnalysis' has no member 'attemptID'`.

- [ ] **Step 3: Write minimal implementation**

In `Ilumionate/AnalysisStateManager.swift`, add to `ActiveAnalysis` after `startedAt`:

```swift
    /// Identifies this attempt. Phase 2b uses it so a late result cannot
    /// overwrite a failure the watchdog already recorded; Phase 2c uses it to
    /// attribute a model download to the right attempt. Excluded from `==` for
    /// the same reason as `startedAt`: it never changes within an instance.
    let attemptID = UUID()

    /// Value snapshot for the Analysis Task Center projection.
    var snapshot: ActiveAnalysisSnapshot {
        ActiveAnalysisSnapshot(
            audioFileID: audioFile.id,
            attemptID: attemptID,
            stage: stage,
            progress: progress,
            startedAt: startedAt
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisAttemptIdentityTests`

Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AnalysisStateManager.swift IlumionateTests/AnalysisAttemptIdentityTests.swift
git commit -m "feat: give each analysis attempt a stable identity"
```

---

## Task 8: Input assembler

**Files:**
- Create: `Ilumionate/AnalysisCenter/AnalysisTaskInputAssembler.swift`
- Modify: `Ilumionate/AnalysisProgressStore.swift` (add `allCheckpoints()`)
- Test: `IlumionateTests/AnalysisTaskInputAssemblerTests.swift`

The assembler owns every disk and store read. It is the only place that knows `GeneratedSessionStore` cannot enumerate — each accessor takes an `AudioFile`, so ready sessions must be discovered by walking the library inventory.

Responsibilities the projection deliberately does not have: de-duplicating the queue, omitting sessions that fail to decode, and deriving `readyAt` from the session file's modification date.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AnalysisTaskInputAssemblerTests.swift`:

```swift
//
//  AnalysisTaskInputAssemblerTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

private func makeAudioFile(id: UUID = UUID()) -> AudioFile {
    AudioFile(
        id: id,
        filename: "test_\(id.uuidString).m4a",
        duration: 300,
        fileSize: 1_024_000,
        createdDate: Date(timeIntervalSince1970: 0)
    )
}

struct AnalysisTaskInputAssemblerTests {

    @Test func queueIsDeduplicatedPreservingFirstOccurrence() {
        let a = UUID(), b = UUID()
        #expect(AnalysisTaskInputAssembler.deduplicate(queue: [a, b, a, b]) == [a, b])
    }

    @Test func deduplicateLeavesAUniqueQueueUnchanged() {
        let a = UUID(), b = UUID()
        #expect(AnalysisTaskInputAssembler.deduplicate(queue: [a, b]) == [a, b])
    }

    @Test func failureSnapshotCarriesDismissalFromTheDurableRecovery() {
        let file = makeAudioFile()
        let dismissedAt = Date(timeIntervalSince1970: 200)
        let checkpoint = AnalysisCheckpoint(
            audioFile: file,
            transcription: nil,
            analysis: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 100),
            manualRecovery: AnalysisManualRecovery(
                reason: .transcription,
                failedStage: .transcription,
                failedAt: Date(timeIntervalSince1970: 100),
                dismissedAt: dismissedAt
            )
        )
        let snapshot = AnalysisTaskInputAssembler.failureSnapshot(from: checkpoint)
        #expect(snapshot?.dismissedAt == dismissedAt)
        #expect(snapshot?.retryState == .manual)
        #expect(snapshot?.failedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func checkpointWithoutManualRecoveryYieldsNoFailureSnapshot() {
        let checkpoint = AnalysisCheckpoint(
            audioFile: makeAudioFile(),
            transcription: nil,
            analysis: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 100)
        )
        #expect(AnalysisTaskInputAssembler.failureSnapshot(from: checkpoint) == nil)
    }

    @Test func checkpointSnapshotCarriesRecoveryStageAndRecency() {
        let checkpoint = AnalysisCheckpoint(
            audioFile: makeAudioFile(),
            transcription: nil,
            analysis: nil,
            startedAt: Date(timeIntervalSince1970: 0),
            lastUpdated: Date(timeIntervalSince1970: 100)
        )
        let snapshot = AnalysisTaskInputAssembler.checkpointSnapshot(from: checkpoint)
        #expect(snapshot.recoveryStage == AnalysisRecoveryStage.none)
        #expect(snapshot.lastUpdated == Date(timeIntervalSince1970: 100))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisTaskInputAssemblerTests`

Expected: **build failure**, `cannot find 'AnalysisTaskInputAssembler' in scope`.

- [ ] **Step 3: Write minimal implementation**

First add the combined accessor to `Ilumionate/AnalysisProgressStore.swift`, next to `allPending()`:

```swift
    /// Every checkpoint, pending and manual-recovery alike. `allPending()` and
    /// `manualRecoveryCheckpoints()` each filter one way; the task projection
    /// needs both.
    func allCheckpoints() -> [AnalysisCheckpoint] {
        Array(checkpoints.values)
    }
```

Create `Ilumionate/AnalysisCenter/AnalysisTaskInputAssembler.swift`:

```swift
//
//  AnalysisTaskInputAssembler.swift
//  Ilumionate
//
//  Every disk and store read for the task projection happens here. The
//  projection itself is pure and receives already-built maps.
//
//  GeneratedSessionStore cannot enumerate — each accessor takes an AudioFile —
//  so ready sessions are discovered by walking the library inventory.
//

import Foundation

nonisolated enum AnalysisTaskInputAssembler {

    // MARK: Pure helpers (unit-tested directly)

    /// Queue uniqueness is enforced here so the projection never has to guess.
    static func deduplicate(queue: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return queue.filter { seen.insert($0).inserted }
    }

    static func failureSnapshot(from checkpoint: AnalysisCheckpoint) -> AnalysisFailureSnapshot? {
        guard let recovery = checkpoint.manualRecovery else { return nil }
        return AnalysisFailureSnapshot(
            reason: recovery.reason,
            failedStage: recovery.failedStage,
            failedAt: recovery.failedAt,
            recoveryStage: checkpoint.recoveryStage,
            // A durable recovery exists precisely because automatic retry was
            // exhausted, so it is always `.manual`.
            retryState: .manual,
            dismissedAt: recovery.dismissedAt
        )
    }

    static func checkpointSnapshot(from checkpoint: AnalysisCheckpoint) -> AnalysisCheckpointSnapshot {
        AnalysisCheckpointSnapshot(
            recoveryStage: checkpoint.recoveryStage,
            startedAt: checkpoint.startedAt,
            lastUpdated: checkpoint.lastUpdated
        )
    }

    static func failureSnapshot(from failure: FailedAnalysis) -> AnalysisFailureSnapshot {
        AnalysisFailureSnapshot(
            reason: failure.reason,
            failedStage: failure.failedStage,
            failedAt: failure.failedAt,
            recoveryStage: failure.recoveryStage,
            retryState: failure.retryState,
            // The runtime list has no dismissal concept; only the durable
            // record carries it, and the merge prefers that on equal failedAt.
            dismissedAt: nil
        )
    }

    /// Ready sessions for the given inventory. A session that is missing or
    /// fails to decode is omitted, so a task never advertises something
    /// unplayable. `readyAt` is the session file's modification date, which
    /// survives relaunch and needs no new persistence format; a bundled gold
    /// session has no generated file, so it falls back to the import date.
    static func readySnapshots(
        for files: [AudioFile],
        store: GeneratedSessionStore
    ) -> [UUID: AnalysisReadySnapshot] {
        var result: [UUID: AnalysisReadySnapshot] = [:]
        for file in files {
            guard let session = store.load(for: file) else { continue }
            let url = store.sessionURL(forAudioFileID: file.id)
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path())[.modificationDate]) as? Date
            result[file.id] = AnalysisReadySnapshot(
                sessionID: session.id,
                readyAt: modified ?? file.createdDate
            )
        }
        return result
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisTaskInputAssemblerTests`

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AnalysisCenter/AnalysisTaskInputAssembler.swift Ilumionate/AnalysisProgressStore.swift IlumionateTests/AnalysisTaskInputAssemblerTests.swift
git commit -m "feat: assemble the analysis task projection input"
```

---

## Task 9: The refresh loop

**Files:**
- Create: `Ilumionate/AnalysisCenter/AnalysisRefreshCoordinator.swift`
- Test: `IlumionateTests/AnalysisRefreshCoordinatorTests.swift`

**This is the riskiest task in Phase 1.** There is no existing generation-guarded coalescing in this codebase to copy. Write the tests first and take them seriously.

The problem: structural refresh is asynchronous (disk reads, actor hops); progress refresh is synchronous and frequent. An in-flight structural read can finish *after* a newer progress tick and clobber it. Four rules prevent that — see the spec's "The refresh loop".

Extracting this as its own type keeps the concurrency logic testable without a view, and keeps it out of `AnalysisStateManager` (already 1,406 lines).

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AnalysisRefreshCoordinatorTests.swift`:

```swift
//
//  AnalysisRefreshCoordinatorTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct AnalysisRefreshCoordinatorTests {

    /// Rule 2: a burst of invalidations during an in-flight pass collapses into
    /// exactly one further pass, not one per invalidation.
    @Test func burstOfInvalidationsCoalescesIntoOneFurtherPass() async {
        var passes = 0
        let gate = AsyncGate()
        let coordinator = AnalysisRefreshCoordinator { 
            passes += 1
            await gate.wait()
            return 0
        }

        coordinator.invalidate()
        await Task.yield()
        for _ in 0..<10 { coordinator.invalidate() }
        await gate.open()
        await coordinator.drain()

        #expect(passes == 2)
    }

    /// Rule 3: a slow pass that started earlier must not commit over a newer one.
    @Test func staleGenerationIsDiscardedAtCommit() async {
        var committed: [Int] = []
        let coordinator = AnalysisRefreshCoordinator(
            load: { 0 },
            commit: { committed.append($0) }
        )
        coordinator.commitIfCurrent(value: 1, generation: 5)
        coordinator.commitIfCurrent(value: 2, generation: 3)   // older, must be dropped
        coordinator.commitIfCurrent(value: 3, generation: 6)

        #expect(committed == [1, 3])
    }

    @Test func invalidationBeforeFirstLoadIsNotLost() async {
        var passes = 0
        let coordinator = AnalysisRefreshCoordinator {
            passes += 1
            return 0
        }
        coordinator.invalidate()          // raised before any pass has started
        await coordinator.drain()
        #expect(passes >= 1)
    }

    @Test func drainReturnsOnlyWhenNoPassIsPending() async {
        var passes = 0
        let coordinator = AnalysisRefreshCoordinator {
            passes += 1
            return 0
        }
        coordinator.invalidate()
        await coordinator.drain()
        let settled = passes
        await coordinator.drain()
        #expect(passes == settled)
    }
}

/// Minimal one-shot gate so a test can hold a pass open deterministically,
/// without sleeping on wall-clock time.
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisRefreshCoordinatorTests`

Expected: **build failure**, `cannot find 'AnalysisRefreshCoordinator' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Ilumionate/AnalysisCenter/AnalysisRefreshCoordinator.swift`:

```swift
//
//  AnalysisRefreshCoordinator.swift
//  Ilumionate
//
//  Coalesces structural refreshes behind a generation guard.
//
//  Structural refresh is async (disk, actor hops); progress refresh is
//  synchronous and frequent. Without a guard, a slow structural read can commit
//  after a newer progress tick and rewind it. Generic over the loaded value so
//  the concurrency rules are testable without disk or SwiftUI.
//

import Foundation

@MainActor
final class AnalysisRefreshCoordinator<Value> {

    private let load: () async -> Value
    private let commit: (Value) -> Void

    private var generation = 0
    private var committedGeneration = -1
    private var isLoading = false
    private var isDirty = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(load: @escaping () async -> Value, commit: @escaping (Value) -> Void = { _ in }) {
        self.load = load
        self.commit = commit
    }

    /// Request a structural refresh. Safe to call from any mutation site; calls
    /// arriving during an in-flight pass set a dirty flag rather than starting
    /// a second pass, so importing forty files costs two passes, not forty.
    func invalidate() {
        guard !isLoading else {
            isDirty = true
            return
        }
        startPass()
    }

    /// Commit a loaded value only if no newer pass has already committed.
    func commitIfCurrent(value: Value, generation passGeneration: Int) {
        guard passGeneration > committedGeneration else { return }
        committedGeneration = passGeneration
        commit(value)
    }

    /// Resumes once no pass is in flight and nothing is pending. Test support;
    /// production code never needs to wait for a refresh.
    func drain() async {
        guard isLoading || isDirty else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    // MARK: Private

    private func startPass() {
        isLoading = true
        generation += 1
        let passGeneration = generation
        Task { @MainActor in
            let value = await load()
            commitIfCurrent(value: value, generation: passGeneration)
            isLoading = false
            if isDirty {
                isDirty = false
                startPass()
            } else {
                let waiters = drainWaiters
                drainWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisRefreshCoordinatorTests`

Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AnalysisCenter/AnalysisRefreshCoordinator.swift IlumionateTests/AnalysisRefreshCoordinatorTests.swift
git commit -m "feat: coalesce structural refreshes behind a generation guard"
```

---

## Task 10: The center model

**Files:**
- Create: `Ilumionate/AnalysisCenter/AnalysisCenterModel.swift`
- Test: `IlumionateTests/AnalysisCenterModelTests.swift`

Owns the input, publishes the snapshot, and routes the two refresh paths. Progress refresh replaces only `activeAnalysis` and `modelDownload` and **never touches disk**; structural refresh rebuilds everything else and merges the live progress fields at commit time so it cannot rewind them.

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AnalysisCenterModelTests.swift`:

```swift
//
//  AnalysisCenterModelTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

private func makeAudioFile(id: UUID = UUID()) -> AudioFile {
    AudioFile(
        id: id,
        filename: "test_\(id.uuidString).m4a",
        duration: 300,
        fileSize: 1_024_000,
        createdDate: Date(timeIntervalSince1970: 0)
    )
}

@MainActor
struct AnalysisCenterModelTests {

    @Test func snapshotIsNilBeforeFirstPublication() {
        let model = AnalysisCenterModel(loadStructure: { .empty })
        #expect(model.tasks == nil)
    }

    @Test func snapshotIsEmptyArrayAfterPublishingAnEmptyLibrary() async {
        let model = AnalysisCenterModel(loadStructure: { .empty })
        await model.refreshAndWait()
        #expect(model.tasks == [])
    }

    @Test func progressRefreshPerformsNoStructuralLoad() async {
        var loads = 0
        let file = makeAudioFile()
        let model = AnalysisCenterModel(loadStructure: {
            loads += 1
            return AnalysisStructuralInput(
                libraryFiles: [file], queue: [file.id], failures: [:], checkpoints: [:], ready: [:]
            )
        })
        await model.refreshAndWait()
        let afterFirstLoad = loads

        model.updateProgress(active: ActiveAnalysisSnapshot(
            audioFileID: file.id, attemptID: UUID(), stage: .transcribing,
            progress: 0.5, startedAt: Date(timeIntervalSince1970: 0)
        ), download: nil)

        #expect(loads == afterFirstLoad)
        #expect(model.tasks?.first?.state == .running(
            stage: .transcribing, progress: 0.5, startedAt: Date(timeIntervalSince1970: 0)
        ))
    }

    /// Rule 4: a structural commit must not rewind progress newer than the
    /// pass that produced it.
    @Test func structuralCommitPreservesNewerProgress() async {
        let file = makeAudioFile()
        let model = AnalysisCenterModel(loadStructure: {
            AnalysisStructuralInput(
                libraryFiles: [file], queue: [file.id], failures: [:], checkpoints: [:], ready: [:]
            )
        })
        await model.refreshAndWait()

        model.updateProgress(active: ActiveAnalysisSnapshot(
            audioFileID: file.id, attemptID: UUID(), stage: .analyzing,
            progress: 0.9, startedAt: Date(timeIntervalSince1970: 0)
        ), download: nil)

        await model.refreshAndWait()

        #expect(model.tasks?.first?.state == .running(
            stage: .analyzing, progress: 0.9, startedAt: Date(timeIntervalSince1970: 0)
        ))
    }

    @Test func pillCandidatesExcludeDismissedFailures() async {
        let dismissed = makeAudioFile()
        let queued = makeAudioFile()
        let model = AnalysisCenterModel(loadStructure: {
            AnalysisStructuralInput(
                libraryFiles: [dismissed, queued],
                queue: [queued.id],
                failures: [dismissed.id: AnalysisFailureSnapshot(
                    reason: .transcription, failedStage: .transcription,
                    failedAt: Date(timeIntervalSince1970: 100),
                    recoveryStage: .transcription, retryState: .manual,
                    dismissedAt: Date(timeIntervalSince1970: 200)
                )],
                checkpoints: [:], ready: [:]
            )
        })
        await model.refreshAndWait()
        #expect(model.pillCandidates.map(\.id) == [queued.id])
    }

    @Test func pillShowsActiveProgressAndAFailureSimultaneously() async {
        let failed = makeAudioFile()
        let running = makeAudioFile()
        let model = AnalysisCenterModel(loadStructure: {
            AnalysisStructuralInput(
                libraryFiles: [failed, running],
                queue: [],
                failures: [failed.id: AnalysisFailureSnapshot(
                    reason: .transcription, failedStage: .transcription,
                    failedAt: Date(timeIntervalSince1970: 100),
                    recoveryStage: .transcription, retryState: .manual, dismissedAt: nil
                )],
                checkpoints: [:], ready: [:]
            )
        })
        await model.refreshAndWait()
        model.updateProgress(active: ActiveAnalysisSnapshot(
            audioFileID: running.id, attemptID: UUID(), stage: .transcribing,
            progress: 0.3, startedAt: Date(timeIntervalSince1970: 0)
        ), download: nil)

        #expect(model.activeTask?.id == running.id)
        #expect(model.attentionCount == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisCenterModelTests`

Expected: **build failure**, `cannot find 'AnalysisCenterModel' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Ilumionate/AnalysisCenter/AnalysisCenterModel.swift`:

```swift
//
//  AnalysisCenterModel.swift
//  Ilumionate
//
//  Single owner of the published [AnalysisTask] snapshot. Created at the app
//  root and injected into every analysis surface; no surface builds its own.
//

import Foundation

/// The disk- and store-backed half of the projection input. The progress half
/// (`activeAnalysis`, `modelDownload`) is held separately so a progress tick
/// never triggers a disk read.
nonisolated struct AnalysisStructuralInput: Equatable, Sendable {
    let libraryFiles: [AudioFile]
    let queue: [UUID]
    let failures: [UUID: AnalysisFailureSnapshot]
    let checkpoints: [UUID: AnalysisCheckpointSnapshot]
    let ready: [UUID: AnalysisReadySnapshot]

    static let empty = AnalysisStructuralInput(
        libraryFiles: [], queue: [], failures: [:], checkpoints: [:], ready: [:]
    )
}

@MainActor
@Observable
final class AnalysisCenterModel {

    /// `nil` until the first publication, so surfaces can tell "still loading"
    /// from "nothing to show" and the pill does not flash an empty state.
    private(set) var tasks: [AnalysisTask]?

    private var structure: AnalysisStructuralInput = .empty
    private var activeAnalysis: ActiveAnalysisSnapshot?
    private var modelDownload: ModelDownloadProgress?

    private var coordinator: AnalysisRefreshCoordinator<AnalysisStructuralInput>!

    init(loadStructure: @escaping () async -> AnalysisStructuralInput) {
        // Observers are installed before any load starts, so an invalidation
        // racing bootstrap is recorded rather than lost.
        coordinator = AnalysisRefreshCoordinator(
            load: loadStructure,
            commit: { [weak self] structure in
                guard let self else { return }
                self.structure = structure
                // Merge the *live* progress fields, never the values captured
                // when the pass began.
                self.republish()
            }
        )
    }

    // MARK: Refresh

    func invalidateStructure() {
        coordinator.invalidate()
    }

    /// Test support: request a refresh and wait for it to settle.
    func refreshAndWait() async {
        coordinator.invalidate()
        await coordinator.drain()
    }

    /// High-frequency path. Never touches disk.
    func updateProgress(active: ActiveAnalysisSnapshot?, download: ModelDownloadProgress?) {
        activeAnalysis = active
        modelDownload = download
        republish()
    }

    private func republish() {
        tasks = AnalysisTaskProjection.tasks(from: AnalysisTaskProjectionInput(
            libraryFiles: structure.libraryFiles,
            activeAnalysis: activeAnalysis,
            modelDownload: modelDownload,
            queue: structure.queue,
            failures: structure.failures,
            checkpoints: structure.checkpoints,
            ready: structure.ready
        ))
    }

    // MARK: Selectors

    /// Everything the pill may represent: live work plus failures that need a
    /// decision. Dismissed failures are excluded.
    var pillCandidates: [AnalysisTask] {
        guard let tasks else { return [] }
        var positions: [UUID: Int] = [:]
        for (index, id) in structure.queue.enumerated() where positions[id] == nil {
            positions[id] = index + 1
        }
        return tasks.filter { task in
            switch task.state {
            case .preparing, .running, .queued:
                return true
            case .paused, .failed, .ready:
                return AnalysisTaskProjection.needsDecision(task, queuePositions: positions)
            }
        }
    }

    /// The pill's headline: live progress, because it is transient and
    /// self-resolving. A failure is a standing decision and gets the chip.
    var activeTask: AnalysisTask? {
        tasks?.first { task in
            switch task.state {
            case .preparing, .running: return true
            default: return false
            }
        }
    }

    var attentionCount: Int {
        guard let tasks else { return 0 }
        var positions: [UUID: Int] = [:]
        for (index, id) in structure.queue.enumerated() where positions[id] == nil {
            positions[id] = index + 1
        }
        return tasks.count { AnalysisTaskProjection.needsDecision($0, queuePositions: positions) }
    }

    func task(for audioFileID: UUID) -> AnalysisTask? {
        tasks?.first { $0.id == audioFileID }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/AnalysisCenterModelTests`

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AnalysisCenter/AnalysisCenterModel.swift IlumionateTests/AnalysisCenterModelTests.swift
git commit -m "feat: publish one analysis task snapshot from a single owner"
```

---

## Task 11: Wire the model to the pipeline

**Files:**
- Modify: `Ilumionate/AnalysisStateManager.swift`
- Modify: `Ilumionate/IlumionateApp.swift`
- Modify: `Ilumionate/ContentView.swift`

Connect the model to real data: one production `loadStructure`, one `invalidateStructure()` funnel called from every structural mutation, and progress forwarding.

- [ ] **Step 1: Add the production loader**

Add to `Ilumionate/AnalysisCenter/AnalysisCenterModel.swift`:

```swift
extension AnalysisCenterModel {

    /// Production wiring. Disk work happens inside `load`, off the main actor,
    /// via the store's own actor isolation and `AudioLibraryStore`'s async API.
    static func live(manager: AnalysisStateManager = .shared) -> AnalysisCenterModel {
        AnalysisCenterModel {
            let files = await AudioLibraryStore.loadRepairingStoredFiles()
            let (checkpoints, durableFailures) = await manager.recoverySnapshot()
            let runtimeFailures = await MainActor.run {
                Dictionary(
                    uniqueKeysWithValues: manager.failedAnalyses.map {
                        ($0.audioFile.id, AnalysisTaskInputAssembler.failureSnapshot(from: $0))
                    }
                )
            }
            let queue = await MainActor.run {
                AnalysisTaskInputAssembler.deduplicate(queue: manager.analysisQueue.map(\.id))
            }
            let ready = AnalysisTaskInputAssembler.readySnapshots(
                for: files, store: GeneratedSessionStore.shared
            )
            return AnalysisStructuralInput(
                libraryFiles: files,
                queue: queue,
                failures: AnalysisFailureMerge.merge(durable: durableFailures, runtime: runtimeFailures),
                checkpoints: checkpoints,
                ready: ready
            )
        }
    }
}
```

- [ ] **Step 2: Add the manager's snapshot accessor**

`AnalysisProgressStore` is a `private` actor on the manager, so the model must not reach into it. Add to `Ilumionate/AnalysisStateManager.swift`:

```swift
    /// Flattens the durable store into plain values for the task projection.
    /// Exists so `AnalysisCenterModel` never touches the private actor.
    func recoverySnapshot() async -> (
        checkpoints: [UUID: AnalysisCheckpointSnapshot],
        failures: [UUID: AnalysisFailureSnapshot]
    ) {
        let all = await progressStore.allCheckpoints()
        var checkpoints: [UUID: AnalysisCheckpointSnapshot] = [:]
        var failures: [UUID: AnalysisFailureSnapshot] = [:]
        for checkpoint in all {
            let id = checkpoint.audioFile.id
            checkpoints[id] = AnalysisTaskInputAssembler.checkpointSnapshot(from: checkpoint)
            if let failure = AnalysisTaskInputAssembler.failureSnapshot(from: checkpoint) {
                failures[id] = failure
            }
        }
        return (checkpoints, failures)
    }

    /// Called by every structural mutation. Set by the app root at launch.
    var onStructuralChange: (@MainActor () -> Void)?
```

- [ ] **Step 3: Call the funnel from every structural mutation**

In `Ilumionate/AnalysisStateManager.swift`, call `onStructuralChange?()` at the end of each of these, which is the complete set of structural triggers from the spec:

- `queueForAnalysis(_:priority:)` (both overloads)
- `removeFromQueue(audioFile:)`
- `moveUpInQueue(audioFile:)`, `moveDownInQueue(audioFile:)`, `prioritizeInQueue(audioFile:)`
- `clearQueue()`
- `cancelCurrentAnalysis()`, `cancelAllAnalyses()`
- `recordFailure(_:)`
- `retryFailedAnalysis(_:)`
- `restoreManualRecoveries()`
- `handleAnalysisComplete` (the success path that clears a checkpoint)
- `removeCompletedAnalysis(for:)`

Queue mutations matter as much as the rest: queue position is projection input, so a reorder that does not invalidate leaves every position stale.

- [ ] **Step 4: Own the model at the app root**

In `Ilumionate/IlumionateApp.swift`, create the single instance and inject it:

```swift
    @State private var analysisCenter = AnalysisCenterModel.live()
```

Pass it into the root view's environment:

```swift
            ContentView(engine: engine)
                .environment(analysisCenter)
                .task {
                    // Observers before bootstrap: an invalidation raised during
                    // the first load is recorded, not lost.
                    AnalysisStateManager.shared.onStructuralChange = { [analysisCenter] in
                        analysisCenter.invalidateStructure()
                    }
                    analysisCenter.invalidateStructure()
                }
```

In `Ilumionate/ContentView.swift`, forward progress on every change of the active analysis:

```swift
        .onChange(of: analysisManager.currentAnalysis?.snapshot) { _, snapshot in
            analysisCenter.updateProgress(active: snapshot, download: nil)
        }
```

`download:` is always `nil` in Phase 1 — nothing produces `ModelDownloadProgress` until Phase 2c.

- [ ] **Step 5: Verify the build and commit**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build`

Expected: `** BUILD SUCCEEDED **`

```bash
git add Ilumionate/AnalysisCenter Ilumionate/AnalysisStateManager.swift Ilumionate/IlumionateApp.swift Ilumionate/ContentView.swift
git commit -m "feat: wire the analysis center model to the pipeline"
```

---

## Task 12: The four surfaces

**Files:**
- Create: `Ilumionate/AnalysisCenter/AnalysisStatusPill.swift`
- Create: `Ilumionate/AnalysisCenter/AnalysisTaskRow.swift`
- Create: `Ilumionate/AnalysisCenter/AnalysisCenterView.swift`
- Create: `Ilumionate/AnalysisCenter/LibraryAnalysisEntryRow.swift`
- Modify: `Ilumionate/ContentView.swift:197-235`, `Ilumionate/LibraryView.swift:261`, `Ilumionate/SessionDetailView.swift:447-495`

Follow the existing Trance design system: `LiminalCard` / `GlassCard`, `TranceSpacing`, `TranceTypography`, `Color.roseGold`, `Color.textPrimary`, `Color.textSecondary`. Do not hardcode font sizes or padding.

- [ ] **Step 1: Build the pill**

Create `Ilumionate/AnalysisCenter/AnalysisStatusPill.swift`. The pill shows **live progress as the headline and a persistent attention chip** — both at once. This is the deliberate divergence from the tier order: applied literally, a `.manual` failure would take the headline and hide progress for as long as it existed, which reintroduces the defect being removed.

```swift
//
//  AnalysisStatusPill.swift
//  Ilumionate
//
//  Ambient analysis signal in the bottom chrome. Replaces AnalysisStatusOverlay
//  and AnalysisRecoveryStatusOverlay, which shared one slot and so could never
//  show active work and a failure at the same time.
//

import SwiftUI

struct AnalysisStatusPill: View {
    let activeTask: AnalysisTask?
    let queuedCount: Int
    let attentionCount: Int
    let onTap: () -> Void

    var body: some View {
        Button {
            TranceHaptics.shared.light()
            onTap()
        } label: {
            HStack(spacing: TranceSpacing.inner) {
                if let activeTask {
                    ProgressView().tint(.roseGold).controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeTask.audioFile.displayName)
                            .font(TranceTypography.caption).bold()
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(headlineDetail(for: activeTask))
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.roseGold)
                    Text("Analysis needs attention")
                        .font(TranceTypography.caption).bold()
                        .foregroundStyle(Color.textPrimary)
                }

                Spacer(minLength: TranceSpacing.inner)

                if queuedCount > 0 {
                    Text("+\(queuedCount)")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, TranceSpacing.micro)
                        .padding(.vertical, 2)
                        .background(Color.roseGold.opacity(0.8))
                        .clipShape(.capsule)
                }

                // The whole point of the rewrite: a failure stays visible while
                // other work runs.
                if attentionCount > 0 {
                    Label("\(attentionCount)", systemImage: "exclamationmark.circle.fill")
                        .font(TranceTypography.caption).bold()
                        .foregroundStyle(Color.roseDeep)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.horizontal, TranceSpacing.card)
            .padding(.vertical, TranceSpacing.inner)
            .background(.ultraThinMaterial)
            .background(Color.bgCard)
            .clipShape(.rect(cornerRadius: TranceRadius.tabItem))
            .overlay {
                RoundedRectangle(cornerRadius: TranceRadius.tabItem)
                    .strokeBorder(Color.roseGold.opacity(0.3), lineWidth: 1)
            }
            .padding(.horizontal, TranceSpacing.screen)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the analysis center")
    }

    private func headlineDetail(for task: AnalysisTask) -> String {
        switch task.state {
        case .preparing:
            return "Preparing analyzer"
        case .running(let stage, _, _):
            return AnalysisStageFeedback.stageSummary(stage)
        default:
            return ""
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let activeTask { parts.append("Analyzing \(activeTask.audioFile.displayName)") }
        if queuedCount > 0 { parts.append("\(queuedCount) queued") }
        if attentionCount > 0 { parts.append("\(attentionCount) need attention") }
        return parts.joined(separator: ", ")
    }
}
```

- [ ] **Step 2: Replace the overlays in ContentView**

In `Ilumionate/ContentView.swift`, replace the `Group` at `:202-217` (the `if let analysis … else if let failure …` block) with:

```swift
                Group {
                    if analysisCenter.activeTask != nil || analysisCenter.attentionCount > 0 {
                        AnalysisStatusPill(
                            activeTask: analysisCenter.activeTask,
                            queuedCount: analysisCenter.pillCandidates.count(where: {
                                if case .queued = $0.state { return true } else { return false }
                            }),
                            attentionCount: analysisCenter.attentionCount
                        ) {
                            showingAnalysisQueue = true
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
```

Add `@Environment(AnalysisCenterModel.self) private var analysisCenter` to `ContentView`.

- [ ] **Step 3: Build the row and the center**

Create `Ilumionate/AnalysisCenter/AnalysisTaskRow.swift` rendering one task for each of the six states, plus the actions each state allows:

- `.queued` — Remove from queue, Move to front
- `.preparing` / `.running` — Cancel
- `.paused` — Retry
- `.failed` — Retry (when `lastFailure.presentation.canRetry`), Dismiss, Remove
- `.ready` — Play

Use `task.lastFailure?.presentation` for all failure copy — `title`, `message`, `recoveryMessage`, `statusMessage` already exist on `AnalysisFailurePresentation` and are the stable user-facing strings.

**Remove is destructive and must be confirmed.** Present a `confirmationDialog` whose message says it deletes *saved analysis progress* — the transcript or analysis a retry would have resumed from — and that it does **not** delete the audio file. Pass `task.lastFailure!.failedAt` as `expectingFailedAt` so a confirmation raised for one occurrence cannot act on a newer one.

Create `Ilumionate/AnalysisCenter/AnalysisCenterView.swift` presenting `model.tasks` grouped by tier, with a `ProgressView` while `model.tasks == nil` and an idle card when it is `[]`. Keep the existing "Clear Queue" toolbar item and its confirmation dialog from `AnalyzerView.swift:48-62`.

Activity-oriented views show the three most recent `.ready` tasks; the center's full list shows all of them. Ageing out is a view filter, never a model deletion.

- [ ] **Step 4: Replace the Library section and Session Detail reads**

Create `Ilumionate/AnalysisCenter/LibraryAnalysisEntryRow.swift` — one row summarising counts from the shared snapshot (`"3 analyzing · 1 needs attention"`), opening the center on tap. In `Ilumionate/LibraryView.swift:261`, replace the `LibraryAnalysisStatusSection(...)` call with it.

In `Ilumionate/SessionDetailView.swift`, replace the manager reads in `analyzeNowSection`, `analyzingIndicator`, and `stageText(active:isThisFile:)` (`:447-495`) with a single lookup:

```swift
    private var task: AnalysisTask? {
        analysisCenter.task(for: audioFile.id)
    }
```

`analyzingIndicator` then switches on `task?.state` rather than comparing `AnalysisStateManager.shared.currentAnalysis?.audioFile.id` itself. Delete `stageText(active:isThisFile:)` — the task already answers "is this file active".

- [ ] **Step 5: Verify the build and commit**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build`

Expected: `** BUILD SUCCEEDED **`

Run the same for iOS Simulator:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

```bash
git add Ilumionate/AnalysisCenter Ilumionate/ContentView.swift Ilumionate/LibraryView.swift Ilumionate/SessionDetailView.swift
git commit -m "feat: render every analysis surface from the shared task snapshot"
```

---

## Task 13: Delete the legacy views

**Files:**
- Delete: `Ilumionate/AnalysisStatusBar.swift`, `Ilumionate/AnalysisStatusOverlay.swift`, `Ilumionate/LibraryAnalysisStatusSection.swift`
- Modify: `Ilumionate/AnalyzerView.swift`, `Ilumionate/AudioLibraryView.swift:264`, `Ilumionate/LibraryView.swift:193-195`

`AnalyzerView` is **not** deleted. Its Live Status and Ready Sessions sections are replaced by the center, but its third section `AnalyzerLibraryIntelligenceSection` is out of scope and has no other entry point. Leaving it reachable from one entry avoids orphaning a working feature; `task_34b6360c` relocates it to Library and deletes both together.

- [ ] **Step 1: Confirm nothing references the doomed files**

```bash
grep -rn "AnalysisStatusBar\|AnalysisStatusOverlay\|AnalysisRecoveryStatusOverlay\|LibraryAnalysisStatusSection" --include="*.swift" Ilumionate/ IlumionateTests/
```

Expected: only the three files' own definitions. If `ContentView.swift` still appears, Task 12 Step 2 is incomplete.

- [ ] **Step 2: Delete them**

```bash
git rm Ilumionate/AnalysisStatusBar.swift Ilumionate/AnalysisStatusOverlay.swift Ilumionate/LibraryAnalysisStatusSection.swift
```

- [ ] **Step 3: Repoint the sheet presentations**

In `Ilumionate/ContentView.swift:91-93`, `Ilumionate/LibraryView.swift:193-195`, and `Ilumionate/AudioLibraryView.swift:264`, present `AnalysisCenterView()` instead of `AnalyzerView(engine:)`. Add a single overflow entry inside `AnalysisCenterView` that pushes `AnalyzerView(engine:)` so Library Intelligence stays reachable.

Then strip `AnalyzerLiveStatusSection` and the `AnalysisReadySessionsCard` call from `AnalyzerView.swift`, leaving only `AnalyzerLibraryIntelligenceSection`. Delete the now-unused `AnalyzerActiveAnalysisContent`, the queue card, and the failure-log card.

- [ ] **Step 4: Verify the build and full suite**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build`

Expected: `** BUILD SUCCEEDED **`

Run: `Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests`

Expected: PASS. ERR-001 records six timing tests that are flaky under full-suite parallel load — if failures are confined to that set, they are pre-existing.

Run: `Scripts/run-tests.sh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IlumionateTests`

Expected: PASS.

- [ ] **Step 5: Update the records and commit**

Mark ERR-013 `completed` in `ERRORS.md`, move it to Resolved, and fill in the Resolution with what changed and how it was verified.

Update `plan.md`'s Audio Library section to note the Task Center replaced the scattered analysis surfaces.

```bash
git add -A
git commit -m "refactor: delete the superseded analysis status views"
```

---

## Self-review

**Spec coverage.** Every acceptance criterion maps to a task: (1) Task 2, (2) Task 10, (3) Task 4, (4) Task 4, (5) Task 5, (6) Task 5, (7) Tasks 4 and 5, (8) Task 4 attribute tests, (9) Tasks 5 and 12, (10) Tasks 10 and 12. Dismissal persistence is Task 6; refresh mechanics are Tasks 9 and 11; deletions are Task 13.

**Deliberately deferred within Phase 1.** `.preparing` is defined and projected but never produced — nothing constructs a `ModelDownloadProgress` until Phase 2c, and Task 11 Step 4 passes `download: nil` explicitly. The projection test covers it via a hand-built snapshot, which is the correct level.

**Known gap to watch.** Task 12 Steps 3 and 4 describe the row and center in prose rather than complete code, because the row's six states times four actions is largely mechanical composition against an existing design system. If the implementing agent needs literal code there, that step should be expanded before it starts rather than improvised — it is the one place in this plan where taste is being delegated.

**Riskiest task:** Task 9. There is no precedent for generation-guarded coalescing in this codebase, its four tests are the ones most likely to expose a design error, and every surface depends on it being right.

