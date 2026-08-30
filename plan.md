# LumeSync (Ilumionate) — Unified Development Plan

> Consolidated from all planning documents. Last updated: 2026-08-26.

## Where documentation lives

| Path | Contents | Tracked? |
|---|---|---|
| `plan.md` | This file — status and open work, the source of truth | yes |
| `ERRORS.md` | Deferred/known errors, dated, with status | yes |
| `CLAUDE.md` | Architecture, conventions, build and test commands | yes |
| `APP_STORE_RELEASE_CHECKLIST.md` | Release source of truth | yes |
| `docs/superpowers/{plans,specs}/` | Current design docs (2026-08 onward) | yes |
| `docs/research/` | Research write-ups | yes |
| `docs/archive/superpowers/` | Historical design docs (pre-2026-08) | **no** — local only |
| `doc/` | Reference audio and bulk source media | **no** — local only |

`docs/archive/` was consolidated from the old `/doc/superpowers/` tree on 2026-08-26 so every
document lives under `docs/`. It stays untracked because this repository is public and the
original policy was that design docs are not published. Links into it resolve in a local
checkout only.

A batch of superseded documents was retired on 2026-08-26 — twenty stale docs inside
`Ilumionate/` (Phase-3 testing guides describing a deleted `LightEngineTests.swift`, an
`OBSERVABLE_MIGRATION.md` for a migration with zero remaining `@Published` usages), plus
`ANALYZER_IMPROVEMENT_PLAN.md`, `ANALYSIS_PIPELINE_PROGRESS.md`, `ANALYSIS_ENHANCEMENTS.md`,
`remediation_plan.md`, `TESTFLIGHT_CHECKLIST.md`, `READER_MODES_PLAN.md`,
`ENHANCED_LIGHT_SCORE_GUIDE.md` (documented the deleted `AudioLightScoreGenerator`),
`adaptive_refresh_test_results.md`, and the orphaned `claude_neuro_app.md` /
`neuro_visual_entrainment_design.md` pair from before the LumeSync rename. Everything still
open from them is folded into the sections below; git history holds the originals.

---

## Project Vision

A premium Apple-platform light therapy (photoentrainment) app for iOS and native macOS that synchronizes adaptive visual patterns with audio content — using on-device AI to analyze hypnosis, meditation, and music files and generate personalized light sessions.

### Platform Status

- iOS 18+ and native macOS 26+ are first-class destinations of the shared `Ilumionate` target.
- **iOS deployment target dropped 26.0 → 18.0 on 2026-08-27** so the app installs on the
  installed base rather than on iOS 26 alone. iOS 18 keeps the whole functional app — import,
  transcription, playback, session generation, visuals, playlists, saved sessions — and loses
  only the Foundation Models layer: AI content analysis, the chunked phase classifier, AI
  enrichment (titles, themes, summaries, key moments, trance-depth curves), and continued
  background processing. Those degrade to keyword/metadata/audio heuristics and deferred
  background recovery. iOS 26 is unchanged; one binary serves both.
  Gating rules and the full fallback table: `CLAUDE.md` → "iOS 18 back-compatibility".
- iOS uses the compact four-tab shell; macOS uses a resizable native window, sidebar navigation, and a Settings scene.
- Feature models, stores, analysis, playback, and views are shared so fixes stay aligned across platforms.
- Mac Catalyst remains available as a compatibility destination.
- App data is currently local to each installation; cross-device library and settings sync is separate future work.

---

## STATUS LEGEND
- ✅ Complete
- 🔄 In progress / partial
- ❌ Not started

> 📋 **Audit note (2026-06-19):** A spec-vs-code audit found several status markers below are stale.
> Verified-but-marked-❌: audio-file playback in player (`UnifiedPlayerViewModel.swift:422`) and
> GeneratedSession persistence (`GeneratedSessionStore.swift`) are implemented. Marked-✅-but-absent:
> `AudioRecorderView` does not exist. Nav is 4-tab (Home/Library/Read/Create), not the 5-tab set
> noted below. Top real open item: `LightScorePlayer` external time-sync. Statuses left unchanged
> pending production verification per project rules. Full detail: `docs/archive/superpowers/spec-audit-2026-06-19.md`.

---

## FOUNDATION — Light Engine & Core System

