# Why TestFlight users churned — telemetry investigation

**Date:** 2026-08-09
**Sources:** App Store Connect (153 testers), TelemetryDeck app `Illuminate`
(`1A7508D7-…`, last 30 days), local reproduction on build 0.7.6 + current `main`.

---

## Summary

Users were not leaving because the app crashed. **App Store Connect reports zero
crashes.** They left because the core value path — import audio, analyse it, get a
light session — fails most of the time and fails *silently*.

The measured funnel:

| Step | Users | Events |
|---|---|---|
| `onboarding.completed` | 27 | 28 |
| `audio.imported` | 15 | **116** |
| `audio.analyzeStarted` | 14 | **61** |
| `audio.analyzeCompleted` | **8** | **16** |
| `activation.completed` | 8 | 8 |
| `create.completed` | 2 | 3 |
| `retention.sevenDayReturn` | **3** | 3 |

- **Analysis succeeds 26% of the time** (16 of 61 attempts).
- **14% of imported files** are ever analysed (16 of 116).
- **30% of users activate** (8 of 27). Activation *is* a completed analysis.
- Daily active users decayed from a peak of 6 (~Jul 12) to 0–1 from Jul 26 onward.

Onboarding is not the problem — all 27 users completed it. Import is not the
problem either; users imported ~8 files each. The failure is analysis.

---

## The silent-stall finding

Accounting for the 61 analysis attempts:

```
61 started
−16 completed
−18 errors        (3 users)
− 2 cancelled
────
 25 unaccounted
```

**25 attempts produced no terminal event at all** — no completion, no error, no
cancellation. Only 3 users ever saw an error, yet 6 of the 14 who attempted
analysis never completed one. Roughly half the failures were invisible.

### Broken down by version

| Version | Started | Completed | Errors | Unexplained |
|---|---|---|---|---|
| 0.6.1 | 31 | 6 | 13 | 12 |
| 0.7.2 | 13 | 7 | 5 | **1** |
| **0.7.3** | **13** | **1** | **0** | **12** |
| 0.7.4 | 4 | 2 | 0 | 2 |

On 0.7.2 failures were loud and fully accounted for. On **0.7.3 — the build
containing the "failure recovery" work (`1bc85b8`, Jul 19) — 13 analyses started,
1 completed, and zero errors were reported.** The errors did not stop because the
failures stopped; they stopped because that build stopped reporting them.

0.7.3 has the worst success rate of any build measured: **8%**.

Where errors *were* still visible (0.7.2), the parameters were unambiguous:
`stage: transcription`, `reason: transcription` and `modelInitialization`.

**0.7.5 and 0.7.6 have zero analysis attempts** — not zero completions, zero
starts. Current builds are untested in the wild, because DAU was already ~0 by the
time they shipped.

---

## Root cause, reproduced locally

Reproduced on current `main` (2026-08-09, iPhone 17 Pro simulator) by importing
audio via **Import from Web**.

### What the log shows

```
[audio]    📁 Audio stored at: …/Documents/1062-stolen_thoughts.mp3
[audio]    Could not load audio duration: Operation Stopped
[audio]    ✅ Successfully downloaded audio: 1062-stolen_thoughts.mp3 (Duration: 0.000000s)
[audio]    🔬 Auto-queuing downloaded file for analysis...
[analysis] 🔄 Processing: 1062-stolen_thoughts.mp3 (queue position: 0)
[audio]    🔄 Initializing WhisperKit...
[audio]    ✅ WhisperKit initialized successfully
[analysis] ❌ Analysis failed - The operation could not be completed
[analysis] 🔁 Preserving checkpoint for one retry
[analysis] 🔄 Processing (retry) → Resuming from stage: transcribing
[analysis] ❌ Analysis failed - The operation could not be completed
[analysis] ⏸️ Automatic retry stopped; manual retry available
[analysis] ✅ Queue processing complete - no more files
```

Note **WhisperKit initialised successfully** — the earlier hypothesis that model
init was the cause was wrong. The model downloads correctly from
`huggingface.co/argmaxinc/whisperkit-coreml/…/openai_whisper-base/` (~500 network
log entries), taking roughly 100 seconds on first run with no user-facing progress.

### The actual defect

The downloaded "audio file" was not audio:

```
$ file 1062-stolen_thoughts.mp3
HTML document text, ASCII text, with very long lines

$ xxd 1062-stolen_thoughts.mp3 | head -1
00000000: 3c21 444f 4354 5950 4520 6874 6d6c 3e0a  <!DOCTYPE html>.
```

30KB of HTML, saved with an `.mp3` extension and admitted into the library.

**`Ilumionate/AudioManager.swift:170–195`** — the URL importer:

1. If the URL path ends in a known audio extension, the name is used directly and
   **`Content-Type` is never checked** (lines 172–175).
