# Phase Feature Extraction & Dataset Export — Design

**Status:** Approved design (2026-06-10). First sub-project of the Phase 2 "learned fusion model" track.
**Scope:** Build per-second feature-vector extraction from the existing analyzer feature extractors, plus a dataset exporter that writes a training-ready CSV from the labeled corpus. The model and training pipeline are **out of scope** for this sub-project.

---

## 1. Context

The phase-training plan's Phase 2 replaces the analyzer's hand-tuned feature fusion with a learned classifier (per-window `P(phase)` → Viterbi over a learned transition matrix). That work is **data-blocked**: only ~2 real labeled sessions plus a few fixtures exist today. Rather than train prematurely, we build the foundation every later step needs and that is valuable regardless of data volume: turning labeled corpus cases into `(features, label)` rows.

Key facts established before this design:
- `CorpusCase` carries only transcripts (text + timestamps), **not audio**. Prosody/audio-texture features cannot be derived from it.
- The relevant feature extractors are app-target Swift: `HypnosisPhaseAnalyzer.buildHitMap`, `TranscriptFeatureAnalyzer`, `TechniqueDetector`, plus trivial position.
- The harness grades per-second (`PhaseTimelineEvaluator`); the plan's classifier is per-second. Per-second is therefore the natural extraction unit.

## 2. Goals

- A reusable, deterministic **`PhaseFeatureExtractor`** (app target) producing a per-second feature vector from a transcription, using the same extractors the analyzer uses — so training and inference features match.
- A **`PhaseDatasetExporter`** (test-target dev harness) that writes a training-ready CSV from the labeled corpus.
- Unit + export tests.

### Non-goals (later sub-projects)
- Audio/prosody features (no audio in corpus).
- The model, training pipeline, Core ML conversion, learned transition matrix.
- Runtime integration of any model into the analyzer.
- Corpus growth (synthetic generation at scale, more real labeling).

## 3. Architecture

### 3a. `PhaseFeatureExtractor` (app target — `Ilumionate/Training/`)
Given an `AudioTranscriptionResult`, precompute per-second signals **once** (build the keyword hit-map, the transcript analysis, technique evidence), then expose `featureVector(at second: Int) -> PhaseFeatureVector`. Deterministic and side-effect free. This same type is what the eventual model calls at inference, guaranteeing train/infer parity.

`PhaseFeatureVector` is an ordered, named numeric vector (stable column order) plus a way to render its values and header.

### 3b. `PhaseDatasetExporter` (test target — `IlumionateTests/Corpus/`)
Loads `CorpusLoader.load("fixtures") + load("synthetic") + load("real")`, keeps truth-bearing cases, and for each **labeled** second emits one CSV row via the extractor. Gray-zone (unlabeled) seconds are skipped. Writes `Corpus/dataset/phase-features.csv`.

### 3c. Data flow
```
Corpus/* (CorpusCase)
  → AudioTranscriptionResult (from CorpusCase.transcriptionSegments)
  → PhaseFeatureExtractor.precompute()
  → for second in 0..<Int(ceil(duration)):
       truthPhase(at: second) ?? continue        // skip gray zones
       row = featureVector(at: second) + label
  → CSV (header + rows) → Corpus/dataset/phase-features.csv
```

## 4. Row schema (one row per labeled second)

| Group | Columns | Source |
|---|---|---|
| Trace (non-feature) | `case_id`, `second` | `CorpusCase.id`, loop index |
| Position | `position` | `second / duration`, 0–1 |
| Keyword hit-map | `kw_<phase>` × 11 | `buildHitMap`[second][phase] for `orderedHypnosisPhases` |
| Transcript features | `tf_*` | `TranscriptFeatureAnalyzer` section metrics at `second` |
| Technique evidence | `tech_*` | `TechniqueDetector` evidence at `second` |
| Label | `label` | truth phase rawValue at `second` |

- The exact `tf_*` and `tech_*` columns are enumerated from the public fields of `TranscriptSectionMetrics` and the technique evidence map **during implementation** — they are not invented here. Column order is fixed and stable.
- `case_id` and `second` are written for traceability and train/val splitting; they are excluded from the feature set used for training.
- Format: CSV with a header row. Universal for CreateML, coremltools, and sklearn.

## 5. File layout

| File | Target | Purpose |
|---|---|---|
| `Ilumionate/Training/PhaseFeatureExtractor.swift` | app | extractor + `PhaseFeatureVector` |
| `IlumionateTests/Corpus/PhaseFeatureExtractorTests.swift` | test | unit tests |
| `IlumionateTests/Corpus/PhaseDatasetExportTests.swift` | test | export harness + shape assertions |
| `Corpus/dataset/phase-features.csv` | output | **gitignored** (derived, regenerable, transcript-derived) |

Add `Corpus/dataset/*.csv` to `.gitignore`.

## 6. Error handling & edge cases

- **Gray-zone / no-truth second** → skipped (it is unlabeled, not a class).
- **Empty transcript** → keyword/feature signals are zeros; the row is still valid and emitted for labeled seconds. A case with empty `truth` is skipped entirely.
- **Determinism** → stable column order, cases sorted by id, integer-second iteration; identical input yields identical CSV.
- **Duration rounding** → iterate `0..<Int(ceil(duration))`, consistent with the harness's bucketing.

## 7. Testing

- **Unit (`PhaseFeatureExtractorTests`):** feed a known keyword-dense transcript (e.g. the induction/deepening fixture text); assert specific feature values — `kw_induction > 0` in the induction region, `position` monotonically increasing, vector width constant across seconds, header matches value count.
- **Export (`PhaseDatasetExportTests`):** run over the fixtures; assert a well-formed CSV — header present, row count equals the number of labeled seconds across truth-bearing cases, every `label` parses to a valid `TrancePhase`, no row falls in a gray zone, and the file re-parses into the same row count.

## 8. Success criteria

- `PhaseFeatureExtractor` returns a fixed-width, deterministic per-second vector reusing the real extractors.
- `phase-features.csv` is produced from the labeled corpus, gray zones excluded, and validated by tests.
- All new tests green; no regression to existing suites.

## 9. Open questions

None. Exact `tf_*`/`tech_*` columns are deferred to implementation (read from the extractor APIs) by design, not left ambiguous.
