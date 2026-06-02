# Corpus Generator Subsystem — Design Spec

**Date:** 2026-06-02
**Status:** Approved (brainstorming complete) — ready for implementation planning
**Parent spec:** `docs/superpowers/specs/2026-05-31-phase-classifier-training-design.md` (§3 — the generator)
**Prerequisite (landed):** `docs/superpowers/plans/2026-05-31-phase-eval-harness.md` (corpus schema + timeline metrics, commits `a77f6ed`→`2c60aa1`)

## Problem

The phase-classifier training plan put a ground-truth corpus schema and timeline metrics into the test
harness, but there is **no way to generate synthetic corpus data at scale**. Today `Corpus/synthetic/` is
empty; only hand-written fixtures exist. Without a generator, config-tuning and (later) a learned model
have nothing to chase. This subsystem is parent-spec §3: a **dev-time CLI that emits synthetic
`CorpusCase` JSON** with exact, free boundary truth.

## Goals

1. Generate schema-valid synthetic corpus cases the **existing** harness can load and score with no harness
   changes.
2. Author each case **one phase block at a time** so boundary truth is exact by construction (parent §3b).
3. Share the corpus schema between the CLI and the test harness via a **single source of truth** (no drift).
4. Seed realistic style from **real labeled transcripts** when available; degrade gracefully to zero-shot.
5. Keep it **dev-time only** — never shipped, never run per-CI, no network in unit tests.

## Non-goals

- TTS / synthetic *audio* (parent spec non-goal — the classifier reads transcripts).
- The full archetype library, full ambiguity distribution, and bulk generation — those are **follow-up
  plans** built on top of this proven tracer bullet.
- Converting the two real labeled files into `Corpus/real/` anchored cases — free later, not on the
  tracer-bullet critical path.
- Editing `features.json` (project rule).

## Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Schema sharing | **Extract shared `CorpusKit` SwiftPM module** | Single source of truth imported by CLI + test target + app; eliminates drift (parent §2). |
| Few-shot seeding | **Optional, built now** | Real label files are available; seed path active when present, zero-shot fallback when absent. |
| First scope | **Tracer-bullet end-to-end** | One archetype, one ambiguity default; prove the whole pipe before widening. |
| Package location | **New package under `Tools/CorpusGenerator/`** | Isolates the subsystem; leaves the root `Package.swift` and existing tooling untouched (matches parent §3 path). |
| Phase enum | **Move `TrancePhase` into `CorpusKit`** | Already standalone/platform-agnostic; `HypnosisMetadata.Phase` is `typealias Phase = TrancePhase` (`AudioFile.swift:222`) so the lift is clean. |
| API access | **`URLSession` over Anthropic Messages API** | No official Swift SDK; thin client per the `claude-api` skill, key from `ANTHROPIC_API_KEY`. |
| Cost control | **Few-shot seeds in prompt-cache prefix; manual dev-time runs only** | Identical prefix across calls → cheaper; never per-CI. |
| Offline testability | **`--dry-run` stub responder** | Unit tests exercise plan/assembly with no network or API key. |

## Architecture & build topology

A new self-contained SwiftPM package with **two targets**:

```
Tools/CorpusGenerator/
  Package.swift                    # platforms: .macOS(.v14) ; no external deps (URLSession only)
  Sources/
    CorpusKit/                     # shared library, platform-agnostic (Foundation only)
      TrancePhase.swift            #   MOVED from Ilumionate/ (single source of truth)
      CorpusCase.swift             #   MOVED from IlumionateTests/Corpus/ (DTOs + conversions)
      CorpusLoader.swift           #   MOVED from IlumionateTests/Corpus/ (source-relative loader)
    CorpusGenerator/               # the CLI executable (macOS dev tool, never ships)
      main.swift
      CLIOptions.swift
      ClaudeClient.swift
      PhasePlan.swift
      SeedLibrary.swift
      SessionAssembler.swift
  Tests/CorpusGeneratorTests/      # offline unit tests (assembler/plan/seed — no network)
```

**Single source of truth.** `TrancePhase` and the corpus DTOs move into `CorpusKit`. `CorpusKit` is added to
`Ilumionate.xcodeproj` as a **local package dependency** and linked to three existing targets: the app
(`Ilumionate`), `IlumionateTests`, and `LumeLabel`. The old `Ilumionate/TrancePhase.swift` and
`IlumionateTests/Corpus/{CorpusCase,CorpusLoader}.swift` are deleted and replaced with `import CorpusKit`.
The app keeps its `typealias Phase = TrancePhase` shim so the 8 files referencing `TrancePhase` do not churn.

**Why not the root `Package.swift`.** That manifest declares the iOS app target and is wired into existing
tooling; isolating the new subsystem under `Tools/` avoids perturbing it and matches the parent spec path.

**Risk — Xcode package linking.** Linking a local SwiftPM package into Xcode targets is the one mechanical
risk (this project uses synchronized groups and is sensitive to target membership). Mitigation: make the
extraction + linking the **first plan task**, gated by a green `xcodebuild ... -scheme Ilumionate build` and
a green `IlumionateTests` run **before** any generator logic is written. **Fallback** (only if linking
proves intractable): keep `TrancePhase` in the app and have the test target compare predicted vs. truth via
`rawValue` bridge — this reintroduces drift and is the explicit non-preferred path.

