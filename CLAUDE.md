# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Session start

Read `plan.md` first — it is the consolidated, current source of truth for status and open work. Pick up the next unstarted item unless directed otherwise.

- `features.json` is a historical product spec (it still uses the old "Hypnosis Mind Machine" name and an iPhone/Android platform plan). Treat it as archive, not as current scope. **Never edit it unless explicitly asked.**
- Only mark a `plan.md` item done once it is fully implemented, tested for edge cases, and user feedback is incorporated. Not "compiles" — done.

## Project overview

LumeSync is a SwiftUI light therapy (photoentrainment) app that syncs visual entrainment patterns with audio. iOS and native macOS are both first-class destinations built from one shared feature target. On-device AI analyzes audio (hypnosis, meditation, music) and generates personalized light sessions.

The Xcode project and app target are named `Ilumionate`; the user-facing product name is LumeSync.

## Build and test

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.0' build
```

**Pick a simulator that actually exists on the machine.** `xcodebuild` does not
error on an unresolvable `-destination` — it hangs at 0% CPU indefinitely. This
machine has no iPhone 17 Pro; available iPhone 16 Pro runtimes are 18.0, 18.1,
18.3, 18.4, 18.5, and 26.0. Pin `OS=` explicitly, because several simulators
share the same name. Check before trusting a destination:

```bash
xcrun simctl list devices available | grep iPhone
```

See ERRORS.md ERR-026.

Mac Catalyst is a compatibility destination — keep it compiling, but it is not the primary Mac experience:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' build
```

Shared unit tests run on both first-class platforms:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.0' test -only-testing:IlumionateTests
```

```bash
xcodebuild -project Ilumionate.xcodeproj clean
```

### Running a subset of tests

**A `-only-testing:` filter that matches nothing still reports success.** `xcodebuild` runs
zero tests and prints `** TEST SUCCEEDED **`, so a failing test reads as passing. Swift
Testing identifiers end in `()`; XCTest method names do not:

```bash
-only-testing:IlumionateTests/MyTests/myTest()   # runs the test
-only-testing:IlumionateTests/MyTests/myTest     # matches nothing, "succeeds"
```

Filter at suite level (`-only-testing:IlumionateTests/MyTests`) unless you need one test.

Prefer the wrapper, which fails when zero test cases ran:

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests
```

See ERRORS.md ERR-002.

### Targets

| Target | Purpose |
|---|---|
| `Ilumionate` | The app (iOS + macOS, shared sources) |
| `IlumionateShareExtension` | Share sheet import |
| `LumeLabel` | Companion labelling/annotation app |
| `AnalyzerImprover` | Analyzer tuning tool |
| `IlumionateTests` / `IlumionateUITests` | App tests |

Additional schemes: `corpus-gen` and `CorpusKit` (local `Tools/CorpusGenerator` package).

### Dependencies (SPM)

WhisperKit (transcription), TelemetryDeck (analytics), swift-transformers, swift-jinja, swift-crypto, swift-collections, swift-argument-parser, swift-asn1, yyjson. **Ask before adding any new third-party dependency.**

## Architecture

### Light engine

`EngineLightEngine.swift` drives visual entrainment via the native display-link API on each platform: real-time brightness, waveform generation, and bilateral mode (independent left/right field). It is an `@Observable` class publishing brightness to SwiftUI. Waveform math lives in `EngineWaveforms.swift`.

### Sessions

- `LightSession.swift` — data models for JSON-defined sessions
- `LightScoreReader.swift` — loads and validates bundled session files
- `LightScorePlayer.swift` — playback timing
- `UnifiedPlayerView.swift` / `UnifiedPlayerViewModel.swift` — the player surface, composed from ~25 `Player*.swift` components (transport, brightness, bilateral, binaural, overlays, trays)

Sessions are JSON with time-ordered `LightMoment` control points specifying frequency, intensity, waveform, and optional bilateral/color parameters.

### Audio and analysis

