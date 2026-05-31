# Phase Classifier Training — Design Spec

**Date:** 2026-05-31
**Status:** Approved (brainstorming complete) — ready for implementation planning
**Companion illustration:** `docs/phase-training-plan.html`

## Problem

LumeSync turns a hypnosis/trance mp3 into a light score. The pipeline is:

```
mp3 ─Whisper─▶ transcript ─▶ PHASE CLASSIFY ─▶ PhaseSegments ─▶ SessionGenerator ─▶ light score
```

The **phase classification** stage is the roadblock. Getting the *phase of trance* right — and
especially *where one phase ends and the next begins* — is unreliable.

### Root cause

Every scoring function in the current classifier is **intrinsic** — `intrinsicQualityScore`,
`transcriptSupportScore`, ordering/coverage bonuses. The AnalyzerImprover optimizer can only reward the
analyzer for being internally self-consistent and well-ordered, never for being *actually correct*,
because there is no labeled ground truth in the loop. It is an elaborate machine optimizing a proxy that
is not "did this match a real trance file."

A second, verified problem: current evaluation scoring is **coarse**. `AnalysisEvaluator.scorePhaseOrder`
checks only phase *presence* and *monotonic order*, never *boundary placement*. The real defect is
boundary placement, which nothing currently measures.

## Goals

1. Put **labeled ground truth** into the improvement loop so the classifier chases correctness.
2. Measure **boundary placement** directly, not just phase presence/order.
3. Generate labeled data at **scale** so config-tuning and (later) a learned model have enough signal.
4. Keep the work **honest** — synthetic data must not "teach to the test."
5. End state (**Approach C**): ship a tuned baseline, personalize on-device from user corrections, and
   export those corrections back to grow the offline corpus.

## Non-goals

- TTS / synthetic *audio*. The classifier reads transcripts, not raw audio; synthetic speech is too clean
  and would test the wrong layer. Transcription robustness is validated separately via hand-labeled real
  audio.
- Shipping the generator in the iOS app. It is a dev-time tool only.
- Editing `features.json` (project rule).

## Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Where training runs | **Both (C)** | Offline tunes a shipped baseline; device personalizes & exports corrections back. |
| Signals used | **All** | Text + technique markers + prosody + audio texture + position priors. |
| Boundary labeling (real) | **Anchor regions** | Label only what's certain; gray zones unlabeled and free. Matches blurry reality; gray zones become light-score cross-fades. |
| Engine strategy | **Phased: 3 → 2** | Config-tune now (immediate win), flip to learned model as corpus grows. |
| Artifact generated | **Synthetic transcripts, not audio** | Classifier reads transcripts; audio robustness deferred to real-audio layer. |
| Generation engine | **Claude API, dev-time** | Few-shot from real transcripts; inject realistic ambiguity. |
| Generator packaging | **Standalone SwiftPM CLI** (`Tools/CorpusGenerator/`) | Imports app model types so JSON schema can't drift; never ships. |
| Phase plans | **Template library + variation** | Realistic archetypes, varied lengths/orderings, full phase coverage. |
| Anti-vanity safeguard | **Held-out real corpus as judge** | Tune/train on synthetic; report real accuracy as true north. |
| Label granularity | **Segment-level truth + new timeline metrics** | Generator authors each block so truth is free; new metrics catch boundary bug. |

## Architecture overview

Two complementary ground-truth sources feed **one** evaluator:

| | Synthetic corpus (Claude API) | Real corpus (LumeLabel) |
|---|---|---|
| Truth | Exact, segment-level (generator authors it) | Blurry anchor regions (hand-labeled) |
| Scale | Hundreds, cheap | Scarce, expensive |
| Risk | "Teaching to the test" | None, but small |
| Role | **Training / tuning** + boundary metrics | **Held-out validation** — honesty judge |

Operational honesty rule: **synthetic tunes the model; real judges it.** Every report shows synthetic and
real accuracy side by side. Synthetic ↑ + real flat = overfit → reject. Synthetic ↑ + real ↑ = ship.

### Important correction vs. earlier plan

The evaluation harness is **not built fresh** — it already exists in the test target and is **extended**:

- `IlumionateTests/AnalysisEvaluationMetrics.swift` — `EvaluationCase` (truth) + `AnalysisEvaluator`
  (`scoreContentType`, `scorePhasePresence`, `scorePhaseOrder`, `scoreFrequencyRange`,
  `scoreSessionValidity` → `AnalysisQualityScore.overallScore`).
- `IlumionateTests/EvaluationCorpus.swift` — current hand-written cases (`EvaluationCorpus.all`); the thing
  that scales up.
