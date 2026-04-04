# Ilumionate Remediation Plan

## Goal

Fix the architecture, data-flow, concurrency, and security issues identified in `code_review_issues.json` without destabilizing the app during the transition.

## Guiding Principles

- Prefer narrow, reversible refactors over broad rewrites.
- Move ownership boundaries before changing behavior.
- Separate UI isolation from background work explicitly.
- Keep one source of truth per domain.
- Maintain a green build after each phase.

## Success Criteria

- Non-UI services no longer depend on default `MainActor` isolation.
- Audio analysis, content analysis, and session generation run off the UI actor by design.
- `AudioFile` and streaming metadata have a single observable source of truth.
- Streaming analysis is either real, deterministic, or clearly gated off.
- Secrets are stored in Keychain instead of `UserDefaults`.
- Current compiler concurrency warnings are removed or intentionally documented.

## Constraints

- The app currently builds successfully and that should remain true after every phase.
- The codebase is already heavily invested in `@Observable`, singleton state, and `UserDefaults`.
- The target currently relies on `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so removing that too early will create a large blast radius.

## Execution Order

### Phase 0: Baseline and Guardrails

Purpose: create a safe starting point before touching isolation or state ownership.

- [ ] Save the current warning baseline from `xcodebuild` and treat it as a regression budget.
- [ ] Add a short architecture note defining the intended ownership model:
  - UI state: `@MainActor`
  - domain services: explicit actor or nonisolated
  - persistence: repository/store layer
  - models: value types without hidden persistence side effects
- [ ] Create a tracked list of concurrency warnings to eliminate:
  - `AudioLightSyncPlayer.swift`
  - `ProsodyAnalyzer.swift`
  - `TechniqueDetector.swift`
  - `ClosedRange+Codable.swift`
- [ ] Add smoke tests around analysis queue behavior, persisted `AudioFile` updates, and streaming settings persistence before refactoring.

Verification gate:

- `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- Existing analysis and playback tests still pass.

### Phase 1: Remove the Most Dangerous Fake or Insecure Behavior

Purpose: eliminate misleading production behavior before deeper refactors.

#### 1.1 Streaming feature safety

- [ ] Decide one of these paths explicitly:
  - Disable streaming session generation in production UI until real analysis exists.
  - Keep it enabled, but rename it as heuristic generation and make it deterministic.
- [ ] Remove random outputs from `StreamingAnalyzer.analyzeAudioCharacteristics`.
- [ ] Remove the fake `AIContentAnalyzer.analyzeContent(from:data:)` implementation or rename it to a heuristic fallback.
- [ ] Change `StreamingManager.analyzeAndCreateSession` to persist the exact analysis used to generate the session.

Files:

- `Ilumionate/StreamingAnalyzer.swift`
- `Ilumionate/StreamingManager.swift`
- any UI entry points exposing streaming analysis

Acceptance criteria:

- The same streaming track produces the same analysis/session output for the same inputs.
- No production code path claims to do AI analysis while returning fixed placeholder data.

#### 1.2 Secrets handling

- [ ] Replace `UserDefaults` storage for SoundCloud client ID, secret, and token with Keychain-backed storage.
- [ ] Keep only non-sensitive UI preferences in `UserDefaults`.
- [ ] Add migration logic:
  - read old values once
  - move to Keychain
  - delete old defaults

Files:

- `Ilumionate/StreamingSettingsView.swift`
- `Ilumionate/SoundCloudService.swift`
- new `KeychainStore` or equivalent helper

Acceptance criteria:

- No client secret or access token remains in `UserDefaults`.

Verification gate:

- build succeeds
- manual auth flow still works
- migration from old defaults path succeeds in a test or debug harness

### Phase 2: Introduce Explicit State Ownership

Purpose: fix the hidden data flow problems before touching target-wide actor settings.

#### 2.1 Audio library source of truth

- [ ] Create an `AudioLibraryStore` or repository that owns:
  - in-memory `[AudioFile]`
  - persistence to disk or `UserDefaults`
  - updates to analysis/transcription metadata
- [ ] Update `ContentView`, `AudioLibraryView`, `LibraryView`, `StreamingBrowserView`, and `AnalysisStateManager` to use that store instead of direct `UserDefaults` mutation.
- [ ] Remove `persistAnalysisToAudioFiles` from `AnalysisStateManager`.

Files:

- `Ilumionate/ContentView.swift`
- `Ilumionate/AnalysisStateManager.swift`
- `Ilumionate/AudioLibraryView*.swift`
- `Ilumionate/LibraryView.swift`
- `Ilumionate/StreamingBrowserView.swift`
- new store/repository file

Acceptance criteria:

- Analysis completion updates visible UI state without reloading the root view.
- `AudioFile` persistence is owned by exactly one component.

#### 2.2 Streaming metadata ownership

- [ ] Remove the `AudioFile.streamingTrack` computed property side effects.
- [ ] Store streaming metadata in the same repository/store layer as `AudioFile`.
- [ ] Make `AudioFile` a pure value model again.

Files:

- `Ilumionate/StreamingManager.swift`
- `Ilumionate/AudioFile.swift`
- new repository/store file

Acceptance criteria:

- Reading a model does not perform hidden persistence I/O.

Verification gate:

- library and analysis UI refresh correctly from one store
- no direct `UserDefaults.standard` writes remain in analysis/domain code

### Phase 3: Untangle Service Isolation From UI Isolation

Purpose: make the architecture honest before removing global MainActor defaults.

#### 3.1 Redefine service protocols

- [ ] Remove `@MainActor` from:
  - `AudioTranscribingService`
  - `ContentAnalyzingService`
  - `SessionGeneratingService`
