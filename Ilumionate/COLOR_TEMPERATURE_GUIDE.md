# Color Temperature Implementation Guide

## Overview

Color temperature support has been added to provide **circadian rhythm benefits** based on research showing that different color temperatures affect alertness and melatonin production.

This is **NOT** for full-spectrum color (which has minimal entrainment value), but rather for warm/cool white control that affects physiology.

## Scientific Basis

### Why Color Temperature Matters

**Blue/Cool Light (5000-6500K)**
- ✅ Suppresses melatonin production
- ✅ Increases alertness and cognitive performance
- ✅ Mimics daylight
- **Use for**: Morning sessions, focus, concentration

**Warm/Amber Light (2000-3000K)**
- ✅ Minimal melatonin suppression
- ✅ Promotes relaxation
- ✅ Prepares body for sleep
- **Use for**: Evening sessions, relaxation, sleep prep

**Neutral White (3500-4500K)**
- ✅ Balanced response
- ✅ Comfortable for extended viewing
- **Use for**: Midday sessions, general use

### Research Sources
- Cajochen et al. (2005) - Blue light and circadian rhythms
- Lockley et al. (2006) - Melanopsin and alertness
- Chang et al. (2015) - Evening light exposure and sleep

## JSON Format

### Basic Usage

```json
{
  "time": 180,
  "frequency": 8.0,
  "intensity": 0.6,
  "waveform": "sine",
  "color_temperature": 3000
}
```

### Color Temperature Values

| Kelvin | Description | Color | Use Case |
|--------|-------------|-------|----------|
| **2000K** | Very warm | Deep amber/orange | Deep sleep prep |
| **2500K** | Warm | Amber | Evening relaxation |
| **3000K** | Warm white | Soft yellow-white | Late evening |
| **3500K** | Neutral warm | Neutral white | General evening |
| **4000K** | Cool white | Slightly blue-white | Daytime |
| **4500K** | Daylight | Blue-white | Morning/focus |
| **5000K** | Bright daylight | Cool blue-white | Alert focus |
| **5500K** | Very cool | Intense blue-white | Peak alertness |
| **6500K** | Cool daylight | Maximum blue | Maximum alertness |

### Smooth Interpolation

Color temperature smoothly interpolates between moments:

```json
{
  "light_score": [
    {"time": 0, "color_temperature": 5000},
    {"time": 300, "color_temperature": 2500}
  ]
}
```

Over 5 minutes, the color will gradually shift from cool white → warm amber.

## Session Design Patterns

### 1. Evening Wind Down

**Goal**: Prepare for sleep by gradually warming the light

```json
{
  "session_name": "Evening Wind Down",
  "duration_sec": 600,
  "light_score": [
    {
      "time": 0,
      "frequency": 10.0,
      "intensity": 0.4,
      "color_temperature": 4500
    },
    {
      "time": 240,
      "frequency": 7.0,
      "intensity": 0.6,
      "color_temperature": 2800
    },
    {
      "time": 480,
      "frequency": 5.0,
      "intensity": 0.7,
      "color_temperature": 2000
    }
  ]
}
```

**Effect**: Progressive color warming matches frequency descent into delta

### 2. Morning Energizer

**Goal**: Wake up alertness with cool blue-white light

```json
{
  "session_name": "Morning Energizer",
  "duration_sec": 480,
  "light_score": [
    {
      "time": 0,
      "frequency": 6.0,
      "intensity": 0.3,
      "color_temperature": 3000
    },
    {
      "time": 240,
      "frequency": 10.0,
      "intensity": 0.6,
      "color_temperature": 5200
    },
    {
      "time": 360,
      "frequency": 12.0,
      "intensity": 0.7,
      "color_temperature": 5800
    }
  ]
}
```

**Effect**: Progressively cooler light increases alertness alongside frequency

### 3. Neutral Session (No Color)

**Goal**: Pure entrainment without circadian effects

```json
{
  "time": 180,
  "frequency": 8.0,
  "intensity": 0.6,
  "waveform": "sine"
}
```

Omit `color_temperature` field for pure white light (no tint).

## Best Practices

