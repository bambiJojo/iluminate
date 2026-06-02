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

- `earlyBrainwashingVocabularyDoesNotOverridePretalkAnchoring` — early spurious
  brainwashing spike gets locked in by `enforcePhaseOrdering`'s forward-only
  clamp, then short pre_talk is collapsed away. A position-curve attempt
  regressed `affirmationsHasNoDeepening` and was reverted.
- `suggestPhaseTimelineBuildsOrderedPhraseDrivenProposal`,
  `adaptPredictedPhasesCanAdoptPhraseDrivenProposalWhenSeedTimelineIsWeak`,
  `hybridSelectionCanFuseBestSectionsFromKeywordAndChunkedOutputs` — the
  phrase-proposal DP (`decodePhaseEvidenceWindows`) scores window emissions from
  transcript *trait* features, not the keyword hitMap, so strong cues like
  "wide awake"/"count to five" don't pull windows to emergence/conditioning.
  Needs the DP emission model wired to keyword evidence — an architectural change
  best done against the synthetic eval corpus as a safety net.

## To re-apply (if ever reverted)

```sh
git apply patches/analyzer-phase-fixes.patch
git apply patches/transcript-window-sizing-fix.patch
```