- `AudioIntake.swift`, `AudioAcquisition.swift`, `AudioImportWorker.swift` — validated file and URL import
- `PlaybackRuntime.swift`, `AudioLightSyncPlayer.swift` — playback clocks and audio/light synchronization
- `AudioAnalyzer.swift`, `AudioEnergyAnalyzer.swift` — feature extraction
- `AIContentAnalyzer.swift`, `AIAnalysisManager*.swift` — Apple Foundation Models, on-device, with graceful fallback when unavailable
- `AnalysisStateManager.swift` + `AnalysisPipelineProtocols.swift` — queueing, orchestration, recovery, and cache state
- `SessionGenerator.swift` — turns analysis into light sessions
- `AudioLibraryStore.swift`, `AudioFile.swift` — library state and models

Audio formats: M4A and MP3. WhisperKit speech recognition requires the speech recognition permission.

### Feature directories under `Ilumionate/`

| Directory | Contents |
|---|---|
| `DesignSystem/` | Palettes, orb, aurora backgrounds, motion, shared visual components |
| `Visuals/` | Trance visual field, Metal shaders, tint/modulation/fade |
| `TextTrance/` | Reader mode — script import, ORP, attention monitor, reader controls |
| `Threshold/` | Launch threshold choreography and phase machine |
| `Create/` | Session creation UI and binaural/mind-machine models |
| `Analytics/`, `Training/`, `PlaylistImport/`, `AnalyzerConfig/`, `Models/` | Supporting subsystems |

Most app sources sit flat at the top of `Ilumionate/` (~215 files); prefer adding new work into a feature directory rather than growing the flat layer.

### Platform strategy

iOS and macOS share the `Ilumionate` target and all feature sources. `ContentView` picks its shell via `AppNavigationPresentation` — compact tabs on iOS, native sidebar on macOS. Confine `#if os(...)` to platform boundaries: lifecycle, permissions, input, window presentation, framework adapters. Platform seams live in `Platform*.swift` (`PlatformAudioSession`, `PlatformApplication`, `PlatformAccessibility`, `PlatformFullScreenCover`, `PlatformViewModifiers`). Do not fork feature implementations per platform.

`AVAudioSession` is configured on iOS only; macOS uses AVFoundation playback with no audio session.

### iOS 18 back-compatibility

The app deploys to **iOS 18.0** and **macOS 26.0**, built against the iOS 26 SDK. The two
numbers differ, so `@available(iOS 26.0, macOS 26.0, *)` is a real gate on iOS and a no-op on
native macOS. Mac Catalyst follows the *iOS* target, so it can reach the iOS 18 branches while
running on a Mac — word user-facing copy in those branches accordingly.

What is gated, and what iOS 18 gets instead:

| iOS 26 only | iOS 18 fallback |
|---|---|
| `FoundationModels` — every `@Generable` type, `LanguageModelSession`, `SystemLanguageModel` | `AIAnalysisManager.analyzeContentWithBuiltInModels` — keyword, metadata, and audio heuristics |
| `ChunkedPhaseAnalyzer` context-aware phase classification | `HypnosisPhaseAnalyzer` keyword phase detection |
| `BGContinuedProcessingTask` — analysis continues out of foreground | `BGProcessingTask` deferred recovery only |

Rules when touching this:

- `FoundationModels` is **weak-linked**. Keep every one of its types behind `@available`,
  including in stored properties and function signatures, or the app fails to launch on iOS 18.
- Any keyword fallback must record why. Build the result with an `AIGenerationDiagnosis.Kind`
  and emit `UsageAnalytics.aiGenerationFallback` — a fallback that reports nothing is invisible
  in the funnel, because analysis still "completes".
- Never label work as AI that iOS 18 does with keywords. `SessionDetailView`'s badge,
  `AnalysisStageFeedback.stageSummary`, and `UnifiedPlayerViewModel.stageLabel` are all
  deliberately worded for this.
- A setting that only feeds `AnalysisPreferences.aiSystemAddendum` does nothing on iOS 18.
  Disable it there rather than letting it look effective.
- New SF Symbols must exist in iOS 18 — a too-new symbol renders blank with no build error.
- `guard #available(iOS 26...) else { return }` in a test makes it **pass** on iOS 18, not skip.
  Prefer a Swift Testing `.enabled(if:)` trait so the skip is visible.