- [ ] Split progress reporting from work execution if needed:
  - service work runs off-main
  - UI-facing progress adapters publish on `MainActor`

Files:

- `Ilumionate/AnalysisPipelineProtocols.swift`
- `Ilumionate/AudioAnalyzer.swift`
- `Ilumionate/AIContentAnalyzer.swift`
- `Ilumionate/SessionGenerator.swift`

Acceptance criteria:

- Service protocols express background-safe work by default.
- UI state updates remain on `MainActor`, but heavy processing does not.

#### 3.2 Move generation and analysis orchestration off MainActor

- [ ] Make `AnalysisPipeline` non-UI by default.
- [ ] Remove `MainActor.run` from `AnalysisCoordinator.generateLightSession`.
- [ ] Introduce a dedicated worker actor or nonisolated service for session generation.
- [ ] Ensure progress updates are forwarded back to UI state explicitly.

Files:

- `Ilumionate/AnalysisPipeline.swift`
- `Ilumionate/AnalysisStateManager.swift`
- `AudioLightScoreGenerator.swift`
- `Ilumionate/SessionGenerator.swift`

Acceptance criteria:

- The pipeline coordinator no longer requires MainActor isolation.
- Session generation and analysis do not block the UI actor.

Verification gate:

- build succeeds
- analysis queue still works end to end
- no regressions in session generation output

### Phase 4: Fix Structured Concurrency and Cancellation Semantics

Purpose: make long-running work predictable and cancellable.

#### 4.1 Replace detached work where structure is required

- [ ] Replace `Task.detached` in `AnalysisPipeline.runParallelAnalysis` with `async let` or `withThrowingTaskGroup`.
- [ ] Ensure prosody work cancels automatically when the enclosing pipeline fails or is cancelled.

Files:

- `Ilumionate/AnalysisPipeline.swift`

#### 4.2 Fix timer/task capture warnings and actor leaks

- [ ] Refactor `AudioLightSyncPlayer` timer closure to avoid captured `self` in concurrently executing code.
- [ ] Refactor `ProsodyAnalyzer` so all helper contexts and called dependencies are truly nonisolated.
- [ ] Make `AnalyzerConfigLoader.load()` safe to call from nonisolated analysis code, or inject config earlier.

Files:

- `AudioLightSyncPlayer.swift`
- `Ilumionate/ProsodyAnalyzer.swift`
- `Ilumionate/TechniqueDetector.swift`
- `Ilumionate/AnalyzerConfig/AnalyzerConfigLoader.swift`
- `Ilumionate/HypnosisPhaseAnalyzer.swift`

Acceptance criteria:

- Current concurrency warnings from these files are removed.

Verification gate:

- build succeeds with fewer warnings than the baseline
- cancellation tests pass for queue analysis and playback-related timers

### Phase 5: Remove Global MainActor Default Isolation

Purpose: finish the architecture cleanup once code paths are explicitly isolated.

- [ ] Change the target away from `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- [ ] Annotate only genuine UI-facing types with `@MainActor`.
- [ ] Rebuild and fix resulting isolation diagnostics category by category:
  - UI models/views
  - analysis services
  - playback services
  - persistence/repositories
- [ ] Reassess `Sendable` annotations after boundaries are explicit.

Files:

- `Ilumionate.xcodeproj/project.pbxproj`
- all types surfaced by compiler diagnostics

Acceptance criteria:

- The app builds without relying on global MainActor default isolation.
- Remaining `@MainActor` annotations are intentional and justified by UI ownership.

Verification gate:

- full app build succeeds
- concurrency warnings are materially reduced or eliminated

### Phase 6: Cleanup and Hardening

Purpose: remove technical debt created by the old architecture.

- [ ] Delete `ClosedRange+Codable.swift`.
- [ ] Remove stale comments that claim code is background-safe when it is not.
- [ ] Add targeted tests for:
  - analysis queue resume and cancellation
  - repository update propagation
  - streaming analysis determinism
  - Keychain migration
- [ ] Add a short architecture README describing:
  - app state stores
  - analysis worker boundaries
  - persistence ownership
  - security-sensitive storage rules

Acceptance criteria:

- No misleading compatibility shims or contradictory comments remain.
- The repo has a documented architecture that matches the code.

## Recommended Work Breakdown

### Track A: Immediate risk reduction

1. Secure credentials.
2. Remove fake/random streaming behavior or gate the feature.
3. Remove hard-coded persisted analysis mismatch in streaming.

### Track B: State ownership

1. Add `AudioLibraryStore`.
2. Route analysis completion through the store.
3. Remove hidden `UserDefaults` model side effects.

### Track C: Concurrency architecture

1. Redefine service protocols.
2. Move pipeline/generation off MainActor.
3. Replace detached work and fix warnings.
4. Remove target-wide MainActor default isolation.

## Risks

- Removing default MainActor isolation too early will produce a noisy diagnostic burst and slow the refactor.
- Changing analysis persistence before adding a shared store could break library refresh behavior.
- Refactoring generation and playback code together would be too much surface area at once.

## Recommended Sequence for Actual Execution

1. Phase 1
2. Phase 2
3. Phase 3
4. Phase 4
5. Phase 5
6. Phase 6

This order reduces user-facing risk first, then fixes ownership, then fixes concurrency architecture, then removes the global isolation crutch.

## Definition of Done

- Review findings in `code_review_issues.json` are either fixed, intentionally deferred with rationale, or reclassified.
- The project builds cleanly with explicit isolation boundaries.
- Streaming analysis behavior is no longer misleading.
- Secrets are stored securely.
- The state model is unified and observable without hidden persistence side effects.