2. Otherwise `Content-Type` is sniffed, and anything unrecognised — including
   `text/html` — falls through to `ext = "mp3" // safe fallback` (lines 190–191).
3. There is no magic-byte check and no check that the file decodes.
4. `AudioImportWorker.swift:99` logs the duration failure at `info` and continues.
5. `AudioManager.swift:210` logs **"✅ Successfully downloaded audio"** with
   `Duration: 0.0` and returns the file as valid.

The file then enters the library looking normal (play button, 0:00), auto-queues
for analysis, fails transcription twice, and is parked for manual retry with no
visible error.

### Why this matches the reports

A tester on 2026-03-11 wrote: *"I can't submit a video but the attachments don't
load or save."* Their screenshots show five files in the library and an empty
playlist picker. That is this bug's exact signature: files that import
"successfully", never analyse, and never become playable.

Import errors (`Audio.Import.FileFailed`, `URLInvalid`, `URLServerRejected`,
`URLDownloadFailed`) are all at **zero** in telemetry — because this failure mode
is never reported as an import error.

---

---

## The silent stall itself — found and fixed

The HTML import explains files that fail *loudly*. It does not explain the 25
attempts that produced no event at all. That is a second, independent defect.

`AnalysisStateManager.queueForAnalysis(_:priority:)` returned early when a file was
already queued:

```swift
guard !isQueuedOrActive(audioFile) else {
    Log.analysis.info("📋 File already in queue: …")
    return              // ← before startAutomaticProcessing()
}
…
await startAutomaticProcessing(priority: priority)   // new files only
```

A queue can outlive its processor: once the automatic task finishes or is
cancelled, entries remain with nothing draining them. From that point on the file
is permanently stuck — it is "in the queue", so every later call (including the
user tapping **Analyze Now**) hits the early return and does nothing. No
completion, no error, no telemetry, and no UI change on tap.

The batch overload (`queueForAnalysis(_ audioFiles:)`) always calls
`startAutomaticProcessing`, so it never had this bug — only the single-file path
used by the manual retry button.

**Reproduced and fixed 2026-08-09.** With the guard re-arming the processor, a
9:30 hypnosis file analysed end to end on current code:

```
📊 Segments: 93, Words: 952
📊 Content type: hypnosis
✅ Light score alignment: 98%
✅ Analysis completed
```

---

## Why AI analysis never runs

Every on-device generation attempt failed. The logging only recorded
`type(of: error)` — always `GenerationError` — which is why this looked like a
single opaque failure. Logging the error itself gave the answer:

```
guardrailViolation(debugDescription: "May contain sensitive or unsafe content",
  underlyingErrors: [com.apple.SensitiveContentAnalysisML Code=15
    "Failed model manager query for model …instruct_300m.safety:
     InferenceError::hostFailed::invalidClientData::
     DecodingError.keyNotFound: Key '_promptRequest' not found … Path: countTokens._0"])
```

**The content was never evaluated.** Foundation Models could not query its own
safety classifier — a decoding failure inside `countTokens` — and *fails closed*,
reporting infrastructure breakage in the language of a content refusal. The
"sensitive or unsafe content" wording blames the audio for a broken host.

This was observed in the **simulator**, where the safety model host appears not to
function. It is therefore **not** evidence that the AI path fails on real devices,
and not evidence that Apple refuses this app's content. Both remain open questions
— which is exactly why the fallback is now reported (below).

### What was fixed

- `AIGenerationDiagnosis` classifies the failure: `safetyHostUnavailable`,
  `guardrail`, `contextWindow`, `assetsUnavailable`, `other`.
- **The retry is no longer wasted.** Only `contextWindow` (and unrecognised
  errors) are retried with the shorter prompt; a refusal, a missing model, or an
  unavailable safety host fails identically the second time, so the code now
  rethrows instead of spending another full model round-trip.
- **`ai.generationFallback` telemetry** with a `reason` parameter. The fallback
  was previously invisible — analysis still "completes", so nothing in the funnel
  revealed that AI never ran. This is the only way to learn how often real devices
  hit it, and with which reason.
- **The badge no longer lies.** `SessionDetailView` credited "AI Analyzed" even
  when keyword classification produced the result, directly contradicting the AI
  Insights card below it. It now reads "Keyword Analysis".

### Still open

- Transcription quality is poor on this material. The captured transcript loops —
  *"my mother's mother … mother mother mother"* — which is classic Whisper
  degeneration on soft or whispered speech. `openai_whisper-base` may be too small
  for this content; phases came back "Low-confidence".
- First analysis downloads the WhisperKit CoreML model (~100s) with no progress
  shown. WhisperKit itself initialises correctly.

---

---

## Second pass — what else the data says

**The data is trustworthy.** 25 of 27 users are real TestFlight installs on real
devices (903 of 915 events); the other 2 are direct installs. **Zero simulator,
zero debug** — local testing is not polluting these numbers.