### Light Engine
- ✅ Native display-link brightness calculation with waveform generation on iOS and macOS
- ✅ Bilateral mode (independent left/right field stimulation)
- ✅ Frequency ramping with configurable curves
- ✅ Color temperature support (warm/cool interpolation)
- ✅ 120Hz ProMotion support (CAFrameRateRange)
- ✅ Frequency multiplier (0.5×–2.0×) wired to user settings
- ✅ 69/69 unit + integration + performance tests passing
- ✅ All performance targets exceeded by 10–33×
- ✅ Photosensitive safety validation (max 60Hz, rapid-change detection)
- ✅ Session JSON format (`LightMoment` arrays) with full validation

### Session System
- ✅ `LightSession` / `LightScoreReader` / `LightScorePlayer`
- ✅ 12 pre-built sessions bundled (relaxation, focus, sleep, bilateral variants)
- ✅ Session diagnostics & validation tools
- ✅ Countdown start screen (3-2-1 overlay with haptics)
- ✅ Session lock mode (reduced-touch UI during playback)

---

## DESIGN SYSTEM — "Trance" UI

### Foundation
- ✅ Rose-gold / pink Trance color palette
- ✅ Glass morphism (ultraThinMaterial) view modifier
- ✅ Shadow system, spacing constants, corner radius system
- ✅ GlassCard, CategoryIcon, CTAButton, PhasePill, ProgressRingView
- ✅ AudioScrubber, IntensityDial, PulseOrb, MandalaVisualizer
- ✅ Full-screen FlashView, BilateralFlashView, ColorPulseView

### Navigation
- ✅ Compact tab navigation on iOS and native sidebar navigation on macOS
- ✅ Shared feature destinations with platform-appropriate stacks and modal presentation

---

## SCREENS

