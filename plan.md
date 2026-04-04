# LumeSync (Ilumionate) — Unified Development Plan

> Consolidated from all planning documents. Last updated: 2026-04-01.

---

## Project Vision

A premium iOS light therapy (photoentrainment) app that synchronizes adaptive visual patterns with audio content — using on-device AI to analyze hypnosis, meditation, and music files and generate personalized light sessions.

---

## STATUS LEGEND
- ✅ Complete
- 🔄 In progress / partial
- ❌ Not started

---

## FOUNDATION — Light Engine & Core System

### Light Engine
- ✅ CADisplayLink-based brightness calculation with waveform generation
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
- ✅ Tab bar with Home, Library, Machine, Store, Profile
- ✅ NavigationStack on each tab, fullScreenCover for player/flash

---

## SCREENS

### Home Dashboard
- ✅ Greeting section (dynamic time-based messages)
- ✅ Category icon grid (Sleep, Focus, Energy, Relax, Trance)
- ✅ Continue Session card, Quick Start section, Library scroll
- ✅ Staggered entrance animations

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

### Audio Library (AudioLibraryView)
- ✅ Glass card layout, deterministic waveform thumbnails
- ✅ Import from Files, URL, in-app browser (shown in toolbar + empty state)
- ✅ Analysis status indicators, batch delete + analyze-all
- 🔄 "Analyze & Generate Session" per-file flow — backend ready, UI wiring pending

### Session Library (LibraryView)
- ✅ Session cards with metadata, filtering/search, gradient thumbnails
- 🔄 Session selection flow into player — needs completion

### Session Generation (SessionGenerationView)
- ✅ Phase detection visualization, customization controls, generation CTA
- 🔄 Preview playback functionality — not yet implemented

### Settings & Profile
- ✅ Settings split into 3 files (SwiftLint compliant)
- ✅ Session Notifications toggle, Export Session Data
- ✅ Intensity, duration, bilateral, frequency scale, listening history toggles
- ✅ Profile with weekly activity chart, session history
- 🔄 Accessibility options (reduce motion, Dynamic Type toggles) — partial
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
- ❌ Reduce motion alternatives
- ❌ Custom app icon (rose-gold mandala design)
- ❌ Contextual help system
- ❌ Sound effects for key interactions

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
