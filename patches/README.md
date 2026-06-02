# Analyzer phase-classification fixes (working-tree patches)

These patches capture verified fixes to `HypnosisPhaseAnalyzer.swift` and
`TranscriptFeatureAnalyzer.swift`. They are stored as patch files rather than
committed source because, at the time of writing, those files have extensive
**uncommitted prior-session work** in the working tree (the committed HEAD
version of `HypnosisPhaseAnalyzer.swift` is the old ~403-line file; the working
tree has the ~2280-line modern analyzer). Committing the files directly would
bundle ~1900 lines of unrelated in-flight work into these fix commits.

The fixes are **already applied in the working tree** — these patches are the
reviewable record of exactly what changed. When the surrounding analyzer work is
ready to commit, these hunks go in with it.

## `analyzer-phase-fixes.patch` — 4 fixes, 5 hunks in `HypnosisPhaseAnalyzer.swift`

1. **Induction-drop fix** (`refinePhaseAssignments`): block relabels that move a
   segment *backward* in canonical phase order. A backward relabel
   (induction → pre_talk) doesn't refine a phase, it erases it by merging into
   the earlier adjacent phase. Fixes `classicHypnosisCorePhasesPresentInOrder`.
   Verified isolated via controlled A/B (only that test flips).

2. **Proposal merge floor** (`mergeShortSuggestedSegments`): lower the minimum
   phase duration for phrase-driven *evidence windows* from `max(25, …)` to
   `min(18, … * 0.60)`. The 25s floor erased genuine ~16–24s proposal phases on
   short clips. Advances the phrase-proposal tests from 1 → 4 phases (no
   regressions in Golden/ordering/consolidation suites).

3. **Keyword-alignment redistribution** (`phaseKeywordAlignment`): when a section
   has signal in only some evidence channels (word/phrase/way-marker),
   redistribute the missing channels' weight onto the active ones, instead of
   capping at 0.45 when only strong word matches exist. Fixes
   `repetitiveBrainwashingSectionIsPromotedToHighConfidence` (confidence → high).

4. **Confidence rationale ordering** (`confidenceRationale`): move the
   vocabulary / phrase / way-marker match reasons ahead of the generic prosody
   prose so they survive the `prefix(3)` cap. Makes the rationale mention
   "vocabulary" when word matches drive the score.

## `transcript-window-sizing-fix.patch` — 1 hunk in `TranscriptFeatureAnalyzer.swift`

**Window sizing** (`makeTimelineWindowSeeds`): cap window duration at ~¼ of the
transcript so short transcripts yield several distinct, low-overlap windows.
Previously a 96s clip produced 3 heavily-overlapping 45s windows that
cascade-merged (via `shouldMergeTimelineWindows`) into a single window,
collapsing the phrase-driven proposal to one phase. Long files are unchanged
(still 45–60s windows). Verified: short transcript 1 → 5 windows; 600s file
unchanged at 11 windows.

## Still failing (NOT fixed — deep evidence-scoring, deferred)

### Issue 1 — `earlyBrainwashingVocabularyDoesNotOverridePretalkAnchoring` (C1)

**Symptom:** a 90s clip that opens with "welcome / comfortable" then a dense
"brainwashing / indoctrination / brainwash" block (8–12s) decodes as
`brainwashing[0-90]` instead of opening with `pre_talk`.

**Full stage trace (instrumented):**
- `RESOLVED`: `pre_talk 0-5 | brainwashing 6-17 | …` — position weighting *works*;
  pre_talk correctly wins the first ~5s. The dense brainwashing block then wins
  6–17s (5 keywords × ~3.2 weight beat pre_talk's "welcome" 1.2 + "comfortable"
  0.8 even after the 0.22× position penalty).
- `ORDERED` (`enforcePhaseOrdering`): **this is the actual culprit.** The
  forward-only clamp locks the floor to the highest phase seen so far. Once the
  spurious `brainwashing` (ordered index 8) appears at 6s, every later second is
  forced `≥ brainwashing`, so the genuine downstream `induction` and `deepening`
  are *rewritten to brainwashing*.
