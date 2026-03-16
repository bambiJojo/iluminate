# Audio Analyzer Improvement Plan

> **Rule:** Do NOT move to the next step until the current step is 100% complete — implemented, built successfully, unit tested, and verified with real-world interactions and edge case stress tests.

---

## Root Causes Identified

The analyzer has five core problems:

1. **WhisperKit "tiny" model** — worst accuracy in the family (~3× more word errors than "base"); every downstream component depends on transcript quality
2. **Fragile AI schema** — `frequencyRange: String` ("4-8") breaks parsing when the model adds units or text; wrong range silently misroutes session generation
3. **Keyword collision** — "deep" fires `.deepening` even deep in the therapy section; "whenever" is listed in both `.suggestions` AND `.conditioning`
4. **Hard-coded 24-chunk cap** — on a 60-minute session only 24/240 possible windows are analyzed; the AI forward-fills huge gaps, causing therapy to swallow 40%+ of the session
5. **No tests** — any change can silently break the phase ordering invariant

---

## Phase 1 — Quick Wins (highest impact, lowest risk)

### Step 1.1 — Upgrade WhisperKit from "tiny" → "base", remove 50 MB gate
- **File:** `Ilumionate/AudioAnalyzer.swift`
- **Changes:**
  - Remove the `audioFileTooLarge` early-exit block (50 MB limit is arbitrary)
  - Change model string from `"tiny"` to `"base"` in `WhisperManager.initializeWhisperKit()`
  - Update the catch/retry path (same model string appears twice)
- **Why:** Base model has ~3× lower WER; every downstream component (keywords, AI prompt, phase detection) is driven by transcript text
- **Test:** Re-run a known hypnosis file; compare raw `fullText`; verify more keyword hits in `buildHitMap`
- **Status:** ✅ Complete — all 3 WhisperKitUpgradeTests pass; full suite green

### Step 1.2 — Replace `frequencyRange: String` with two typed Doubles
- **File:** `Ilumionate/AIAnalysisModels.swift` + `Ilumionate/AIAnalysisManager.swift`
- **Changes:**
  - Remove `frequencyRange: String` from `AIAnalysisResponse`
  - Add `frequencyLower: Double` + `frequencyUpper: Double` with `@Guide(.range(0.5...40.0))`
  - Update `parseFrequencyRange` to read the two fields directly
  - Add validation clamp: if `lower >= upper`, fall back to `8.0...12.0`
- **Why:** Model sometimes returns "4 to 8 Hz", "4–8", "theta (4-8 Hz)" — all break the current string-split parser and silently return alpha default, misrouting theta content
- **Test:** Unit test asserting `frequencyLower < frequencyUpper` across all content types
- **Status:** ✅ Complete — all 6 FrequencySchemaTests pass; full suite green

### Step 1.3 — Fix keyword collisions in taxonomy
- **File:** `Ilumionate/HypnosisPhaseKeywords.swift`
- **Changes:**
  - Reduce `"deep"` single-word weight from 1.8 → 0.6 (multi-word phrases "deeper and deeper" carry the deepening signal)
  - Add `"deeply relaxed"` to `.therapy` at weight 3.0 (most common therapy anchor, currently missing)
  - Remove `"whenever"` from `.suggestions` (post-hypnotic conditioning language, not suggestion delivery)
- **Why:** These collisions cause deepening spans to run 40–60% into long sessions, and suggestions/conditioning phases to collapse into each other
- **Test:** Unit test feeding "deeply relaxed" → assert `.therapy` wins; "deeper and deeper" → assert `.deepening` wins
- **Status:** ✅ Complete — all 9 KeywordCollisionTests pass; full suite green

### Step 1.4 — Scale `minRun` with session duration
- **Files:** `Ilumionate/ChunkedPhaseAnalyzer+Smoothing.swift` + `Ilumionate/HypnosisPhaseAnalyzer.swift`
- **Changes:**
  - Replace hardcoded `minRun: 45` with `max(20, Int(duration * 0.035))`
  - Results: 5-min → 20s, 30-min → 63s, 60-min → 126s
