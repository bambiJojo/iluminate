# Error Log

Running list of errors, bugs, and broken behavior found in this repository **and not fixed
at the time they were found** — discovered in passing, out of scope for the task at hand,
blocked, or deferred. An error fixed as part of the work that surfaced it does not belong
here; the fix and its commit are the record.

The test is whether something still needs attention, not whether a fix happened. Log it even
after fixing when any of these hold:

- The **symptom** was fixed but the **root cause** was not.
- The fix **could not be verified** — no coverage, or the original condition can't be reproduced.
- **One instance of a pattern** was fixed and the pattern plausibly exists elsewhere.

In those cases, state plainly in the entry what was fixed and what remains outstanding.

Each entry must carry enough context that a future session — or a different agent — can
pick it up cold and fix it without re-discovering anything.

**This file is append-and-update, never rewrite.** Add new entries at the top of Open
Issues. When an issue is fixed, move it to Resolved with the resolution filled in.

## Status values

| Status | Meaning |
|---|---|
| `identified` | Found and written up. Nobody is on it. |
| `working` | Actively being fixed right now. |
| `completed` | Fixed and verified. Moved to the Resolved section. |

## Entry template

Copy this block for every new error.

```markdown
### ERR-000 — Short title

- **Date discovered:** YYYY-MM-DD
- **Status:** identified
- **Severity:** critical | high | medium | low
- **Area:** e.g. light engine, analysis pipeline, playlist import, build

**Symptom**
What actually goes wrong, observed — error text, wrong output, crash, failing test name.

**Where**
`path/to/File.swift:123` — the specific call site(s) involved.

**Reproduction**
Exact steps or the exact command. Include the failing test filter if there is one.

**Root cause**
What is actually wrong, if known. Write "unknown — not yet investigated" rather than guessing.

**Already done** _(only if partly fixed when found)_
What was fixed at discovery time, and what is still outstanding — the unverified fix, the
untouched root cause, or the other instances of the pattern.

**Proposed fix**
The change that should resolve it, and anything it would touch.

**Risks / blockers**
Coupled behavior, missing decisions, or anything that makes this non-obvious.

**Resolution**
Filled in when status becomes `completed`: what was changed, and how it was verified.
```

---

## Open issues

### ERR-009 — Memory climbs past 500 MB during queued analysis

- **Date discovered:** 2026-08-11
- **Status:** identified
- **Severity:** medium
- **Area:** analysis pipeline, memory

**Symptom**
A device run reported `⚠️ High memory usage: 269MB` at launch and `🔥 CRITICAL memory usage:
565MB` a few seconds later, while WhisperKit was initialising and the analysis queue was
filling. The previous run peaked at 450 MB, so it is getting worse, not better.

The app's own pressure handling reacts (`🔥 Performing aggressive memory cleanup...`,
`🧹 Performing moderate memory cleanup...`) and the app survives, so this is a headroom
problem rather than a crash today. On a lower-memory device or with a longer queue it would
be a termination.

**Where**
Not attributed. Candidates, in rough order of size: the WhisperKit model
(`🔄 Initializing WhisperKit...` immediately precedes the 565 MB reading), the 108 entries of
`cachedResults` held by `AnalysisStateManager` (`📂 Loaded 108 cached analysis result(s)`),
and the audio library itself — every `AudioFile` carries its full transcript and
`AnalysisResult`, and `AudioLibraryStore.load` decodes all of them into memory on every call.

**Reproduction**
Run on device with a ~100-file analysed library and queue several files. Watch for the
`🔥 CRITICAL memory usage` line. Instruments' Allocations template would attribute it; the
log alone does not.

**The allocation rate is the sharper signal.** Three Allocations traces were attempted on
2026-08-11. Two crashed Instruments by growing past **30 GB**; the two that could be saved are
**10 GB** and **4.1 GB**. The 4.1 GB one covers **55.6 seconds**
(`allocationRun002.trace`, template `Allocations`, pid 14007) — about **74 MB of allocation
records per second**.

An Allocations trace records roughly one event per malloc/free, so that implies tens of
millions of allocation events in under a minute. The problem is therefore **churn**, not only
the 565 MB resident peak: something in the analysis path is allocating and freeing
continuously. A steady 565 MB of retained objects would produce a small trace.

**Root cause**
Unknown. The traces are too large to analyse on the machine that produced them — exporting
the 81 MB Time Profiler trace expanded it 2.3× to 189 MB and filled the disk, so exporting a
4.1 GB one is not viable at present.

Note the capture strategy is the obstacle, not the bug. Full Allocations recording is the
wrong instrument for a churn-heavy app: it records every event. Better options, cheapest
first:

1. **Memory Graph Debugger** (Xcode, Debug Navigator → capture) at the 565 MB peak. A
   point-in-time snapshot of what is *retained*, with object counts. No trace at all, and it
   answers "what is holding 565 MB" directly.
2. **Allocations with "Discard events for freed memory" enabled** — records only live
   allocations and drops the churn, shrinking the trace by orders of magnitude.
3. **Mark Generation** snapshots either side of one file's analysis, then diff — this
   attributes growth to a specific operation rather than to a whole session.
4. Failing all that, record a much shorter window: launch, let it settle, then start
   recording immediately before the suspect operation.

**Proposed fix**
Measure before changing anything. If the library decode is a material share, the fix pairs
naturally with ERR-005's note: keep `transcription` and `analysisResult` out of the in-memory
`AudioFile` and read them from the analysis cache file on demand, so the resident library is
metadata only.

**Risks / blockers**
`AudioLibraryStore.load()` is called from many places and returns a full `[AudioFile]`; making
the heavy fields lazy changes the shape of the type every consumer sees.

**Correction** _(2026-08-17)_
This entry was filed under "Resolved" with `Status: completed` while ending at "Proposed fix:
Measure before changing anything" and carrying no Resolution section. Nothing was fixed.
Status corrected to `identified` and the entry moved to Open issues. This is the second
mis-filed entry found this way, after ERR-013 — an entry with no Resolution section should
never be in Resolved.

**New sighting** _(2026-08-17)_ — the peak is now **higher**, not stable:

```
🔥 CRITICAL memory usage: 628MB
🔥 Performing aggressive memory cleanup...
🧹 Performing moderate memory cleanup...
```

628 MB against the 565 MB recorded above, on a device log during resumed analysis of a
`.wav` import. Two things changed since the original measurement that plausibly bear on it:
the library grew by 21 tracks via the Finder cable import, and `.wav` files are far larger
than the `.mp3`/`.m4a` the original sighting covered.

This matters more than the number suggests. `~/Library/Logs/CrashReporter/MobileDevice/`
contains `JetsamEvent` entries for this device, and an iOS app sitting at 628 MB is a
candidate for exactly that — the app would be killed mid-analysis with no crash report
attributable to app code, which is indistinguishable from the stall class ERR-001 and the
Analysis Task Center's Phase 2b watchdog are concerned with.

Still unmeasured. The instrument guidance above (Memory Graph Debugger at peak, rather than a
full Allocations trace) remains the cheapest next step.

---

## Resolved

### ERR-017 — Session Complete prints raw Swift source to the user

- **Date discovered:** 2026-08-16
- **Status:** completed
- **Severity:** high
- **Area:** player / session completion

**Symptom**
The completion overlay's duration line renders the literal text:

```
You completed (Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))).
```

instead of `You completed 12:30.` The backslash is missing from the string interpolation, so
the expression is inert string content, not code. It compiles cleanly because it is a valid
string literal.

**Where**
`Ilumionate/PlayerCompletionOverlay.swift:39`

**Reproduction**
Play any session to its natural end so `PlayerCompletionOverlay` is presented with
`duration > 0`. The line appears under the session title. No test covers the rendered text,
which is why it survived two commits (`0d54ef6`, `ef22342`).