Verify platform changes on a real iOS 18 runtime, not just by compiling:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' build
```

### Other layout notes

- Root-level `Playlist*.swift` files handle playlist functionality
- Session JSON files ship as bundle resources and need target membership enabled in Xcode
- `Scripts/release-testflight.sh` handles TestFlight releases

## Code conventions

Write as a senior Apple platforms engineer. Follow Apple's Human Interface Guidelines and App Review guidelines.

### Swift

- Target iOS 18.0+ / macOS 26.0+, Swift 6.2+, strict concurrency.
- **iOS deploys to 18.0, so the iOS 26 SDK is not a free floor.** Anything newer than iOS 18.0
  needs `@available` / `#available` with a working fallback — see "iOS 18 back-compatibility".
- Prefer `async`/`await` over closure-based APIs wherever both exist. Never use GCD (`DispatchQueue.main.async`) for new code.
- Shared state uses `@Observable` classes with `@State` for ownership and `@Bindable`/`@Environment` for passing. Avoid `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject` except in legacy or integration corners where migrating is disproportionate.
- `@Observable` classes must be `@MainActor` unless the project adopts main-actor default isolation. Flag any that aren't.
- Avoid force unwraps and force `try` unless failure is genuinely unrecoverable.
- Avoid UIKit unless asked; never use UIKit colors in SwiftUI.
- Prefer Swift-native and modern Foundation API: `replacing(_:with:)` over `replacingOccurrences`, `URL.documentsDirectory`, `appending(path:)`.
- Use `FormatStyle`, never legacy `Formatter` subclasses and never `String(format:)`: `Text(change, format: .number.precision(.fractionLength(2)))`, `date.formatted(date: .abbreviated, time: .shortened)`, `Date(input, strategy: .iso8601)`.
- User-input text filtering uses `localizedStandardContains()`, not `contains()`.
- Prefer static member lookup: `.circle` over `Circle()`, `.borderedProminent` over `BorderedProminentButtonStyle()`.
- `Task.sleep(for:)`, never `Task.sleep(nanoseconds:)`.

### SwiftUI

- `foregroundStyle()` not `foregroundColor()`; `clipShape(.rect(cornerRadius:))` not `cornerRadius()`; the `Tab` API not `tabItem()`; `NavigationStack` + `navigationDestination(for:)` not `NavigationView`.
- `onChange()` — use the two-parameter or zero-parameter variant, never the one-parameter form.
- Use `Button` rather than `onTapGesture()` unless you genuinely need tap location or count.
- Split views into new `View` structs, not computed properties. Avoid `AnyView` unless truly required.
- Put view logic in view models so it can be tested.
- Respect Dynamic Type — don't hardcode font sizes. Use `bold()` rather than `fontWeight(.bold)`.
- Don't hardcode padding/stack spacing unless asked.
- Avoid `GeometryReader` when `containerRelativeFrame()` or `visualEffect()` will do. Never read layout size from `UIScreen.main.bounds`.
- Use current ScrollView APIs (`ScrollPosition`, `defaultScrollAnchor`) over `ScrollViewReader`; `.scrollIndicators(.hidden)` over `showsIndicators: false`.
- `ForEach(x.enumerated(), id: \.element.id)` — don't wrap in `Array(...)`.
- Prefer `ImageRenderer` over `UIGraphicsImageRenderer`.
- Buttons with image labels still carry text: `Button("Tap me", systemImage: "plus", action: action)`.

### Files and naming

One primary type per file. Keep folder layout organized by feature. Strict, consistent naming for types, properties, and methods. Add doc comments where the intent isn't obvious. Never commit secrets or API keys.

## Testing

The test suite uses **Swift Testing** (`import Testing`) throughout — no XCTest. Match that when adding tests.

- `IlumionateTests/` — ~95 test files covering the light engine, analysis pipeline, stores, playback, and import
- Write unit tests for core logic; reach for UI tests only when a unit test can't cover the behavior
- Run tests on both macOS and iOS Simulator for shared changes

## Common tasks

**New session type:** define the JSON following existing patterns → add to the bundle with target membership → update `LightScoreReader.discoverBundledSessions()`.

**New light pattern:** add the waveform in `EngineWaveforms.swift` → extend `WaveformType` in `LightSession.swift:167` → cover it in `WaveformSampleTests.swift` and check real-time behavior against `LightEngineGateTests.swift`.

**Analysis changes:** extend the `AnalysisResult` structures → update generation strategy in `SessionGenerator` → add phases/patterns as needed.
