//
//  FlashController.swift
//  Ilumionate
//
//  High-precision flash controller using CADisplayLink.
//  Bilateral mode uses a slowly oscillating phase offset instead of a fixed 180°
//  alternation — signals start in sync, drift apart to full alternation, then
//  converge back.  This "drift" pattern avoids the habituation that comes from
//  constant fixed-offset stimulation (Herrmann 2001; Siever 2003).
//

import SwiftUI
import UIKit
import QuartzCore

/// High-precision flash controller using CADisplayLink.
@MainActor
@Observable
final class FlashController: Sendable {
    // Outputs
    var leftOpacity: Double = 0.0
    var rightOpacity: Double = 0.0

    // Status
    var isFlashing = false
    var isPaused = false
    var sessionDuration: TimeInterval = 0

    // Config
    var frequency: Double
    var intensity: Double
    var pattern: MindMachineModel.LightPattern
    var bilateralMode: Bool = false {
        didSet {
            // Always restart from 0 so the first experience is signals in sync
            if bilateralMode && !oldValue { bilateralDriftPhase = 0.0 }
        }
    }

    /// Drift-cycle rate in Hz. One cycle = sync → apart → sync.
    /// 0.033 ≈ 30 s (deep),  0.05 ≈ 20 s (default),  0.1 ≈ 10 s (active).
    var bilateralDriftRate: Double = 0.05

    /// Normalised drift position [0, 1].  0 = synchronized, 0.5 = max separation.
    private(set) var bilateralDriftProgress: Double = 0.0

    // Private engine state
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var sessionStartTime: Date?
    private var originalBrightness: CGFloat = 0.5
    private var bilateralDriftPhase: Double = 0.0

    private var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
    }

    init(frequency: Double, intensity: Double, pattern: MindMachineModel.LightPattern) {
        self.frequency = frequency
        self.intensity = intensity
        self.pattern = pattern
    }

    deinit { }

    func start() {
        guard !isFlashing else {
            if isPaused { resume() }
            return
        }
        isFlashing = true
        isPaused = false
        TranceHaptics.shared.heavy()

        if let screen = currentScreen {
            originalBrightness = screen.brightness
            screen.brightness = 1.0
        }

        sessionStartTime = Date()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        displayLink?.add(to: .main, forMode: .common)
        startTime = CACurrentMediaTime()
    }

    func pause() {
        guard isFlashing, !isPaused else { return }
        isPaused = true
        leftOpacity = 0.0
        rightOpacity = 0.0
        TranceHaptics.shared.medium()
    }

    func resume() {
        guard isFlashing, isPaused else { return }
        isPaused = false
        TranceHaptics.shared.medium()
    }

    func stop() {
        guard isFlashing else { return }
        isFlashing = false
        displayLink?.invalidate()
        displayLink = nil
        currentScreen?.brightness = originalBrightness
        leftOpacity = 0.0
        rightOpacity = 0.0
    }

    @objc private func tick(link: CADisplayLink) {
        if let start = sessionStartTime {
            sessionDuration = Date().timeIntervalSince(start)
        }

        if isPaused {
            leftOpacity = 0.0
            rightOpacity = 0.0
            startTime += link.targetTimestamp - link.timestamp
            return
        }

        let elapsed = link.targetTimestamp - startTime
        let dt = link.targetTimestamp - link.timestamp

        // Primary waveform phase
        let period = 1.0 / frequency
        let phase = elapsed.truncatingRemainder(dividingBy: period) / period
        let amplitude = calculateAmplitude(phase: phase) * intensity

        if bilateralMode {
            // Advance drift oscillator
            bilateralDriftPhase += bilateralDriftRate * dt
            if bilateralDriftPhase >= 1.0 { bilateralDriftPhase -= 1.0 }
            bilateralDriftProgress = bilateralDriftPhase

            // Dynamic phase offset: 0.25 × (1 − cos(2π × drift)) spans [0, 0.5]
            let dynamicOffset = 0.25 * (1.0 - cos(2.0 * .pi * bilateralDriftPhase))
            let rightPhase = (phase + dynamicOffset).truncatingRemainder(dividingBy: 1.0)
            leftOpacity = amplitude
            rightOpacity = calculateAmplitude(phase: rightPhase) * intensity
        } else {
            bilateralDriftProgress = 0.0
            leftOpacity = amplitude
            rightOpacity = amplitude
        }
    }

    private func calculateAmplitude(phase: Double) -> Double {
        switch pattern {
        case .sine:
            return (sin(phase * 2 * .pi) + 1.0) / 2.0
        case .square:
            return phase < 0.5 ? 1.0 : 0.0
        case .triangle:
            return phase < 0.5 ? phase * 2.0 : 1.0 - (phase - 0.5) * 2.0
        case .sawtooth:
            return phase
        case .pulse:
            return phase < 0.1 ? 1.0 : 0.0
        }
    }
}
