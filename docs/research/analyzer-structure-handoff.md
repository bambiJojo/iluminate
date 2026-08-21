# Analyzer structure work — handoff

**Branch:** `research/light-session-duration-guardrails`
**Date:** 2026-08-21
**Status:** measurement complete, nothing wired into the shipping pipeline

---

## The headline

A **fixed positional template beats or matches the entire structural pipeline.**

Frequency deviation from a light session generated using the labeller's own
boundaries and labels, as a share of the generator's 8.8 Hz range, across the
four hand-labelled corpus files:

| approach | BF | DFTC | Mind Melt | Tick Tock | mean | spread |
|---|---|---|---|---|---|---|
| as shipped (keyword analyser) | 28% | 21% | 7% | 23% | **19.8%** | |
| full pipeline (detector + namer) | 8% | 11% | 17% | 19% | **13.8%** | 8–19% |
| **fixed positional template** | 15% | 11% | 15% | 13% | **13.5%** | 11–15% |
| detector with *perfect* labels | 4% | 4% | 4% | 4% | 4.0% | |

The template uses **no audio, no transcript and no detection**: induction to 15%
of the file, deepening to 60%, suggestions to 85%, conditioning to 96%,
emergence after. Per file the pipeline runs −7, 0, +2, +6 against it — mean
+0.25, in the template's favour, with worse consistency.

### Why

Trance depth, measured across 32 labelled segments:

| feature | correlation with depth |
|---|---|
| speech rate | +0.09 |
| pitch | −0.01 |
| volume | +0.01 |
| speech/silence ratio | +0.38 |
| **position in file** | **+0.40** |
| deepening words (lexical) | +0.14 |
| awakening words (lexical) | −0.23 |

**Position is the strongest signal measured anywhere in this work.** Trance depth
is not in the acoustics and not in simple word counts — it is in meaning, which
is what a labeller supplies and what the on-device model refuses to read on this
content.

This single fact explains the rest of the branch: why boundary recall caps at
50%, why merging failed twice, why naming carries most of the error, and why
fractionation resisted two separate detection mechanisms.

---

## What is worth shipping

**The seven-phase taxonomy.** This is where the six-point gain over the shipping
analyser came from — not from any detection. It is already committed and live in
`TrancePhase` (`8b602e1`).

**The template**, if you want the improvement now. It is fast, deterministic,
needs no transcription, and cannot be refused by a guardrail. It is currently
only a row in a test, not production code.

---

## What was built

### Structural detection — `Ilumionate/Structure/`

