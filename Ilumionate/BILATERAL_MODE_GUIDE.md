# Bilateral Mode Session Guide

## Overview

Bilateral mode creates alternating left/right visual stimulation by phase-shifting the right side of the screen. This guide covers how to use bilateral mode effectively in your session JSON files with smooth, imperceptible transitions.

## How Bilateral Mode Works

### Phase Offset

- **Mono Mode**: Left and right sides are synchronized (phase offset = 0.0)
- **Bilateral Mode**: Right side is phase-shifted (default offset = 0.5)
  - `0.5` = Perfect alternation (when left is bright, right is dark)
  - `0.25` = Quadrature (90° phase shift)
  - `0.0` = Synchronized (same as mono)

### Smooth Transitions

The key feature is **gradual bilateral transitions** - the two sides smoothly "slip apart" over several seconds instead of instantly switching.

```
Instant (jarring):
Left:  ████████████████████████
Right: ████████      ████      
             ↑ Abrupt change

Smooth (8 seconds):
Left:  ████████████████████████
Right: ████████▓▓▓▓▒▒▒▒░░      
             ↑ Gradual slip
```

## JSON Session Format

### Basic Fields

```json
{
  "time": 180,
  "frequency": 8.0,
  "intensity": 0.6,
  "waveform": "sine",
  "bilateral": true,
  "bilateral_transition_duration": 8.0
}
```

### Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `bilateral` | boolean | No | Enable/disable bilateral mode |
| `bilateral_transition_duration` | number | No | Seconds to transition (default: 3.0) |

## Design Patterns

### 1. Simple On/Off Pattern

Use bilateral for the deepest part of the session:

```json
{
  "light_score": [
    {"time": 0, "frequency": 10.0, "bilateral": false},
    {"time": 120, "frequency": 8.0, "bilateral": true, "bilateral_transition_duration": 8.0},
    {"time": 480, "frequency": 8.0, "bilateral": true},
    {"time": 600, "frequency": 10.0, "bilateral": false, "bilateral_transition_duration": 10.0}
  ]
}
```

**Use case**: Deep relaxation sessions where bilateral stimulation enhances the trance state.

### 2. Wave Pattern

Alternate between mono and bilateral multiple times:

```json
{
  "light_score": [
    {"time": 0, "frequency": 10.0, "bilateral": false},
    {"time": 60, "frequency": 9.0, "bilateral": true, "bilateral_transition_duration": 5.0},
    {"time": 120, "frequency": 8.5, "bilateral": false, "bilateral_transition_duration": 4.0},
    {"time": 180, "frequency": 8.0, "bilateral": true, "bilateral_transition_duration": 6.0},
    {"time": 240, "frequency": 7.5, "bilateral": false, "bilateral_transition_duration": 5.0}
  ]
}
```

**Use case**: Progressive deepening with alternating stimulation patterns.

### 3. Deep Immersion

Long bilateral section for extended trance:

```json
{
  "light_score": [
    {"time": 0, "frequency": 9.0, "bilateral": false},
    {"time": 180, "frequency": 7.5, "bilateral": true, "bilateral_transition_duration": 10.0},
    {"time": 720, "frequency": 7.5, "bilateral": true},
    {"time": 780, "frequency": 9.0, "bilateral": false, "bilateral_transition_duration": 12.0}
  ]
}
```

**Use case**: Hypnagogic sessions where you want sustained bilateral stimulation during the deepest phase.

## Transition Duration Guidelines

### Recommended Durations

| Scenario | Duration | Effect |
|----------|----------|--------|
| **Quick shift** | 2-4 seconds | Noticeable but smooth |
| **Standard** | 5-8 seconds | Very smooth, barely perceptible |
| **Ultra-subtle** | 10-15 seconds | Completely imperceptible |

### Choosing Transition Duration

**Short transitions (2-4s):**
- When frequency is also changing rapidly
- For experienced users
- During transitions between session phases

**Medium transitions (5-8s):**
- Default choice for most sessions
- Balances smoothness with timing
- Works well during stable frequency ranges

**Long transitions (10-15s):**
- Deep meditation/hypnosis sessions
- When maintaining unbroken trance state is critical
- During the deepest part of the session

## Example Sessions

### Deep Relaxation Session

Progressive descent with bilateral activation at theta range:

```json
{
  "session_name": "Deep Relaxation",
  "duration_sec": 720,
  "light_score": [
    {
      "time": 0,
      "frequency": 10.0,
      "intensity": 0.2,
      "waveform": "sine",
      "bilateral": false
    },
    {
      "time": 180,
      "frequency": 8.5,
      "intensity": 0.5,
      "waveform": "sine",
      "bilateral": true,
      "bilateral_transition_duration": 8.0
    },
    {
      "time": 360,
      "frequency": 7.0,
      "intensity": 0.7,
      "waveform": "triangle",
      "bilateral": true
    },
    {
      "time": 480,
      "frequency": 6.0,
      "intensity": 0.8,
      "waveform": "sine",
      "bilateral": true
    },
    {
      "time": 600,
      "frequency": 7.0,
      "intensity": 0.6,
      "waveform": "sine",
      "bilateral": false,
      "bilateral_transition_duration": 10.0
    },
    {
      "time": 720,
      "frequency": 10.0,
      "intensity": 0.3,
      "waveform": "sine",
      "bilateral": false
    }
  ]
}
```

