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

### ERR-006 — Foundation Models blocked by Game Mode; every analysis silently degrades

- **Date discovered:** 2026-08-11
- **Status:** identified
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

Nothing surfaces this in the UI. The user sees a completed analysis and a generated session
with no indication it was built without the language model.

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

---

### ERR-004 — `AudioFile.==` ignores content fingerprint and remote provenance

- **Date discovered:** 2026-08-11
- **Status:** identified
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

---

### ERR-003 — Files-picker duplicate check cannot use the duration signals

- **Date discovered:** 2026-08-11
- **Status:** identified
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

---

### ERR-002 — Function-level `-only-testing` filters run zero tests and report success

- **Date discovered:** 2026-08-11
- **Status:** identified
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
Unknown — not yet investigated. Likely that `-only-testing` addresses XCTest-style method
identifiers and does not resolve a Swift Testing `@Test` function name, leaving an empty
test set that is not treated as an error.

**Proposed fix**
Short term, and already the working practice: filter at struct level only, never at function
level, and confirm the expected `Test case '…' passed` lines appear rather than trusting the
summary banner. Longer term, check whether `swift test --filter` or the `TEST_RUNNER_`
environment resolves individual `@Test` names, and correct the filters quoted in `CLAUDE.md`
and the plan document.

**Risks / blockers**
The danger is silent: any agent or engineer verifying a single test this way gets a false
green. Worth fixing in the documented commands before it costs someone a real bug.

---

### ERR-001 — Six timing tests fail under full-suite parallel load

- **Date discovered:** 2026-08-11
- **Status:** identified
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

Each takes 36–59 seconds inside the suite. The same tests pass in roughly 0.15 seconds when
their struct is run alone.

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

---

## Resolved

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

**Already done**
Nothing fixed. Note that the duplicate-detection work committed on
`feature/audio-duplicate-detection` **adds** to the blob: a 64-character
`contentFingerprint` and a `remoteSource` record per file. Marginal against 4 MiB, but it
moves in the wrong direction.

**Why this matters beyond lost analysis**
It defeats duplicate detection. `DuplicateAudioIndex` is built from the *persisted* library
(`Ilumionate/AudioManager.swift:138`, `Ilumionate/PlaylistImport/BambiCloudPlaylistImportViewModel.swift:170`).
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