### Home Dashboard
- ✅ Launcher layout: greeting, four equal door quadrants (Listen/Read/Visuals/Pulse), Current, Continue
- ✅ Settings reachable from a pinned toolbar gear (iOS); macOS uses the sidebar `SettingsLink`
- ✅ Doors deep-link to Create with the segment preselected, preserving the flash safety warning
- ✅ Listen opens the Library tab; Continue moved here from Library (listening + reading)
- ✅ Current shows active playback; `MiniPlayerBar` suppressed on home so it isn't doubled
- ✅ Continue reads `PlaybackProgressStore` — verified end-to-end in the simulator
- ✅ Staggered entrance animations, reduce-motion aware
- ✅ Quadrants reflow to one column at accessibility text sizes
- ❌ Tab bar still maps to Home/Library/Read/Create rather than the four product surfaces
      (home compensates via deep links; see the design doc's decision 6)

### Audio Player (SessionPlayerView)
- ✅ MandalaVisualizer centerpiece, phase indicator, audio scrubber
- ✅ Navigation controls, SyncToggle, Up Next section
- 🔄 Player animations (mandala pulse, button press) — spec defined, not fully wired
- ❌ Audio file playback integrated into player (audio sync pending — see AI Pipeline section)

### Mind Machine (MindMachineView)
- ✅ PulseOrb visualization, frequency slider with brainwave zone labels
- ✅ Color temperature dot grid, pattern cards, IntensityDial
- ✅ Visual mode selector: Flash / Color Pulse / Bilateral
- ✅ Safety warning before entering flash mode
- ✅ Screen brightness set to 1.0 during flash, restored on stop
- ✅ Focus Spots — optional black fixation spots over the light field, with a
      calibration screen for vertical position, spacing, and diameter

### Audio Library (AudioLibraryView)
- ✅ Glass card layout, deterministic waveform thumbnails
- ✅ Import from Files, URL, in-app browser (shown in toolbar + empty state)
- ✅ Analysis status indicators, batch delete + analyze-all
- 🔄 Duplicate detection on import — content fingerprint and publisher provenance
      checked at all three import doors before any bytes are written, so a repeat
      BambiCloud playlist costs nothing and no `Name (1).mp3` is created. "Find
      Duplicates" in the toolbar merges existing duplicates, folding in play
      counts and ratings and repointing playlists. Automated coverage complete on
      macOS and iOS; **awaiting on-device verification against real playlists**.
      Design: `docs/superpowers/specs/2026-08-10-audio-duplicate-detection-design.md`
- 🔄 "Analyze & Generate Session" per-file flow — backend ready, UI wiring pending

### Session Library (LibraryView)
- ✅ Session cards with metadata, filtering/search, gradient thumbnails
- ✅ "Your Sessions" shelf for user-generated scores (added when home's launcher
      rewrite dropped its own copy)
- ✅ Continue section removed — it now lives on Home
- 🔄 Session selection flow into player — needs completion

### Session Generation (SessionGenerationView)
- 🔄 The legacy `SessionGenerationView` implementation is not presented by the current
      navigation graph; decide whether to reconnect or retire it before doing more UI work
- ✅ Session generation remains live through the analysis queue and generated-session store

### Settings & Profile
- ✅ Settings split into 3 files (SwiftLint compliant)
- ✅ Session Notifications toggle, Export Session Data
- ✅ Intensity, duration, bilateral, frequency scale, listening history toggles
- ✅ Profile with weekly activity chart, session history — in `ProfileSettingsView`,
      reached from the home toolbar gear ("Profile & Settings")
- 🔄 Accessibility options — Steady Light toggle ✅ (Session Defaults); Dynamic Type toggles still open
- ❌ Achievements / milestones section

### Onboarding
- ✅ 6-step onboarding flow with welcome session
- ✅ Seizure warning on first launch + before first light session

---

## AI AUDIO PIPELINE

### Phase 1 — Audio Infrastructure ✅
- ✅ `AudioFile` model (metadata, transcription, analysis result)
- ✅ `AudioIntake` / `AudioAcquisition` / `AudioImportWorker` — validated Files, URL,
      browser, and playlist import through one persistence path
- ✅ `PlaybackRuntime` / `AudioLightSyncPlayer` — shared playback clocks and audio/light sync

### Phase 2 — AI Analysis ✅
- ✅ `AudioAnalyzer` — on-device SFSpeechRecognizer with enhanced hypnosis vocabulary
- ✅ `AIContentAnalyzer` — Foundation Models integration, `@Generable` structured output
- ✅ Content type detection (hypnosis, meditation, affirmations, guided imagery)
- ✅ Multi-pass hypnosis analysis: structural pass (phases, induction style, techniques) + therapeutic pass (trance depth curve, receptivity, voice characteristics)
- ✅ **Analysis Task Center (Phase 1)** — one canonical `AnalysisTask` per audio file,
      produced by a pure `AnalysisTaskProjection` and published by a single
      `AnalysisCenterModel`. The pill, the center sheet, Library's entry row, and Session
      Detail all filter that one snapshot; none rebuilds state of its own. Replaced
      `AnalysisStatusOverlay`, `AnalysisRecoveryStatusOverlay`, `LibraryAnalysisStatusSection`,
      and the dead `AnalysisStatusBar`, all deleted. The pill now shows active progress and
      outstanding failures at the same time — the two overlays it replaced shared one slot,
      so a failure was invisible while anything was running. Failure dismissal is durable
      (ERR-013) and preserves the checkpoint so a retry still resumes from the saved
      transcript. `AnalyzerView` survives carrying only Library Intelligence, reachable from
      the center's toolbar until that moves to Library.
      Design: `docs/superpowers/specs/2026-08-16-analysis-task-center-design.md`
      Plan: `docs/superpowers/plans/2026-08-16-analysis-task-center-phase-1.md`
- ❌ Analysis Task Center Phase 2 — 2a teardown/cancellation spike, 2b stall watchdog and
      `.stalled`, 2c WhisperKit model-download progress (`.preparing` ships unused in Phase 1).
      **Stalls remain unobservable until 2b lands:** no timeout exists in the pipeline, so a
      hung analysis still shows a frozen percentage and emits no terminal event

### Phase 2b — Prosody & Technique Detection ✅
*(folded in from the retired `ANALYSIS_PIPELINE_PROGRESS.md`, 2026-04-04)*

The analyzer responds to the hypnotist's vocal *delivery*, not just their words.

- ✅ `ProsodyAnalyzer` (+ `ProsodyAnalyzer+PauseDetection`) — per-window RMS volume via
      `vDSP_svesq`, F0 pitch by autocorrelation via `vDSP_dotpr`, speech rate from WhisperKit
      word timestamps, and pause classification (natural / deliberate / musicOnly / silence).
      All `nonisolated`/`Sendable`, so it runs off the main actor
- ✅ `TechniqueDetector` — nine hypnotic techniques from word timestamps + prosody
- ✅ Runs in parallel with AI analysis (`Task.detached` in `AnalysisPipeline`), then merges
      into `AnalysisResult.prosodicProfile` / `.techniqueDetection` and populates
      `VoiceCharacteristics`, which was previously always nil
- ✅ `SessionGenerator+ProsodicModulation` — per-moment frequency (±1.5 Hz) and intensity
      (±8%) modulation, technique-responsive light events for 8 technique types, and breath
      oscillation synced to speech rate (150 WPM → 0.15 Hz, 60 WPM → 0.07 Hz) with the
      duration-based rate as fallback

### Analyzer accuracy work ✅
*(folded in from the retired `ANALYZER_IMPROVEMENT_PLAN.md`, 2026-03-16 — all steps verified
complete against the code on 2026-08-26 except where noted)*

WhisperKit `tiny`→`base` and the 50 MB gate removal; typed `frequencyLower`/`frequencyUpper`
replacing the fragile `frequencyRange: String`; keyword-collision fixes in
`HypnosisPhaseKeywords`; duration-scaled `minRun` and chunk cap; wider transcript sampling;
few-shot AVE prompt examples; persisted + content-addressed analysis cache; surfaced
`AnalysisPipelineError`; duration-scaled breath rate; parallel two-pass chunk classification;
structured `LightAction` enum replacing `action: String`; and the golden-dataset regression
fixtures.

- ❌ **Language auto-detection** — the one item never done. `AudioAnalyzer.swift:652` still
      passes `language: nil` to WhisperKit; detected locale is not forwarded to the AI prompt

### Phase 3 — Session Generation ✅ (backend) / 🔄 (UI integration)
- ✅ `SessionGenerator` — converts AnalysisResult into `LightSession` with phase-aware light patterns
- ✅ `AudioSyncController` — AVAudioPlayer wrapper with 0.1s time-update callbacks
- 🔄 `SessionGenerationView` — preview + customization UI exists but preview playback not wired
- ❌ `AudioLibraryView` "Generate Session" button wired to full analysis → generate → preview flow
- ❌ `SessionPlayerView` audio integration (load AudioFile, start AudioSyncController, sync to LightScorePlayer)
- ❌ `LightScorePlayer` external time-sync mode (`.internal` vs `.external` time source)
- ❌ `GeneratedSession` persistence model + display in library with "Audio-Enhanced" badge
- ❌ End-to-end test: import audio → analyze → generate → play in sync

---

## POLISH & ACCESSIBILITY (Phase 9)

- 🔄 Transition animations per design spec — partial
- 🔄 Haptic feedback throughout interactions — partial (Aug 28). The Library shelves were the
  worst offender: the artist and new-playlist cards buzzed while the audio, playlist and
  built-in-session play buttons next to them did nothing, so adjacent cards felt like different
  apps. All four play paths now fire `medium()` and the shelf info button fires `light()`, matching
  the vocabulary `TranceHaptics` already documents (light = navigation, medium = play/start).
  Still open: no `UINotificationFeedbackGenerator` at all, so analysis completing, an import
  succeeding and an import failing are indistinguishable; and no generator calls `prepare()`, which
  makes the first tap of a session measurably laggier than the rest.
- ❌ Loading states with pulse animations
- ❌ Success/error feedback states
- 🔄 Dynamic Type support — partial (Aug 28). `TranceTypography` is now built entirely from
  relative text styles, so all 423 call sites across 87 files scale, including at accessibility
  sizes; text that bypassed the scale on Library, Home, Reader, Profile and the session cards was
  pulled into it (27 sites). The Library shelf cards scale their heights with `@ScaledMetric` so
  wrapped titles grow instead of clipping, and `TranceTabBar` clamps at `.xxLarge` the way UIKit's
  own tab bar does. Still open: shelf cards keep a fixed 0.46 width fraction, so a long title still
  truncates at accessibility sizes (a full-width card there, as `HomeDoorsView` already does with
  its columns, would fix it); the remaining ~53 fixed `.frame(height:)` sites have not been audited
  for text they constrain; `TranceSpacing.tabBarClearance` is a static computed value and cannot
  scale; and verification so far is iOS 18.5 at `accessibility-extra-large` on Library and Home
  only — the player, Create, and Reader surfaces have not been checked at any accessibility size.
- ✅ Reduce motion alternatives for the light path — in-app Steady Light toggle, unioned with system Reduce Motion across engine, flash controller, and flash view (from TestFlight feedback, Apr 10)
- ✅ Mini player transport (Aug 28) — the bar's play/pause glyph is a real control layered over
  the bar's own button, so it pauses in place instead of opening the full player. Verified on
  iOS 18.5: the glyph toggles playback, the bar body still opens the player.
- ✅ Library empty state is actionable (Aug 28) — `LibraryEmptyCard` carries the same add menu as
  the header's "+" rather than describing a button elsewhere and doing nothing when tapped.
- 🔄 Mac keyboard shortcuts (Aug 28) — a Playback menu (Play/Pause ⌘⇧P, End Session ⌘.), ⌘1–⌘4
  for the four sections via `focusedSceneValue`, and ⌘F for Library search. See
  `Ilumionate/AppCommands.swift`. **Not runtime-verified** — builds clean and the app launches, but
  the menus have not been exercised on a running Mac. Space was deliberately not used for
  play/pause: AppKit dispatches menu key equivalents ahead of the responder chain, so a plain Space
  would be swallowed app-wide and break typing in every text field. Revisit by scoping Space to the
  player view with `onKeyPress` instead of a menu shortcut.
- ❌ Custom app icon (rose-gold mandala design)
- ❌ Contextual help system
- ❌ Sound effects for key interactions

---

## FROM TELEMETRY (see TELEMETRY_FINDINGS.md)

- ✅ URL import accepted non-audio payloads — a link returning HTML was saved as
  `.mp3`, logged as "✅ Successfully downloaded audio", and admitted to the library
  where it failed transcription silently. Root cause of the 26% analysis success
  rate. `AudioDownloadValidation` now gates both import paths on Content-Type and
  container signature; the consolidated `AudioIntake.swift` path now serves Files,
  URL, in-app browser, and playlist imports
- ✅ **The silent stall** — `queueForAnalysis(_:priority:)` returned early for an
  already-queued file *before* starting the processor, so a queue that outlived
  its processor was stuck forever and "Analyze Now" was a permanent no-op. This is
  what produced 0.7.3's 13 starts / 1 completion / 0 errors. Fixed by re-arming
  `startAutomaticProcessing` on that path; verified end to end (93 segments,
  hypnosis, 98% alignment, session generated)
- ✅ "Analyze Now" now shows queue/stage progress instead of appearing to do
  nothing (`SessionDetailView.analyzeNowSection`)
- ❌ Analysis stalls still emit no terminal telemetry — worth adding
  `Audio.Analysis.Failed` on the give-up path so this class of bug is visible
- ✅ Session telemetry now records which player rendered (`mode` on
  `session.started`/`.ended` via `PlayerMode.analyticsName`) — the one real gap;
  `endReason`/`startType`/end-event coverage turned out to be correct since 0.7.2
  and only looked broken because 0.6.1 traffic dominates the 30-day window
- ✅ Diagnosed why AI analysis never runs — Foundation Models fails *closed* when
  it cannot query its own safety classifier, reporting
  `guardrailViolation("May contain sensitive or unsafe content")` whose underlying
  error is `Failed model manager query … InferenceError::hostFailed`. The content
  is never evaluated. `AIGenerationDiagnosis` now classifies this, the futile
  retry is skipped, `ai.generationFallback` telemetry is emitted, and the badge
  reads "Keyword Analysis" instead of falsely claiming "AI Analyzed"
  - ⚠️ Observed in the **simulator** only — not proof the AI path fails on device.
    The new telemetry is what will answer that
- ❌ Whisper transcription degenerates on soft speech (observed output loops:
  "mother mother mother"); `openai_whisper-base` may be too small for this content
- ❌ First analysis downloads the WhisperKit model (~100s) with no progress shown
- ❌ First analysis silently downloads a ~100s CoreML model with no progress shown

## FROM TESTFLIGHT FEEDBACK

Both reports came from real testers; screenshots and analysis in session notes.

- ✅ In-app Steady Light toggle (Apr 10 report) — see Polish & Accessibility above
- ✅ Playlist picker dead end (Mar 11 report) — un-analyzed files were listed but
  disabled, reading as "my imports didn't save". Rows now start analysis on tap,
  show "Analyzing…", and become selectable in place. `PlaylistPickerRowState`
- ✅ Selectable flash colour (Apr 10 report) — `FlashTint` overrides the rendered
  colour at render time only. Sessions keep their Kelvin `color_temperature`, so
  the JSON schema, `SessionGenerator`, and the AI models are untouched. Picker in
  Session Defaults; "Match Session" is the default. `FlashTint`, `FlashTintSheet`
  - Note: `Color.fromKelvin` is a blackbody curve (2000K–6500K) with no teal,
    violet, or rose on it, which is why exposing Kelvin alone could not have
    answered this request
  - Decision: no colour-specific seizure rules; the frequency cap in
    `LightSafety` and the photosensitivity warning remain the only guards

---

## SECURITY / HYGIENE
*(folded in from the retired `remediation_plan.md`, 2026-04-04; the rest of that plan is moot —
`StreamingAnalyzer.swift`, `StreamingManager.swift`, and `ClosedRange+Codable.swift` no longer
exist, so the "fake streaming analysis" phase resolved itself by deletion)*

- ✅ **Retired SoundCloud credentials are purged from `UserDefaults`.** The integration was
      removed in `e9cb0f1`; `AppSettingsManager.purgeRetiredStreamingCredentials` now deletes
      the legacy client ID, secret, and access-token keys on launch, and settings export no
      longer exposes their status. See `ERRORS.md` ERR-020.
- 🔄 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is still set on all three configurations.
      The intent was to move domain services off default main-actor isolation; the analysis
      pipeline and prosody work already run detached, so this is now narrower than it was

---

## TESTFLIGHT / RELEASE

> Release source of truth is [`APP_STORE_RELEASE_CHECKLIST.md`](APP_STORE_RELEASE_CHECKLIST.md)
> (Unlisted App distribution, last audited 2026-08-04). The older `TESTFLIGHT_CHECKLIST.md`
> was retired — it was pinned to build 10011 and predated the LumeSync naming.

- ✅ App target at marketing version 0.7.8, build 10022, bundle `com.byronquine.lumenSync`
      (plan.md previously claimed "1.0.0 (Build 1001)" — those are a secondary target's
      values, not the app's; corrected 2026-08-26 from `project.pbxproj`)
- ✅ Privacy policy, medical disclaimer, export compliance
- ✅ Beta release notes + tester guide written
- 🔄 Final pre-upload testing checklist — some items pending full audio sync feature
- ❌ Upload archive + submit for external review
- ❌ Screenshots for all required device sizes

---

## FUTURE / POST-MVP

- ❌ Apple Watch integration (session controls + biometrics)
- ❌ Apple Health export
- ❌ Siri / widget support
- ❌ Cloud import sources (iCloud, Dropbox, Google Drive)
- ❌ Timeline editor / session creator UI
- ❌ Session marketplace / community sharing
- ❌ Real-time audio-reactive mode (live mic input)
- ❌ Biofeedback integration (heart rate, HRV)
- ❌ Android platform

---

## NEXT PRIORITY WORK

In order of dependency:

1. **Wire `LightScorePlayer` for external time-sync** — add `.external` time source mode so audio clock drives light position
2. **Integrate `AudioSyncController` into `SessionPlayerView`** — optional `audioFile` param, sync callbacks
3. **Wire "Generate Session" flow in `AudioLibraryView`** — analyze → generate → present the live generated-session experience
4. **Resolve the retired `SessionGenerationView`** — reconnect it deliberately or replace/delete it before adding preview work
5. **Persist `GeneratedSession`** — save to documents, show in session library with badge
6. **End-to-end smoke test** with real hypnosis/meditation audio
7. **Session selection flow** in Library → Player
8. **Polish pass** — haptics, loading states, Dynamic Type, reduce motion
9. **TestFlight upload** once audio sync is stable