**Root cause**
Missing `\` before `(` in the interpolation. Because `duration > 0` gates the line, an
`isSaved`/`canSave` code path is not involved — every completed session with a nonzero
duration shows it.

**Proposed fix**
Restore the interpolation:

```swift
Text("You completed \(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))).")
```

Add a unit test that asserts the formatted string rather than the view, so the format is
covered without a snapshot test.

**Risks / blockers**
None for the fix itself. Worth grepping for the same slip elsewhere — a `Text("...(` with a
`.formatted(` or `.count` inside and no preceding backslash is the signature. This entry is
one instance of a pattern that string-literal validation would not catch anywhere in the app.

**Resolution** _(2026-08-16)_
Fixed. The line is now built by `PlayerCompletionOverlay.durationSummary(for:)`, a
`nonisolated static func` extracted specifically so the rendered text is assertable without
a snapshot test — the original defect was invisible to the compiler and to every existing
test because a literal is valid Swift.

**The pattern does not exist elsewhere.** A repo-wide grep for a `Text("` literal containing
an unescaped `(` followed by a call returned exactly this one site, so the "other instances"
risk noted above is closed rather than outstanding.

Verified by `IlumionateTests/PlayerCompletionOverlayTests.swift` — four tests covering the
12:30 case, two-digit second padding, a sub-minute session, and a session past an hour
(`minuteSecond` keeps counting in minutes, so 3903s renders "65:03"). One test asserts the
absence of the literal `Duration.seconds` text, which is the specific failure mode.

---

### ERR-013 — Failed analyses can never be dismissed and are restored on every launch

- **Date discovered:** 2026-08-14
- **Status:** completed
- **Severity:** medium
- **Area:** analysis pipeline / UI

**Symptom**
Reported by the user as "when the app runs an analysis and fails, a notification gets stuck
and I can't clear it out — I have like 6 or 8 just sitting there even after quitting the
app." Failed analyses accumulate indefinitely with no user-facing way to remove one.

**Where**
- `Ilumionate/AnalysisStateManager.swift:76` — `failedAnalyses` array.
- `Ilumionate/AnalysisStateManager.swift:254` — `restoreManualRecoveries()` rebuilds the list
  from durable checkpoints on every launch, so entries survive app termination.
- `Ilumionate/AnalysisStateManager.swift:279` — `retryFailedAnalysis` removes an entry, but
  a failing retry re-adds it via `recordFailure` (`:283`).
- `Ilumionate/AnalysisStateManager.swift:680` — `handleAnalysisComplete` is the only other
  removal path, and it requires the analysis to succeed.
- `Ilumionate/AnalyzerView.swift:202` — the "Recent Failures" card offers only a Retry
  button, and none at all when `presentation.canRetry` is false (`:366`).
- `Ilumionate/AnalysisStatusOverlay.swift:108` and `Ilumionate/ContentView.swift:208` — the
  persistent bottom recovery banner, driven by `failedAnalyses.last`.

**Reproduction**
1. Import an audio file that cannot be analyzed (a corrupt/silent file yields the
   `invalidAudio` / `noAudioData` reasons, whose `retryState` is `.unavailable`).
2. Run analysis and let it fail.
3. The recovery banner appears above the tab bar; the Analyzer sheet lists the failure.
4. There is no swipe-to-delete, no clear-all, and for `.unavailable` failures no Retry
   button — the entry cannot be removed by any UI action.
5. Force-quit and relaunch: `restoreManualRecoveries()` restores it.

**Root cause**
No dismissal path was ever implemented. `AnalysisRetryState.unavailable` was designed for
failures that can never succeed on retry (`invalidAudio`, `noAudioData` — see
`Ilumionate/FailedAnalysis.swift:64`), yet the only exits from `failedAnalyses` are a
successful retry or a successful analysis. Those two conditions are unreachable for exactly
the failures that most need clearing, so a permanently-failing file pins its banner forever
and the entries stack up.

**Proposed fix**
Add an explicit dismiss action: a `dismissFailure(_:)` on `AnalysisStateManager` that removes
the entry from `failedAnalyses` *and* clears the underlying manual-recovery checkpoint from
`progressStore` (otherwise `restoreManualRecoveries()` resurrects it on next launch). Surface
it as swipe-to-delete on `AnalysisFailureRow` plus a "Clear All" in the failures card header,
and a dismiss control on `AnalysisRecoveryStatusOverlay`. Cover with unit tests asserting a
dismissed failure does not return after a simulated `restoreManualRecoveries()`.

**Risks / blockers**
Clearing the checkpoint discards saved transcript/analysis progress, so dismissing a
retryable failure throws away work that a later retry could have resumed from. Dismiss should
probably clear only the *surfaced failure* for retryable reasons while leaving the checkpoint
intact, and clear both for `.unavailable` reasons. That distinction needs a decision before
implementing.

**Correction** _(2026-08-16)_
Two errors in this entry, both found while designing the fix.

1. It was filed under "Resolved" with `Status: completed` while its own resolution line read
   "Not yet fixed". No `dismissFailure` exists anywhere in the code. Status corrected to
   `identified` and the entry moved to "Open issues", where it belongs. The Markdown anchor is
   generated from the heading text, so the move does not break existing links to it.
2. Reproduction step 5 is wrong for the failure it describes. `invalidAudio` / `noAudioData`
   yield `retryState == .unavailable`, and that path calls `progressStore.clear(for:)` at
   `AnalysisStateManager.swift:1305` *before* the failure is recorded.
   `restoreManualRecoveries()` rebuilds only from `manualRecoveryCheckpoints()`, which filters
   on `manualRecovery != nil`, so an `.unavailable` failure is **not** restored after relaunch.
   The entries that survive a relaunch are the `.manual` ones, which keep their checkpoint.
   The reported "6 or 8 sitting there after quitting" are therefore retryable failures, not
   unrecoverable ones — which changes the fix: dismissal must preserve the checkpoint so a
   later retry still resumes from the saved transcript.

**Resolution** _(2026-08-16, commit `5f7c7f2` and Phase 1 of the Analysis Task Center)_
Fixed. `dismissedAt` is now a field on `AnalysisManualRecovery`
(`AnalysisProgressStore.swift:58`), so dismissal is stored on the failure *occurrence*
rather than the file. Two existing code paths then invalidate it for free: `saveQueued`
already nils `manualRecovery` when a manual retry is queued (`:120-129`), and
`markRequiresManualRetry` builds a fresh recovery per failure (`:212`).

Two operations, both occurrence-guarded by `failedAt` so a confirmation raised for an old
row cannot act on a newer failure for the same file:

- `dismiss(fileID:expectingFailedAt:)` — persists `dismissedAt`, **leaves the checkpoint
  intact**, so a later retry still resumes from the saved transcript. This is what the
  original "Risks / blockers" note could not decide; preserving the checkpoint is correct
  because the entries that actually survive a relaunch are the retryable `.manual` ones.
- `remove(fileID:expectingFailedAt:)` — clears the recovery, the checkpoint, and the
  runtime `failedAnalyses` entry. Destructive, confirmed in the UI, and the confirmation
  names what it deletes (saved analysis progress) and what it does not (the audio file).

`AnalysisProgressStore.persist()` now returns `Bool` instead of swallowing encoding and
write errors, and both operations roll back their in-memory change when the write does not
land — otherwise a dismissal could appear to stick and return on the next launch, which is
the same defect class as ERR-005.

`.unavailable` failures have no checkpoint (that path clears it before the failure is
recorded), so `AnalysisStateManager.dismissFailure` removes them from `failedAnalyses`
directly and they stay gone; nothing durable ever referenced them.

Verified by `IlumionateTests/AnalysisDismissalTests.swift` — six tests including a dismissed
recovery round-tripping through a freshly constructed store, a stale `failedAt` failing to
dismiss a newer occurrence, and a retry after dismissal still finding the saved transcript.
Full suite green on both platforms: 1539 cases on macOS, 1540 on iOS Simulator, zero
failures.

The UI half is the Analysis Task Center
(`docs/superpowers/specs/2026-08-16-analysis-task-center-design.md`), which replaced the
"Recent Failures" card and the bottom recovery banner named in this entry.

---

### ERR-015 — Unreachable view files compiled into the app

- **Date discovered:** 2026-08-15
- **Status:** completed
- **Severity:** low
- **Area:** navigation / dead code

**Symptom**
Six `View` files are compiled into the `Ilumionate` target but have no presenter anywhere in
the app. They cannot be reached by any tap, swipe, sheet, cover, navigation destination or
deep link. They are carried in every build, and each is a maintenance surface that looks
live.

**Where**
No external reference (only the file's own declaration and `#Preview`):

- `Ilumionate/SessionGenerationView.swift:72` — "Session Designer"
- `Ilumionate/UISessionView.swift`
- `Ilumionate/AudioAnalyzerView.swift`
- `Ilumionate/LibraryFoldersView.swift:154` — "Folders"
- `Ilumionate/QueueManagementView.swift:42` — "Analysis Queue", superseded by
  `Ilumionate/AnalyzerView.swift:47`, which every live call site presents instead
  (`LibraryView.swift:184`, `AudioLibraryView.swift:268`, `ContentView.swift:93`)
- `Ilumionate/BrowseSessionsView.swift:56`, whose only remaining mentions are two
  comments in `Ilumionate/SessionCategory.swift:9-10` that describe it as the live "full-page
  browser". The comments are stale.

**Reproduction**
For each name, this returns only the declaring file and its own preview:

```bash
grep -rn "\bSessionGenerationView\b" --include='*.swift' . | grep -v '\.claude/worktrees'
```

**Root cause**
Unknown — not yet investigated. The shape is consistent with screens superseded during the
Home-doors / unified-Library rework (`QueueManagementView` → `AnalyzerView` is explicitly a
supersession) whose call sites were removed without removing the views.

**Note on target membership**
The project uses `PBXFileSystemSynchronizedRootGroup`, so absence from `project.pbxproj` is
*not* evidence a file is excluded — `ContentView.swift` and `HomeView.swift` are absent from
it too. Every file under `Ilumionate/` is compiled. Do not use a pbxproj grep to decide
whether one of these is in the build.

**Proposed fix**
Decide per file whether it is unfinished work or genuinely retired. Delete the retired ones
and fix the two stale `SessionCategory.swift` comments. For any kept as pending work, add a
comment saying so, so the next reader does not repeat this investigation.

**Partial cleanup** _(2026-08-16)_
Removed the unreachable `StreamingBrowserView` and its transitively dead settings screen,
manager, SoundCloud service, streaming models, artwork tile, analyzer, and importer. No live
Swift caller referenced that graph. The six views listed above remain open for an explicit
reconnect-or-retire decision.

**Risks / blockers**
`AudioAnalyzerView` pulls in analyzer types, so delete only the view rather than assuming its
dependencies are dead. `SessionGenerationView` references `SessionGenerator`, which is very
much live — the view is dead, the generator is not.

**Originally discovered while** tracing the full iOS navigation graph for the screen-atlas
deliverable.

---

### ERR-010 — 23 main-thread hangs in a 6-minute session, one lasting 13.3 seconds

- **Date discovered:** 2026-08-11
- **Status:** completed
- **Severity:** high
- **Area:** main thread / UI responsiveness

**Symptom**
A Time Profiler trace of a 348-second session on an iPhone 17 Pro Max (iOS 26.6) recorded 23
hangs, every one on the main thread:

| Type | Count | Worst |
|---|---|---|
| Severe Hang | 1 | **13.31 s** at 01:15.304 |
| Hang | 3 | 874 ms at 00:07.224 |
| Microhang (>250 ms) | 19 | 581 ms |

The severe hang alone freezes the UI for over thirteen seconds. The 874 ms one lands at
00:07, during launch.

Main-thread samples total 123,035 at 1 ms weight across a 348 s run, so the main thread was
executing roughly 35% of wall-clock time.

**Where**
Not attributed. See the root cause note — this is the open question.

Trace: `/Users/byronquine/Developer/instrumentRuns/run3.trace` (Time Profiler template,
process `Ilumionate` pid 12056, 2026-08-11T08:09:43+03:00).

**Reproduction**
Launch on device with a ~100-file analysed library and let the analysis queue run. The hangs
in this trace cluster around launch, WhisperKit initialisation and queue processing.

**Root cause**
Unknown. Attribution is blocked: `xcrun xctrace export` yields backtraces whose frames are
almost entirely unsymbolicated raw addresses (`0x1042e411d`). Only 521 distinct symbol names
resolved across the whole export, and those are disproportionately system libraries, so
ranking them describes what happened to symbolicate rather than what consumed the time.

An initial read of that ranking wrongly pointed at `AudioTitleNormalizer.tokens(in:)`.
Counting properly across all main-thread samples put it at **20 of 123,035 — 0.0%**. It is
not the cause. Recorded here because the same mistake is easy to repeat: the symbolicated
subset of this export is not a sample of the whole.

**Proposed fix**
Symbolicate before analysing. Open the trace in Instruments with the matching dSYM, or
re-export once the app's symbols resolve, and read the heaviest main-thread stacks in the
13.3 s window (75.304 s – 88.614 s on the trace clock). Only then decide what to change.

Two structural candidates worth checking against the symbolicated trace rather than assuming:
remaining synchronous `AudioLibraryStore.load()` calls still decode the entire library, and
WhisperKit initialisation coincides with the launch-time hang.

**Already done** _(2026-08-11)_
Two concrete main-thread hazards found by inspection were removed while this trace remained
unsymbolicated. `AudioIntake` now awaits the library's `@concurrent` duplicate-index builder,
and ERR-012 moved playlist dead-time PCM scanning through a `@concurrent` worker.
Both have direct off-main-thread coverage. Neither change attributes the original 13.3-second
window, so this issue remains open until that trace is symbolicated.

**Risks / blockers**
Needs the dSYM for the exact build that produced the trace. Without symbolication this is not
diagnosable from the export, only observable.

---

### ERR-008 — Chunked phase detection collapses to one phase and always falls back

- **Date discovered:** 2026-08-11
- **Status:** completed
- **Severity:** high
- **Area:** analysis pipeline

**Symptom**
Every file in a device run logged:

```
⚠️ ChunkedPhaseAnalyzer: 1 phase(s) detected — keyword fallback
```

Three for three, across transcripts of 3,265, 3,663 and 1,179 words. The phase timeline that
reached the light score came from keyword classification each time — 46, 43 and 8 segments —
not from the chunked analyzer.

`✅ AI Analysis completed` is still logged immediately afterwards, because the model *did*
classify content type and mood. Only the phase timeline fell back. Nothing distinguishes the
two in the log or the UI, so a session built on keyword phases is indistinguishable from one
built on model phases.

Now five for five across two runs, including `Sucked Stupid.m4a` and `Platinum Slut.exe.mp3`.

The light scores generated scored 87%, 81%, 98% and 96% alignment, with two logging
`⚠️ Light score alignment below target after 2 repair pass(es)`. Phase alignment was the
weakest component both times (`phase=72`, `phase=63`), which is consistent with a timeline
that did not come from the model.

**An observation worth chasing separately.** Alignment ran *inversely* to phase count: 43
segments scored 81% and 46 scored 87%, while 8 segments scored 96% and 98%. If the alignment
metric rewards a sparse timeline, it is not a good proxy for session quality and should not
be read as one — including in the paragraph above. Which way that causation runs is
unestablished.

**Where**
`Ilumionate/ChunkedPhaseAnalyzer.swift:144` — `distinctCount` counts *distinct* phases across
consolidated segments, and `:145` requires at least two before the result is used.

The collapse happens upstream of that guard, in some combination of `classifyChunks`,
`collapseShortRuns(_:minRun:)` at `:141` — whose `minRun` is `max(20, duration * 0.035)`, so
a 15-minute file demands runs of ~31 chunks before a phase survives — and
`enforcePhaseOrdering` at `:142`.

**Reproduction**
Analyse any hypnosis file of a few thousand words on device and watch for the warning. Not
yet reproduced in a unit test; `ChunkedPhaseAnalyzerTests` covers the helpers in isolation,
not the whole path against a realistic transcript.

**Root cause**
Unknown — not yet investigated. The distinguishing question is whether `classifyChunks`
returns a single phase for every chunk (a prompting or model problem) or returns varied
phases that `collapseShortRuns` then flattens (a threshold problem). The log does not say,
because the timeline is not logged before consolidation.

**Already done** _(2026-08-11, commit `7a77889`)_
The fallback log now reports the distinct phase count at three points — as classified, after
`collapseShortRuns`, and after consolidation — plus the computed `minRun` and the chunk count:

```
⚠️ ChunkedPhaseAnalyzer: 1 phase(s) — keyword fallback
   (classified 4, after collapse 1, minRun 31 of 210 chunks)
```

That distinguishes the two causes from a single device log. `classified 1` means the model
returns one phase per chunk — a prompting problem. `classified 4, after collapse 1` means
`minRun` is flattening a varied timeline — a threshold problem.

**Nothing is fixed yet.** The next device run will say which it is.

**Proposed fix**
Read the numbers above from a device run, then fix whichever cause they name. Separately,
record on the result that phases came from the fallback — the same treatment
`AIGenerationDiagnosis` now gives content analysis (ERR-006) — so a keyword timeline is
visible rather than silent.

**Risks / blockers**
`minRun` exists to stop a jittery timeline producing dozens of one-chunk phases; lowering it
without care trades this failure for that one. Any change wants a fixture built from a real
transcript, which the suite does not currently have.

**Correction to this entry** _(2026-08-16)_
This entry claimed six unreachable views, and one of them was wrong.
`Ilumionate/UISessionView.swift` declares a type named `SessionView`, not
`UISessionView` — the reachability check in the Reproduction section above searches by
*filename*, which finds nothing for it. `SessionView` is live: `PlayerBackgrounds.swift:119`
renders it as the player's entrainment background. Deleting that file on the strength of
this entry would have broken playback.

Anything re-running this check must search by **declared type name**, and must cover
secondary types in the file, not just the one matching the filename. `LibraryFoldersView.swift`
also declared `SmartFolder`, `FolderRow` and `FolderDetailView`; `QueueManagementView.swift`
declared `CurrentAnalysisRow` and `QueueFileRow`.

**Resolution** _(2026-08-16)_
The five genuinely unreachable views were deleted after a per-file reconnect-or-retire
decision. `SessionView` was kept — it was never dead.

Deleted, with the reason each was retired rather than reconnected:

- `QueueManagementView.swift` (309 lines) — superseded by `AnalyzerView`, which every live
  call site already presents.
- `AudioAnalyzerView.swift` (257) — superseded by the
  `AnalysisStateManager` → `AnalyzerView` → `SessionDetailView` path.
- `BrowseSessionsView.swift` (177) — near-duplicate of the live `SessionLibraryView`.
- `LibraryFoldersView.swift` (346) — the shelf model in `LibraryView` replaced folders.
- `SessionGenerationView.swift` (382) — manual generation tuning; generation stays automatic.

Support removed with them, each verified to have no other user:

- `Ilumionate/Folder.swift` — `Folder` and `FolderStore`, used only by `LibraryFoldersView`.
- `Ilumionate/SessionCategory.swift` — the `MindMachineModel.SessionCategory` enum plus
  `SessionCategoryBar` and `SessionCategoryChip`, used only by `BrowseSessionsView`.
- `LibrarySessionRow` in `LibraryView.swift` — used only by `LibraryFoldersView`.
- `MindMachineModel.sessionCategory` — declared and never read. Note the identically named
  `UnifiedPlayerViewModel.sessionCategory` is a *different*, private `String` used for
  analytics, and is live.

About 1,600 lines removed. Verified: no remaining references to any deleted type; iOS and
macOS builds succeed; 1478 tests pass on macOS; Library, which lost `LibrarySessionRow`,
renders correctly on the iPhone 17 Pro simulator.

---

### ERR-016 — Create's start bar renders its text on top of the control tray

- **Date discovered:** 2026-08-16
- **Status:** completed
- **Severity:** low
- **Area:** Create tab / layout

**Symptom**
On the Create tab, "Ready to begin", the summary line ("Spiral · Inward") and the
trailing percentage are drawn over the Strength and Duration tiles of the control tray.
Two runs of text occupy the same pixels and neither is legible. Reproduced on
iPhone 17 Pro simulator, iOS 26, Visuals segment, dark appearance.

**Where**
`Ilumionate/Create/CreateStartBar.swift:49-61` — the bar's background gradient.
`Ilumionate/Create/CreateView.swift:79` — where the bar is attached as a bottom
`safeAreaInset`.

**Reproduction**
1. Launch the app, open the Create tab.
2. Select the Visuals segment (the default).
3. Observe the region just above the "Begin Visuals" button.

**Root cause**
The bar's background is a gradient running `.clear` at location 0 → `bgPrimary.opacity(0.94)`
at 0.24 → opaque at 1, and it is pushed further up by `.padding(.top, -TranceSpacing.content)`.
`safeAreaInset` reserves scroll space for the bar's *layout* height, so the tray does not
scroll under the opaque part — but the bar's text sits inside the top quarter, which is
transparent by construction. Anything behind that band shows through the text.

The fade itself is deliberate; the mistake is placing text in the faded region rather than
below it.

**Proposed fix**
Move the fade above the content: either give the `HStack` its own opaque backing, or shift
the gradient stops so full opacity is reached before the first text baseline (make the
`.clear` → opaque ramp finish by ~0.1 and lengthen the negative top padding to keep the
same visual softness).

**Risks / blockers**
`TranceSpacing.tabBarClearance` is applied both inside `CreateStartBar` and on the
ScrollView content in `CreateView`, so changing the bar's height affects both; verify the
Flash, Colour and Bilateral segments too, since `summary` and `trailingValue` are longer
there and may wrap differently.

**Discovered while** auditing toolbar chrome for nested-container styling; unrelated to that
change, so nothing here was modified.

**Resolution** _(2026-08-16)_
`CreateStartBar`'s backing is now a fixed-height fade strip stacked above an opaque
`Color.bgPrimary`, rather than one gradient spanning the whole background with proportional
stops. The fade lives entirely in the region above the bar, so it always finishes before the
first text baseline no matter how tall the bar gets.

The proportional stops were the root cause: `location: 0.24` is 24% of a background whose
height includes `tabBarClearance` (100pt minimum, more with the mini-player showing). That
put full opacity roughly 60pt down while the first baseline sits about 32pt down, so the
text was inside the transparent ramp by construction — and it got worse whenever the
mini-player grew the clearance.

Verified on iPhone 17 Pro simulator, iOS 26, dark appearance: text legible on the Visuals
and Flash segments, which between them cover both branches of `summary`/`trailingValue`
(Colour and Bilateral share the Flash branch). Scrolled the tray to confirm all six tiles
and the Audio row still clear the bar, so `safeAreaInset` reservation is unaffected.

---

### ERR-014 — Failed analysis tasks persist and accumulate in the Dynamic Island

- **Date discovered:** 2026-08-14
- **Status:** completed
- **Severity:** medium
- **Area:** BackgroundTasks / continued-processing lifecycle

**Symptom**
After an analysis is interrupted, iOS displays an Ilumionate-owned "Analyzing audio — Task
failed" item in the Dynamic Island. Repeated interruptions can produce multiple independent
failed items that remain after the app is quit. A device screenshot on 2026-08-16 captured two
of these entries simultaneously with the Ilumionate app icon.

**Where**

- `Ilumionate/BackgroundAnalysisScheduler.swift` — continued-task submission, completion,
  expiration, and foreground restoration.
- `IlumionateTests/BackgroundAnalysisTests.swift` — task-lifecycle regressions.

**Reproduction**

1. Start an audio analysis, which submits a `BGContinuedProcessingTaskRequest` titled
   "Analyzing audio".
2. Background the app and allow the task to expire while a durable checkpoint remains.
3. The operation unwinds with incomplete work and completes the system task unsuccessfully.
4. Foreground restoration submits another uniquely identified continued task; repeating the
   interruption leaves multiple failed Live Activity entries.

**Root cause**

`BGContinuedProcessingTaskRequest` supplies its title, subtitle, progress, and app identity to
an iOS-managed Live Activity; it does not require an ActivityKit extension. The scheduler used
the queue's durable-work result directly as `setTaskCompleted(success:)`. When expiration left
a resumable checkpoint, that value was `false`, which explicitly asks iOS to present the task
as failed rather than dismissing it. The expiration and normal-unwind paths could also both run
completion-side effects. Finally, `resumeWhenForegrounded()` automatically submitted another
continued task with a new UUID even though foreground restoration was not a new user action.

**Fix**

- Added a one-shot task finisher so expiration and normal unwind cannot complete or recover the
  same background task twice.
- Continued-processing tasks now finish their system presentation cleanly after the app has
  either completed the work or safely preserved it for internal recovery. Domain failures
  remain visible in Ilumionate instead of becoming persistent system failure cards.
- Deferred `BGProcessingTask` work still reports unsuccessful completion when work remains, so
  its scheduler retry semantics are unchanged.
- Foreground restoration now uses deferred processing only and does not create a new continued
  Live Activity. A new one is submitted only for an explicit analysis or retry action.
- Added regressions for checkpointed expiration, one-shot completion, deferred failure
  signaling, and foreground restoration.

**Resolution**
Fixed 2026-08-16. The focused `BackgroundAnalysisTests` suite passes all 15 tests on an iOS 26
simulator.

---

### ERR-012 — Playlist dead-time pre-analysis runs on the main actor

- **Date discovered:** 2026-08-11
- **Status:** completed
- **Severity:** medium
- **Area:** playlist playback / concurrency

**Symptom**
Starting a playlist scanned up to 60 seconds from each end of every uncached
track on the main actor, creating a plausible source of the hangs in ERR-010.

**Where**
`PlaylistPlayerController.swift` — `preAnalyzeDeadTime()` started a
`Task(priority: .utility)` from a `@MainActor` type.

**Root cause**
An unstructured `Task` inherits its enclosing actor; priority does not change
isolation. With approachable concurrency enabled, changing the synchronous scan
to plain `nonisolated async` would still inherit the caller's actor as well.

**Resolution** _(2026-08-11)_
Added `PlaylistDeadTimeWorker.analyze`, a `@concurrent` wrapper around the
synchronous `AudioEnergyAnalyzer` scan. The playlist loop awaits only that scan;
its `audioFiles` mutation stays on the main actor, and the result is persisted
through `AudioLibraryStore.saveDeadTimeProfile`.

`PlaylistDeadTimeWorkerTests.analysisRunsOffTheMainThread` injects the scan
operation and directly records `Thread.isMainThread == false`; the playlist
library tests separately cover profile persistence. Both passed on macOS and in
the full iOS Simulator suite.

---

### ERR-011 — Readers remained bound to the retired `audioFiles` UserDefaults key

- **Date discovered:** 2026-08-11
- **Status:** completed
- **Severity:** medium
- **Area:** settings / data export / reset / playlist playback

**Symptom**
After the library migrated to `Application Support/AudioLibrary/library.json`,
three consumers still used the deleted `audioFiles` `UserDefaults` key:

1. Settings export always reported an empty audio library.
2. "Reset all data" removed the audio files but left `library.json` full of
   records pointing at those now-missing files.
3. Playlist playback resolved no items and skipped straight to the final item at
   0:00 / 0:00.

**Root cause**
The file-backed migration updated known readers, then deliberately cleared the
legacy key. These three direct readers were missed and treated the absent key as
an empty library.

**Resolution** _(2026-08-11)_
All three paths now go through `AudioLibraryStore`. Export awaits `allFiles`;
reset calls the new actor-serialized `deleteLibrary(storage:)`, deleting only the
injected library file and clearing the legacy key; playlist lookup awaits
`allFiles`, and its dead-time write-back uses `saveDeadTimeProfile`. The legacy
settings key remains reset-only and is documented as retired.

`AppSettingsManagerTests` verifies export without the legacy key and reset of a
library outside the injected Documents directory. Four
`PlaylistPlayerControllerLibraryTests` cover file-backed lookup, migration,
missing entries, and profile persistence. The focused suite and both full
platform suites pass.

---

### ERR-007 — The first analysis prompt always exceeds the context window

- **Date discovered:** 2026-08-11
- **Status:** completed
- **Severity:** high
- **Area:** analysis pipeline

**Symptom**
Every saturated transcript failed its first Foundation Models request at
4,765–4,864 tokens against a 4,096-token limit, then usually succeeded after a
second request with minimal instructions. Each file paid for one deterministic
failure before useful generation began.

**Root cause**
The original arithmetic was wrong twice: `chunkSize` counts characters, not
words, and the transcript string was not the dominant cost. Foundation Models'
tokenizer measured the complete saturated requests, including instructions,
schema, and wrappers, as:

| Request | Input tokens |
|---|---:|
| Detailed instructions + 600-character samples | 4,562 |
| Minimal instructions + 600-character samples | 3,408 |
| Minimal instructions + 120-character samples | **3,029** |

The `AIAnalysisResponse` schema alone costs 1,533 tokens and the detailed
instructions cost 1,368. The 7,502-character assembled prompt was only one
component, so a character-only ladder could not diagnose or reliably prevent
the overflow.

**Resolution** _(2026-08-11)_
Promoted the existing successful retry to the primary transcript request:
minimal instructions with 120 characters from each sampled transcript position.
User addenda are still included on the first attempt; if one causes a context
overflow, the retry drops it. A context overflow without an addendum is no
longer retried with the identical request.

`AnalysisPromptBudgetTests` now distinguishes the prompt-string guard from the
actual context calculation. On supported hosts it constructs a `Transcript`
with the real `AIAnalysisResponse` response format and asks Foundation Models to
count the complete request, pinning it below 3,300 input tokens. The measured
request is 3,029 tokens locally, and the focused and full platform suites pass.

The tradeoff is explicit: ordinary transcript classification no longer sees the
detailed few-shot system prompt. In every captured device run it never did—the
detailed request failed before generation—so the delivered classification path
is unchanged while the wasted round-trip is removed.

---

### ERR-003 — Files-picker duplicate check cannot use the duration signals

- **Date discovered:** 2026-08-11
- **Status:** completed
- **Severity:** low
- **Area:** audio import

**Symptom**
`AudioImportWorker.prepareAudioFile` builds its `DuplicateAudioCandidate` with a hardcoded
`duration: 0`. Both duration-based signals in `DuplicateAudioIndex` — `.sizeAndDuration`
(±1s) and `.titleAndDuration` (±2s) — therefore only ever fire against a library entry whose
duration is under about two seconds. In practice they are dead in this code path.

**Where**
`Ilumionate/AudioImportWorker.swift:47` — the `duration: 0` argument.
Signals defined at `Ilumionate/LibraryDedupe/DuplicateAudioIndex.swift:41` and `:49`.

**Reproduction**
Import a file from the Files picker that is byte-identical in size and duration to a library
entry but has a different name and an unreadable fingerprint. Expect `.likely`; get
`.distinct`.

**Root cause**
The source file's duration is not known before the copy — reading it means loading an
`AVURLAsset`, which the import path deliberately defers until after the transfer
(`loadDuration` at `AudioImportWorker.swift:96`, behind a timeout). Passing 0 was the
expedient choice.

**Already done**
Nothing is broken today: the call site acts only on `.identical`
(`AudioImportWorker.swift:55`), and that verdict comes from the SHA-256 fingerprint, which
is computed correctly from the source. The exact-duplicate case this feature exists to
catch is fully covered. What is outstanding is that the code reads as though it performs
four checks when it performs one, so anyone later extending this path to honour `.likely`
will find it silently inert.

**Proposed fix**
Either load the source duration before the verdict (accepting the AVFoundation cost on the
import path, and noting the Catalyst `com.apple.audioanalyticsd` precondition documented at
`PlaylistTrackDownloader.swift:157`), or make the omission explicit by having the candidate
take an optional duration and having `DuplicateAudioIndex` skip the duration signals when it
is absent. The second is cheaper and removes the trap.

**Risks / blockers**
None significant. The second option touches `DuplicateAudioCandidate`'s initialiser, which
has three call sites.

**Resolution** _(2026-08-11, commit `7a77889`)_
`DuplicateAudioCandidate.duration` is now `TimeInterval?`, and `DuplicateAudioIndex.verdict`
returns `.distinct` before the two duration-corroborated signals when it is absent — the
second option from the proposal, taken because loading an `AVURLAsset` on the import path is
the cost that path deliberately defers.

`AudioImportWorker` passes `nil` with a comment saying why. Behaviour is unchanged, which was
the point: the call site only ever acted on `.identical`, which comes from the fingerprint.
What is gone is the trap — the code no longer reads as though four checks run where one does.

Covered by two tests in `DuplicateAudioIndexTests`: an unknown duration skips the signals that
need one, and still resolves an exact fingerprint match.

---

### ERR-004 — `AudioFile.==` ignores content fingerprint and remote provenance

- **Date discovered:** 2026-08-11
- **Status:** completed
- **Severity:** low
- **Area:** models, playlist import

**Symptom**
Two `AudioFile` values holding different audio compare equal, provided their id, filename,
ratings, tags, metadata and play history match. `contentFingerprint` and `remoteSource` are
both absent from the equality implementation.

**Where**
`Ilumionate/AudioFile.swift:139` — the hand-written `==`.
First consumer that can be misled: `PlaylistTrackDownloadOutcome` in
`Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift:11`, which is `Equatable` and wraps
an `AudioFile` in its `.saved` case.

**Reproduction**
No failing test today. Construct two `AudioFile` values that differ only in
`contentFingerprint`, wrap each in `PlaylistTrackDownloadOutcome.saved`, and compare — they
compare equal.

**Root cause**
The custom `==` predates content fingerprinting and lists fields explicitly. It was never
revisited when `contentFingerprint` was added, and `remoteSource` (added 2026-08-11 in
commit `6895041`) followed the same omission for consistency with the existing shape.

**Already done**
Nothing. Noticed while adding `remoteSource`; deliberately left alone rather than widened
mid-feature, because the identity semantics of `==` are used in view diffing and changing
them is not a local decision.

**Proposed fix**
Decide what `==` means for this type first. Either (a) narrow it to `lhs.id == rhs.id`,
matching `hash(into:)` at `AudioFile.swift:157` which already combines only `id` — the
current pair arguably violates the Hashable contract's spirit; or (b) add the two identity
fields to the existing list. Option (a) is the smaller, more defensible surface.

**Risks / blockers**
`==` is consumed by SwiftUI diffing wherever `AudioFile` appears in a `ForEach` or as
`Equatable` view state. Narrowing it to id-only would stop views refreshing when a file's
rating or title changes in place. Audit those call sites before changing.

**Resolution** _(2026-08-11, commit `7a77889`)_
`contentFingerprint` and `remoteSource` joined the field list in `AudioFile.swift:154`.

Option (a) from the proposal — narrowing to `id` only — was **rejected** after checking the
consumers named under Risks. SwiftUI diffs on this type, so identity-only equality would stop
a row refreshing when its rating or title changed in place. The field list stays; it simply
now includes the two fields that say *which audio this is*.

Covered by `AudioFileIdentityEqualityTests` in
`IlumionateTests/RemoteAudioSourceTests.swift`: values differing only in fingerprint, and only
in provenance, are unequal; an unchanged copy is equal; and an in-place edit still reports a
change, which pins the reason the narrowing was rejected.

---

### ERR-001 — Six timing tests fail under full-suite parallel load

- **Date discovered:** 2026-08-11
- **Status:** completed
- **Severity:** medium
- **Area:** test suite

**Symptom**
Running the whole `IlumionateTests` suite fails, with four to six tests failing per run. The
failing set is **not stable between runs**. Observed members across four runs:

- `PlayerControlsVisibilityTests/closingDrawerReArmsTimer()`
- `PlayerControlsVisibilityTests/interactionPostponesHide()`
- `PlayerControlsVisibilityTests/idleTimerHides()`
- `GeneratedSessionStoreTests/corruptSessionIsNotReportedAsReady()`
- `AudioImportWorkerTests/slowFileTransferDoesNotBlockMainActor()`
- `AudioLibraryStoreTests/savingLargeLibraryDoesNotBlockMainActor()`
- `StagedAnalysisPipelineTests/keepsWhisperPrefetchOutOfContentAnalysis()`

**Correction to the original write-up.** Two claims here were wrong. The per-test seconds
reported by `xcodebuild` are cumulative from the start of the run, not per test, so "36–59
seconds" said nothing about how long any test took. And "the same tests pass in isolation"
was verified for exactly one of them and generalised to all six —
`corruptSessionIsNotReportedAsReady` fails in isolation too, in 0.08 seconds.

**Where**
`IlumionateTests/PlayerControlsVisibilityTests.swift`,
`IlumionateTests/GeneratedSessionStoreTests.swift`,
`IlumionateTests/AudioImportWorkerTests.swift:12`,
`IlumionateTests/AudioLibraryStoreTests.swift`,
`IlumionateTests/StagedAnalysisPipelineTests.swift`.

**Reproduction**
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```
Then run any one of the named structs on its own and watch it pass in well under a second.

**Root cause**
Unknown — not yet investigated. The shape of it is consistent: every affected test asserts on
elapsed time or on work not blocking the main actor, and Swift Testing runs structs in
parallel. Under that contention the main actor is genuinely saturated, so the assertions
describe the machine's load rather than the code under test.

**Already done**
Nothing fixed. Confirmed **pre-existing** and unrelated to the duplicate-detection work:
the suite was run at commit `4d80e62` with the in-flight changes stashed, and failed with an
overlapping-but-different set (`slowFileTransfer…`, `corruptSession…`,
`closingDrawerReArmsTimer`, `idleTimerHides`). Recorded here so the next person does not
re-derive that.

**Proposed fix**
Investigate whether these can be made load-independent — injecting a clock and advancing it
rather than sleeping, per the determinism approach already used elsewhere in the suite —
or serialised with `.serialized` on the affected suites if genuine wall-clock behaviour is
what is under test.

**Risks / blockers**
Until this is resolved, a full-suite run cannot answer "did my change break something?"
without a stashed baseline comparison for contrast. That makes every future change more
expensive to verify and is the real cost of leaving it.

**Resolution** _(2026-08-11, commit `c6a8d49`)_
The result bundle — `xcrun xcresulttool get test-results tests` — gave the actual messages the
console had omitted, and they showed **two unrelated causes**.

*Main-actor starvation (five tests).* Not mild contention: the heartbeat in
`savingLargeLibraryDoesNotBlockMainActor` was delayed **43.9 seconds** against a 150 ms limit,
and `slowFileTransferDoesNotBlockMainActor` recorded **22.4 seconds** against 250 ms. Dozens
of `@MainActor` test suites run in parallel and all queue on the one main actor, so any test
measuring main-actor responsiveness was measuring the machine.

- `PlayerControlsVisibility` gained an injectable `idleWait` and `awaitPendingAutoHide()`.
  The three timer tests now use no clock: two release the countdown immediately, and
  `interactionPostponesHide` drives a gate the test opens itself.
- The import test asserts the property directly — the transfer runs off the main thread —
  instead of timing how quickly the main actor notices.
- `StagedAnalysisProbe` gained `waitForActiveAnalysis()`, replacing a poll against a
  15-second deadline with a continuation. It now waits as long as the machine needs and would
  hang visibly if the pipeline never got there, rather than failing an arbitrary timeout.
- `savingLargeLibraryDoesNotBlockMainActor` was **deleted**. Its property is structural now —
  `AudioLibraryPersistence` is a non-main actor and `save` is `async`, so the encode cannot
  run on the main actor — and the functional half is covered deterministically by
  `AudioLibraryStorageTests.oversizedLibraryRoundTrips`.

*A stale test (one test).* `corruptSessionIsNotReportedAsReady` was never flaky. Commit
`86e37db` ("perf: stop the Library shelves decoding a session per audio file") deliberately
made `exists(for:)` stop decoding, so a present-but-corrupt score reports `true` — documented
on the method: badging a row optimistically beats stalling the list. The test asserted the
old behaviour and had been failing ever since. Renamed to
`corruptSessionIsBadgedButNeverLoaded` and rewritten to the documented intent, keeping the
assertion that matters: `load(for:)` returns nil, so nothing broken reaches playback.

Verified by three consecutive full-suite runs on macOS with no failures, and 1471 test cases
passing on iOS Simulator.

**Outstanding.** One deliberate coverage loss, recorded rather than hidden: nothing now
asserts that saving a large library keeps the main actor free. That property rests on
`AudioLibraryPersistence` remaining a non-main actor. Making it `@MainActor` would reintroduce
the original bug and no test would object.

**New sighting** _(2026-08-16, status `identified`)_ — a **seventh** test shows the same
behaviour and is not in the list above:

- `StagedAnalysisPipelineTests/automaticallyRetriesOnceWithoutRepeatingTranscription()`

Observed once during the Analysis Task Center Phase 1 verification: a full-suite iOS
Simulator run aborted after **47 of ~1544 cases** with this test reported failed. The same
commit passed the full macOS suite (1543 cases, zero failures), the suite passed in isolation
on iOS in 0.111s, and an immediate re-run of the full iOS suite passed all 1544 with zero
failures. So it is load-dependent rather than a logic fault, and it is a sibling of
`keepsWhisperPrefetchOutOfContentAnalysis()` in the same suite, which is already listed.

Two things make this worth its own note rather than a silent addition to the list. It
**aborts the whole run** rather than failing alone, so one flake costs all remaining
coverage on that platform — worse than the original six. And the reported "60.000 seconds"
must not be read as a duration: per the correction above, `xcodebuild`'s per-test seconds are
cumulative from the start of the run.

Not investigated. Anyone touching `StagedAnalysisPipelineTests` should treat a full-iOS-suite
failure here as suspect until reproduced twice.

---

### ERR-002 — Function-level `-only-testing` filters run zero tests and report success

- **Date discovered:** 2026-08-11
- **Status:** completed
- **Severity:** high
- **Area:** build / test tooling

**Symptom**
`xcodebuild test` with a filter naming an individual Swift Testing function runs **no tests
at all** and prints `** TEST SUCCEEDED **`. There is no warning that the filter matched
nothing. A red test looks green.

This was hit twice during the duplicate-detection work. In one case a test written to fail
first — `savedDownloadCarriesIdentity`, before its implementation existed — reported
`** TEST SUCCEEDED **`, which would have been accepted as a passing TDD step had the result
not been obviously impossible.

**Where**
Not repository code. The interaction is between `xcodebuild`'s `-only-testing:` filter and
Swift Testing's `@Test` functions. Affects every verification command in
`docs/superpowers/plans/2026-08-10-audio-duplicate-detection.md`, which uses function-level
filters in several steps, and the same pattern in `CLAUDE.md`'s test section.

**Reproduction**
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
  -destination 'platform=macOS,arch=arm64' test \
  -only-testing:IlumionateTests/AudioTitleNormalizerTests/emptyNameNormalizesToEmpty
```
Prints `** TEST SUCCEEDED **` with no `Test case '…' passed` line. Dropping the trailing
function name runs the five tests in the struct and reports honestly.

**Root cause**
A Swift Testing identifier ends in `()`; an XCTest method name does not. `-only-testing`
matches the identifier literally, so the form without parentheses selects nothing — and
`xcodebuild` treats an empty test set as a successful run rather than an error.

Measured directly, counting `^Test case ` lines:

| Filter | Test cases run |
|---|---|
| `…/AudioTitleNormalizerTests/emptyNameNormalizesToEmpty` | **0**, exits 0 |
| `…/AudioTitleNormalizerTests/emptyNameNormalizesToEmpty()` | 1, exits 0 |

**Proposed fix**
Short term, and already the working practice: filter at struct level only, never at function
level, and confirm the expected `Test case '…' passed` lines appear rather than trusting the
summary banner. Longer term, check whether `swift test --filter` or the `TEST_RUNNER_`
environment resolves individual `@Test` names, and correct the filters quoted in `CLAUDE.md`
and the plan document.

**Risks / blockers**
The danger is silent: any agent or engineer verifying a single test this way gets a false
green. Worth fixing in the documented commands before it costs someone a real bug.

**Resolution** _(2026-08-11, commit `8f5c941`)_
`Scripts/run-tests.sh` wraps `xcodebuild test`, passes every argument through, and fails when
`xcodebuild` reports success having run zero test cases — printing the likely cause and the
correct identifier form. Verified against all three cases: the filter without `()` now exits
1, the same filter with `()` exits 0 having run the test, and a suite-level filter exits 0
having run ten.

`CLAUDE.md` gained a "Running a subset of tests" section stating the identifier rule and
pointing at the wrapper. The three function-level filters in
`docs/superpowers/plans/2026-08-10-audio-duplicate-detection.md` were corrected. The filter
quoted in the Reproduction above is deliberately left without `()` — it documents the broken
form.

**Outstanding.** The wrapper is opt-in: a bare `xcodebuild test` invocation still reports a
false green, and nothing enforces its use. Wiring it into a pre-commit or CI step would close
that, and is worth doing if this repository gains CI.

---

### ERR-006 — Foundation Models blocked by Game Mode; every analysis silently degrades

- **Date discovered:** 2026-08-11
- **Status:** completed
- **Severity:** medium
- **Area:** analysis pipeline

**Symptom**
On a device run, **every** AI content analysis failed and fell back to keyword extraction —
six for six. The underlying error each time:

```
Failed model manager query for model com.apple.fm.language.instruct_300m.safety:
Not executed due to current system state ["StandardGameMode"], try again later
```

The pipeline retries once with a minimal prompt, fails the same way, then logs
`❌ AI generation gave up (other) — using keyword fallback`. The resulting sessions are
keyword-quality: `Yes Brain Loop.mp3` produced 3 phase segments, `C-U-M.mp3` produced 1.

**Correction to the original write-up:** it was claimed here that nothing surfaced this.
That was wrong — `SessionDetailView.swift:436` already labelled such results "Keyword
Analysis" rather than "AI Analyzed". What was missing was the *reason*:
`AIGenerationDiagnosis.Kind.userFacingReason` existed but had no callers outside tests.

**Where**
`Ilumionate/AIContentAnalyzer.swift` / `Ilumionate/AIAnalysisManager*.swift` — the retry and
fallback path that emits `⚠️ AI attempt 1 failed (other)` and `↻ Retrying with minimal prompt`.

**Reproduction**
Run analysis on device while the system reports `StandardGameMode`. Not reproducible in the
simulator or on macOS.

**Root cause**
Not the app's code. iOS declines to run the on-device safety model
(`com.apple.fm.language.instruct_300m.safety`) while the system is in that state, and
`FoundationModels` surfaces it as a generic `GenerationError Code=-1`. The graceful fallback
is working as designed; what is missing is any signal that it happened.

**Proposed fix**
Two parts, both small. First, record on `AnalysisResult` whether the language model or the
keyword fallback produced it, and show that in the analysis detail so a keyword-only session
is identifiable after the fact. Second, treat this specific error as retryable-later rather
than terminal — it is a transient system state, unlike a genuine model failure — and offer
re-analysis once the device leaves that state.

**Risks / blockers**
Detecting the state reliably means string-matching `"StandardGameMode"` inside a nested
`NSMultipleUnderlyingErrorsKey` chain, which is fragile across OS versions. Prefer keying the
retry decision on the outer `Code=1013` from `ModelManagerServices.ModelManagerError`.

**Resolution** _(2026-08-11, commit `94589d3`)_
The real defect was a misclassification, not just a missing message.

`classify` checked for a safety-host failure **only inside** a `guardrailViolation`. Foundation
Models reports the same underlying failure a second way — a bare bridged `NSError` chain with
no Swift case name, which is the form the device produced — so it fell through to `.other`.
`.other` is retryable, so every one of the six failures paid for a second full round-trip
that could not succeed. The `↻ Retrying with minimal prompt` line in the log is that waste.

- The busy-system and safety-host checks now run first, independently of the guardrail branch.
- New `Kind.systemBusy`, matched on `ModelManagerError Code=1013` and on the
  `"Not executed due to current system state"` phrasing, since the numeric code is
  undocumented and may not be the only one used.
- New `Kind.isTransient`, distinct from `isRetryable`: the first asks whether a second
  *immediate* attempt with a shorter prompt is worth it, the second whether the same file
  would succeed later untouched. Only `.systemBusy` is transient.
- `fetchAIResponse` returns `AIResponseOutcome` rather than `AIAnalysisResponse?`, so the
  diagnosis reaches `makeKeywordFallbackResult` instead of being logged and dropped.
- `AnalysisResult.keywordFallbackReason` recovers it, and the detail screen renders it under
  the badge. `usedKeywordFallback` moved from equality to prefix matching so results stored
  before this still read as fallbacks.

Verified by `IlumionateTests/AIGenerationDiagnosisTests.swift`, including the device error
text captured verbatim from the 2026-08-11 log, and the two policy tests that pin which kinds
are retryable and which are transient. Green on macOS and iOS Simulator.

**Outstanding.** Two things this does not do. Nothing automatically re-analyses a file that
failed transiently — the user is told it is worth doing and must start it. And the string
matching is inherently fragile: if Apple rewords the message or changes the code, this
degrades to `.other` again, which is the safe direction but silent. A test would not catch
that; only another device log would.

---

### ERR-005 — Audio library exceeds the 4 MiB UserDefaults limit; writes are silently dropped

- **Date discovered:** 2026-08-11
- **Status:** completed
- **Severity:** critical
- **Area:** persistence, audio library

**Symptom**
On a device run with 97 audio files, iOS rejected the library write:

```
CFPrefsPlistSource<0x1021ec800> (Domain: com.byronquine.lumenSync, ...): Attempting to store
>= 4194304 bytes of data in CFPreferences/NSUserDefaults on this platform is invalid.
This is a bug in Ilumionate or a library it uses.
<decode: bad range for [%@] got [offs:359 len:661 within:0]>
CFPrefsPlistSource<0x1021ec800> ...: Transitioning into direct mode
```

The consequence appeared minutes later in the same run: after analysing `Z*C*D*O.m4a` the
app logged `⚠️ AudioFile D905A69B-… not found in persisted list` and the finished analysis
was discarded. Every other file in the run logged `💾 Persisted analysis result…` — but that
line is printed unconditionally and does not mean the write landed.

**Where**
`Ilumionate/AnalysisStateManager.swift:675` and `Ilumionate/AudioLibraryStore.swift:216` —
both call `UserDefaults.set(_:forKey:)` with the whole encoded library under the
`audioFiles` key (`AnalysisStateManager.swift:633`). Neither can detect failure:
`UserDefaults.set` returns `Void`.

`AnalysisStateManager.swift:673` logs `💾 Persisted analysis result to AudioFile in
UserDefaults` immediately after the `set`, so the log actively misreports a dropped write.

**Reproduction**
Build a library large enough to cross 4 MiB when encoded — roughly 90–100 analysed files,
since each carries `transcription` (observed up to 3,145 words) plus a full `AnalysisResult`
with phase segments, linguistic markers, technique detection and prosodic profile. Analyse
one more file and watch for `not found in persisted list`, or read the encoded size directly:

```swift
UserDefaults.standard.data(forKey: "audioFiles")?.count
```

**Root cause**
The entire audio library is persisted as a single JSON blob in `UserDefaults`, which iOS
caps at 4 MiB per value. The design predates transcripts and full analysis results being
stored on `AudioFile`. The analysis cache already lives in a file
(`AnalysisStateManager.swift:546`, `analysisCacheURL`); the library never moved.

The `audioFiles` key is the only plausible multi-megabyte value in this domain — every other
`UserDefaults` writer in the app stores scalars or short strings
(`Ilumionate/AnalysisPreferences.swift:247` onward).

**State when discovered**
Nothing fixed. Note that the duplicate-detection work committed on
`feature/audio-duplicate-detection` **adds** to the blob: a 64-character
`contentFingerprint` and a `remoteSource` record per file. Marginal against 4 MiB, but it
moves in the wrong direction.

**Why this matters beyond lost analysis**
It defeats duplicate detection. At discovery, `DuplicateAudioIndex` was built from the
*persisted* library in the import and BambiCloud playlist paths. Both now await
`AudioLibraryStore.duplicateIndex()`.
When a write is rejected, a downloaded file is absent from the library on next launch, the
index cannot know about it, the verdict is `.distinct`, and `uniqueDestination`
(`PlaylistTrackDownloader.swift:139`) writes `Name (1).mp3`. That is very likely a
contributor to the duplicate accumulation the feature was built to stop, and no amount of
import-time checking fixes it while the store silently drops writes.

**Proposed fix**
Move the library off `UserDefaults` to a file in Application Support, written atomically —
the same shape `AnalysisStateManager` already uses for its analysis cache and
`GeneratedSessionStore` uses for sessions. Migrate once on first launch by reading the
existing `UserDefaults` value, writing the file, and removing the key. Make the write path
`throws` so a failure is logged as a failure rather than announced as a success.

A smaller stopgap, if the move is deferred: keep `transcription` and `analysisResult` out of
the persisted `AudioFile` entirely and read them from the existing analysis cache file on
demand. That is where they already live — `CachedAudioAnalysis` holds both — so the library
blob would shrink to metadata and drop well under the limit.

**Risks / blockers**
`audioFiles` is read from at least four places
(`AudioLibraryStore.swift:64` and `:250`, `AnalysisStateManager.swift:644`,
`SessionDetailView.swift:523`); all must move together or the library will appear to empty.
Migration must be idempotent and must not run while an analysis is mid-write. Worth pairing
with the memory pressure seen in the same run (`⚠️ High memory usage: 274MB` at launch,
`🔥 CRITICAL memory usage: 450MB` later), which has the same cause: the whole library,
transcripts included, is decoded into memory on every load.

**Resolution** _(2026-08-11, commit `ff03c0f`)_
The library moved to `Application Support/AudioLibrary/library.json`, written atomically via
`AudioLibraryStore.write(_:to:)`. `AudioLibraryStorage`
(`Ilumionate/AudioLibraryStorage.swift`) names the location and carries the legacy
`UserDefaults` only so the one-time migration can read it.

- Every mutator on the persistence actor now returns `Bool`, and
  `AudioLibraryStore.save` is `@discardableResult -> Bool`, so a failed write is reported
  rather than assumed.
- `AnalysisStateManager.persistAnalysisToAudioFiles` was deleted; the analyzer calls
  `AudioLibraryStore.saveAnalysis` and logs `❌ Analysis … was NOT persisted` on failure
  instead of announcing success unconditionally.
- `SessionDetailView.refreshAudioFile` reads the store rather than `UserDefaults`.
- Migration copies raw bytes, so nothing `ResilientDecoding` would drop is lost, and clears
  the old key only after the file lands.
- **If the migrating write fails, `load` falls back to the legacy copy.** Returning an empty
  library instead would have let `discoverUnregisteredDocumentFiles` re-register every file
  in `Documents` under a fresh identifier, discarding the analysis, rating and play count on
  each and orphaning every playlist. This was caught by
  `AudioLibraryStorageTests.failedMigrationKeepsLegacyCopy`, which failed against the first
  implementation.

Verified by `IlumionateTests/AudioLibraryStorageTests.swift` — six tests including a
round-trip of a library asserted to exceed 4 MiB when encoded — plus the existing
`AudioLibraryStoreTests` retargeted at the new store. Green on macOS and iOS Simulator. The
full suite shows only the ERR-001 flaky set.

**Not yet verified on device.** The migration path has only been exercised against synthetic
`UserDefaults` fixtures; the real 97-file library has not been migrated yet.
