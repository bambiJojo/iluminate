# Deferred AI Analysis — Design

**Date:** 2026-08-17
**Status:** Awaiting approval
**Surface:** `AIAnalysisManager`, `AnalysisStateManager`, `AnalysisResult`, background scheduling

## Problem

Foundation Models is refused for the foreground app while Game Mode is active. Device evidence
from 2026-08-17, recorded by `AIAttemptLog`:

```
foreground 0/16 used AI, background 3/7 used AI
```

Sixteen consecutive foreground attempts, every one `.systemBusy`. This is not intermittent.

Each refusal is currently terminal. The pipeline logs
`↺ Transient — analysing this file again later should succeed`, then writes the keyword result,
clears the checkpoint, and marks the file complete. Nothing acts on the promise, so a transient
condition produces a **permanent** downgrade. Sixteen files were degraded this way in one
session.

The cost is measurable, not cosmetic: files that fell back have produced light-score alignments
of 76%, 86%, 89% and 90% against 98–99% for files the model analysed.

## The actual defect

Not "the app attempts AI in the foreground". It is:

> **A transient failure is treated as a final answer.**

Framing it that way matters, because gating on foreground/background would be wrong. A device
without Game Mode analyses fine in the foreground, and a blanket gate would defer work that
would have succeeded. Deferring on the *observed transience* of the failure is correct
everywhere and needs no knowledge of why.

## Design

### 1. The result records which kind of fallback produced it

`AnalysisResult` has no machine-readable provenance. `keywordFallbackReason` recovers a
user-facing *sentence* by dropping a prefix from `aiSummary`, so nothing can ask "was this
transient?" without matching English.

Add `aiFallbackKind: AIGenerationDiagnosis.Kind?` — `nil` when the model produced the result.
Optional, so results written before this decode unchanged, and `usedKeywordFallback` keeps its
prefix-matching behaviour for those.

### 2. A transient failure defers instead of finishing

| Failure | Session generated | Checkpoint | File state |
|---|---|---|---|
| `.systemBusy`, `.rateLimited` | yes, from keyword | **kept** | awaiting AI |
| `.guardrail`, `.assetsUnavailable`, `.contextWindow`, `.other` | yes, from keyword | cleared | complete |

The session is still generated from the keyword analysis in both cases. A user who imports a
file must be able to play it now — deferring the *session* would be a worse regression than the
degraded analysis it is trying to avoid.

Retaining the checkpoint is what makes re-entry cheap. The device log already shows
`⏭️ Reusing saved transcript` working, so a retry re-runs only the AI stage, not WhisperKit.

**A guardrail refusal is not transient.** Given this library's subject matter, a real share of
files will be permanently keyword-only. Retrying them would be an infinite loop against a
deterministic refusal.

### 3. Retry runs when the app backgrounds

`BackgroundAnalysisScheduler` already exists. On entering background, take up to
`maximumPerWindow` files awaiting AI and re-run their analysis stage.

```swift
static let maximumRetryAttempts = 3
static let maximumPerWindow = 5
static let spacingBetweenAttempts: Duration = .seconds(30)
```

**All three numbers are policy, not measurement.** Spacing exists because
`ChunkedPhaseAnalyzer` issues one model request per 15-second chunk — 589 on one observed file —
and a successful AI stage is followed by that volume. The interval that actually avoids rate
limiting is unmeasured; 30 seconds is a starting point, and the attempt log will show whether it
holds.

### 4. Attempts are bounded and recorded

`aiRetryCount` on the checkpoint, incremented per attempt. At `maximumRetryAttempts` the file
stops being eligible and its fallback becomes final — a device where Game Mode is permanently on
must not retry forever.

## Out of scope

- Pacing inside `ChunkedPhaseAnalyzer`, and its missing `rateLimited` catch. Real, separate, and
  only reachable once the main AI stage succeeds.
- Aggregate visibility ("N files are keyword-only, re-run them") — that is `task_34b6360c`.
- ERR-009's memory footprint.

## Testing

Pure and testable without a device:

- a transient kind keeps the checkpoint; a non-transient kind clears it
- a session is generated in both cases
- eligibility excludes `.guardrail` and the other non-transient kinds
- eligibility excludes files at the retry ceiling
- `aiFallbackKind` round-trips, and a result encoded without it still decodes
- a successful retry clears the awaiting-AI state and the retry count

Not testable here: whether 30 seconds avoids rate limiting, and whether the background window is
long enough to complete a file. Both need the device, and `AIAttemptLog` already reports the
first.

## Risks

- **The spacing number is a guess**, exactly like the watchdog's five minutes in the Task Center
  spec. It is a named constant so it can move without a redesign.
- **A background window may be too short** for an AI stage plus chunked phase analysis. If so,
  files churn without completing and the retry budget drains against nothing. The attempt log
  will show this as background attempts that neither succeed nor fail.
- **Deferring changes when analysis completes.** A file may sit awaiting AI indefinitely if the
  app is never backgrounded with battery to spare. Its keyword session works throughout, so the
  failure mode is "no improvement" rather than "no session".
