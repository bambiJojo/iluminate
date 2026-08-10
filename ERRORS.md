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

_None yet._
