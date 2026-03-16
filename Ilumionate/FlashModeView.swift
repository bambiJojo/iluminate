//
//  FlashModeView.swift
//  Ilumionate
//
//  Full-screen high-precision flash mode with bilateral phase-drift support.
//  Bilateral mode uses a slowly oscillating phase offset instead of a fixed 180°
//  alternation — signals start in sync, drift apart to full alternation, then
//  converge back.  This "drift" pattern avoids the habituation that comes from
//  constant fixed-offset stimulation (Herrmann 2001; Siever 2003).
//

import SwiftUI
import UIKit
import QuartzCore

// MARK: - Flash Controller

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
            //   drift=0   → offset=0   (synchronized — both eyes flash together)
            //   drift=0.5 → offset=0.5 (full alternation — 180° apart)
            //   drift=1   → offset=0   (back to synchronized)
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

// MARK: - Flash Mode View

struct FlashModeView: View {
    let frequency: Double
    let intensity: Double
    let colorTemperature: Int
    let pattern: MindMachineModel.LightPattern

    @State private var controller: FlashController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        frequency: Double,
        intensity: Double,
        colorTemperature: Int,
        pattern: MindMachineModel.LightPattern
    ) {
        self.frequency = frequency
        self.intensity = intensity
        self.colorTemperature = colorTemperature
        self.pattern = pattern
        _controller = State(initialValue: FlashController(
            frequency: frequency,
            intensity: intensity,
            pattern: pattern
        ))
    }

    var body: some View {
        ZStack {
            flashGrid
            controlsView
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onDisappear { controller.stop() }
        .alert("Photosensitive Warning", isPresented: .constant(
            !UserDefaults.standard.bool(forKey: "hasSeenFlashWarning")
        ), actions: {
            Button("I Understand") {
                UserDefaults.standard.set(true, forKey: "hasSeenFlashWarning")
            }
            Button("Cancel", role: .cancel) { dismiss() }
        }, message: {
            Text("This mode contains rapid flashing lights. " +
                 "Do not use if you suffer from photosensitive epilepsy " +
                 "or other light-sensitive conditions.")
        })
    }

    // MARK: - Flash Visuals

    private var flashGrid: some View {
        let baseColor = Color.fromKelvin(colorTemperature)
        return HStack(spacing: 0) {
            Rectangle()
                .fill(baseColor)
                .opacity(controller.leftOpacity)
                .ignoresSafeArea()
            if controller.bilateralMode {
                Rectangle()
                    .fill(baseColor)
                    .opacity(controller.rightOpacity)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Controls Overlay

    private var controlsView: some View {
        VStack {
            topHUD
            Spacer()
            VStack(spacing: 24) {
                if controller.bilateralMode {
                    bilateralDriftControl
                }
                bottomControls
            }
            .padding(.horizontal, 32)
            .background(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var topHUD: some View {
        HStack {
            Button(action: { controller.stop(); dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding()
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(frequency, specifier: "%.1f") Hz")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(colorTemperature)K")
                    .font(TranceTypography.caption)
                    .foregroundColor(Color.fromKelvin(colorTemperature))
                Text(formatDuration(controller.sessionDuration))
                    .font(TranceTypography.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .monospacedDigit()
            }
            .padding()
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 40) {
            Button(action: { controller.bilateralMode.toggle(); TranceHaptics.shared.medium() }) {
                VStack(spacing: 8) {
                    Image(systemName: controller.bilateralMode ? "eyes.inverse" : "eye")
                        .font(.system(size: 28, weight: .light))
                    Text(controller.bilateralMode ? "Bilateral" : "Unified")
                        .font(TranceTypography.caption)
                }
                .foregroundColor(controller.bilateralMode ? .roseGold : .white.opacity(0.8))
            }

            Button(action: {
                if !controller.isFlashing { controller.start() }
                else if controller.isPaused { controller.resume() }
                else { controller.pause() }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: (controller.isFlashing && !controller.isPaused)
                          ? "pause.fill" : "play.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.bottom, 48)
    }

    // MARK: - Bilateral Drift Control

    private var bilateralDriftControl: some View {
        VStack(spacing: 10) {
            driftStateLabel
            HStack(spacing: 10) {
                driftRateButton("Slow", rate: 0.033, subtitle: "30 s")
                driftRateButton("Medium", rate: 0.05, subtitle: "20 s")
                driftRateButton("Fast", rate: 0.1, subtitle: "10 s")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var driftStateLabel: some View {
        let separating = controller.bilateralDriftProgress < 0.5
        let icon = separating ? "arrow.left.and.right" : "arrow.right.and.line.vertical.and.arrow.left"
        let label = separating ? "Separating" : "Converging"
        return HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(TranceTypography.caption)
        }
        .foregroundColor(.roseGold.opacity(0.9))
    }

    private func driftRateButton(_ title: String, rate: Double, subtitle: String) -> some View {
        let isSelected = abs(controller.bilateralDriftRate - rate) < 0.001
        return Button {
            TranceHaptics.shared.light()
            controller.bilateralDriftRate = rate
        } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .roseGold.opacity(0.8) : .white.opacity(0.5))
            }
            .foregroundColor(isSelected ? .roseGold : .white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color.white.opacity(isSelected ? 0.14 : 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.roseGold.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}

// MARK: - Preview

#Preview {
    FlashModeView(frequency: 10.0, intensity: 0.75, colorTemperature: 3000, pattern: .sine)
}