### ✅ DO

**Match Color to Time of Day**
- Morning: 5000-6500K (cool, alerting)
- Afternoon: 4000-5000K (neutral)
- Evening: 2500-3500K (warm, relaxing)
- Night: 2000-2500K (very warm, sleep-friendly)

**Match Color to Frequency**
- High frequency (12+ Hz): Cooler temps (5000K+)
- Mid frequency (8-12 Hz): Neutral temps (3500-4500K)
- Low frequency (4-8 Hz): Warmer temps (2500-3500K)
- Very low (<4 Hz): Very warm (2000-2500K)

**Use Smooth Transitions**
- Spread color changes over 2-5 minutes minimum
- The interpolation handles this automatically

### ❌ DON'T

**Avoid Conflicting Signals**
```json
// BAD: Cool light for sleep prep
{
  "time": 300,
  "frequency": 4.0,
  "color_temperature": 6500  // ❌ Too cool for theta/sleep
}
```

**Don't Change Too Fast**
```json
// BAD: Jarring color jumps
{
  "light_score": [
    {"time": 0, "color_temperature": 6500},
    {"time": 60, "color_temperature": 2000}  // ❌ Too fast (4500K in 1 min)
  ]
}
```

Aim for ~500-1000K change per minute maximum.

**Don't Use Cool Light at Night**
```json
// BAD: Disrupts circadian rhythm
{
  "session_name": "Evening Session",
  "color_temperature": 6000  // ❌ Will suppress melatonin
}
```

## Implementation Details

### Color Conversion Algorithm

The implementation uses **Tanner Helland's blackbody radiation algorithm**:

```
For temperature T (in Kelvin):
- 2000K → RGB(1.0, 0.65, 0.18)  // Warm amber
- 3500K → RGB(1.0, 0.96, 0.87)  // Neutral white
- 6500K → RGB(1.0, 0.99, 1.0)   // Cool blue-white
```

This produces **scientifically accurate color temperatures** matching natural daylight curves.

### How It's Applied

```swift
// In SessionView:
Color(white: brightness)
    .colorMultiply(colorForTemperature(kelvin))
```

The color multiplier **tints the white brightness** without affecting the entrainment frequency.

### Performance

- Zero overhead when not using color temperature
- Smooth GPU-accelerated color multiplication
- No impact on CADisplayLink timing

## Example Sessions Included

### evening_wind_down.json (10 minutes)
```
Arc: 10 Hz @ 4500K → 6 Hz @ 2800K → 5 Hz @ 2000K → 8 Hz @ 2500K
Purpose: Sleep preparation with progressive warming
```

### morning_energizer.json (8 minutes)
```
Arc: 6 Hz @ 3000K → 10 Hz @ 5200K → 12 Hz @ 5800K → 9 Hz @ 5000K
Purpose: Wake-up with cool blue-white light
```

## Troubleshooting

### Color doesn't appear
- Verify `color_temperature` field is present in JSON
- Check value is between 2000-6500
- Ensure device brightness is sufficient to see tint

### Color looks wrong
- Very warm temps (2000K) should look orange-amber
- Cool temps (6500K) should look slightly blue-white
- This is scientifically correct!

### Color changes too abruptly
- Add more intermediate moments
- The player interpolates linearly between moments
- Aim for gradual changes (500-1000K per minute)

## Optional: Omitting Color Temperature

If you **don't specify** `color_temperature`, the session uses **pure white light** (no tint). This is perfectly valid for sessions where you don't want circadian effects.

```json
{
  "time": 180,
  "frequency": 8.0,
  "intensity": 0.6,
  "waveform": "sine"
  // No color_temperature = pure white
}
```

## Summary

Color temperature provides:
- ✅ **Circadian benefits** (alertness vs. relaxation)
- ✅ **Time-of-day optimization** (morning vs. evening)
- ✅ **Research-backed physiology** (melatonin, alertness)
- ✅ **Smooth interpolation** (automatic transitions)
- ❌ **NOT** for entrainment efficacy (frequency is what matters)

Use it to **complement** your frequency/waveform entrainment with circadian-appropriate lighting.
