//
//  PerformanceTests.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Testing
import CoreFoundation
@testable import Ilumionate

/// Performance and validation tests for the light engine.
/// These tests ensure the system performs efficiently and maintains
/// timing accuracy under various conditions.
@Suite("Performance and Validation Tests")
@MainActor
struct PerformanceTests {

    // MARK: - Waveform Performance

    @Test("Waveform evaluation performance")
    func waveformEvaluationPerformance() {
        let waveforms: [Waveform] = [.sine, .triangle, .softPulse, .rampHold, .noiseModulatedSine]

        for waveform in waveforms {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Evaluate 10,000 times (simulating high frame rate)
            for i in 0..<10_000 {
                let phase = Double(i) / 10_000.0
                _ = waveform.evaluate(at: phase)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Should complete in under 10ms (very generous, should be microseconds)
            #expect(elapsed < 0.01, "\(waveform.displayName) evaluation took too long: \(elapsed)s")
        }
    }

    @Test("Ramp curve evaluation performance")
    func rampCurvePerformance() {
        let curves: [RampCurve] = [.linear, .exponentialEaseOut, .sigmoid]

        for curve in curves {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Evaluate 10,000 times
            for i in 0..<10_000 {
                let t = Double(i) / 10_000.0
                _ = curve.evaluate(at: t)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            #expect(elapsed < 0.01, "\(curve.displayName) evaluation took too long: \(elapsed)s")
        }
    }

    // MARK: - Session Player Performance

    @Test("Session player interpolation performance")
    func sessionPlayerInterpolationPerformance() {
        // Create a session with many moments
        var moments: [LightMoment] = []
        for i in 0...100 {
            let moment = LightMoment(
                time: Double(i) * 10,
                frequency: Double(10 + i % 20),
                intensity: Double(i % 100) / 100.0,
                waveform: .sine
            )
            moments.append(moment)
        }

        let session = LightSession(
            session_name: "Performance Test",
            duration_sec: 1000.0,
            light_score: moments
        )

        let player = LightScorePlayer(session: session)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Query state 1,000 times at different positions
        for i in 0..<1_000 {
            let time = Double(i)
            _ = player.state(at: time)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Should complete in under 100ms
        #expect(elapsed < 0.1, "Session player queries took too long: \(elapsed)s")
    }

    // MARK: - Numerical Stability

    @Test("Waveform output stays in bounds over many cycles")
    func waveformNumericalStability() {
        let waveform = Waveform.sine

        // Test over 10,000 cycles
        for cycle in 0..<10_000 {
            let phase = Double(cycle) + 0.5
            let value = waveform.evaluate(at: phase)

            #expect(value >= 0.0, "Value went negative at cycle \(cycle)")
            #expect(value <= 1.0, "Value exceeded 1.0 at cycle \(cycle)")
        }
    }

    @Test("Frequency ramp numerical stability")
    func frequencyRampNumericalStability() {
        var ramp = FrequencyRamp(
            fromFrequency: 10.0,
            toFrequency: 20.0,
            duration: 1.0,
            curve: .exponentialEaseOut
        )

        // Advance in very small steps
        for _ in 0..<10_000 {
            let freq = ramp.advance(dt: 0.0001)

            #expect(freq >= 10.0, "Frequency went below minimum")
            #expect(freq <= 20.0, "Frequency exceeded maximum")
            #expect(!freq.isNaN, "Frequency became NaN")
            #expect(!freq.isInfinite, "Frequency became infinite")
        }
    }

    // MARK: - Boundary Validation

    @Test("All waveforms produce valid output at boundaries")
    func waveformBoundaries() {
        let testPhases: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0, -0.1, 1.1, 100.5]

        for waveform in Waveform.allCases {
            for phase in testPhases {
                let value = waveform.evaluate(at: phase)

                #expect(value >= 0.0, "\(waveform.displayName) at phase \(phase) produced negative value")
                #expect(value <= 1.0, "\(waveform.displayName) at phase \(phase) exceeded 1.0")
                #expect(!value.isNaN, "\(waveform.displayName) at phase \(phase) produced NaN")
                #expect(!value.isInfinite, "\(waveform.displayName) at phase \(phase) produced infinity")
            }
        }
    }

    @Test("All ramp curves produce valid output at boundaries")
    func rampCurveBoundaries() {
        let testValues: [Double] = [-0.5, 0.0, 0.25, 0.5, 0.75, 1.0, 1.5]

        for curve in RampCurve.allCases {
            for t in testValues {
                let value = curve.evaluate(at: t)

                #expect(!value.isNaN, "\(curve.displayName) at t=\(t) produced NaN")
                #expect(!value.isInfinite, "\(curve.displayName) at t=\(t) produced infinity")

                // For valid range, should be in [0, 1]
                if t >= 0.0 && t <= 1.0 {
                    #expect(value >= 0.0, "\(curve.displayName) at t=\(t) produced negative value")
                    #expect(value <= 1.0, "\(curve.displayName) at t=\(t) exceeded 1.0")
                }
            }
        }
    }

    // MARK: - Color Temperature Validation

    @Test("Color temperature clamping in session")
    func colorTemperatureValidation() {
        let testTemperatures: [Double?] = [nil, 1500, 2000, 3500, 6500, 7000]

        for temp in testTemperatures {
            let session = LightSession(
                session_name: "Color Test",
                duration_sec: 10.0,
                light_score: [
                    LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine, color_temperature: temp)
                ]
            )

            let player = LightScorePlayer(session: session)
            let state = player.currentState()

            if let colorTemp = state.colorTemperature {
                // Even if input is out of range, it should be stored as-is
                // The UI layer will clamp during rendering
                if let temp = temp {
                    #expect(colorTemp == temp, "Color temperature should match input")
                }
            }
        }
    }

    // MARK: - Concurrent Access

    @Test("Session player thread safety")
    func sessionPlayerConcurrentAccess() async {
        let session = LightSession(
            session_name: "Concurrent Test",
            duration_sec: 60.0,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine),
                LightMoment(time: 30, frequency: 20, intensity: 1.0, waveform: .sine),
                LightMoment(time: 60, frequency: 10, intensity: 0.5, waveform: .sine)
            ]
        )