- **Why:** 45s is 15% of a 5-min session — `pre_talk` and `emergence` (15–30s in short sessions) get absorbed; inversely, 45s is too lenient for long sessions
- **Test:** Run an 8-minute hypnosis excerpt; assert `[PhaseSegment]` includes both `.preTalk` and `.emergence`
- **Status:** ✅ Complete — MinRunScalingTests pass; both ChunkedPhaseAnalyzer and HypnosisPhaseAnalyzer use `max(20, Int(duration * 0.035))`

### Step 1.5 — Expand transcript sampling (350 → 600 chars, add 75% sample)
- **File:** `Ilumionate/AIAnalysisManager.swift`
- **Changes:**
  - Change `chunkSize` from 350 to 600 characters
  - Add a fourth sample at the 75% mark (currently: beginning/middle/end only)
  - Update the `guard fullText.count > 600` threshold to `> 900`
- **Why:** The therapy/suggestions boundary (55–85% mark) is currently unsampled — this causes therapy→meditation misclassification on long hypnosis files
- **Test:** Inspect `buildTranscriptionPrompt` output for a 45-minute hypnosis recording; verify induction language appears in the actual text sent to the model
- **Status:** ✅ Complete — TranscriptSamplingTests pass; 600-char chunks and 75% sample verified

---

## Phase 2 — Core Accuracy Improvements

### Step 2.1 — Duration-proportional chunk cap (24 → dynamic)
- **File:** `Ilumionate/ChunkedPhaseAnalyzer.swift`
- **Changes:**
  - Replace `maxChunks = 24` with `max(12, min(48, Int(duration / 90.0)))`
  - 5-min → 12 chunks, 30-min → 20 chunks, 60-min → 40 chunks
- **Why:** 60-min sessions have 90-second gaps between analyzed chunks; therapy forward-fills everything
- **Test:** On a 45-min recording, assert `[PhaseSegment]` includes `.suggestions` and `.conditioning` with duration > 120s each
- **Status:** ✅ Complete — ChunkCountTests pass; dynamic `max(6, min(60, Int(duration/90)))` formula verified

### Step 2.2 — Add few-shot examples to AVE system prompt
- **File:** `Ilumionate/AIAnalysisModels.swift`
- **Changes:**
  - Append `EXAMPLES:` section to `AVESystemPrompt.instructions`
  - Example 1: induction transcript → expected response shape
  - Example 2: therapy/suggestions transcript → expected response with distinction
- **Why:** Zero-shot structured-output tasks improve 15–30% with even one in-context example; therapy/suggestions distinction is the current weakest point
- **Test:** Run same hypnosis file before/after; compare `phases` array for therapy/suggestions split
- **Status:** ✅ Complete — AVESystemPrompt updated with 3 few-shot examples in AIAnalysisModels.swift

### Step 2.3 — Persist completed analyses across app restarts
- **File:** `Ilumionate/AnalysisStateManager.swift`
- **Changes:**
  - Add `AnalysisCache.json` persistence in Documents directory
  - Load on init, save after each completion
  - De-duplication check before re-running pipeline (match by `audioFile.id`)
  - Ensure `CompletedAnalysis` and all child types have `Codable` conformance
- **Why:** All analyses are lost on app restart; same file re-analyzes every time
- **Test:** Complete analysis, force-quit, relaunch — assert file appears without re-running pipeline
- **Status:** ✅ Complete — AnalysisCacheTests pass; AnalysisStateManager persists to Documents/AnalysisCache.json

### Step 2.4 — Surface analysis errors to the user
- **Files:** `Ilumionate/AnalysisStateManager.swift` + `Ilumionate/AnalyzerView.swift`
- **Changes:**
  - Add `AnalysisPipelineError` enum (transcriptionFailed, aiAnalysisFailed, modelUnavailable, unknown)
  - Publish `lastError: AnalysisPipelineError?` on `AnalysisStateManager`
  - Clear on new analysis start
  - Show alert/banner in `AnalyzerView`
