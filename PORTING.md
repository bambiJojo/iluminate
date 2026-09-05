# Porting LumeSync

Notes for anyone rebuilding LumeSync on another platform. This is written for
Android, but the split it describes — a small portable core inside a large
Apple-specific shell — holds for any target.

Read [CLAUDE.md](CLAUDE.md) first. It is the architecture document; this file
only covers what does and does not cross the platform boundary.

> **Before you start:** this code is not open source. It is published for
> reading, and no licence to copy, modify, or redistribute it is granted by its
> presence here. If you intend to build on it, get written permission from the
> author first. See [Licence](README.md#licence).

## The short version

`Ilumionate/` holds 229 Swift files. Almost all of them are SwiftUI views and
Apple-framework glue that you will rewrite rather than translate. The part worth
reading closely is much smaller: the session format, the waveform maths, and the
generator that turns audio analysis into a session.

Port the core first and verify it against the existing tests. The UI is a
rewrite either way.

## What actually ports

### Session format

`Ilumionate/LightSession.swift` (194 lines) defines the whole data model, and
the five `Ilumionate/session_*.json` files are working examples. This is the
most valuable artefact in the repository: it is a plain, versioned JSON format
with no Apple types in it, so sessions authored for the iOS app play unchanged
on any implementation that reads it.

A session is a name, a duration, and a time-ordered list of control points:

```
LightSession
  session_name        String
  duration_sec        Double
  light_score         [LightMoment]
  binaural_enabled    Bool
  binaural_carrier    Double      // Hz
  binaural_volume     Double

LightMoment
  time                Double      // seconds from session start
  frequency           Double      // target frequency, Hz
  intensity           Double      // 0.0–1.0
  waveform            WaveformType
  ramp_duration       Double?     // optional glide into this moment
  bilateral           Bool?       // independent left/right field
  bilateral_transition_duration  Double?
  color_temperature   Double?
```

Moments are control points, not frames. The engine interpolates between them,
which is why `ramp_duration` matters and why a naive implementation that snaps
between values will look wrong.

### Waveform maths

`Ilumionate/EngineWaveforms.swift` (168 lines) is pure arithmetic with no
framework dependency. Eight waveforms — `sine`, `triangle`, `square`, `sawUp`,
`sawDown`, `softPulse`, `rampHold`, `noiseModulatedSine` — and three ramp curves
— `linear`, `exponentialEaseOut`, `sigmoid`.

Translate this file more or less literally. `IlumionateTests/WaveformSampleTests.swift`
pins the expected outputs, so you can port the tests alongside it and know
immediately whether your version matches.

### Session generation

`Ilumionate/SessionGenerator.swift` (243 lines) maps analysis results onto a
light score. The policy it encodes — which frequencies suit which phase, how
intensity tracks energy — is the product, and it is platform-neutral.

### Tests as specification

`IlumionateTests/` has 210 files. Where prose and code disagree, the tests are
correct. They are the closest thing to a written specification of intended
behaviour and are worth reading before any of the views.

## What does not port

None of the following has an Android equivalent. Each needs a replacement
chosen deliberately, not a translation.

| Apple dependency | Where | What it does | Android direction |
| --- | --- | --- | --- |
| **WhisperKit** | 14 files | On-device speech transcription via CoreML | whisper.cpp via JNI, or ONNX Runtime |
| **FoundationModels** | 4 files | On-device LLM analysis (iOS 26+) | Gemini Nano / ML Kit, or a server call |
| **CADisplayLink** | `EngineLightEngine.swift`, `FlashController.swift` | Frame-synced brightness updates | `Choreographer.postFrameCallback` |
| **Metal** | `Visuals/TranceVisuals.metal` | Trance visual field shader | GLSL or AGSL, rewritten |
| **AVFoundation / AVAudioSession** | `PlatformAudioSession.swift` and playback | Playback clock, audio focus, routing | ExoPlayer / Media3 + AudioManager |
| **SwiftUI** | most of 229 files | Entire UI | Compose, rewritten |

### The display link is the hard part

`EngineLightEngine.swift` (662 lines) is where the real difficulty sits. It
drives brightness in real time against the audio clock, and the app's whole
value depends on light and sound staying locked together. Frame-callback
semantics, vsync behaviour, and timing jitter differ enough between platforms
that this needs designing for Android rather than porting.

Treat drift between the audio clock and the light clock as the primary risk.
Everything else here is ordinary work.

### Already-abstracted seams

Five files mark the boundaries the iOS/macOS split already forced into the open,
and they are a useful map of what is platform-specific:

```
PlatformAccessibility.swift   PlatformApplication.swift
PlatformAudioSession.swift    PlatformFullScreenCover.swift
PlatformViewModifiers.swift
```

The codebase keeps `#if os(...)` confined to these seams by convention, so where
you find one you have found a genuine platform difference rather than an
accident.

## Suggested order

1. Port `EngineWaveforms.swift` and its tests. Small, self-contained, provable.
2. Read `LightSession.swift` and load a bundled `session_*.json`.
3. Build a frame-callback loop that plays a session against an audio clock.
   This is the risk; find out early whether the timing holds.
4. Port `SessionGenerator.swift`.
5. Only then start on UI.

## Things that will surprise you

- **iOS 18 versus iOS 26.** The app deploys to iOS 18 but builds against the
  iOS 26 SDK, so AI analysis is gated behind `@available` with a keyword-based
  fallback. `CLAUDE.md` documents this. On Android you are choosing one path,
  not maintaining both.
- **Photosensitivity is a real constraint, not a formality.** The app gates
  flashing content behind an explicit warning during onboarding. Any port
  should keep an equivalent gate.
- **Bilateral mode drives left and right independently.** It is not a stereo
  effect on one field; it is two fields.
- **Sessions ship as bundle resources** and need target membership enabled in
  Xcode — an easy thing to miss when comparing file lists.

## Not in this repository

- **Screenshots and App Store assets** are deliberately untracked; ask for them
  directly if you want a UI reference.
- **`LumeLabel`**, the companion labelling app, is untracked. The Xcode project
  still declares the target, so a fresh clone shows it with missing files. This
  does not affect building the app: no target depends on it.
- **`Corpus/real/`** is empty by design. The training corpus is not published.