- `IlumionateTests/EvaluationHarnessTests.swift` — runs the corpus through the **real** keyword pipeline
  (`HypnosisPhaseAnalyzer().analyzeTranscription` → `SessionGenerator` → `AnalysisEvaluator`); AI-gated
  cases tagged `.enabled(if: ChunkedPhaseAnalyzer.isAvailable)` so CI skips cleanly.

Missing pieces are only: (a) the generator, (b) scaled corpus data, (c) richer timeline metrics.

## Section 1 — Shared spine (corpus format + evaluator)

The corpus JSON format and the evaluator are the spine that every phase reuses. One data format and one
evaluator serve config-tuning, model-training, and regression-testing.

## Section 2 — Corpus JSON format & layout

One file per case. Unified schema across synthetic and real, bridged by a `boundaryMode` flag.

```json
{
  "id": "synth-induction-deepening-0042",
  "source": "synthetic",
  "boundaryMode": "exact",
  "ambiguityLevel": "high",
  "duration": 1840.0,
  "segments": [
    { "text": "just let your eyes close…", "timestamp": 35.0, "duration": 4.2, "confidence": 1.0 }
  ],
  "truth": [
    { "phase": "induction", "start": 0.0,   "end": 128.0 },
    { "phase": "deepening", "start": 128.0, "end": 410.0 }
  ]
}
```

- `source`: `"synthetic"` | `"real"`.
- `boundaryMode`: `"exact"` (synthetic — boundaries known to the second) | `"anchored"` (real — `truth`
  spans are anchor regions; gaps between them are unlabeled gray zones the evaluator does not grade).
- `segments`: shape matches `AudioTranscriptionSegment(text:timestamp:duration:confidence:)`.
- `truth`: segment-level phase spans with `start`/`end`.

**Layout & loading:**

- `Tools/CorpusGenerator/Corpus/synthetic/*.json` and `…/real/*.json`.
- A shared SwiftPM module defines the `CorpusCase` Codable type, imported by **both** the CLI and the test
  target — single source of truth for the schema (prevents drift).
- The test target loads corpus files as a bundle resource so `EvaluationHarnessTests` can iterate the
  whole corpus.

## Section 3 — The generator (`Tools/CorpusGenerator/`)

Dev-time SwiftPM CLI calling the Claude API.

- **3a. Style seeding (few-shot):** one-time, transcribe a handful of real mp3s via the existing
  app/WhisperKit, export transcripts. The generator feeds 2–3 as few-shot examples so scripts sound
  genuine. Few-shot blocks live in the **prompt-cache prefix** (identical across calls → cost saving).