## Generator internals

Assembles a session one phase block at a time so boundary truth is exact and free.

- **`PhasePlan` — template + variation.** A plan is an ordered `[(phase: TrancePhase, durationSec: Double)]`.
  Tracer bullet ships **one archetype**: `preTalk → induction → deepening → therapy → emergence`, with block
  durations randomized within sane per-phase ranges. (Archetype *library* is a follow-up.)
- **`SeedLibrary` — few-shot, optional.** Reads `~/Documents/TrainingCorpus/` label files + their
  SHA-keyed cached transcripts (`AnalyzerDataset/cache/transcripts/<sha>.json`), slices each transcript by
  the labeled phase anchors, and yields *real per-phase excerpts*. These populate the prompt-cache prefix.
  Absent/empty dir → zero-shot with hand-written style guidance.
- **`ClaudeClient`.** Thin `URLSession` wrapper over the Anthropic Messages API. Key from
  `ANTHROPIC_API_KEY`. System prompt + few-shot seeds as a cached prefix; one request per phase block
  ("write ~90s of deepening transitioning toward therapy, in this style"). Model + temperature are flags.
- **`SessionAssembler`.** Places each returned block at its computed `[start, end)`, splits block text into
  `CorpusSegment`s with timestamps, and emits one `CorpusCase` (`source: .synthetic`,
  `boundaryMode: .exact`, stamped `ambiguityLevel`). Because the assembler owns placement, `truth` spans are
  exact by construction.
- **`main.swift` / `CLIOptions`.** Flags: `--out` (default `Corpus/synthetic/`),
  `--ambiguity {low|medium|high}` (default `low`), `--count`, `--seeds <dir>`, `--model`, `--dry-run`. Each
  emitted file stamps its generation params (plan, ambiguity, seed-set id, model) for reproducibility.

## Data sources (verified on disk)

For each of the two labeled files in `~/Documents/TrainingCorpus/`:

- Label JSON (`<uuid>.json`): `phases[]` = `{ phase: <rawValue>, startTime, endTime }` (ground-truth
  anchors), plus `audioDuration`, `expectedContentType`, `expectedFrequencyBand`.
- Cached transcript (`AnalyzerDataset/cache/transcripts/<sha256>.json`): `transcription` =
  `{ fullText, segments[], duration, locale }`; segment shape matches `AudioTranscriptionSegment`.

Joined by `audioSHA256`, these give per-phase real text for seeding (and, later and for free, the first
`Corpus/real/` anchored cases).

## Data flow (tracer bullet)

```
SeedLibrary (2 real files, optional)
        │  cached prefix
        ▼
PhasePlan(classic) ──block──▶ ClaudeClient ──text──▶ SessionAssembler
                                                          │
                                                          ▼
                                          Corpus/synthetic/synth-*.json   (one valid CorpusCase)
                                                          │
                                                          ▼
              EXISTING harness: CorpusLoader → analyzer → PhaseTimelineEvaluator → score
```

## Definition of done (tracer bullet)

1. `CorpusKit` extracted; app + `IlumionateTests` + `LumeLabel` build green importing it; existing tests
   still pass.
2. `swift run corpus-gen --dry-run` produces one schema-valid `Corpus/synthetic/*.json` offline (no API
   key, no network).
3. With `ANTHROPIC_API_KEY` set, a real run produces a genuine synthetic case.
4. The existing `EvaluationHarnessTests` loads and scores the generated file with **no harness code change**.

## Deferred to follow-up plans

- Archetype template library (fractionation-heavy, erotic, brainwashing, etc.).
- Full ambiguity distribution + bulk generation.
- Converting the two real labeled files into `Corpus/real/` anchored honesty-judge cases.
- Phase-1 AnalyzerImprover tuning against the synthetic score (parent spec step 5).

## Constraints / guardrails

- Generator is **dev-time only** — must not ship in any app bundle; no network in unit tests.
- `ANTHROPIC_API_KEY` from environment only — never hardcoded.
- Watch the "teaching to the test" trap — the held-out real corpus stays the safeguard (parent spec).
- Never edit `features.json` unless explicitly asked.
- Swift 6.2 / modern concurrency; `async`/`await` over closures.
- Build: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build`;
  package: `swift build` / `swift test` inside `Tools/CorpusGenerator/`.

## Key references

- `Ilumionate/TrancePhase.swift` — phase enum to move into `CorpusKit`.
- `Ilumionate/AudioFile.swift:222` — `typealias Phase = TrancePhase`.
- `IlumionateTests/Corpus/{CorpusCase,CorpusLoader,PhaseTimelineEvaluator}.swift` — landed schema/loader/metrics.
- `IlumionateTests/EvaluationHarnessTests.swift` — `KeywordPipelineEvaluationTests` (the consumer).
- `AnalyzerImprover/` — precedent dev-time CLI that mirrors model types locally.
- `~/Documents/TrainingCorpus/` — two real label files + SHA-keyed transcript cache (seed source).

## Suggested skills for implementation

- `macos-spm-app-packaging` — scaffold the `Tools/CorpusGenerator/` package.
- `claude-api` — `ClaudeClient` Messages API calls with prompt caching for the few-shot prefix.
- `swift-testing-pro` — offline unit tests for plan/seed/assembler.
- `swift-concurrency` — `async`/`await` client + Swift 6 isolation.
