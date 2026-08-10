# LumeSync (Ilumionate) — Unified Development Plan

> Consolidated from all planning documents. Last updated: 2026-07-31.

---

## Project Vision

A premium Apple-platform light therapy (photoentrainment) app for iOS and native macOS that synchronizes adaptive visual patterns with audio content — using on-device AI to analyze hypnosis, meditation, and music files and generate personalized light sessions.

### Platform Status

- iOS 26+ and native macOS 26+ are first-class destinations of the shared `Ilumionate` target.
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
> pending production verification per project rules. Full detail: `docs/superpowers/spec-audit-2026-06-19.md`.

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
- 🔄 "Analyze & Generate Session" per-file flow — backend ready, UI wiring pending

### Session Library (LibraryView)
- ✅ Session cards with metadata, filtering/search, gradient thumbnails
- ✅ "Your Sessions" shelf for user-generated scores (added when home's launcher
      rewrite dropped its own copy)
- ✅ Continue section removed — it now lives on Home
- 🔄 Session selection flow into player — needs completion

### Session Generation (SessionGenerationView)
- ✅ Phase detection visualization, customization controls, generation CTA
- 🔄 Preview playback functionality — not yet implemented

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
- ✅ `AudioManager` — recording, playback, import (AAC 44.1kHz stereo)
- ✅ `AudioRecorderView` — waveform visualization, timer, save/discard

### Phase 2 — AI Analysis ✅
- ✅ `AudioAnalyzer` — on-device SFSpeechRecognizer with enhanced hypnosis vocabulary
- ✅ `AIContentAnalyzer` — Foundation Models integration, `@Generable` structured output
- ✅ Content type detection (hypnosis, meditation, affirmations, guided imagery)
- ✅ Multi-pass hypnosis analysis: structural pass (phases, induction style, techniques) + therapeutic pass (trance depth curve, receptivity, voice characteristics)
- ✅ `AnalysisProgressView` — animated multi-stage progress UI

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
- ❌ Haptic feedback throughout interactions
- ❌ Loading states with pulse animations
- ❌ Success/error feedback states
- ❌ Dynamic Type support
- ✅ Reduce motion alternatives for the light path — in-app Steady Light toggle, unioned with system Reduce Motion across engine, flash controller, and flash view (from TestFlight feedback, Apr 10)
- ❌ Custom app icon (rose-gold mandala design)
- ❌ Contextual help system
- ❌ Sound effects for key interactions

---

## FROM TELEMETRY (see TELEMETRY_FINDINGS.md)

- ✅ URL import accepted non-audio payloads — a link returning HTML was saved as
  `.mp3`, logged as "✅ Successfully downloaded audio", and admitted to the library
  where it failed transcription silently. Root cause of the 26% analysis success
  rate. `AudioDownloadValidation` now gates both import paths on Content-Type and
  container signature; `AudioManager.swift` and `InAppBrowserView.swift` (which
  had the same `?: "mp3"` fallback) both fixed
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

## TESTFLIGHT / RELEASE

- ✅ Version 1.0.0 (Build 1001), bundle ID set
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
3. **Wire "Generate Session" flow in `AudioLibraryView`** — analyze → generate → navigate to `SessionGenerationView`
4. **Complete `SessionGenerationView` preview playback** — short preview using `AudioSyncController` + `LightEngine`
5. **Persist `GeneratedSession`** — save to documents, show in session library with badge
6. **End-to-end smoke test** with real hypnosis/meditation audio
7. **Session selection flow** in Library → Player
8. **Polish pass** — haptics, loading states, Dynamic Type, reduce motion
9. **TestFlight upload** once audio sync is stable