- **3b. Generation unit = one phase block at a time.** Claude writes one phase (e.g. "90s of deepening
  transitioning toward therapy"); the CLI assembles blocks into a session. Because the CLI places each
  block, the boundary truth is free and exact. Enables varied orderings/lengths.
- **3c. Ambiguity controls (`--ambiguity`):** `low` (direct, some keyword overlap), `medium` (paraphrase,
  indirect/Ericksonian), `high` (fuzzy transitions, phase-bleed, metaphor — the hard cases). Corpus is
  generated across a distribution and each file stamped with `ambiguityLevel`.
- **3d. Determinism & cost:** each file records its generation params (phase plan, ambiguity, few-shot set
  id) for reproducibility. Generation is occasional dev cost, never per-CI.
- **3e. Phase plans = template library + variation.** Realistic archetypes (classic
  induction→deepening→therapy→emergence, fractionation-heavy, erotic, brainwashing, etc.); the generator
  varies lengths/orderings within each, ensuring full phase coverage and realistic structure.

## Section 4 — New timeline metrics (evaluator extension)

Extend `AnalysisEvaluator` in `IlumionateTests/AnalysisEvaluationMetrics.swift`. Both truth and predicted
sides carry timestamps (`PhaseSegment.startTime/endTime`, `Ilumionate/HypnosisPhaseAnalyzer.swift:43-44`;
`AIPhaseSegment.startTime/endTime`, `Ilumionate/AIAnalysisModels.swift:240,243`). Canonical phase order in
`AnalysisEvaluator`: `[.preTalk, .induction, .deepening, .therapy, .suggestions, .conditioning,
.emergence]`. Existing metrics are kept (backward compatible); these are added:

- **Per-second phase agreement** — headline "anchor accuracy." Walk timeline second-by-second; compare
  predicted vs truth. `exact` files grade every second; `anchored` files grade only anchored seconds.
- **Boundary-placement error** — for each true transition, mean & median |Δt| to the nearest predicted
  boundary. *The number that directly measures the roadblock.* On `anchored` files, Δt inside the gray zone
  scores zero error; only spill into an adjacent anchored region is penalized.
- **Confusion matrix** — per-phase, which phases are mistaken for which (debugging lens).
- **Per-phase precision / recall / F1** — chronic over-/under-calling of a phase.
- **Accuracy-by-ambiguity breakdown** — per-second agreement pivoted by `ambiguityLevel` → accuracy-vs-
  difficulty curve.

Aggregate run emits a report struct (overall agreement, boundary error, confusion matrix, by-ambiguity
table) serving optimizer fitness (Phase 1), training/eval signal (Phase 2), and CI regression gate.

## Section 5 — End-to-end workflow (three loops, one harness)

**Loop 1 — Corpus generation (occasional, dev-time, manual):**
```
one-time: real mp3s ─Whisper─▶ exported transcripts (few-shot seeds)
generate: CorpusGenerator CLI ─Claude API─▶ Corpus/synthetic/*.json
          (template plans × ambiguity distribution; params stamped per file)
```

**Loop 2 — Real validation set (occasional, manual):**
```
LumeLabel ─hand anchor-label─▶ Corpus/real/*.json (boundaryMode: anchored)
```
Small, slow-growing, never training data — the held-out honesty judge.

**Loop 3 — Score & improve (fast, repeatable, daily driver):**
```
EvaluationHarnessTests ─▶ run pipeline over BOTH corpora ─▶ extended AnalysisEvaluator
   ─▶ report: per-second agreement · boundary error · confusion · by-ambiguity
   ─▶ split readout: synthetic accuracy vs real accuracy
```

- **Phase 1:** AnalyzerImprover optimizes `AnalyzerConfig` + corpus weights against the **synthetic** score;
  watch the **real** score to confirm no overfit. Ship the winning config.
- **Phase 2:** synthetic corpus becomes training data for a learned fusion model (Core ML: per-window
  feature vector from existing extractors → P(phase); Viterbi decode over a learned transition matrix
  replacing hand-tuned ordering/smoothing/ensemble; emits per-second probabilities = native cross-fade
  data). Real corpus stays held-out test.
- **CI:** a subset runs as a regression gate (AI-dependent cases already tagged
  `.enabled(if: ChunkedPhaseAnalyzer.isAvailable)`). Regression = synthetic *or* real accuracy below
  threshold.

## Phasing & sequencing

1. **Spine first:** unify the corpus `CorpusCase` schema + shared SwiftPM module; migrate existing
   `EvaluationCorpus` cases into the file format.
2. **Metrics:** extend `AnalysisEvaluator` with timeline metrics + report struct; wire into
   `EvaluationHarnessTests`.
3. **Generator:** scaffold `Tools/CorpusGenerator/` SwiftPM CLI; few-shot seeding; template plans;
   ambiguity knob; emit synthetic corpus.
4. **Real set:** anchor-label a small real corpus via LumeLabel into `Corpus/real/`.
5. **Phase 1 tuning:** point AnalyzerImprover fitness at synthetic score; validate against real; ship config.
6. **Phase 2 (later):** train learned fusion model once corpus is large enough to beat heuristics on
   held-out real files.
7. **Approach C (later):** on-device personalization from user corrections; export corrections as
   `boundaryMode: anchored` cases back into `Corpus/real/`.

## Key codebase references

- `Ilumionate/HypnosisPhaseAnalyzer.swift` — keyword pipeline; `PhaseSegment` (`:43-44`).
- `Ilumionate/ChunkedPhaseAnalyzer.swift` — alt analyzer; `isAvailable` CI gate.
- `Ilumionate/AIAnalysisModels.swift` — `AIPhaseSegment` (`:240,243`), `HypnosisMetadata.phases` (`:174`).
- `Ilumionate/AnalyzerConfig{,Loader}.swift`, `Ilumionate/AnalyzerConfig/AnalyzerConfig_default.json` — tunable params.
- `Ilumionate/CorpusPhaseKnowledge.swift` — learned weights.
- `IlumionateTests/AnalysisEvaluationMetrics.swift`, `EvaluationCorpus.swift`, `EvaluationHarnessTests.swift` — harness to extend.
- `LumeLabel/`, `Ilumionate/Training/TrainingCorpusManager.swift` (`Documents/TrainingCorpus/`, `AnalyzerDataset/dataset.jsonl`) — real-audio labeling infra.

## Constraints / guardrails

- Generator is **dev-time only** — must not ship in the iOS bundle.
- Watch the "teaching to the test" trap — held-out real corpus is the safeguard.
- Never edit `features.json` unless explicitly asked.
- Modern Swift 6.2 / SwiftUI / `@Observable` conventions.
- Build: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build`.

## Suggested skills for implementation

- `macos-spm-app-packaging` — scaffold the standalone SwiftPM `Tools/CorpusGenerator/`.
- `claude-api` — generator's Claude API calls, with prompt caching for few-shot examples.
- `swift-testing-pro` — extending the evaluator tests.
