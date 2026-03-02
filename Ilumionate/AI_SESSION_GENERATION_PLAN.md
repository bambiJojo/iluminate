# AI Audio Processing & Session Generation Plan

## Overview
This feature will allow users to record or import audio (guided meditations, music, podcasts) and use Apple's on-device AI to analyze the audio and automatically generate optimized light therapy sessions that synchronize with the audio content.

---

## Phase 1: Audio Recording & Import Infrastructure
**Goal:** Allow users to record or select audio files

### Step 1.1: Audio Recording View
- [ ] Create `AudioRecorderView.swift`
- [ ] Use `AVAudioRecorder` for recording
- [ ] Add waveform visualization during recording
- [ ] Implement record/pause/stop controls
- [ ] Add audio playback preview
- [ ] Save recordings to app's documents directory

### Step 1.2: Audio Import
- [ ] Add file picker for importing audio files
- [ ] Support common formats: MP3, M4A, WAV, AAC
- [ ] Convert imported audio to app's working format
- [ ] Display audio duration and metadata

### Step 1.3: Audio Library
- [ ] Create `AudioLibraryView.swift`
- [ ] Display list of recorded/imported audio files
- [ ] Show audio metadata (duration, date, file size)
- [ ] Add delete/rename functionality
- [ ] Implement audio preview playback

**Files to create:**
- `AudioRecorderView.swift`
- `AudioImportView.swift`
- `AudioLibraryView.swift`
- `AudioFile.swift` (model)
- `AudioManager.swift` (handles recording/playback)

---

## Phase 2: AI Audio Analysis
**Goal:** Use Apple's Foundation Models to analyze audio content

### Step 2.1: Audio-to-Text Transcription
- [ ] Implement `Speech` framework for transcription
- [ ] Use `SFSpeechRecognizer` for on-device transcription
- [ ] Handle multiple languages
- [ ] Extract timestamps with transcribed text
- [ ] Store transcription with audio file

### Step 2.2: Content Analysis with Foundation Models
- [ ] Check `SystemLanguageModel` availability
- [ ] Create analysis prompt that identifies:
  - Overall mood/energy (relaxing, energizing, neutral)
  - Emotional arc (does energy increase/decrease?)
  - Key moments (transitions, climaxes, pauses)
  - Suggested frequency ranges for each section
  - Recommended intensity levels
  - Color temperature preferences
  
### Step 2.3: Audio Feature Extraction
- [ ] Extract audio features using `AVAudioEngine`:
  - Average amplitude over time
  - Tempo/BPM detection
  - Frequency spectrum analysis
  - Volume envelope
- [ ] Combine with AI analysis for comprehensive understanding

**Files to create:**
- `AudioAnalyzer.swift` (handles transcription)
- `AIContentAnalyzer.swift` (Foundation Models integration)
- `AudioFeatureExtractor.swift` (signal processing)
- `AnalysisResult.swift` (model for analysis data)

---

## Phase 3: Intelligent Session Generation
**Goal:** Generate light therapy sessions based on analysis

### Step 3.1: Session Generator Core
- [ ] Create `SessionGenerator.swift`
- [ ] Define generation strategies:
  - Content-driven (based on transcription analysis)
  - Audio-feature-driven (based on amplitude/tempo)
  - Hybrid (combines both approaches)
- [ ] Generate `LightMoment` arrays with:
  - Time-aligned frequency changes
  - Intensity curves matching audio
  - Smooth transitions between sections
  - Color temperature variations

### Step 3.2: Generation Presets
- [ ] Create preset templates:
  - **Meditation Mode**: Gradual frequency reduction, warm colors
  - **Music Sync**: Match tempo and energy of music
  - **Sleep Journey**: Progressive dimming and frequency lowering
  - **Focus Enhancement**: Maintain steady alpha/beta frequencies
  - **Energy Boost**: Gradual frequency increase with cool colors
  
### Step 3.3: AI-Guided Recommendations
- [ ] Use Foundation Models to suggest:
  - Best preset for the audio content
  - Custom adjustments to presets
  - Warning about potentially conflicting patterns
  - Optimal session parameters

**Files to create:**
- `SessionGenerator.swift`
- `GenerationStrategy.swift` (protocol + implementations)
- `GenerationPreset.swift` (model)
- `AISessionRecommender.swift`

---

## Phase 4: Session Customization & Preview
**Goal:** Allow users to review and customize generated sessions

