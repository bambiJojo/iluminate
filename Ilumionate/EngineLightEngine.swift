//
//  LightEngine.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/7/26.
//

import Foundation
import QuartzCore
import Observation

/// Lightweight proxy that breaks the CADisplayLink → LightEngine retain cycle.
/// CADisplayLink strongly retains its target, so we give it this proxy which
/// holds only a weak reference back to the engine.
private final class DisplayLinkProxy: NSObject {
    weak var engine: LightEngine?

    @objc func tick(_ link: CADisplayLink) {
        engine?.tick(link)
    }
}

/// Drives the visual entrainment loop using CADisplayLink.
///
/// CADisplayLink runs on the main run loop. All oscillator math executes
/// inline on the display callback — it is pure arithmetic and takes
/// negligible time per frame. No background thread is needed until the
/// AVAudioEngine master clock is wired in (Phase 4).
///
/// Threading note per architecture spec:
///   - UI thread: SwiftUI reads `brightness` via @Observable
///   - Display loop: CADisplayLink fires on main, updates `brightness`
///   - Audio thread (Phase 4): will supply the authoritative timestamp
@Observable
@MainActor
final class LightEngine {

    // MARK: - Public State

    /// Current normalized brightness output in [0, 1].
    /// In bilateral mode, use brightnessLeft / brightnessRight instead.
    private(set) var brightness: Double = 0.0

    /// Left field brightness in [0, 1]. Equal to `brightness` when bilateral is off.
    private(set) var brightnessLeft: Double = 0.0

    /// Right field brightness in [0, 1]. Phase-shifted when bilateral is on.
    private(set) var brightnessRight: Double = 0.0

    /// Whether the engine is currently running.
    private(set) var isRunning: Bool = false

    /// The instantaneous frequency being output (may differ from targetFrequency
    /// during a ramp).
    private(set) var currentFrequency: Double = 10.0

    /// Current color temperature in Kelvin (2000-6500).
    /// nil = neutral white, 2000 = warm amber, 6500 = cool blue-white
    private(set) var colorTemperature: Double?

    // MARK: - Performance Monitoring

    /// Frame rate monitoring for performance tracking
    private(set) var currentFPS: Int = 0
    private var frameCounter: Int = 0
    private var lastFPSCheck: CFTimeInterval = 0

    /// Adaptive refresh rate for power efficiency
    private(set) var targetRefreshRate: Int = 120
    private var lastRefreshRateUpdate: CFTimeInterval = 0

    /// Power efficiency tracking
    private(set) var powerEfficiencyGain: Double = 0.0 // Percentage CPU savings vs 120Hz
    private var cumulativeFramesRendered: Int = 0
    private var cumulativeFramesSaved: Int = 0

    // MARK: - Adaptive Refresh Rate

    /// Calculate optimal refresh rate based on current therapeutic frequencies
    /// Uses 8x oversampling minimum for smooth waveform rendering
    private func calculateOptimalRefreshRate() -> Int {
        let leftFreq = currentFrequency + (bilateralMode ? currentBilateralOffset : 0.0)
        let rightFreq = currentFrequency - (bilateralMode ? currentBilateralOffset : 0.0)

        let maxTherapeuticFreq = max(leftFreq, rightFreq)

        // Minimum 8 samples per cycle for smooth waveforms
        let minRequiredRefresh = maxTherapeuticFreq * 8.0

        // Clamp between 30Hz (minimum for flicker-free) and 120Hz (maximum hardware)
        let optimalRefresh = max(30.0, min(120.0, minRequiredRefresh))

        return Int(optimalRefresh.rounded())
    }

