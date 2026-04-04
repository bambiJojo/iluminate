# Analysis Pipeline Improvement — Progress Log

## Goal
Improve the audio analysis pipeline to respond to the hypnotist's actual vocal delivery (prosody) rather than just their words, producing light sessions that better match therapeutic intent and enhance the trance experience.

## Plan Summary
| # | Improvement | Status |
|---|-------------|--------|
| 1 | Data Model Types (AudioFile.swift) | DONE |
| 2 | Prosodic Feature Extraction (ProsodyAnalyzer.swift) | DONE |
| 3 | Hypnotic Technique Detection (TechniqueDetector.swift) | DONE |
| 4 | Pipeline Protocol (AnalysisPipelineProtocols.swift) | DONE |
| 5 | Parallel Pipeline Integration (AnalysisPipeline.swift) | DONE |
| 6 | VoiceCharacteristics Population (AnalysisPipeline.swift) | DONE |
| 7 | Adaptive Session Generation (SessionGenerator+ProsodicModulation.swift) | DONE |
| 8 | Adaptive Light Scoring (SessionGenerator+Strategies.swift) | DONE |
| 9 | Final Build & Verification | DONE |

---

## Completed Steps

### Step 1: Data Model Types (AudioFile.swift) — BUILD VERIFIED
- Added `PauseCategory` enum (natural, deliberate, musicOnly, silence)
- Added `DetectedPause` struct with id, startTime, duration, precedingText, followingText, category
- Added `ProsodicProfile` struct with per-window curves and convenience accessors
- Added `prosodicProfile: ProsodicProfile?` field to `AnalysisResult`
- Added `techniqueDetection: TechniqueDetectionResult?` field to `AnalysisResult`
- Made `voiceCharacteristics` mutable (`var`) for pipeline enrichment

### Step 2: ProsodyAnalyzer.swift (NEW FILE) — BUILD VERIFIED, SWIFTLINT CLEAN
- Reads raw PCM audio via AVFoundation
- Computes per-window RMS energy (volume curve) using vDSP_svesq
- Estimates F0 pitch via autocorrelation using vDSP_dotpr
- Derives speech rate from WhisperKit word timestamps
- All methods are nonisolated/Sendable — safe for background threads
- Split into ProsodyAnalyzer.swift (290 lines) + ProsodyAnalyzer+PauseDetection.swift (151 lines)
- Uses context structs (PauseDetectionContext, PitchEstimationContext, WindowAnalysisContext) for SwiftLint compliance

### Step 3: TechniqueDetector.swift (NEW FILE) — BUILD VERIFIED
- Detects 9 types of hypnotic techniques from word timestamps + prosodic data
- Made `TechniqueDetectionResult` Codable for persistence in AnalysisResult

### Step 4: Pipeline Protocol (AnalysisPipelineProtocols.swift) — BUILD VERIFIED
- Added `ProsodyAnalyzingService` protocol (non-MainActor, Sendable)
- ProsodyAnalyzer conforms to the protocol

### Step 5: Parallel Pipeline Integration (AnalysisPipeline.swift) — BUILD VERIFIED
- Added `prosodyAnalyzer: any ProsodyAnalyzingService` to pipeline
- Prosody extraction runs on background thread via `Task.detached` in parallel with AI analysis
- After both complete: merges prosodic profile, populates VoiceCharacteristics, runs technique detection
- Default parameter so existing test call sites don't break

### Step 6: VoiceCharacteristics Population — BUILD VERIFIED
- `buildVoiceCharacteristics(from:)` derives averagePace, paceVariation, pausePatterns, tonalQualities, volumePattern from ProsodicProfile
- `inferVolumePattern(from:)` classifies curve trend as steady/gradually quieter/gradually louder/dynamic
- Previously always-nil `voiceCharacteristics` is now populated when prosody is available

### Step 7: Adaptive Session Generation (SessionGenerator+ProsodicModulation.swift) — BUILD VERIFIED, SWIFTLINT CLEAN
- **Per-moment vocal modulation**: adjusts frequency (±1.5 Hz) and intensity (±8%) based on speech rate and volume at each timestamp
- **Technique-responsive moments**: inserts targeted light events for 8 technique types:
  - Countdown → stepwise frequency drop
  - Deepening command → intensity pulse + frequency dip + bilateral
  - Deliberate pause → gentle frequency dip, no disruption
  - Embedded command → brief bilateral activation burst
  - Progressive relaxation → gradual intensity reduction
  - Anchoring → bilateral mode + warm color shift
  - Repetition → rhythmic pulsing at speech cadence
  - Fractionation → oscillating frequency (theta→alpha→deeper theta)
- **Adaptive breath oscillation**: synced to speech rate (150 WPM → 0.15 Hz, 60 WPM → 0.07 Hz) instead of fixed duration-based rate

### Step 8: Strategy Integration (SessionGenerator+Strategies.swift) — BUILD VERIFIED
- Hypnosis strategy: applies prosodic modulation + adaptive/fixed breath as top-level post-processing
- Meditation strategy: applies prosodic modulation + adaptive breath oscillation
- Removed internal `applyBreathOscillation` calls from sub-methods to prevent double-modulation
- Breath oscillation selection: adaptive when prosody available, fixed duration-based fallback

### Step 9: Final Build Verification — BUILD SUCCEEDED
- Full project compiles with zero errors
- All new files pass SwiftLint with zero violations
- Pre-existing SwiftLint warnings in SessionGenerator+Strategies.swift and AudioFile.swift unchanged

---

## Architecture Summary

### Pipeline Flow (Before)
```
Transcribe → AI Analyze → Generate Session (sequential, text-only)
```

### Pipeline Flow (After)
```
Transcribe → ┌─ AI Analyze ──────┐ → Technique Detection → Generate Session
             └─ Prosody Extract ──┘   + VoiceCharacteristics   + Prosodic Modulation
              (parallel, background)                             + Adaptive Breath
```

### New Files
| File | Lines | Purpose |
|------|-------|---------|
| ProsodyAnalyzer.swift | 290 | Audio-level prosodic feature extraction |
| ProsodyAnalyzer+PauseDetection.swift | 151 | Pause detection/classification (split for SwiftLint) |
| TechniqueDetector.swift | ~724 | Hypnotic technique & linguistic marker detection |
| SessionGenerator+ProsodicModulation.swift | ~230 | Prosodic modulation, technique moments, adaptive breath |

### Modified Files
| File | Changes |
|------|---------|
| AudioFile.swift | Added ProsodicProfile, DetectedPause, PauseCategory, TechniqueDetectionResult field |
| AnalysisPipelineProtocols.swift | Added ProsodyAnalyzingService protocol |
| AnalysisPipeline.swift | Parallel prosody extraction, VoiceCharacteristics, technique detection |
| SessionGenerator+Strategies.swift | Prosodic modulation + adaptive breath in hypnosis/meditation strategies |
