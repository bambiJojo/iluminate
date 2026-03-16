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

    /// Whether the engine is paused (running but not updating brightness)
    private(set) var isPaused: Bool = false

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

    // bilateralCache removed — the cache keyed only on offset but rightValue also
    // depends on the per-frame phase accumulator, so it always returned stale data.

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

    /// When true, left and right fields are driven with a slowly drifting phase offset
    /// that cycles between 0 (synchronized) and `bilateralPhaseOffset` (full separation).
    /// This avoids the habituation caused by a fixed 180° alternation.
    var bilateralMode: Bool = false {
        didSet {
            guard bilateralMode != oldValue else { return }
            isBilateralTransitioning = true
            bilateralTransitionElapsed = 0.0
            if bilateralMode {
                bilateralDriftPhase = 0.0  // always start from synchronized state
            } else {
                bilateralFadeOutStartOffset = currentBilateralOffset
            }
        }
    }

    /// Peak phase offset for the right field in cycles [0, 1).
    /// The drift oscillator cycles between 0 and this value.
    /// 0.5 = full alternation (180°), 0.25 = quadrature.
    var bilateralPhaseOffset: Double = 0.5 {
        didSet { bilateralPhaseOffset = max(0.0, min(bilateralPhaseOffset, 1.0)) }
    }

    /// Drift-cycle rate in Hz. One cycle = sync → apart → sync.
    /// 0.033 ≈ 30 s (deep),  0.05 ≈ 20 s (default),  0.1 ≈ 10 s (active).
    var bilateralDriftRate: Double = 0.05 {
        didSet { bilateralDriftRate = max(0.01, min(bilateralDriftRate, 0.5)) }
    }

    /// Normalised drift position [0, 1].  0 = synchronized, 0.5 = max separation.
    private(set) var bilateralDriftProgress: Double = 0.0

    /// Duration in seconds for transitioning between mono and bilateral modes.
    var bilateralTransitionDuration: Double = 3.0

    /// Minimum brightness floor in [0, 1]. Prevents full blackout.
    var minimumBrightness: Double = 0.0

    /// Maximum brightness ceiling in [0, 1].
    var maximumBrightness: Double = 1.0

    /// User-controlled brightness multiplier in [0.1, 1.0].
    /// This is preserved during session playback and multiplies with session intensity.
    /// Use this for the brightness slider in the UI.
    var userBrightnessMultiplier: Double = 1.0

    /// User-controlled frequency scale in [0.5, 2.0].
    /// Scales the actual oscillation rate without changing the session's source frequency.
    /// E.g., 0.5× halves the flash rate; 2.0× doubles it.
    var userFrequencyMultiplier: Double = 1.0

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

    /// Current interpolated bilateral phase offset (0.0 = mono, drifting to peak when on)
    private var currentBilateralOffset: Double = 0.0

    /// Drift oscillator accumulator — advances at bilateralDriftRate Hz while bilateral is on
    private var bilateralDriftPhase: Double = 0.0

    /// The offset value captured at the moment bilateral turns off, used for a clean fade-out
    private var bilateralFadeOutStartOffset: Double = 0.0

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
        isPaused = false

        // Use a proxy to avoid retaining self in the display link target.
        // Clear any existing proxy first to prevent memory leaks
        proxy = nil
        let linkProxy = DisplayLinkProxy()
        linkProxy.engine = self
        proxy = linkProxy

        let link = CADisplayLink(target: linkProxy, selector: #selector(DisplayLinkProxy.tick(_:)))

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
        isPaused = false
        brightness = 0.0
        brightnessLeft = 0.0
        brightnessRight = 0.0
        phase = 0.0
        lastTimestamp = 0.0
        activeRamp = nil
        currentFrequency = targetFrequency
    }

    /// Pause the engine (keep running but freeze brightness at 0)
    func pause() {
        guard isRunning else { return }
        isPaused = true
        brightness = 0.0
        brightnessLeft = 0.0
        brightnessRight = 0.0
        print("⏸️ Light engine paused")
    }

    /// Resume the engine from pause state
    func resume() {
        guard isRunning else { return }
        isPaused = false
        print("▶️ Light engine resumed")
    }

    // MARK: - Display Tick

    fileprivate func tick(_ link: CADisplayLink) {
        #if DEBUG
        let tickStart = CFAbsoluteTimeGetCurrent()
        #endif

        guard lastTimestamp > 0 else {
            lastTimestamp = link.timestamp
            lastFPSCheck = link.timestamp
            return
        }

        let deltaTime = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp

        // Early return when paused — keep timestamp fresh to prevent phase jump on resume.
        if isPaused {
            brightness = 0.0
            brightnessLeft = 0.0
            brightnessRight = 0.0
            return
        }

        updatePerformanceCounters(timestamp: link.timestamp)
        updateAdaptiveRefreshRate(link.timestamp)
        updateBilateralTransition(deltaTime: deltaTime)
        applySessionState()
        advanceFrequency(deltaTime: deltaTime)

        // Phase accumulation — scaled by user frequency multiplier
        phase += currentFrequency * userFrequencyMultiplier * deltaTime
        if phase >= 1000.0 { phase -= 1000.0 }

        let (leftOut, rightOut) = evaluateOscillator()
        brightness = leftOut
        brightnessLeft = leftOut
        brightnessRight = rightOut

        #if DEBUG
        let tickDuration = CFAbsoluteTimeGetCurrent() - tickStart
        if tickDuration > 0.016 {
            print("⚠️ Light Engine slow tick: \(String(format: "%.3f", tickDuration * 1000))ms")
        }
        if frameCounter % 240 == 0 {
            let freqStr = String(format: "%.1f", currentFrequency)
            let brightStr = String(format: "%.3f", brightness)
            print("🔄 Engine: brightness=\(brightStr) freq=\(freqStr)Hz")
        }
        #endif
    }

    // MARK: - Tick Helpers

    /// Updates FPS counter and power-efficiency tracking.
    private func updatePerformanceCounters(timestamp: CFTimeInterval) {
        frameCounter += 1
        cumulativeFramesRendered += 1

        if targetRefreshRate < 120 {
            cumulativeFramesSaved += 120 - targetRefreshRate
        }

        guard timestamp - lastFPSCheck >= 1.0 else { return }
        currentFPS = Int(Double(frameCounter) / (timestamp - lastFPSCheck))

        if cumulativeFramesRendered > 0 {
            let saved = Double(cumulativeFramesSaved)
            let total = Double(cumulativeFramesRendered + cumulativeFramesSaved)
            powerEfficiencyGain = (saved / total) * 100.0
        }

        frameCounter = 0
        lastFPSCheck = timestamp

        if currentFPS < 50 {
            print("⚠️ Light Engine FPS: \(currentFPS) (target: \(targetRefreshRate)+)")
        }
    }

    /// Advances the bilateral drift oscillator and interpolates the phase offset.
    ///
    /// When bilateral is ON the offset cycles between 0 (sync) and bilateralPhaseOffset
    /// (full separation) using the formula:
    ///   offset = (bilateralPhaseOffset / 2) × (1 − cos(2π × driftPhase))
    /// A 3-second ease-in envelope is applied when the mode first activates.
    ///
    /// When bilateral is OFF the offset fades from wherever it was to 0.
    private func updateBilateralTransition(deltaTime: Double) {
        if bilateralMode {
            // Advance drift oscillator
            bilateralDriftPhase += bilateralDriftRate * deltaTime
            if bilateralDriftPhase >= 1.0 { bilateralDriftPhase -= 1.0 }
            bilateralDriftProgress = bilateralDriftPhase

            // Cosine drift: spans 0 → bilateralPhaseOffset → 0 each cycle
            let drifted = (bilateralPhaseOffset / 2.0) * (1.0 - cos(2.0 * .pi * bilateralDriftPhase))

            if isBilateralTransitioning {
                bilateralTransitionElapsed += deltaTime
                let progress = min(bilateralTransitionElapsed / bilateralTransitionDuration, 1.0)
                let eased = 1.0 - pow(1.0 - progress, 3.0)
                currentBilateralOffset = drifted * eased
                if progress >= 1.0 { isBilateralTransitioning = false }
            } else {
                currentBilateralOffset = drifted
            }
        } else {
            bilateralDriftProgress = 0.0
            if isBilateralTransitioning {
                bilateralTransitionElapsed += deltaTime
                let progress = min(bilateralTransitionElapsed / bilateralTransitionDuration, 1.0)
                let eased = 1.0 - pow(1.0 - progress, 3.0)
                currentBilateralOffset = bilateralFadeOutStartOffset * (1.0 - eased)
                if progress >= 1.0 {
                    isBilateralTransitioning = false
                    currentBilateralOffset = 0.0
                }
            } else {
                currentBilateralOffset = 0.0
            }
        }
    }

    /// Applies state from the attached session player if one is active.
    private func applySessionState() {
        guard let player = sessionPlayer else { return }
        player.updateTime()
        let state = player.currentState()

        waveform = state.waveform
        if let transitionDuration = state.bilateralTransitionDuration {
            bilateralTransitionDuration = transitionDuration
        }
        bilateralMode = state.bilateral
        colorTemperature = state.colorTemperature

        let clampedMultiplier = max(0.1, min(userBrightnessMultiplier, 1.0))
        maximumBrightness = max(0.0, min(1.0, state.intensity * clampedMultiplier))

        guard abs(state.frequency - currentFrequency) > 0.01 else { return }
        if let rampDur = state.rampDuration {
            activeRamp = FrequencyRamp(
                fromFrequency: currentFrequency,
                toFrequency: state.frequency,
                duration: rampDur,
                curve: rampCurve
            )
        } else if activeRamp == nil {
            activeRamp = FrequencyRamp(
                fromFrequency: currentFrequency,
                toFrequency: state.frequency,
                duration: rampDuration,
                curve: rampCurve
            )
        }
    }

    /// Advances the active frequency ramp or tracks the target directly.
    private func advanceFrequency(deltaTime: Double) {
        let baseFrequency = sessionPlayer?.currentState().frequency ?? targetFrequency
        guard activeRamp != nil else {
            currentFrequency = baseFrequency
            return
        }

        currentFrequency = activeRamp!.advance(dt: deltaTime)
        if activeRamp?.isComplete == true {
            activeRamp = nil
            currentFrequency = baseFrequency
        }
    }

    /// Evaluates the waveform oscillator for left and right channels.
    /// The right channel is offset by currentBilateralOffset (which drifts over time).
    private func evaluateOscillator() -> (left: Double, right: Double) {
        let rawLeft = waveform.evaluate(at: phase)
        let rawRight = currentBilateralOffset > 0.001
            ? waveform.evaluate(at: phase + currentBilateralOffset)
            : rawLeft

        let correctedLeft = applyGammaCorrection(rawLeft)
        let correctedRight = applyGammaCorrection(rawRight)
        let range = maximumBrightness - minimumBrightness
        let leftOut = max(0.0, min(1.0, minimumBrightness + correctedLeft * range))
        let rightOut = max(0.0, min(1.0, minimumBrightness + correctedRight * range))
        return (leftOut, rightOut)
    }
}
