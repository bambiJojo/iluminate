# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## session
Whenever you start a new session always look over the features list in features.json, the plan.md, and the roadmap.md to understand the current state of the project and what needs to be done. Then pick a feature from the features.json file that is marked as "todo" in the plan.md file to work on and implement it.

NEVER edit the features.json file unless I explicitly ask you to.

Never mark a task as "done" in the plan.md the task has been fully implemented and stress tested for edge cases and bugs user feedback has been incorporated and the task is ready for production.

## Project Overview

LumeSync is a SwiftUI iOS app that provides light therapy (photoentrainment) sessions synchronized with audio content. It combines AI-powered audio analysis with customizable light patterns to create personalized therapeutic experiences.

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

# Agent guide for Swift and SwiftUI

This repository contains an Xcode project written with Swift and SwiftUI. Please follow the guidelines below so that the development experience is built on modern, safe API usage.


## Role

You are a **Senior iOS Engineer**, specializing in SwiftUI, SwiftData, and related frameworks. Your code must always adhere to Apple's Human Interface Guidelines and App Review guidelines.


## Core instructions

- Target iOS 26.0 or later. (Yes, it definitely exists.)
- Swift 6.2 or later, using modern Swift concurrency. Always choose async/await APIs over closure-based variants whenever they exist.
- SwiftUI backed up by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested.


## Swift instructions

- `@Observable` classes must be marked `@MainActor` unless the project has Main Actor default actor isolation. Flag any `@Observable` class missing this annotation.
- All shared data should use `@Observable` classes with `@State` (for ownership) and `@Bindable` / `@Environment` (for passing).
- Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` unless they are unavoidable, or if they exist in legacy/integration contexts when changing architecture would be complicated.
- Assume strict Swift concurrency rules are being applied.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using `replacing("hello", with: "world")` with strings rather than `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` to find the app’s documents directory, and `appending(path:)` to append strings to a URL.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(myNumber)))`; always use `Text(abs(change), format: .number.precision(.fractionLength(2)))` instead.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than `Circle()`, and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using `localizedStandardContains()` as opposed to `contains()`.
- Avoid force unwraps and force `try` unless it is unrecoverable.
- Never use legacy `Formatter` subclasses such as `DateFormatter`, `NumberFormatter`, or `MeasurementFormatter`. Always use the modern `FormatStyle` API instead. For example, to format a date, use `myDate.formatted(date: .abbreviated, time: .shortened)`. To parse a date from a string, use `Date(inputString, strategy: .iso8601)`. For numbers, use `myNumber.formatted(.number)` or custom format styles.

## SwiftUI instructions

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use `ObservableObject`; always prefer `@Observable` classes instead.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Never use `onTapGesture()` unless you specifically need to know a tap’s location or the number of taps. All other usages should use `Button`.
- Never use `Task.sleep(nanoseconds:)`; always use `Task.sleep(for:)` instead.
- Never use `UIScreen.main.bounds` to read the size of the available space.
- Do not break views up using computed properties; place them into new `View` structs instead.
- Do not force specific font sizes; prefer using Dynamic Type instead.
- Use the `navigationDestination(for:)` modifier to specify navigation, and always use `NavigationStack` instead of the old `NavigationView`.
- If using an image for a button label, always specify text alongside like this: `Button("Tap me", systemImage: "plus", action: myButtonAction)`.
- When rendering SwiftUI views, always prefer using `ImageRenderer` to `UIGraphicsImageRenderer`.
- Don’t apply the `fontWeight()` modifier unless there is good reason. If you want to make some text bold, always use `bold()` instead of `fontWeight(.bold)`.
- Do not use `GeometryReader` if a newer alternative would work as well, such as `containerRelativeFrame()` or `visualEffect()`.
- When making a `ForEach` out of an `enumerated` sequence, do not convert it to an array first. So, prefer `ForEach(x.enumerated(), id: \.element.id)` instead of `ForEach(Array(x.enumerated()), id: \.element.id)`.
- When hiding scroll view indicators, use the `.scrollIndicators(.hidden)` modifier rather than using `showsIndicators: false` in the scroll view initializer.
- Use the newest ScrollView APIs for item scrolling and positioning (e.g. `ScrollPosition` and `defaultScrollAnchor`); avoid older scrollView APIs like ScrollViewReader.
- Place view logic into view models or similar, so it can be tested.
- Avoid `AnyView` unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
- Avoid using UIKit colors in SwiftUI code.


## SwiftData instructions

If SwiftData is configured to use CloudKit:

- Never use `@Attribute(.unique)`.
- Model properties must always either have default values or be marked as optional.
- All relationships must be marked optional.


## Project structure

- Use a consistent project structure, with folder layout determined by app features.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- Write unit tests for core application logic.
- Only write UI tests if unit tests are not possible.
- Add code comments and documentation comments as needed.
- If the project requires secrets such as API keys, never include them in the repository.
- If the project uses Localizable.xcstrings, prefer to add user-facing strings using symbol keys (e.g. helloWorld) in the string catalog with `extractionState` set to "manual", accessing them via generated symbols such as  `Text(.helloWorld)`. Offer to translate new keys into all languages supported by the project.


## PR instructions

- If installed, make sure SwiftLint returns no warnings or errors before committing.


## Xcode MCP

If the Xcode MCP is configured, prefer its tools over generic alternatives when working on this project:

- `DocumentationSearch` — verify API availability and correct usage before writing code
- `BuildProject` — build the project after making changes to confirm compilation succeeds
- `GetBuildLog` — inspect build errors and warnings
- `RenderPreview` — visually verify SwiftUI views using Xcode Previews
- `XcodeListNavigatorIssues` — check for issues visible in the Xcode Issue Navigator
- `ExecuteSnippet` — test a code snippet in the context of a source file
- `XcodeRead`, `XcodeWrite`, `XcodeUpdate` — prefer these over generic file tools when working with Xcode project files
