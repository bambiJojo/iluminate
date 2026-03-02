
# CLAUDE.md

This file provides guidance for working on the **Neuro‑Visual Entrainment App** codebase.

---

## Project Overview

This project is a **neuro‑visual entrainment and hypnosis support app** for iPhone.

It synchronizes:

- Structured light modulation (screen + flashlight)
- Hypnosis / guided audio playback
- Pre‑analyzed audio pacing data

The app functions as a **real‑time signal synthesis engine**, not a typical UI‑driven application.

Primary goals:

- Deep relaxation support
- Trance / absorption facilitation
- Mental focus and internal attention
- Smooth nervous system entrainment

---

## Core Architecture

### Technology Stack

- **Language:** Swift  
- **UI Framework:** SwiftUI  
- **Audio:** AVAudioEngine  
- **Timing:** CADisplayLink (display refresh loop)  
- **ML/Analysis:** Core ML + SoundAnalysis (offline pre‑analysis)  

---

## Architectural Model

UI Layer (SwiftUI)  
↓  
Session Controller  
↓  
Light Engine (real‑time oscillator system)  
↓  
Audio Engine (master clock)  
↓  
Hardware Output (Screen + Flash)

This is a **signal‑driven architecture**, not form‑driven or CRUD‑style.

---

## Master Timing Rule

**Audio playback time is the master clock.**

All light modulation is derived from AVAudioEngine’s playback time to ensure:

- Phase stability
- No drift
- Tight audio‑visual coherence

SwiftUI timers or animation clocks must NOT drive entrainment logic.

---

## Light Engine Design

The light engine is a continuous oscillator, not a blinking system.

Core model:

brightness = waveform(phase) × intensity  
phase += 2π × frequency × dt

Features:

- Continuous phase accumulator
- Frame‑synchronized updates via CADisplayLink
- Smooth interpolation of curves

---

## Light Score System

Audio files are pre‑analyzed to generate a **Light Score**:

- Frequency curve F(t)
- Intensity curve I(t)
- Waveform markers
- Event markers

Playback engine interpolates values during session.

Real‑time audio reanalysis is NOT required for V1.

---

## Waveform Engine

Supported waveform types:

| Type | Use |
|------|-----|
| Sine | Base induction & deep phases |
| Triangle | Guided pacing |
| Soft Pulse | Suggestion emphasis |
| Ramp-Hold | Relaxation/release cues |
| Noise‑modulated sine | Long deep phases |

Waveform changes are accents, not constant behavior.

---

## Multi‑Oscillator System

Multiple oscillators may be layered:

- Base entrainment frequency
- Subharmonic slow drift
- Bilateral phase offsets (left vs right)

Used to create immersive visual field effects.

---

## Bilateral Phase Model

Left and right visual fields can run with small phase differences to produce:

- Perceived motion
- Reduced fixation
- Increased immersion

Large offsets or mismatched frequencies must be avoided.

---

## Entrainment Ramp Rules

Frequency transitions must use smooth ramps:

- Linear
- Exponential ease‑out
- Sigmoid

No hard jumps between frequencies.

Micro‑variability is used to prevent neural habituation.

---

## Audio System

AVAudioEngine provides:

- Playback
- Master timing reference
- Future generative audio support

Light engine queries audio playback time each frame.

---

## Flashlight Integration

Torch is a secondary ambient channel via AVCaptureDevice.

Used for field illumination, not high‑precision waveform shaping.

---

## Threading Model

| Thread | Role |
|-------|------|
| UI | SwiftUI interface only |
| Audio | AVAudioEngine |
| Display Loop | Light oscillator math |
| Background | ML/audio analysis |

Signal engine must not depend on UI thread.

---

## What This App Is NOT

- Not a form‑based app  
- Not data‑entry driven  
- Not network dependent  
- Not a medical device  
- Not claiming clinical or therapeutic outcomes  

It is a **sensory environment generator**.

---

## Development Priority Order

1. Signal stability  
2. Phase continuity  
3. Smooth ramps  
4. Audio sync  
5. Immersive field effects  
6. AI analysis pipeline  
7. Future biofeedback adaptation  

Performance and timing integrity are more important than UI complexity.