**Session Arc:**
- 0-3 min: Alpha range, mono (settling in)
- 3-8 min: Alpha→Theta, bilateral ON over 8s (deep descent)
- 8-10 min: Theta range, bilateral (deep state)
- 10-12 min: Theta→Alpha, bilateral OFF over 10s (gentle return)

### Focused Trance Session

Sustained bilateral for enhanced focus:

```json
{
  "session_name": "Focused Trance",
  "duration_sec": 900,
  "light_score": [
    {
      "time": 0,
      "frequency": 9.0,
      "intensity": 0.2,
      "waveform": "sine",
      "bilateral": false
    },
    {
      "time": 120,
      "frequency": 8.5,
      "intensity": 0.4,
      "waveform": "sine",
      "bilateral": true,
      "bilateral_transition_duration": 6.0
    },
    {
      "time": 300,
      "frequency": 7.75,
      "intensity": 0.6,
      "waveform": "triangle",
      "bilateral": true
    },
    {
      "time": 600,
      "frequency": 8.0,
      "intensity": 0.75,
      "waveform": "sine",
      "bilateral": true
    },
    {
      "time": 780,
      "frequency": 8.0,
      "intensity": 0.55,
      "waveform": "sine",
      "bilateral": false,
      "bilateral_transition_duration": 8.0
    },
    {
      "time": 900,
      "frequency": 9.0,
      "intensity": 0.3,
      "waveform": "sine",
      "bilateral": false
    }
  ]
}
```

**Session Arc:**
- 0-2 min: Alpha, mono (entry)
- 2-13 min: Alpha→Theta, bilateral ON over 6s (focused trance state)
- 13-15 min: Theta→Alpha, bilateral OFF over 8s (smooth exit)

## Best Practices

### 1. Transition Timing

✅ **DO:**
- Use longer transitions when entering bilateral mode during deep states
- Use shorter transitions when frequency is also changing
- Match transition duration to the overall session pace

❌ **DON'T:**
- Use instant transitions (always specify `bilateral_transition_duration`)
- Change bilateral mode at the same moment as major frequency changes
- Use transitions shorter than 2 seconds

### 2. Session Structure

✅ **DO:**
- Enable bilateral during theta/delta ranges (6-8 Hz)
- Return to mono before ending the session
- Give users at least 1-2 minutes in bilateral before transitioning out

❌ **DON'T:**
- Toggle bilateral mode rapidly (< 1 minute between changes)
- End a session while still in bilateral mode
- Enable bilateral at very high frequencies (>12 Hz)

### 3. User Experience

✅ **DO:**
- Test your sessions to ensure transitions are imperceptible
- Use longer transitions for first-time users
- Document bilateral usage in session descriptions

❌ **DON'T:**
- Surprise users with sudden bilateral changes
- Use bilateral for entire sessions (reserve it for key moments)
- Skip the transition duration parameter (always specify it)

## Technical Details

### How the Engine Handles Transitions

```swift
// When bilateral mode changes, the engine:
1. Detects mode change in didSet { }
2. Sets isBilateralTransitioning = true
3. Each frame, advances bilateralTransitionElapsed
4. Calculates progress with cubic ease-out curve
5. Interpolates currentBilateralOffset from 0.0 → 0.5 (or vice versa)
6. Evaluates waveform for right side: phase + currentBilateralOffset
```

### Ease-Out Curve

The transition uses a **cubic ease-out** curve for natural perception:

```
easedProgress = 1 - (1 - progress)³

Progress over 8 seconds:
t=0s: 0.00 (mono)
t=2s: 0.58 (halfway in perception)
t=4s: 0.88 (almost there)
t=6s: 0.97 (nearly complete)
t=8s: 1.00 (full bilateral)
```

This curve matches how humans perceive gradual changes - faster at first, then settling gently.

## Troubleshooting

### Transition feels too fast
- Increase `bilateral_transition_duration` to 10-15 seconds
- Ensure frequency isn't changing at the same time

### Can't notice when bilateral activates
✅ **This is correct!** The transition should be imperceptible. Check the SessionPlayerView UI to confirm mode changes.

### Jarring sensation when entering bilateral
- Increase transition duration
- Check that intensity isn't changing abruptly at the same moment
- Ensure session is in appropriate frequency range (6-10 Hz)

### Bilateral seems to have no effect
- Ensure the device is in landscape orientation (left/right split visible)
- Check that `bilateralPhaseOffset` is 0.5 (default)
- Verify waveform is not too subtle (triangle is more visible than sine)

## Summary

Bilateral mode with smooth transitions provides a professional, therapeutic experience. Key points:

- **Always specify transition duration** - Never use instant switches
- **Use 5-10 second transitions** for most cases
- **Reserve bilateral for deep states** - Theta range (6-8 Hz) is ideal
- **Plan the session arc** - On during deep phase, off during exit
- **Test thoroughly** - Transitions should be completely imperceptible

The gradual "slipping apart" effect maintains the user's trance state while adding the benefits of bilateral stimulation.