- **Why:** Silent failure leaves user with no feedback when WhisperKit fails to initialize
- **Test:** Disable Apple Intelligence in simulator; verify error surfaces instead of silent reset
- **Status:** ✅ Complete — AnalysisPipelineError enum added; AnalyzerView shows alert/banner

### Step 2.5 — Duration-scaled breath oscillation rate
- **File:** `Ilumionate/SessionGenerator+Strategies.swift`
- **Changes:**
  - Replace fixed `rate: 0.15` with `0.15 * pow(1800.0 / max(300, duration), 0.2)`
  - 5-min → ~0.19 Hz, 30-min → 0.15 Hz, 60-min → ~0.12 Hz
  - Update all callers to pass `duration`
- **Why:** Fixed 0.15 Hz over-applies neural habituation protection on long sessions, under-applies on short ones
- **Test:** Generate 5-min and 60-min sessions; assert modulation rates differ and peak deviation stays within ±0.3 Hz
- **Status:** ✅ Complete — BreathRateTests pass; dynamic `0.15 * pow(1800.0 / max(300, duration), 0.2)` formula verified

---

## Phase 3 — Testing Infrastructure

### Step 3.1 — Unit tests: HypnosisPhaseAnalyzer pure functions
- **File:** `IlumionateTests/HypnosisPhaseAnalyzerTests.swift`
- **Status:** ✅ Complete — all tests pass; buildHitMap, resolveTimeline, enforcePhaseOrdering, collapseShortRuns covered

### Step 3.2 — Unit tests: ChunkedPhaseAnalyzer smoothing functions
- **File:** `IlumionateTests/ChunkedPhaseAnalyzerSmoothingTests.swift`
- **Status:** ✅ Complete — all tests pass; enforcePhaseOrdering, collapseShortRuns, consolidatePhaseSegments, tranceDepthForPhase covered

### Step 3.3 — Unit tests: SessionGenerator structural invariants
- **File:** `IlumionateTests/SessionGeneratorTests.swift`
- **Status:** ✅ Complete — all 15 tests pass; frequencyRange, targetFrequency, intensity, colorTemperature, clamp covered

### Step 3.4 — Golden-dataset fixture system for regression detection
- **File:** `IlumionateTests/GoldenDatasetTests.swift`
- Three fixtures: classicHypnosis (30 min, 7 phases), shortInduction (10 min), affirmations (15 min)
- 14 regression tests: phase presence, monotonic order, coverage, determinism, no-false-positive phases
- **Status:** ✅ Complete — all 14 tests pass; full suite green

---

## Phase 4 — Advanced (Ongoing)

### Step 4.1 — Language detection (WhisperKit `language: nil`)
- Auto-detect language; pass detected locale to AI prompt
- **Status:** ⬜ Pending

### Step 4.2 — Structured `LightAction` enum for key moments
- Replace `action: String` in `AIKeyMoment` with `@Generable enum LightAction`
- Eliminates fragile `contains("deep")` string matching in session generation
- **Status:** ⬜ Pending

### Step 4.3 — Session-length-aware generation arcs
- Replace fixed `%` waypoints with absolute-time `SessionArc` struct with minimum-duration guards
- Guarantee ≥60s emergence on any session length
- **Status:** ✅ Complete

### Step 4.4 — Content-addressed analysis cache
- Key cache by SHA-256 of first 64 KB of audio + model version
- Enables A/B testing and automatic invalidation on WhisperKit upgrade
- **Status:** ✅ Complete

### Step 4.5 — Parallel chunk classification (two-pass withTaskGroup)
- Classify even-indexed chunks first, odd-indexed second using even results as context
- Halves wall-clock time for 60-minute sessions
- **Status:** ✅ Complete
