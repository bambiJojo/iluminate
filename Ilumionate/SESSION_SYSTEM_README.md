# Light Session System Documentation

## Overview

The Light Session system allows you to create pre-programmed light entrainment experiences defined in JSON files. Sessions contain a timeline of control points that specify frequency, intensity, waveform, and other parameters. The engine smoothly interpolates between these points during playback.

## Architecture

### Components

1. **LightSession** (`LightSession.swift`)
   - Data model representing a complete session
   - Decoded from JSON files
   - Contains metadata and an array of `LightMoment` control points

2. **LightScoreReader** (`LightScoreReader.swift`)
   - Loads and validates session JSON files
   - Supports bundled resources and imported files
   - Discovers available sessions in the app bundle

3. **LightScorePlayer** (`LightScorePlayer.swift`)
   - Runtime interpolator that plays back sessions
   - Calculates target state at any given time
   - Handles playback control (play/pause/stop/seek)

4. **LightEngine Integration** (`EngineLightEngine.swift`)
   - Engine can be driven by a `LightScorePlayer`
   - Automatically applies session state each frame
   - Supports both manual and session-driven modes

### UI Components

- **SessionLibraryView** - Browse and select available sessions
- **SessionPlayerView** - Full-screen player with controls and progress display

## JSON Session Format

### Basic Structure

```json
{
  "session_name": "Deep Relaxation",
  "duration_sec": 600,
  "light_score": [
    {
      "time": 0,
      "frequency": 14.0,
      "intensity": 0.5,
      "waveform": "sine",
      "ramp_duration": 5.0,
      "bilateral": false
    }
  ]
}
```

### Fields

#### Session Level
- `session_name` (string, required) - Display name for the session
- `duration_sec` (number, required) - Total session duration in seconds
- `light_score` (array, required) - Array of `LightMoment` control points

#### LightMoment Fields
- `time` (number, required) - Timestamp in seconds from session start
- `frequency` (number, required) - Target frequency in Hz (0.1 - 100.0)
- `intensity` (number, required) - Brightness intensity (0.0 - 1.0)
- `waveform` (string, required) - Waveform type (see below)
- `ramp_duration` (number, optional) - Override ramp duration for this transition
- `bilateral` (bool, optional) - Enable bilateral alternating mode
- `bilateral_transition_duration` (number, optional) - Duration in seconds for smooth bilateral mode transition (default: 3.0)

#### Supported Waveforms
- `"sine"` - Smooth sine wave
- `"triangle"` - Linear triangle wave
- `"soft_pulse"` - Smoothed pulse with ease curves
- `"ramp_hold"` - Ramp up then hold pattern
- `"noise_sine"` - Sine with subtle noise modulation

## Usage

### 1. Creating a Session File

Create a JSON file following the format above. Place it in your Xcode project and ensure it's included in the app bundle (target membership).

**Example:** `deep_relaxation_session.json`

```json
{
  "session_name": "Deep Relaxation",
  "duration_sec": 600,
  "light_score": [
    {
      "time": 0,
      "frequency": 14.0,
      "intensity": 0.3,
      "waveform": "sine",
      "ramp_duration": 5.0,
      "bilateral": false
    },
    {
      "time": 60,
      "frequency": 10.0,
      "intensity": 0.5,
      "waveform": "sine",
      "ramp_duration": 10.0,
      "bilateral": false
    },
    {
      "time": 180,
      "frequency": 8.0,
      "intensity": 0.6,
      "waveform": "soft_pulse",
      "ramp_duration": 15.0,
      "bilateral": false
    },
    {
      "time": 600,
      "frequency": 12.0,
      "intensity": 0.2,
      "waveform": "sine",
      "ramp_duration": 5.0,
      "bilateral": false
    }
  ]
}
```

### 2. Loading a Session Programmatically

```swift
// Load from bundle
do {
    let session = try LightScoreReader.loadSession(named: "deep_relaxation_session")
    print("Loaded: \(session.displayName)")
} catch {
    print("Error: \(error.localizedDescription)")
}

// Load from URL
if let url = Bundle.main.url(forResource: "deep_relaxation_session", withExtension: "json") {
    let session = try LightScoreReader.loadSession(from: url)
}

// Discover all bundled sessions
let availableSessions = LightScoreReader.discoverBundledSessions()
```

### 3. Playing a Session

```swift
// Create a player
let player = LightScorePlayer(session: session)

// Attach to engine
engine.attachSession(player: player)

// Start engine and playback
engine.start()
player.play()

// In your CADisplayLink or timer, the player updates automatically
// The engine will follow the session's control curve
```

### 4. Using the UI

```swift
// Show session library
@State private var showSessionLibrary = false

Button("Browse Sessions") {
    showSessionLibrary = true
}
.sheet(isPresented: $showSessionLibrary) {
    SessionLibraryView(engine: engine)
}
```

