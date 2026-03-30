# Analyzer Improvement Pipeline — Design Spec

**Date:** 2026-03-29
**Status:** Approved

## Goal

Build a decoupled, tunable analyzer that plugs into the app and an evolutionary improvement pipeline that iterates on the analyzer's configuration using ground-truth labeled data until output quality converges.

## Constraints

- Foundation Models do not support fine-tuning on device. Improvement must come from prompt engineering, few-shot injection, and numeric parameter optimization.
- WhisperKit transcription is expensive. Cache results per audio file (keyed by SHA256).
- Labeled corpus will be small (5–20 files initially). Population and generation counts must stay small.
- The analyzer must remain a pluggable unit — no UI coupling. Config in, results out.

---

## 1. Architecture

Three independent pieces communicating through files on disk:

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│  Labeling UI     │     │  Improvement Pipeline │     │  App Runtime     │
│  (in-app view)   │────>│  (Xcode test target)  │────>│  (reads config)  │
│                  │     │                        │     │                  │
│  Produces:       │     │  Reads:                │     │  Reads:          │
│  LabeledFile.json│     │  - labeled corpus      │     │  - AnalyzerConfig│
│  per audio file  │     │  - current config      │     │                  │
└─────────────────┘     │                        │     └─────────────────┘
                         │  Produces:             │
                         │  - evolved config      │
                         │  - evaluation report   │
                         └──────────────────────┘
```

**LabeledFile** — JSON sidecar per labeled MP3 in `Documents/TrainingCorpus/`.

**AnalyzerConfig** — single JSON controlling all analyzer parameters. Loaded at startup from `Documents/AnalyzerConfig.json` (trained) or `Bundle/AnalyzerConfig_default.json` (baseline).

**Improvement Pipeline** — Xcode test target. Evolutionary optimizer that evaluates config variants against the labeled corpus and writes the best config + evaluation report to disk.

---

## 2. LabeledFile Format

```json
{
  "version": 1,
  "audioFilename": "mike_mandel_induction.mp3",
  "audioDuration": 1847.5,
  "audioSHA256": "a3f2...",
  "expectedContentType": "hypnosis",
  "expectedFrequencyBand": { "lower": 0.5, "upper": 10.0 },
  "phases": [
    { "phase": "pre_talk", "startTime": 0.0, "endTime": 45.0, "notes": "greeting" },
    { "phase": "induction", "startTime": 45.0, "endTime": 210.0, "notes": "progressive relaxation" },
    { "phase": "deepening", "startTime": 210.0, "endTime": 480.0, "notes": "staircase" },
    { "phase": "therapy", "startTime": 480.0, "endTime": 1200.0, "notes": "passive imagery" },
    { "phase": "suggestions", "startTime": 1200.0, "endTime": 1560.0, "notes": "direct" },
    { "phase": "conditioning", "startTime": 1560.0, "endTime": 1700.0, "notes": "future pacing" },
    { "phase": "emergence", "startTime": 1700.0, "endTime": 1847.5, "notes": "" }
  ],
  "techniques": [
    { "name": "progressive_relaxation", "startTime": 50.0, "endTime": 180.0 },
    { "name": "arm_levitation", "startTime": 300.0, "endTime": 360.0 }
  ],
  "labeledAt": "2026-03-29T10:00:00Z",
  "labelerNotes": "Clear transitions, Ericksonian style"
}
```

`audioSHA256` ties the label to a specific audio file so the pipeline detects if the audio changed.

---

## 3. Labeling UI

Accessed from Settings → "Analyzer Training" behind a developer toggle.

### Screen 1: Corpus Manager

- List of all files in `Documents/TrainingCorpus/`
- Status badge per file: unlabeled / rough / refined
- Import MP3 button (copies into TrainingCorpus directory)
- Tap a file to open the Phase Labeler

### Screen 2: Phase Labeler

**Quick-label mode (first pass):**
- Audio player: play/pause, scrub bar, current time display (mm:ss)
- Row of 7 phase buttons (Pre-talk, Induction, Deepening, Therapy, Suggestions, Conditioning, Emergence)
- Tap a phase button while listening → previous phase ends at current time, new phase starts at current time
- Content type picker, frequency band picker (presets or custom)
- Save button

**Refine mode (second pass):**
- Timeline view showing phases as colored blocks proportional to duration
- Drag phase boundaries left/right to adjust (±1 second precision)
- Tap a phase block to edit type, add notes
- Add/remove technique annotations with start/end markers
- Save button

---

## 4. AnalyzerConfig Format

```json
{
  "version": 1,
  "generation": 0,
  "fitness": 0.0,

  "keywordPipeline": {
    "weights": {
      "pre_talk": { "welcome": 1.0, "comfortable": 0.8, "explain": 0.7, "begin": 0.6 },
      "induction": { "close your eyes": 1.5, "breathe": 1.2, "relax": 1.0, "heavy": 0.9, "letting go": 1.1 },
      "deepening": { "deeper": 1.5, "float": 1.0, "sinking": 1.2, "staircase": 1.3, "drift": 0.9 },
      "therapy": { "imagine": 0.8, "notice": 0.7, "allow": 0.6 },
      "suggestions": { "you will": 1.5, "from now on": 1.4, "whenever": 1.2, "your subconscious": 1.3 },
      "conditioning": { "future": 1.0, "carry with you": 1.1, "remember this": 1.0, "anchor": 0.9 },
      "emergence": { "wide awake": 1.5, "open your eyes": 1.4, "coming back": 1.2, "alert": 1.0 }
    },
    "contextWindowSeconds": 5,
    "smoothingWindowSize": 5,
    "minimumPhaseDurationSeconds": 45,
    "collapseThresholdFraction": 0.035
  },

  "chunkedAnalyzer": {
    "chunkDurationSeconds": 15.0,
    "chunkOverlapSeconds": 5.0,
    "minChunks": 6,
    "maxChunks": 60,
    "systemInstructions": "You are a hypnosis session analyst...",
    "fewShotExamples": [
      {
        "text": "Close your eyes and breathe slowly...",
        "position": 0.08,
        "correctPhase": "induction"
      }
    ]
  },

  "prosody": {
    "speechRateWindowSeconds": 3.0,
    "pauseThresholdSeconds": 1.0,
    "deliberatePauseMinSeconds": 3.0,
    "musicOnlyPauseMinSeconds": 5.0
  },

  "techniqueDetection": {
    "sensitivityThreshold": 0.5,
    "minConfidence": 0.3
  },

  "sessionGeneration": {
    "frequencyBands": {
      "hypnosis": { "lower": 0.5, "upper": 10.0 },
      "meditation": { "lower": 4.0, "upper": 12.0 },
      "affirmations": { "lower": 9.0, "upper": 11.0 },
      "music": { "lower": 8.0, "upper": 18.0 }
    },
    "transitionSmoothingSeconds": 5.0,
    "intensityCurve": "gradual"
  }
}
```

The app ships with `AnalyzerConfig_default.json` in the bundle. A trained version in `Documents/` takes precedence.

---

## 5. Improvement Pipeline (Evolutionary Loop)

Runs as an Xcode test target.

### Loop Structure

```
Load labeled corpus + current config
         │
         ▼
   Generation 0: seed population (current config + N random mutations)
         │
         ▼
   Evaluate: run analyzer on every labeled file per config, score vs truth
         │
         ▼
   Select top 30%, mutate to fill population, crossover top 2
         │
         ▼
   Generation N+1 (repeat until plateau or max generations)
         │
         ▼
   Write best config + evaluation report
