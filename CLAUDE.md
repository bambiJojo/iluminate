# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ilumionate is a SwiftUI iOS app that provides light therapy (photoentrainment) sessions synchronized with audio content. It combines AI-powered audio analysis with customizable light patterns to create personalized therapeutic experiences.

## Build Commands

**Build the project:**
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build
```

**Run tests:**
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Clean build:**
```bash
xcodebuild -project Ilumionate.xcodeproj clean
```

## Architecture Overview

### Core Components

**Light Engine (`EngineLightEngine.swift`)**
- The heart of the app that drives visual entrainment using CADisplayLink
- Handles real-time brightness calculations and waveform generation
- Supports bilateral mode (independent left/right field stimulation)
- Observable class that publishes brightness values to SwiftUI views

**Session System**
- `LightSession.swift`: Data models for sessions loaded from JSON files
- `LightScoreReader.swift`: Loads and validates session files from app bundle
- `SessionPlayerView.swift`: UI for playing sessions with synchronized controls
- `LightScorePlayer.swift`: Coordinates session playback timing

**Audio Processing Pipeline**
- `AudioManager.swift`: Handles recording, playback, and file import
- `AIContentAnalyzer.swift`: Uses Apple's on-device Foundation Models for content analysis
- `AudioAnalyzer.swift`: Audio feature extraction and processing
- `SessionGenerator.swift`: Generates light sessions from audio analysis

**Content Generation**
- `AudioFile.swift`: Model representing imported/recorded audio files
- AI-powered analysis determines content type (hypnosis, meditation, music, etc.)
- Custom light sessions generated based on audio characteristics

### Key Architectural Patterns

**Observer Pattern**: Uses SwiftUI's `@Observable` macro extensively for state management rather than traditional `@ObservableObject`.

**Session JSON Format**: Sessions are defined as JSON files with time-based light control points (`LightMoment` structures) that specify frequency, intensity, waveform type, and optional bilateral/color parameters.

**Main Actor Isolation**: Most classes are marked `@MainActor` to ensure UI thread safety, particularly important for the real-time light engine.

**Dependency Management**: Uses Swift Package Manager with WhisperKit for audio transcription.

## Development Guidelines

### File Organization
- Main app code in `Ilumionate/` directory
- Test files in `IlumionateTests/` and `IlumionateUITests/`
- Session JSON files are included as app bundle resources
- Root-level Swift files (Playlist*.swift) handle playlist functionality

### Testing Strategy
- `LightEngineTests.swift`: Unit tests for core light engine functionality
- `SessionIntegrationTests.swift`: Integration tests for session loading and playback
- Performance tests in separate files for audio processing components

### Session File Guidelines
- JSON session files must have target membership enabled in Xcode
- Session files include metadata like duration and display name
- Light moments are sorted by time for proper playback sequence

### AI Integration
- Uses Apple's Foundation Models for on-device content analysis
- Graceful fallback when AI models are unavailable
- Analysis results drive automatic session parameter selection

### Audio Requirements
- Supports M4A and MP3 formats
- WhisperKit integration for speech recognition (requires speech recognition permission)
- Audio session configured for playback and recording capabilities

## Common Development Tasks

### Adding New Session Types
1. Define new session JSON structure following existing patterns
2. Add to app bundle with target membership
3. Update session discovery logic in `LightScoreReader.discoverBundledSessions()`

### Modifying Light Patterns
1. Update waveform types in `EngineWaveforms.swift`
2. Extend `WaveformType` enum in `LightSession.swift`
3. Test real-time performance with `LightEngineTests`

### Audio Analysis Customization
1. Extend `AnalysisResult` structures for new content types
2. Update generation strategies in `SessionGenerator`
3. Add new hypnosis phases or meditation patterns as needed