    /// Update display link refresh rate if needed (max once per second to avoid thrashing)
    private func updateAdaptiveRefreshRate(_ currentTime: CFTimeInterval) {
        guard currentTime - lastRefreshRateUpdate >= 1.0 else { return }

        let optimalRate = calculateOptimalRefreshRate()

        // Only update if there's a significant change (≥10Hz difference)
        guard abs(optimalRate - targetRefreshRate) >= 10 else { return }

        targetRefreshRate = optimalRate
        lastRefreshRateUpdate = currentTime

        // Update the display link with new refresh rate
        if let link = displayLink {
            let minimum = max(30, optimalRate - 10)
            let maximum = min(120, optimalRate + 10)

            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(minimum),
                maximum: Float(maximum),
                preferred: Float(optimalRate)
            )

            let efficiencyText = powerEfficiencyGain > 0 ? String(format: " (%.1f%% power savings)", powerEfficiencyGain) : ""
            print("🔄 Adaptive refresh rate: \(optimalRate)Hz (therapeutic: \(String(format: "%.1f", max(currentFrequency + abs(currentBilateralOffset), currentFrequency - abs(currentBilateralOffset))))Hz)\(efficiencyText)")
        }
    }

    // MARK: - Performance Optimizations

    /// Pre-computed gamma correction lookup table (gamma = 0.5)
    /// Eliminates expensive pow() calls in display loop running at 120Hz
    private static let gammaLookupTable: [Double] = {
        let tableSize = 1001 // 0.0 to 1.0 in 0.001 steps
        let gamma = 0.5
        return (0..<tableSize).map { index in
            let input = Double(index) / Double(tableSize - 1)
            return pow(input, gamma)
        }
    }()

    /// Fast gamma correction using lookup table
    private func applyGammaCorrection(_ input: Double) -> Double {
        let clampedInput = max(0.0, min(1.0, input))
        let index = Int(clampedInput * Double(Self.gammaLookupTable.count - 1))
        return Self.gammaLookupTable[index]
    }

    /// Cache for bilateral calculations to avoid redundant waveform evaluations
    private var bilateralCache: (offset: Double, rightValue: Double) = (0.0, 0.0)

    // MARK: - Configuration

    /// Desired entrainment frequency in Hz.
    /// In normal use the phase accumulator tracks this directly each frame.
    /// Call `rampTo(_:duration:curve:)` for a smooth programmatic transition.
    var targetFrequency: Double = 10.0 {
        didSet { targetFrequency = max(0.1, min(targetFrequency, 100.0)) }
    }

    /// Smoothly transition to a new frequency over a given duration.
    /// Use this for protocol-driven frequency changes — never hard-jump.
    func rampTo(_ frequency: Double, duration: Double? = nil, curve: RampCurve? = nil) {
        let target = max(0.1, min(frequency, 100.0))
        targetFrequency = target
        guard isRunning else { return }
        activeRamp = FrequencyRamp(
            fromFrequency: currentFrequency,
            toFrequency: target,
            duration: duration ?? rampDuration,
            curve: curve ?? rampCurve
        )
    }

    /// Duration in seconds for frequency transitions.
    var rampDuration: Double = 3.0

    /// Interpolation curve used for frequency ramps.
    var rampCurve: RampCurve = .exponentialEaseOut

    /// Waveform shape for brightness modulation.
    var waveform: Waveform = .sine

    /// When true, left and right fields are driven with a phase offset
    /// to create a bilateral alternating stimulation effect.
    var bilateralMode: Bool = false {
        didSet {
            if bilateralMode != oldValue {
                // Start a transition when bilateral mode changes
                isBilateralTransitioning = true
                bilateralTransitionElapsed = 0.0
            }
        }
    }

    /// Phase offset for the right field in cycles [0, 1).
    /// 0.5 = perfect alternation (right is inverted), 0.25 = quadrature.
    var bilateralPhaseOffset: Double = 0.5 {
        didSet { bilateralPhaseOffset = max(0.0, min(bilateralPhaseOffset, 1.0)) }
    }

    /// Duration in seconds for transitioning between mono and bilateral modes.
    var bilateralTransitionDuration: Double = 3.0

    /// Minimum brightness floor in [0, 1]. Prevents full blackout.
    var minimumBrightness: Double = 0.0

    /// Maximum brightness ceiling in [0, 1].
    var maximumBrightness: Double = 1.0

    /// User-controlled brightness multiplier in [0.1, 1.0].
    /// This is preserved during session playback and multiplies with session intensity.
    /// Use this for the brightness slider in the UI.
    var userBrightnessMultiplier: Double = 1.0 {
        didSet { userBrightnessMultiplier = max(0.1, min(userBrightnessMultiplier, 1.0)) }
    }

    // MARK: - Private State

    private var displayLink: CADisplayLink?
    private var proxy: DisplayLinkProxy?

    /// Continuous phase accumulator. Advances by frequency × dt each frame.
    /// Represents cycles elapsed. Bounded to [0, 1000) to prevent
    /// floating-point drift over long sessions.
    private var phase: Double = 0.0

    private var lastTimestamp: CFTimeInterval = 0.0

    /// Active frequency ramp, if any. Nil when frequency is stable.
    private var activeRamp: FrequencyRamp?

    /// Optional session player that can drive the engine parameters
    private var sessionPlayer: LightScorePlayer?

    /// Whether a bilateral mode transition is in progress
    private var isBilateralTransitioning: Bool = false

    /// Elapsed time during bilateral transition
    private var bilateralTransitionElapsed: Double = 0.0

    /// Current interpolated bilateral phase offset (0.0 = mono, target = full bilateral)
    private var currentBilateralOffset: Double = 0.0

    // MARK: - Session Mode

    /// Attach a session player to drive the engine automatically.
    /// When a player is attached, the engine will follow the session's control curve
    /// instead of manual targetFrequency changes.
    func attachSession(player: LightScorePlayer) {
        sessionPlayer = player
    }

    /// Detach the current session player and return to manual control
    func detachSession() {
        sessionPlayer = nil
    }

    /// Whether the engine is currently being driven by a session
    var hasActiveSession: Bool {
        sessionPlayer != nil
    }

    // MARK: - Lifecycle

    /// Start the display loop on the main run loop.
    func start() {
        guard !isRunning else { return }

        phase = 0.0
        lastTimestamp = 0.0
        currentFrequency = targetFrequency
        activeRamp = nil
        isRunning = true

        // Use a proxy to avoid retaining self in the display link target.
        // Clear any existing proxy first to prevent memory leaks
        proxy = nil
        let p = DisplayLinkProxy()
        p.engine = self
        proxy = p

        let link = CADisplayLink(target: p, selector: #selector(DisplayLinkProxy.tick(_:)))

        // Start with adaptive refresh rate based on current frequency
        targetRefreshRate = calculateOptimalRefreshRate()
        let minimum = max(30, targetRefreshRate - 10)
        let maximum = min(120, targetRefreshRate + 10)

        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(minimum),
            maximum: Float(maximum),
            preferred: Float(targetRefreshRate)
        )

        link.add(to: .main, forMode: .common)
        displayLink = link

        print("🚀 Light engine started with adaptive refresh rate: \(targetRefreshRate)Hz")
        print("   Therapeutic frequency: \(String(format: "%.1f", currentFrequency))Hz")
    }

    /// Stop the display loop and reset state.
    func stop() {
        guard isRunning else { return }

        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
        isRunning = false
        brightness = 0.0
        brightnessLeft = 0.0
        brightnessRight = 0.0
        phase = 0.0
        lastTimestamp = 0.0
        activeRamp = nil
        currentFrequency = targetFrequency
    }

    // MARK: - Display Tick

    fileprivate func tick(_ link: CADisplayLink) {
        guard lastTimestamp > 0 else {
            lastTimestamp = link.timestamp
            lastFPSCheck = link.timestamp
            return
        }

        let dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp

        // Performance monitoring
        frameCounter += 1
        cumulativeFramesRendered += 1

        // Calculate power efficiency gains
        if targetRefreshRate < 120 {
            let framesSavedThisTick = 120 - targetRefreshRate
            cumulativeFramesSaved += framesSavedThisTick
        }

        if link.timestamp - lastFPSCheck >= 1.0 {
            currentFPS = Int(Double(frameCounter) / (link.timestamp - lastFPSCheck))

            // Calculate power efficiency percentage
            if cumulativeFramesRendered > 0 {
                powerEfficiencyGain = (Double(cumulativeFramesSaved) / Double(cumulativeFramesRendered + cumulativeFramesSaved)) * 100.0
            }

            frameCounter = 0
            lastFPSCheck = link.timestamp

            // Only log performance warnings, not every FPS update
            if currentFPS < 50 {
                print("⚠️ Light Engine FPS: \(currentFPS) (target: \(targetRefreshRate)+)")
            }
        }

        // Adaptive refresh rate optimization (check once per second)
        updateAdaptiveRefreshRate(link.timestamp)

        // --- Bilateral mode transition ---
        // Smoothly interpolate the phase offset when transitioning between mono and bilateral
        if isBilateralTransitioning {
            bilateralTransitionElapsed += dt

            let progress = min(bilateralTransitionElapsed / bilateralTransitionDuration, 1.0)

            // Use ease-out curve for smooth feel
            let easedProgress = 1.0 - pow(1.0 - progress, 3.0)

            if bilateralMode {
                // Transitioning TO bilateral: 0 → target offset
                currentBilateralOffset = bilateralPhaseOffset * easedProgress
            } else {
                // Transitioning FROM bilateral: current offset → 0
                currentBilateralOffset = bilateralPhaseOffset * (1.0 - easedProgress)
            }

            // Complete transition
            if progress >= 1.0 {
                isBilateralTransitioning = false
                currentBilateralOffset = bilateralMode ? bilateralPhaseOffset : 0.0
            }
        } else {
            // No transition in progress, use direct value
            currentBilateralOffset = bilateralMode ? bilateralPhaseOffset : 0.0
        }

        // --- Session-driven mode ---
        // If a session player is attached, let it drive the parameters
        if let player = sessionPlayer {
            player.updateTime()
            let state = player.currentState()

            // Apply session state to engine
            waveform = state.waveform

            // Update bilateral transition duration if specified in session
            if let transitionDuration = state.bilateralTransitionDuration {
                bilateralTransitionDuration = transitionDuration
            }

            // Set bilateral mode (this will trigger the transition via didSet)
            bilateralMode = state.bilateral

            // Update color temperature (smoothly interpolated by the player)
            colorTemperature = state.colorTemperature

            // Update intensity range based on session intensity
            // Session intensity is multiplied by user brightness multiplier
            maximumBrightness = state.intensity * userBrightnessMultiplier

            // Ramp to the target frequency with optional custom ramp duration
            if abs(state.frequency - currentFrequency) > 0.01 {
                if let rampDur = state.rampDuration {
                    // Use moment-specific ramp duration
                    activeRamp = FrequencyRamp(
                        fromFrequency: currentFrequency,
                        toFrequency: state.frequency,
                        duration: rampDur,
                        curve: rampCurve
                    )
                } else if activeRamp == nil {
                    // Start a new ramp with default duration
                    activeRamp = FrequencyRamp(
                        fromFrequency: currentFrequency,
                        toFrequency: state.frequency,
                        duration: rampDuration,
                        curve: rampCurve
                    )
                }
            }
        }

        // --- Frequency ramp ---
        // If a ramp is active, advance it. Otherwise track targetFrequency directly.
        if activeRamp != nil {
            currentFrequency = activeRamp!.advance(dt: dt)
            if activeRamp!.isComplete {
                activeRamp = nil
                currentFrequency = sessionPlayer != nil
                    ? sessionPlayer!.currentState().frequency
                    : targetFrequency
            }
        } else {
            currentFrequency = sessionPlayer != nil
                ? sessionPlayer!.currentState().frequency
                : targetFrequency
        }

        // --- Phase accumulator ---
        phase += currentFrequency * dt
        if phase >= 1000.0 { phase -= 1000.0 }

        // --- Waveform evaluation ---
        let rawLeft = waveform.evaluate(at: phase)

        // --- Bilateral phase offset with smooth transition (optimized) ---
        // Use the interpolated offset instead of the direct value
        // This creates a gradual "slipping apart" effect
        let rawRight: Double
        if currentBilateralOffset > 0.001 {
            // Check if we can use cached value
            if abs(bilateralCache.offset - currentBilateralOffset) < 0.0001 {
                rawRight = bilateralCache.rightValue
            } else {
                rawRight = waveform.evaluate(at: phase + currentBilateralOffset)
                bilateralCache = (currentBilateralOffset, rawRight)
            }
        } else {
            rawRight = rawLeft
        }

        // --- Intensity mapping (optimized) ---
        // Apply gamma correction using fast lookup table instead of expensive pow()
        let correctedLeft = applyGammaCorrection(rawLeft)
        let correctedRight = applyGammaCorrection(rawRight)

        brightness = minimumBrightness + correctedLeft * (maximumBrightness - minimumBrightness)
        brightnessLeft = brightness
        brightnessRight = minimumBrightness + correctedRight * (maximumBrightness - minimumBrightness)
    }
}