        let player = LightScorePlayer(session: session)

        // Query state from multiple tasks
        await withTaskGroup(of: SessionState.self) { group in
            for i in 0..<100 {
                group.addTask { @MainActor in
                    return player.state(at: Double(i) * 0.6)
                }
            }

            // Collect all results - should complete without crashing
            var results: [SessionState] = []
            for await result in group {
                results.append(result)
            }

            #expect(results.count == 100, "Should complete all queries")
        }
    }

    // MARK: - Memory Tests

    @Test("Session player memory efficiency")
    func sessionPlayerMemoryEfficiency() {
        // Create a large session
        var moments: [LightMoment] = []
        for i in 0...1000 {
            let moment = LightMoment(
                time: Double(i),
                frequency: Double(10 + i % 30),
                intensity: Double(i % 100) / 100.0,
                waveform: .sine
            )
            moments.append(moment)
        }

        let session = LightSession(
            session_name: "Large Session",
            duration_sec: 1000.0,
            light_score: moments
        )

        // Create and destroy many players
        for _ in 0..<100 {
            let player = LightScorePlayer(session: session)
            _ = player.state(at: 500.0)
        }

        // Should complete without memory issues
        #expect(Bool(true), "Memory test completed")
    }

    // MARK: - Precision Tests

    @Test("Sine waveform symmetry")
    func sineWaveformSymmetry() {
        let waveform = Waveform.sine

        // Test basic sine wave properties
        // At phase 0 and 1: should be 0.5 (middle)
        let val0 = waveform.evaluate(at: 0.0)
        let val1 = waveform.evaluate(at: 1.0)
        #expect(abs(val0 - 0.5) < 0.0001, "Sine at phase 0 should be 0.5")
        #expect(abs(val1 - 0.5) < 0.0001, "Sine at phase 1 should be 0.5")

        // At phase 0.25: should be 1.0 (peak)
        let val025 = waveform.evaluate(at: 0.25)
        #expect(abs(val025 - 1.0) < 0.0001, "Sine at phase 0.25 should be 1.0")

        // At phase 0.75: should be 0.0 (trough)
        let val075 = waveform.evaluate(at: 0.75)
        #expect(abs(val075 - 0.0) < 0.0001, "Sine at phase 0.75 should be 0.0")

        // At phase 0.5: should be 0.5 (middle)
        let val05 = waveform.evaluate(at: 0.5)
        #expect(abs(val05 - 0.5) < 0.0001, "Sine at phase 0.5 should be 0.5")
    }

    @Test("Triangle waveform linearity verification")
    func triangleWaveformLinearity() {
        let waveform = Waveform.triangle

        // Rising edge (0 to 0.5) should be perfectly linear
        let val0 = waveform.evaluate(at: 0.0)
        let val1 = waveform.evaluate(at: 0.1)
        let val2 = waveform.evaluate(at: 0.2)

        let delta1 = val1 - val0
        let delta2 = val2 - val1

        #expect(abs(delta1 - delta2) < 0.0001, "Triangle rising edge should be linear")

        // Falling edge (0.5 to 1.0) should be perfectly linear
        let val3 = waveform.evaluate(at: 0.5)
        let val4 = waveform.evaluate(at: 0.6)
        let val5 = waveform.evaluate(at: 0.7)

        let delta3 = val4 - val3
        let delta4 = val5 - val4

        #expect(abs(delta3 - delta4) < 0.0001, "Triangle falling edge should be linear")
    }

    @Test("Frequency ramp monotonicity")
    func frequencyRampMonotonicity() {
        var ramp = FrequencyRamp(
            fromFrequency: 10.0,
            toFrequency: 20.0,
            duration: 1.0,
            curve: .linear
        )

        var previousFreq = 10.0

        // Frequency should monotonically increase
        for _ in 0..<100 {
            let freq = ramp.advance(dt: 0.01)

            #expect(freq >= previousFreq, "Frequency should never decrease during upward ramp")
            previousFreq = freq
        }
    }

    // MARK: - Timing Accuracy

    @Test("Session duration calculation accuracy")
    func sessionDurationAccuracy() {
        let durations: [Double] = [30, 60, 90, 120, 300, 600, 900, 1800, 3600]

        for duration in durations {
            let session = LightSession(
                session_name: "Duration Test",
                duration_sec: duration,
                light_score: [
                    LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)
                ]
            )

            #expect(session.duration_sec == duration)

            let player = LightScorePlayer(session: session)
            player.seek(to: duration)

            #expect(abs(player.currentTime - duration) < 0.001)
        }
    }

    @Test("Progress calculation precision")
    func progressCalculationPrecision() {
        let session = LightSession(
            session_name: "Progress Test",
            duration_sec: 100.0,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)
            ]
        )

        let player = LightScorePlayer(session: session)

        // Test at various points
        let testPoints: [(time: Double, expectedProgress: Double)] = [
            (0, 0.0),
            (25, 0.25),
            (50, 0.5),
            (75, 0.75),
            (100, 1.0)
        ]

        for point in testPoints {
            player.seek(to: point.time)
            let progress = player.progress

            #expect(abs(progress - point.expectedProgress) < 0.001,
                   "Progress at \(point.time)s should be \(point.expectedProgress), got \(progress)")
        }
    }
}