- `SMOOTHED` → `pre_talk 0-5 | brainwashing 5-90`; `COLLAPSED` → the 5s pre_talk
  is below `minRun` (20s) and is absorbed → `brainwashing 0-90`.

**Root cause:** not position weighting — it's that `enforcePhaseOrdering` lets a
brief, early, out-of-position spike permanently raise the ordering floor, and then
`collapseShortRuns` removes the short correct pre_talk.

**FAILED ATTEMPT (reverted):** steepening `phasePositionWeight` (square the
normalised distance, floor 0.22→0.06, divisor 35→30). It did NOT fix C1 *and*
regressed `affirmationsHasNoDeepening`. Lesson: the position curve is shared by
all phases; deepening the penalty mislabels legitimate mid-phase content.

**What it actually needs:** make `enforcePhaseOrdering` (or the resolve step)
resistant to a *short, low-support* early run raising the floor — e.g. don't let a
run shorter than `minRun`, or below a confidence floor, advance the ordering
high-water mark. This is the single most load-bearing invariant in the pipeline;
change it only with the eval corpus measuring net effect across many files.

### Issue 2 — phrase-proposal DP misses conditioning/emergence (3 tests)

`suggestPhaseTimelineBuildsOrderedPhraseDrivenProposal`,
`adaptPredictedPhasesCanAdoptPhraseDrivenProposalWhenSeedTimelineIsWeak`,
`hybridSelectionCanFuseBestSectionsFromKeywordAndChunkedOutputs`.

**Root cause (instrumented):** `baseEvidenceBreakdowns` (the per-window emission
scorer feeding the Viterbi `decodePhaseEvidenceWindows`) scores each window from
4 channels — `transcriptSupportScore` (prosody traits) ×0.48, `phraseLibraryAlignment`
(corpus knowledge, **empty at runtime in tests**) ×0.24, `phaseWaymarkerAlignment`
×0.18, `phasePositionWeight` ×0.10. **None read the keyword taxonomy.** So strong
cues like "wide awake" / "count to five" / "trigger" in the window text contribute
nothing, and windows mis-decode to `therapy`/`fractionation`.

**FAILED ATTEMPT (reverted):** added a `phaseKeywordAlignment` channel to the
emission score, rebalancing weights (tried transcript 0.48→0.38 then →0.46, keyword
0.18–0.22, etc).
- *Directionally correct*: `emergence` then **did** appear (was `therapy`) —
  proof the keyword channel is the right idea.
- *But* every rebalance regressed other tests: `affirmationsHasNoDeepening`,
  `hybridSelection*` selection flips, and at one setting induction mis-labelled as
  fractionation. Tuning 5 interacting emission weights against 3 fixtures trades
  one pass for another failure.

**Second, independent blocker — taxonomy gap:** even a perfect DP can't find
`conditioning` in the `suggestPhaseTimeline` fixture, because its conditioning
window text is "when i snap my fingers this response returns instantly" — which
contains **no conditioning keyword** ("snap", "response returns", "instantly" are
not in the taxonomy; only "trigger" phrases are, and that word isn't in this
window's top terms). Window top-words instrumented:
`win60-84 {count/fingers/instantly/response/returns}` — "count"/"fingers" actually
pull toward *emergence*. Conditioning detection here needs taxonomy additions
(e.g. "snap (my) fingers", "response returns", "this response") **validated
against the corpus** so they don't pollute other phases.

**What it actually needs:** (a) wire keyword evidence into the DP emission model,
weight-tuned against the synthetic eval corpus (net accuracy over hundreds of
cases, not 3 fixtures); (b) close the conditioning taxonomy gap, corpus-validated.

### Meta-lesson for the next session

Two naive hand-fixes were attempted on this deep logic; **both regressed other
tests and were reverted.** These two issues are global tuning of interacting
weights / the core ordering invariant — they are *not* safely fixable against a
handful of fixtures. Build/finish the synthetic eval corpus first (spec §3–4),
then tune with net-accuracy feedback. This is the through-line the whole
phase-classifier-training spec was pointing at.

## To re-apply (if ever reverted)

```sh
git apply patches/analyzer-phase-fixes.patch
git apply patches/transcript-window-sizing-fix.patch
```