### Step 4.1: Session Preview Interface
- [ ] Create `GeneratedSessionPreview.swift`
- [ ] Show timeline visualization:
  - Audio waveform
  - Frequency curve overlay
  - Intensity curve overlay
  - Color temperature indicators
- [ ] Allow playback of audio with live preview
- [ ] Display AI analysis summary

### Step 4.2: Manual Adjustments
- [ ] Add controls for:
  - Overall intensity multiplier
  - Frequency range limits
  - Transition smoothness
  - Color temperature override
- [ ] Real-time preview of adjustments
- [ ] Reset to AI-generated defaults

### Step 4.3: Session Export
- [ ] Generate final `LightSession` JSON
- [ ] Save to app bundle or documents
- [ ] Add to session library
- [ ] Link audio file to session

**Files to create:**
- `GeneratedSessionPreview.swift`
- `SessionCustomizationView.swift`
- `SessionTimelineView.swift` (visualization)
- `SessionExporter.swift`

---

## Phase 5: Synchronized Playback
**Goal:** Play audio and light session together

### Step 5.1: Audio Engine Integration
- [ ] Extend `LightEngine` to support audio playback
- [ ] Use `AVAudioPlayer` for audio playback
- [ ] Synchronize audio time with `LightScorePlayer` time
- [ ] Handle audio interruptions (calls, etc.)

### Step 5.2: Enhanced Session Player
- [ ] Add audio controls to `SessionPlayerView`
- [ ] Show audio progress alongside light progress
- [ ] Add audio volume control
- [ ] Implement audio-only mode (lights optional)

### Step 5.3: Sync Refinement
- [ ] Ensure tight audio/light synchronization
- [ ] Handle audio seek operations
- [ ] Maintain sync through pause/resume

**Files to modify:**
- `LightEngine.swift` (add audio playback)
- `LightScorePlayer.swift` (add audio sync)
- `SessionPlayerView.swift` (add audio controls)

**Files to create:**
- `AudioSyncController.swift`

---

## Phase 6: User Interface Flow
**Goal:** Integrate everything into cohesive UX

### Step 6.1: Main Navigation
- [ ] Add "Create Session" button to ContentView
- [ ] Create navigation flow:
  1. Choose audio source (record/import/library)
  2. Analyze audio (show progress)
  3. Review AI analysis
  4. Customize generated session
  5. Save and preview

### Step 6.2: Session Creation Wizard
- [ ] Create `SessionCreationWizard.swift`
- [ ] Step-by-step flow with progress indicator
- [ ] Handle errors gracefully
- [ ] Provide helpful tips and guidance

### Step 6.3: Enhanced Session Cards
- [ ] Add badge for "AI Generated" sessions
- [ ] Show linked audio file info
- [ ] Display generation date and strategy used

**Files to create:**
- `SessionCreationWizard.swift`
- `AudioSourcePickerView.swift`
- `AnalysisProgressView.swift`

---

## Technical Architecture

### Data Models
```
AudioFile
├── id: UUID
├── url: URL
├── duration: TimeInterval
├── transcription: String?
├── analysisResult: AnalysisResult?
└── createdDate: Date

AnalysisResult
├── mood: Mood (relaxing, energizing, neutral)
├── energyArc: [TimeInterval: Double] // energy level over time
├── keyMoments: [KeyMoment]
├── suggestedPreset: GenerationPreset
└── aiRecommendations: String

GeneratedSession
├── lightSession: LightSession
├── audioFile: AudioFile
├── generationStrategy: GenerationStrategy
├── customizations: [String: Any]
└── createdDate: Date
```

### Key Technologies
- **AVFoundation**: Audio recording, playback, processing
- **Speech**: On-device transcription
- **Foundation Models**: Content analysis and recommendations
- **Accelerate**: Signal processing for audio features
- **Swift Charts**: Visualization of audio and light curves

---

## Success Metrics
- Audio analysis completes in < 10 seconds for 10-minute audio
- Generated sessions feel natural and complementary to audio
- AI recommendations are helpful and accurate
- Tight audio/light synchronization (< 50ms drift)
- User can create a custom session in < 2 minutes

---

## Future Enhancements (Post-MVP)
- [ ] Music library integration (Apple Music, Spotify)
- [ ] Collaborative sessions (share audio + light patterns)
- [ ] Machine learning model for frequency optimization
- [ ] Real-time audio-reactive mode (live microphone input)
- [ ] Community-generated session marketplace
- [ ] Biofeedback integration (adjust based on heart rate, etc.)

---

## Getting Started
We'll begin with **Phase 1: Audio Recording & Import Infrastructure** to establish the foundation for audio handling.