```

### Fitness Function

```
fitness = (0.25 × contentTypeAccuracy)
        + (0.25 × phaseBoundaryScore)
        + (0.20 × phasePresenceScore)
        + (0.10 × phaseOrderScore)
        + (0.10 × frequencyRangeScore)
        + (0.10 × sessionValidityScore)
```

**`phaseBoundaryScore`** (new): for each truth boundary, find nearest detected boundary. Score = `1.0 - (avgErrorSeconds / toleranceSeconds)` clamped to 0. Tolerance: 30 seconds initially.

### Mutation Operators

| Parameter type | Strategy |
|---|---|
| Keyword weights | Gaussian perturbation ±20% |
| Timing thresholds | Gaussian perturbation ±30% |
| Integer params | Random ±1 or ±2 |
| Frequency bands | Shift ±1 Hz |
| System instructions | Swap/insert/remove sentences from prompt variant bank |
| Few-shot examples | Add/remove/replace from labeled corpus |
| Sensitivity thresholds | Gaussian perturbation ±15% |

### Crossover

Randomly select each section (keyword, chunked, prosody, technique, sessionGen) from one parent or the other. Keeps sections internally coherent.

### Pipeline Parameters

- Population: **10**
- Generations: **20** (early stop after 5 generations with no improvement)
- Elitism: **top 3** survive unchanged
- Mutation rate: **0.8**
- Foundation Models flag: optional. Run keyword-only for fast iterations, full AI for final pass.

### Caching

WhisperKit transcriptions cached per file (keyed by SHA256). Transcription runs once per file ever. Keyword pipeline evaluates in milliseconds. Foundation Models evaluation is the bottleneck — the optional flag enables fast/slow modes.

### Output

Written to `Documents/TrainingOutput/`:

1. `AnalyzerConfig_gen{N}.json` — best config, ready for app bundle
2. `EvaluationReport_gen{N}.json` — per-file scores, per-metric breakdown, generation fitness curve, which mutations helped most

---

## 6. App Integration — Config Loading

### Priority Order

1. `Documents/AnalyzerConfig.json` (trained version)
2. `Bundle/AnalyzerConfig_default.json` (shipped baseline)

### Refactor

All analyzers receive config at init instead of using hardcoded constants:

```swift
struct HypnosisPhaseAnalyzer {
    let config: AnalyzerConfig.KeywordPipeline

    func analyze(segments:, duration:) -> [PhaseSegment] {
        // reads config.contextWindowSeconds, config.weights, etc.
    }
}
```

Same pattern for `ChunkedPhaseAnalyzer`, `ProsodyAnalyzer`, `TechniqueDetector`, `SessionGenerator`.

`AnalyzerConfigLoader` handles the load-with-fallback logic.

---

## 7. File Layout

```
Ilumionate/
  AnalyzerConfig/
    AnalyzerConfig.swift            // Codable model
    AnalyzerConfigLoader.swift      // load from Documents or Bundle
    AnalyzerConfig_default.json     // shipped baseline
  Training/
    LabeledFile.swift               // Codable model
    TrainingCorpusManager.swift     // CRUD for labeled files
    CorpusManagerView.swift         // list of labeled files
    PhaseLabelingView.swift         // quick-label + refine UI

IlumionateTests/
  Training/
    EvolutionaryOptimizer.swift     // population, mutation, crossover, selection
    FitnessEvaluator.swift          // extended scoring with boundary accuracy
    MutationOperators.swift         // per-parameter-type mutation strategies
    PipelineRunner.swift            // orchestrates generations, caching, reporting
    EvolutionaryPipelineTests.swift // entry point to run the pipeline
```
