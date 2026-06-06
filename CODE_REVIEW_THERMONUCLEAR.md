# Thermo-Nuclear Code Quality Review — Ilumionate (LumeSync)

**Date:** 2026-05-30
**Scope:** Whole codebase, structural (154 Swift files, ~41,300 lines)
**Framework:** [Thermo-Nuclear Code Quality Review](https://github.com/cursor/plugins/blob/main/cursor-team-kit/skills/thermo-nuclear-code-quality-review/SKILL.md) — ambitious about structure, "code judo," design over pragmatism.

---

## Verdict

**Micro-quality is genuinely strong; macro-structure is where the debt lives.**

This codebase is unusually disciplined at the line level. The repository-wide scans found **zero** `as!` force casts, **zero** `try!`, only ~22 force unwraps total, no `ObservableObject`/`@Published`/`@StateObject`, and only one `DispatchQueue` site. Functions are mostly short, documented, and read cleanly. That is the opposite of most codebases this size.

The structural picture is the concern. Logic and types have accreted into a handful of very large files, an 11-singleton service layer creates implicit coupling that the project's own guidelines argue against, and 298 `print()` calls stand in for real logging. Under the thermo-nuclear bar, **the analyzer subsystem has a clear "decompose this first" problem** and there are visible code-judo simplifications being left on the table.

Findings below are ordered by the skill's priority: structural regressions → missed simplification → spaghetti → boundaries → file size → legibility.

---

## 🔴 Blocking-class findings

### B1. `HypnosisPhaseAnalyzer.swift` is a 3,698-line file holding 15 distinct types

This single file ([HypnosisPhaseAnalyzer.swift](Ilumionate/HypnosisPhaseAnalyzer.swift)) is **3.7× the 1,000-line boundary** and is really an entire module wearing one filename. It declares:

| Type | Line | Role |
|------|------|------|
| `WordTimestamp` | 26 | shared data model |
| `HypnosisPhaseAnalyzer` | 46 | the analyzer (huge) |
| `TranscriptAnalysis` | 2268 | result model |
| `TranscriptSectionMetrics` | 2318 | result model |
| `TranscriptWordStatistic` | 2443 | result model |
| `TranscriptPhraseStatistic` | 2450 | result model |
| `HypnosisWaymarkerMatch` | 2457 | result model |
| `HypnosisPhraseEvidenceOrigin` | 2479 | enum |
| `HypnosisPhraseAssociation` | 2485 | model |
| `CuratedHypnosisPhrasePrior` | 2499 | data |
| `CuratedHypnosisPhraseLibrary` | 2507 | static lexicon |
| `HypnosisWaymarkerLexicon` | 2665 | static lexicon |
| `TranscriptFeatureAnalyzer` | 2707 | a *second* ~535-line analyzer |
| `CorpusPhaseKnowledge` | 3242 | model |
| `CorpusPhaseKnowledgeCache` | 3253 | **singleton** |
| `CorpusPhaseKnowledgeBuilder` | 3326 | builder w/ a 143-line `build()` |

This violates the file-size boundary **and** the project's explicit rule ("Break different types up into different Swift files"). The thermo-nuclear response is the literal one: *"this pushes the file past 1k lines — can we decompose this first?"*

**Decompose into a `HypnosisAnalysis/` folder, one type (or cohesive cluster) per file:**
- `WordTimestamp.swift` (it's a *shared* model — see B4, it does not belong in the analyzer's file at all)
- `HypnosisPhaseAnalyzer.swift` (just the analyzer + its nested `PhaseEvidence*` types, [lines 46–~2267](Ilumionate/HypnosisPhaseAnalyzer.swift:46))
- `TranscriptModels.swift` (the `Transcript*` / `Hypnosis*Match` result structs, 2268–2498)
- `CuratedHypnosisPhraseLibrary.swift` + `HypnosisWaymarkerLexicon.swift` (the static data lexicons, 2499–2706)
- `TranscriptFeatureAnalyzer.swift` (2707–3241 — this is its own analyzer, not part of the phase analyzer)
- `CorpusPhaseKnowledge.swift` (model + cache + builder, 3242–end)

Until this split happens, every other improvement in the analyzer is being made inside a file no reviewer can hold in their head.

### B2. The 143-line `CorpusPhaseKnowledgeBuilder.build()` is the spaghetti epicenter

[`build()` at line ~3326](Ilumionate/HypnosisPhaseAnalyzer.swift:3326) is the longest function in the codebase by a wide margin (143 lines vs. the next-longest analyzer function at 76). A 143-line builder that also nests a local `makeSegment` helper is doing several jobs in one scope. This is exactly the "ad-hoc logic that should move into a dedicated abstraction" pattern — extract the windowing, the scoring aggregation, and the segment assembly into named private methods or a small pipeline of steps so `build()` reads as a sequence of intentions, not an implementation dump.

---

## 🟠 Missed simplification ("code judo")

### S1. `LightMoment` construction is copy-pasted with near-identical argument lists

In [SessionGenerator+Strategies.swift](Ilumionate/SessionGenerator+Strategies.swift:171) the phase-generation loop builds `LightMoment` three+ times per segment (base, contour points, hold point), each repeating the same `bilateral: useBilat ? true : nil, bilateral_transition_duration: …, color_temperature: colorTemp` boilerplate. The `useBilat ? true : nil` idiom alone appears 3× in this one function.

**Judo move:** a single private factory on `SessionGenerator` —
```swift
func phaseMoment(at time: TimeInterval, phase: PhaseSegment, progress: Double, config: GenerationConfig) -> LightMoment
```
— collapses the three call sites into `moments.append(phaseMoment(...))` and makes the per-point differences (waveform swap at `segDuration > 120`, ramp duration) the *only* visible variation. This removes moving pieces rather than tidying them.

### S2. Two near-identical `init`s on `HypnosisPhaseAnalyzer`

[Lines 89–102](Ilumionate/HypnosisPhaseAnalyzer.swift:89): `init(config: KeywordPipeline?)` and `init(config: AnalyzerConfig)` both assign the same four stored properties from a resolved config. Funnel one into the other (`convenience`-style delegation, or have the optional initializer build an `AnalyzerConfig` and call the canonical one) so the property-assignment list exists exactly once. As fields get added to the config, the current shape guarantees they'll be updated in one initializer and forgotten in the other.

### S3. Big `switch` statements distributed across phase/frequency mapping

`SessionGenerator+Strategies.swift` (88 `case`s), `HypnosisPhaseAnalyzer.swift` (78), `LightScorePhaseTargeting.swift` (72) all switch on `HypnosisMetadata.Phase`. When the same enum is switched exhaustively in many files, each new phase becomes a multi-file edit. Consider whether per-phase parameters (target frequency, waveform, color temp, intensity, bilateral) belong as **data on the phase** (a `PhaseProfile` table) rather than as parallel switch statements — one canonical lookup instead of N scattered ones.

---

## 🟡 Boundary & ownership problems

### O1. Eleven singletons form an implicit, hard-to-test service graph

`static let shared` declarations exist on: `NowPlayingState`, `AnalysisStateManager`, `PerformanceOptimizer`, `FolderStore`, `AnalysisPreferences`, `TranceHaptics`, `OrbCrashLogger`, `AnalysisProgressStore`, `CorpusPhaseKnowledgeCache`, `SessionHistoryManager`, `TrainingCorpusManager`.

`UnifiedPlayerViewModel` alone reaches into `.shared` **19 times**; `AudioLibraryView` 10×; `AnalysisStateManager` 9×. The project's own SwiftUI guidance is explicit: shared data should flow through `@State` ownership + `@Environment`/`@Bindable` injection, *not* global accessors. Singletons make the dependency graph invisible and the views/view-models hard to unit test (note `AnalysisStateManager` already had to add a second `init` purely "for unit testing" — [line 51](Ilumionate/AnalysisStateManager.swift:51) — which is the tell that the singleton is fighting testability).

This is a large refactor, not a one-liner. The judo path: introduce an `AppEnvironment` (or a few `@Environment` keys) that owns these once at the app root and inject downward. You don't have to do all 11 at once — start with the ones views touch most (`AnalysisStateManager`, `NowPlayingState`, `AnalysisProgressStore`).

### O2. `WordTimestamp` (a shared model) lives inside the analyzer's file

`WordTimestamp` is defined at [line 26 of HypnosisPhaseAnalyzer.swift](Ilumionate/HypnosisPhaseAnalyzer.swift:26) but is consumed across `TechniqueDetector`, `ChunkedPhaseAnalyzer`, and `SessionGenerator`. A foundational shared type owned by one feature file is a canonical-ownership leak — anyone importing it inherits a 3,698-line dependency. Move it to its own `WordTimestamp.swift`.

### O3. `@MainActor @Observable class … : Sendable`

[AnalysisStateManager:25](Ilumionate/AnalysisStateManager.swift:25) declares an explicit `: Sendable` conformance on a `@MainActor` mutable `@Observable` class. `@MainActor` types are already implicitly `Sendable`; the explicit conformance on a class with mutable `var` state (`currentAnalysis`, `analysisQueue`, …) is redundant at best and misleading at worst (it reads as "this is safe to pass across actors" when its safety actually comes from main-actor isolation). Drop the explicit conformance. Worth a sweep for the same pattern elsewhere.

---

## 🟡 File-size boundary (secondary offenders)

Beyond B1, two more files cross 1k lines and should be decomposed before they grow further:

- **[AnalyzerOptimizer.swift](Ilumionate/Training/AnalyzerOptimizer/AnalyzerOptimizer.swift) — 1,337 lines.** Holds `OptimizerProgressCounter` (actor), `OptimizerConcurrencyProfile`, and `AnalyzerOptimizer`. Checkpoint/scorecard persistence (`writeScorecard`, `writeCheckpoint`, `appendScorecardHistory`) is a natural extraction into an `AnalyzerOptimizerPersistence` extension/file.
- **[SessionGenerator+Strategies.swift](Ilumionate/SessionGenerator+Strategies.swift) — 1,055 lines.** Already an extension file; split per content strategy (hypnosis vs. sleep vs. shared phase-targeting helpers) into `SessionGenerator+Hypnosis.swift`, `SessionGenerator+Sleep.swift`, etc.

Approaching-the-line watchlist (decompose opportunistically): `AnalysisStateManager` (871), `UnifiedPlayerViewModel` (791), `LibraryView` (786), `TechniqueDetector` (771).

---

## 🟢 Legibility

### L1. 298 `print()` calls instead of structured logging

`print()` appears 298 times. The codebase already has `os.Logger` available (`OrbCrashLogger` imports `os`), so the canonical tool exists — it's just not used. Top offenders: `SessionValidationExample` (81), `AnalysisStateManager` (35), `AudioManager` (23), `AudioLibraryView+Actions` (21). `print` in a shipping app target is invisible in production, not filterable by level/subsystem, and runs unconditionally on the calling thread. Replace with a shared `Logger` per subsystem.

### L2. `SessionValidationExample.swift` looks like example/scratch code in the app target

[SessionValidationExample.swift](Ilumionate/SessionValidationExample.swift) is self-described as *"Example code… can be run from a command-line tool or in Xcode"* and is 81 of the 298 `print`s. If it's a dev utility it should not be in the shipping target — move it to a tools target, a test target, or delete it. Example code that ships is dead weight a reviewer keeps tripping over.

### L3. SwiftUI views decomposed via computed `some View` properties instead of child `View` structs

`MindMachineView` and `LibraryView` each expose **14** `var x: some View` computed properties; `StreamingBrowserView` 12, `AnalyzerView`/`ProfileSettingsView+Sections` 11. The project guideline is explicit: *"Do not break views up using computed properties; place them into new View structs instead."* Computed-property decomposition keeps the whole view's state in one giant struct (so SwiftUI invalidates more than it needs) and defeats per-subview previews. These same files dominate the deep-nesting scan (MindMachineView 128 lines indented ≥24 spaces, HomeView 111) — a symptom of the same root cause. Extracting real `View` structs fixes legibility *and* the implied render-invalidation cost.

### L4. `GeometryReader` / `UIScreen.main` in 11 files

Guidelines steer toward `containerRelativeFrame()`/`visualEffect()` over `GeometryReader`, and forbid `UIScreen.main.bounds`. 11 files use one or the other (incl. `MindMachineView`, `HomeView`, `UnifiedPlayerViewModel`). Audit each — many `GeometryReader` uses for simple proportional sizing have a modern one-line replacement, and `UIScreen.main` breaks on iPad multitasking/Stage Manager.

---

## What's already good (don't regress it)

- **No force casts, no `try!`, ~22 force unwraps total** across 41k lines — exceptional.
- **No legacy Observation** (`ObservableObject`/`@Published`/`@StateObject` count: 0). The codebase is on `@Observable` + `@MainActor` as the guidelines require.
- **One `DispatchQueue` site** (InAppBrowserView) — the rest is async/await.
- Functions are short and documented; the *content* of the analyzer logic is readable. The problem is purely how it's packaged.

---

## Recommended sequence

1. **Decompose `HypnosisPhaseAnalyzer.swift`** (B1) — split the 15 types into a folder. Pure file moves, behavior-preserving, unblocks everything else. *Do this first.*
2. Move `WordTimestamp` out to its own file (O2) as part of step 1.
3. Split `SessionGenerator+Strategies.swift` and `AnalyzerOptimizer.swift` under 1k (file-size).
4. Extract the `LightMoment` factory (S1) and merge the duplicate inits (S2) — small, high-leverage judo.
5. Refactor `CorpusPhaseKnowledgeBuilder.build()` into named steps (B2).
6. Introduce `os.Logger`, retire `print()`, and remove/relocate `SessionValidationExample` (L1/L2).
7. **Plan** the singleton → `@Environment` migration (O1) — biggest payoff for testability, biggest effort; sequence it deliberately, highest-traffic services first.
8. Convert computed-property sub-views to `View` structs in the worst offenders (L3).

---

*This review intentionally does not approve or block a specific PR — it's a whole-codebase structural pass. Under the thermo-nuclear bar, item B1 alone would block any PR that added to that file without decomposing it.*