**Hardware is not why AI analysis fails.** Device breakdown shows ~21 of 26 users
(81%) on Apple-Intelligence-capable hardware (iPhone 17 Pro Max alone is 12 users,
44%). Only 6 are on pre-A17 devices. Whatever stops Foundation Models, it is not
that users lack the silicon.

**Retention, measured directly.** `TelemetryDeck.Retention.distinctDaysUsed`:

| Distinct days used | Users |
|---|---|
| 1 | 27 |
| 2 | 7 |
| 3 | 3 |
| 4 | 2 |
| 14 | 1 |

Only 7 of 27 ever reached a second day. **20 users (74%) opened the app on exactly
one day and never came back.**

**Sessions are abandoned early.** Of 35 `session.ended` events: 6 complete, 3 at
75–95%, 5 at 50–75%, 1 at 25–50%, and **8 under 25%**. A further 12 report
`notApplicable`. Seven ends are explicitly `userStopped`, four of those under 25%.
Set against 60 `session.started`, **25 sessions never emitted an end event at all.**

### The finding that sets priority

Ordered funnel, per user:

| Step | Users | % of previous |
|---|---|---|
| Onboarded | 27 | — |
| Imported audio | 15 | 56% |
| Started analysis | 14 | 93% |
| **Analysis completed** | **8** | 57% |
| Returned after 7 days | 2 | **25%** |

Three users in total returned at seven days, and two of them are in the
analysis-completed group. So:

- Completed an analysis: **2 of 8 returned (25%)**
- Never completed one: **1 of 19 returned (5%)**

**Users who got a working analysis were roughly five times more likely to come
back.** Sample sizes are tiny (2 versus 1 returner) so this is directional, not
statistically established — but it points the same way as everything else: the
analysis pipeline is the product, and every hour spent there is worth more than
anything downstream of it.

### Instrumentation — mostly already fixed

An initial read of the aggregate totals suggested four gaps. Splitting by version
showed three of them were already closed:

| Apparent gap | Reality |
|---|---|
| `endReason` missing on 25 of 35 ends | All 25 are 0.6.1/0.7. Correct since **0.7.2** |
| `startType` missing on 46 of 60 starts | Same: 0.6.1/0.7 only. Correct since **0.7.2** |
| 25 sessions never emit an end | **21 are 0.6.1**; newer versions are short by exactly one each, i.e. sessions still in flight |
| `mode` absent | **Real** — session events never carried it |

Two things worth recording from that check:

- **`startType` is `fresh` on every event from 0.7.2 onward, never `resumed`.** The
  resume path is instrumented correctly (`PlaybackResumeDecision` sets `.resumed`
  when stored progress is between 0 and 1), so this is behaviour, not a defect:
  **nobody resumed a session in 30 days.** Consistent with 74% one-and-done.
- `source` and `category` were already good — preset (31) / generated (24) /
  mindMachine (5), across Trance (28) / Focus (18) / Energy (13) / Sleep (1).

**Fixed:** `mode` is now sent on `session.started` and `session.ended` via
`PlayerMode.analyticsName` (`session`, `flash`, `colorPulse`, `visualField`,
`audioLight`, `playlist`). With 8 of 35 measured sessions abandoned under 25%,
this is what will show *which* experience people walk out of.

---

## Recommended fixes, in priority order

1. **Validate downloaded content before accepting it** (`AudioManager.swift:170–210`).
   Reject non-audio `Content-Type`, check magic bytes, and require a decodable
   duration > 0. Fail the import with a clear message ("That link didn't return an
   audio file") rather than saving HTML as `.mp3`. Remove the
   `ext = "mp3" // safe fallback` path.
2. **Restore terminal telemetry for analysis.** A stall must emit
   `Audio.Analysis.Failed` (e.g. `reason: unknown` on timeout). This failure mode
   was only discoverable by subtracting completions from starts.
3. **Surface failure in the UI.** A parked "manual retry available" file currently
   looks identical to a healthy one. The playlist picker fix (2026-08-09) makes
   un-analysed rows actionable, but a row whose analysis will always fail still
   leads nowhere.
4. **Show model-download progress.** First analysis silently downloads a CoreML
   model for ~100s. On a poor network this is indistinguishable from a hang.
5. **Re-check `durationTimeout: .seconds(5)`** in the import path — a slow decode
   currently degrades to a silently-accepted 0-duration file.

## Caveats

- TelemetryDeck analytics are double opt-in (`UsageAnalytics.swift:61`), so the 27
  users are a subset of the 153 testers; rates are representative, not exhaustive.
- The 30-day window clips a few attempts at the boundary — enough to explain two or
  three of the 25 unaccounted, not all of them.
- The local reproduction used a URL that returned HTML. That the URL was bad is not
  the bug; that the app accepted it as audio and reported success is.