| file | purpose |
|---|---|
| `StructuralFrames.swift` | transcript + `ProsodicProfile` → normalised frames |
| `StructuralNovelty.swift` | self-similarity + checkerboard kernel → novelty curve (Foote's method, borrowed from music structure analysis) |
| `CountingRunDetector.swift` | counted passages; down = deepener, up = awakening; also `fractionationWindows` |
| `StructuralSegmenter.swift` | novelty peaks + counting anchors + minimum length → segments |
| `SegmentPhaseNamer.swift` | position + counting + prosody, Viterbi-decoded over ordered phases |
| `StructuralMerger.swift` | **dead code, deliberately kept** — see negative results |
| `StructuralReport.swift` | renders a segmentation for a human to read |

Scores **F1 35%** on boundaries against the labelled corpus (recall 50%,
precision 26%, median error 10 s when matched) versus the shipping keyword
analyser's **F1 11%** (3 of 34 boundaries; two files score zero).

### Taxonomy — `Tools/CorpusGenerator/Sources/CorpusKit/TrancePhase.swift`

Target widened from five phases to seven. A phase reaches the light through
exactly two things — its `intensityContour` branch and its
`tranceDepthEstimate`:

```
induction      decay     0.22     target
fractionation  fast-osc  0.42     ADDED — lost a unique contour, and 0.42 → 0.62
deepening      decay     0.62     target
conditioning   osc       0.58     ADDED — shallower than suggestions, so folding
                                  it in lit the close of sessions too deep
suggestions    osc       0.72     target
brainwashing   osc       0.82     target
emergence      rise      0.24     target

pre_talk       decay     0.22     folded — identical light to induction
confusion      decay     0.62     folded — identical light to deepening
erotic_sugg.   osc       0.78     folded — 0.06 from suggestions
therapy        osc       0.84     folded — 0.12 from suggestions
```

**Four separate sites were collapsing phases.** Three are fixed; the export one
is deliberate (it carries the target vocabulary, which is what the analyzer
should be trained to emit). Existing labels need no rework — the mapping is
deterministic.

### LumeLabel

- `Ilumionate/Training/TranscriptInventory.swift` — which files have transcripts, work ordering (tested)
- `LumeLabel/BulkTranscriptionController.swift` — "Transcribe All", sequential, one analyser reused, failures recorded and skipped
- Sidebar shows a per-row transcript badge and sorts by transcript presence

### Measurement apparatus

| tool | what it does |
|---|---|
| `Tools/structure-harness/` | runs the detector over an exported `AnalysisCache.json` |
| `Tools/structure-eval/` | scores boundaries against labels; sweeps novelty, minimum segment, prominence, merge cliff |
| `Tools/structure-prosody/` | computes `ProsodicProfile` for corpus audio using the app's real `ProsodyAnalyzer` |
| `IlumionateTests/IncumbentBaselineTests.swift` | scores the shipping keyword analyser |
| `IlumionateTests/LightImpactOfBoundariesTests.swift` | **the important one** — compares light trajectories |
| `IlumionateTests/FractionationSignatureTests.swift` | tests candidate fractionation signatures |

---

## How to run things

Every test target, in one command (the `Ilumionate` scheme alone silently skips
LumeLabel's 25 tests):

```sh
Scripts/run-all-tests.sh -destination 'platform=macOS,arch=arm64'
```

Corpus-backed measurements are opt-in and report through Swift Testing
attachments — the sandboxed macOS test host cannot write to `/tmp`,
`~/Downloads` or even its own Documents directory, and `xcodebuild` does not
surface test stdout:

```sh
TEST_RUNNER_LUMESYNC_CORPUS=/Volumes/HardDrive01/Backup/TrainingCorpus \
TEST_RUNNER_LUMESYNC_PROSODY=$HOME/Downloads/lumesync-prosody \
  Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' \
    -only-testing:IlumionateTests/LightImpactOfBoundariesTests
```

Read the result back:

```sh
xcrun xcresulttool export attachments --path <latest.xcresult> --output-path /tmp/att
```

---

## Negative results — do not repeat these

Four plausible mechanisms were built, measured, and overruled. Each is recorded
in the source next to the code so a later attempt starts from the measurement.

1. **Agglomerative merging for boundary precision.** Never better, usually worse.
   At the mildest setting it cost 21 points of recall and *lowered* precision.
   Whole-segment similarity discriminates no better than local novelty.
2. **Merging before naming**, on the theory that fewer segments means fewer
   naming errors. Catastrophic — BF went 14% → 43%. **Over-segmentation is
   protective**: extra boundaries inside a homogeneous stretch cost almost
   nothing, while too few leave the namer no resolution to place an emergence.
3. **Fractionation from alternating counting runs.** Fires on 1 of 4 labelled
   fractionation files and 7 of 63 others — near chance. The detector is kept
   and tested; the namer does not use it.
4. **Fractionation from sleep/wake command density.** Medians look clean (7.9
   vs 1.1 per ten minutes) but distributions overlap; best threshold captures
   2 of 4 with 40% precision. `Rapport Deepener.mp3` has a higher sleep density
   than any labelled fractionation file.

---

## Open questions and risks

**`tranceDepthEstimate` is unvalidated.** It is a hand-assigned constant per
phase. Every measurement in this branch treats a session built from those
constants as ground truth, so part of what no feature can predict may simply be
arbitrary. **Checking these by ear is probably higher-leverage than any further
classification work.**

**Four labelled files is the binding constraint.** 34 boundaries. The 95%
interval on a recall of 50% is ±17 points, and three separate improvements in
this branch could not be distinguished from noise. Roughly 25 files with real
boundaries would let a 10-point change be detected. Of 78 corpus label files, 63
carry a single whole-file "silver" label and 11 carry none.

**16 fractionation files** are at `~/Downloads/fractFiles`; 12 have no transcript
yet. Import them into LumeLabel and use *Transcribe All*, then re-run
`FractionationSignatureTests` with 16 positives instead of 4. Note these are
whole-file labels — they say a file *is* fractionation, not where within a mixed
file it occurs.

**DFTC.mp3** counts ↓462s ↑757s ↓955s, which the alternation rule reads as
fractionation while the labels say deepening and erotic_suggestions. The
signature test suggests the rule over-fires rather than the label being wrong,
but a human ear would settle it.

**ERR-018** — `AnalyzerImprover` does not build. Same target-membership drift
that broke LumeLabel, but it cascades much further.

**ERR-009** — memory peaked at 516 MB on device. Unmeasured, reopened earlier.

**Not examined** — `ScriptPhaseCorpus` and `ScriptCorpusExtractor` project
through `labelingPhase` at several sites. Probably correct (they are consumers,
not storage) but unchecked.

---

## Recommended next steps, in order

1. **Validate the depth table by ear.** Everything downstream inherits it and
   nothing has checked it. One listening session could move more than this
   entire branch did.
2. **Ship the template** if the six-point gain is wanted now — it is simple,
   fast, and cannot be refused by a guardrail.
3. **Label ~20 more files with real boundaries.** This is the constraint behind
   every inconclusive result here.
4. **Stop adding features to the namer.** Four overruled mechanisms is enough
   evidence that this feature set is exhausted.

---

## Verification at handoff

- `Scripts/run-all-tests.sh` — **1762 + 25 test cases, 0 failures**
- `Ilumionate` (macOS), `Ilumionate` (iOS Simulator), `LumeLabel` — all build
- `AnalyzerImprover` — does not build (ERR-018, pre-existing)
- Nothing in `Ilumionate/Structure/` is wired into the shipping analysis
  pipeline; `ChunkedPhaseAnalyzer` is untouched
