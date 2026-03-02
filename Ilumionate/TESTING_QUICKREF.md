# Testing Quick Reference

## Run Tests

| Action | Shortcut | Command Line |
|--------|----------|--------------|
| Run all tests | `⌘U` | `xcodebuild test -scheme Ilumionate` |
| Run single test | Click diamond | N/A |
| Debug test | Click diamond + hold | N/A |

## Validate Session

```swift
// Quick validation
let result = SessionDiagnostics.validateSession(session)
print(result.summary)

// Show all issues
for error in result.errors {
    print("❌", error)
}
for warning in result.warnings {
    print("⚠️", warning)
}
```

## Analyze Session

```swift
let analysis = SessionDiagnostics.analyzeSession(session)
print("Effectiveness:", analysis.estimatedEntrainmentEffectiveness.emoji)
print("Frequency range:", analysis.frequencyRange)
print("Intensity range:", analysis.intensityRange)

for suggestion in analysis.suggestions {
    print("💡", suggestion)
}
```

## Debug Engine

```swift
// Capture state
let snapshot = SessionDiagnostics.captureEngineState(engine)
print(snapshot.description)

// Quick checks
print("Running:", engine.isRunning)
print("Frequency:", engine.currentFrequency, "Hz")
print("Brightness:", engine.brightness)
print("Bilateral:", engine.bilateralMode)
```

## Debug Player

```swift
// Capture state
let snapshot = SessionDiagnostics.capturePlayerState(player)
print(snapshot.description)

// Quick checks
print("Time:", player.currentTime, "/", player.session.duration_sec)
print("Progress:", Int(player.progress * 100), "%")
print("Playing:", player.isPlaying)
```

## Log Session

```swift
// Detailed log
print(SessionDiagnostics.logSessionDetails(session))
```

## Performance Targets

| Component | Target |
|-----------|--------|
| Waveform eval (10K) | <10ms |
| Ramp curves (10K) | <10ms |
| Player queries (1K) | <100ms |
| Frame budget (120Hz) | 8.3ms |

## Safety Limits

| Parameter | Limit | Reason |
|-----------|-------|--------|
| Max frequency | 60 Hz | Photosensitive seizure risk |
| Rapid changes | <20 Hz/0.5s | Seizure prevention |
| Min frequency | 0.1 Hz | Practical lower bound |
| Intensity range | 0.0-1.0 | Display capability |
| Color temp | 2000-6500K | Natural range |

## Common Patterns

### Create Test Session

```swift
let session = LightSession(
    session_name: "Test",
    duration_sec: 60.0,
    light_score: [
        LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine),
        LightMoment(time: 30, frequency: 20, intensity: 0.8, waveform: .softPulse),
        LightMoment(time: 60, frequency: 10, intensity: 0.5, waveform: .sine)
    ]
)
```

### Test Playback

```swift
let engine = LightEngine()
let player = LightScorePlayer(session: session)

engine.attachSession(player: player)
engine.start()
player.play()

// ... test ...

player.stop()
engine.detachSession()
engine.stop()
```

### Check Interpolation

```swift
let player = LightScorePlayer(session: session)

// Query at specific time
let state = player.state(at: 15.0)
print("Frequency:", state.frequency)
print("Intensity:", state.intensity)
print("Bilateral:", state.bilateral)
```

### Verify Range

```swift
#expect(value >= 0.0, "Should not be negative")
#expect(value <= 1.0, "Should not exceed 1.0")
```

### Test Precision

```swift
#expect(abs(value1 - value2) < 0.001, "Values should match")
```

## Effectiveness Rating

| Stars | Rating | Description |
|-------|--------|-------------|
| ⭐️ | Minimal | Unlikely to produce entrainment |
| ⭐️⭐️ | Low | Weak entrainment effect |
| ⭐️⭐️⭐️ | Moderate | Noticeable effect for some users |
| ⭐️⭐️⭐️⭐️ | Good | Strong effect for most users |
| ⭐️⭐️⭐️⭐️⭐️ | Excellent | Optimal entrainment parameters |

## Checklist Before Release

Session Quality:
- [ ] Validate with zero errors
- [ ] Review all warnings
- [ ] Effectiveness rating ≥ Good
- [ ] Test playback visually
- [ ] Comfortable brightness
- [ ] Smooth transitions

Code Quality:
- [ ] All tests pass
- [ ] No performance regressions
- [ ] No memory leaks
- [ ] Thread-safe
- [ ] Documented

## File Organization

```
Tests/
  ├── LightEngineTests.swift       # Unit tests
  ├── SessionIntegrationTests.swift # Integration tests
  └── PerformanceTests.swift       # Performance tests

Source/
  ├── EngineLightEngine.swift      # Core engine
  ├── EngineWaveforms.swift        # Waveforms & ramps
  ├── LightScorePlayer.swift       # Timeline player
  ├── LightSession.swift           # Data models
  ├── UISessionView.swift          # Rendering
  ├── SessionPlayerView.swift      # Player UI
  └── SessionDiagnostics.swift     # Validation tools
```

## Test Categories

- **Unit**: Individual component correctness
- **Integration**: Components working together
- **Performance**: Speed and efficiency
- **Safety**: Seizure risk prevention
- **Stability**: Numerical precision over time

## When to Use Each Tool

| Tool | When |
|------|------|
| `validateSession()` | Before loading session |
| `analyzeSession()` | During session design |
| `captureEngineState()` | When engine behaves unexpectedly |
| `capturePlayerState()` | When timing seems off |
| `logSessionDetails()` | When reviewing session structure |

## Common Test Failures

### "Value out of range"
- Check waveform produces 0.0-1.0
- Check brightness bounds
- Check frequency clamping

### "Interpolation incorrect"
- Verify moment times are sorted
- Check alpha calculation
- Verify boundary handling

### "Performance too slow"
- Profile with Instruments
- Check for expensive operations in tight loops
- Verify no accidental O(n²) algorithms

### "Numerical instability"
- Check for accumulation errors
- Verify phase wrapping
- Check floating point precision

## Resources

- **TESTING_GUIDE.md**: Complete testing documentation
- **PHASE3_COMPLETE.md**: Phase 3 summary
- **Test files**: Comprehensive examples
- **SessionDiagnostics.swift**: Tool implementation

---

**Quick Start**: Press `⌘U` to run all tests!