## How Interpolation Works

The `LightScorePlayer` doesn't step through discrete points. Instead, it interpolates between consecutive moments:

1. **Time Query** - Player is asked for state at time `t`
2. **Find Neighbors** - Locate the moments before and after `t`
3. **Calculate Alpha** - `alpha = (t - prevTime) / (nextTime - prevTime)`
4. **Interpolate** - Linear interpolation:
   - `frequency = prev.frequency + (next.frequency - prev.frequency) * alpha`
   - `intensity = prev.intensity + (next.intensity - prev.intensity) * alpha`
5. **Apply** - Engine ramps smoothly to these interpolated targets

### Waveform and Mode Changes
- Waveform and bilateral mode use the *previous* moment's value until the next moment is reached
- This prevents jarring mid-transition changes

## Best Practices

### Session Design

1. **Start Gentle** - Begin with moderate frequency/intensity
2. **Smooth Transitions** - Use appropriate `ramp_duration` values
3. **Progressive Arc** - Consider the overall energy curve
4. **Cool Down** - End sessions with a gentle ramp down

### Timing

- Place moments at key transition points
- Don't over-specify - the interpolation handles smooth curves
- Typical moment spacing: 30-120 seconds

### Frequencies

- **Delta (0.5-4 Hz)** - Deep relaxation, sleep
- **Theta (4-8 Hz)** - Meditation, creativity
- **Alpha (8-14 Hz)** - Relaxed alertness
- **Beta (14-30 Hz)** - Focus, concentration
- **Gamma (30+ Hz)** - High cognitive function

### Example Session Arc

```
0:00  - 14 Hz (Alpha) - Settle in
1:00  - 10 Hz (Alpha) - Deepen
3:00  - 8 Hz (Theta) - Transition to deep state
5:00  - 6 Hz (Theta) - Deep meditation
7:00  - 4 Hz (Delta) - Deepest point
9:00  - 8 Hz (Theta) - Begin return
10:00 - 12 Hz (Alpha) - Gentle awakening
```

## Session Validation

The `LightScoreReader` automatically validates:

✅ Duration is positive  
✅ Light score is not empty  
✅ All moments are within session duration  
✅ Frequencies are in valid range (0.1-100 Hz)  
✅ Intensities are in valid range (0.0-1.0)  
✅ Moments are sorted by time  

Invalid sessions will throw descriptive errors.

## Advanced Features

### Custom Ramp Duration per Moment

Override the engine's default ramp duration for specific transitions:

```json
{
  "time": 180,
  "frequency": 8.0,
  "intensity": 0.6,
  "waveform": "soft_pulse",
  "ramp_duration": 30.0  // 30 second smooth transition
}
```

### Bilateral Mode

Enable alternating left/right stimulation at specific points:

```json
{
  "time": 120,
  "frequency": 15.0,
  "intensity": 0.7,
  "waveform": "sine",
  "bilateral": true,  // Split left/right with phase offset
  "bilateral_transition_duration": 5.0  // 5 second smooth "slipping apart" transition
}
```

**How Bilateral Transitions Work:**

When the session changes from mono to bilateral (or vice versa), the left and right fields gradually "slip apart" over the specified duration:

- **Mono → Bilateral**: The right field's phase offset gradually increases from 0 to the target offset (default 0.5 = full alternation)
- **Bilateral → Mono**: The phase offset gradually decreases back to 0, bringing both sides back into sync

This creates a smooth, imperceptible transition that won't jar the user. The default transition duration is 3.0 seconds, but you can customize it per moment using `bilateral_transition_duration`.

### Session Metadata

Add additional optional fields for organization:

```json
{
  "id": "uuid-here",  // Optional UUID for tracking
  "session_name": "Focus Enhancement",
  "duration_sec": 300,
  "light_score": [...]
}
```

## Example Sessions Included

### 1. Deep Relaxation (10 minutes)
- Progressive descent from Alpha → Theta → Delta
- Gentle sine waves throughout
- Perfect for meditation or pre-sleep

### 2. Focus Enhancement (5 minutes)
- Ramp from Alpha → Beta range
- Uses bilateral stimulation
- Varied waveforms for engagement

## Troubleshooting

### Session Not Loading
- Verify JSON syntax is valid
- Check that file is included in app bundle (target membership)
- Look for validation errors in console

### Jerky Transitions
- Increase `ramp_duration` values
- Ensure moments aren't too close together
- Check that frequency changes aren't too large

### Session Not Playing
- Verify engine is started: `engine.start()`
- Verify player is started: `player.play()`
- Check that session is attached: `engine.attachSession(player: player)`

## Future Enhancements

Potential additions to the session system:

- Audio synchronization (Phase 4)
- Dynamic intensity curves per moment
- Conditional branching based on time of day
- User feedback integration
- Export/import custom sessions
- Session editor UI
