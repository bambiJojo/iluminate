
# Neuro-Visual Entrainment App — Design & Engineering Summary

## Overview

This project is a precision iOS-based neuro-visual stimulation system designed to pair structured light modulation with hypnosis or guided audio. The system functions as a **real-time signal synthesis engine**, not a simple flashing light app.

Primary goals:

- Deep relaxation
- Absorption / trance support
- Mental focus
- Smooth nervous system entrainment

Built using **Swift**, **SwiftUI**, and **Xcode** for iPhone.

---

## Core System Architecture

UI Layer (SwiftUI)  
↓  
Session Controller  
↓  
Light Engine (real-time signal synthesis)  
↓  
Audio Engine (master clock)  
↓  
Hardware Output (Screen + Flash)

---

## Master Timing Model

**Audio time is the master clock.**

The light engine reads playback time from `AVAudioEngine` to maintain sample-accurate synchronization.

Each display frame:

1. Read audio playback time  
2. Look up frequency F(t)  
3. Look up intensity I(t)  
4. Advance oscillator phase  
5. Compute waveform  
6. Output brightness to screen and torch

Frame loop uses **CADisplayLink**.

---

## Oscillator Model

Continuous phase model (not discrete flashing):

brightness = waveform(phase) × intensity  
phase += 2π × frequency × dt

This creates smooth, non-jarring modulation.

---

## Waveform Types

| Waveform | Psychological Effect | Use Case |
|----------|----------------------|----------|
| Sine | Calm, immersive | Base induction & deep phases |
| Triangle | Structured guidance | Instructional pacing |
| Soft Pulse | Emphasis | Suggestion reinforcement |
| Ramp-Hold | Release sensation | Relaxation scripts |
| Noise-Modulated Sine | Organic feel | Long deep phases |

---

## Multi-Oscillator Layering

Signals can be combined:

brightness = baseWave × 0.7 + slowSubharmonic × 0.3

Creates depth and immersive “wave field” sensation.

---

## Bilateral Phase System

Left and right visual fields run with slight phase differences.

Effects:

- Perceived motion
- Reduced fixation
- Increased immersion

Optional slow phase drift prevents neural habituation.

---

## Entrainment Ramp Design

Frequency changes use glide curves instead of steps.

Ramp shapes:

- Linear
- Exponential ease-out (sinking effect)
- Sigmoid (natural transitions)

Micro-undulations keep signal alive and prevent fatigue.

---

## Light Score Model

Pre-analysis of audio generates:

- Frequency curve F(t)
- Intensity curve I(t)
- Waveform markers
- Event markers

Playback engine interpolates values.

---

## Audio System

`AVAudioEngine` provides:

- Playback
- Clock synchronization
- Future support for generative audio

---

## Flashlight Integration

Torch controlled via `AVCaptureDevice`.

Used as secondary ambient channel, not precision oscillator.

---

## Threading Model

| Thread | Responsibility |
|--------|----------------|
| UI | SwiftUI interface |
| Audio | AVAudioEngine |
| DisplayLink | Light engine |
| Background | ML/audio analysis |

Signal engine never depends on UI thread.

---

## Development Roadmap

### Phase 1 — Signal Engine Core
- Full-screen brightness modulation
- Phase accumulator
- Intensity control

### Phase 2 — Light Field Depth
- Bilateral phase control
- Multi-oscillator mixing
- Waveform library

### Phase 3 — Entrainment Intelligence
- Frequency ramps
- Light score playback

### Phase 4 — Audio Integration
- Audio sync
- Pre-analysis pipeline

### Phase 5 — Hardware Immersion
- Torch integration
- Optical enclosure optimization

### Phase 6 — Advanced Neurodynamics
- Phase drift
- Noise modulation
- Counterphase pulses

### Phase 7 — Adaptive V2 (Future)
- Biofeedback
- Generative hypnosis audio
- Closed-loop entrainment

---

## System Identity

This is a **neurodynamic environment generator**, not a flashing light app.
