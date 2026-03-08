//
//  FlashModeView.swift
//  Ilumionate
//
//  Full-screen high-precision flash mode with bilateral support
//

import SwiftUI
import UIKit
import QuartzCore

// MARK: - Flash Controller

/// High-precision flash controller using CADisplayLink
@MainActor
@Observable
final class FlashController {
    // Current drawn output
    var leftOpacity: Double = 0.0
    var rightOpacity: Double = 0.0
    
    // Status
    var isFlashing = false
    var sessionDuration: TimeInterval = 0
    
    // Config
    var frequency: Double
    var intensity: Double
    var pattern: MindMachineModel.LightPattern
    var bilateralMode: Bool = false
    var bilateralDrift: Double = 0.0 // -1 to 1
    
    // Engine State
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var sessionStartTime: Date?
    private var originalBrightness: CGFloat = 0.5
    
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
    
    // `CADisplayLink` must be invalidated manually on the main actor via `stop()`.
    // We cannot do it in `deinit` because `deinit` is nonisolated.
    deinit {
        // Stop should be called before deallocation
    }
    
    func start() {
        guard !isFlashing else { return }
        isFlashing = true
        TranceHaptics.shared.heavy()
        
        // Maximize brightness
        if let screen = currentScreen {
            originalBrightness = screen.brightness
            screen.brightness = 1.0
        }
        
        sessionStartTime = Date()
        
        // Setup DisplayLink for screen-refresh-rate precision
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        // Opt into max refresh rate if ProMotion is available
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        displayLink?.add(to: .main, forMode: .common)
        startTime = CACurrentMediaTime()
    }
    
    func stop() {
        guard isFlashing else { return }
        isFlashing = false
        displayLink?.invalidate()
        displayLink = nil
        
        // Restore brightness
        currentScreen?.brightness = originalBrightness
        
        // Reset output
        leftOpacity = 0.0
        rightOpacity = 0.0
    }
    
    @objc private func tick(link: CADisplayLink) {
        let elapsedTime = link.targetTimestamp - startTime
        updateDuration()
        
        // Calculate cycle phase (0.0 to 1.0)
        let period = 1.0 / frequency
        let timeInCycle = elapsedTime.truncatingRemainder(dividingBy: period)
        let phase = timeInCycle / period
        
        // Calculate base amplitude based on pattern
        let amplitude = calculateAmplitude(phase: phase) * intensity
        
        // Apply bilateral dynamics
        if bilateralMode {
            // Smoothly alternate emphasis based on drift (-1 left, +1 right)
            // When drift is 0, both eyes sync.
            let rightEmphasis = max(0, min(1, (bilateralDrift + 1.0) / 2.0))
            let leftEmphasis = 1.0 - rightEmphasis
            
            // Introduce a phase offset for the alternating effect
            let altPhase = (phase + 0.5).truncatingRemainder(dividingBy: 1.0)
            let altAmplitude = calculateAmplitude(phase: altPhase) * intensity
            
            // Blend based on emphasis
            leftOpacity = (amplitude * leftEmphasis) + (altAmplitude * (1.0 - leftEmphasis))
            rightOpacity = (amplitude * rightEmphasis) + (altAmplitude * (1.0 - rightEmphasis))
        } else {
            // Unified mode
            leftOpacity = amplitude
            rightOpacity = amplitude
        }
    }
    
    private func updateDuration() {
        if let start = sessionStartTime {
            sessionDuration = Date().timeIntervalSince(start)
        }
    }
    
    private func calculateAmplitude(phase: Double) -> Double {
        switch pattern {
        case .sine:
            // Normalize sine wave from [-1, 1] to [0, 1]
            return (sin(phase * 2 * .pi) + 1.0) / 2.0
            
        case .square:
            return phase < 0.5 ? 1.0 : 0.0
            
        case .triangle:
            if phase < 0.5 {
                // Rise 0 to 1
                return phase * 2.0
            } else {
                // Fall 1 to 0
                return 1.0 - ((phase - 0.5) * 2.0)
            }
            
        case .sawtooth:
            // Rapid rise, sudden drop
            return phase
            
        case .pulse:
            // Very brief flash (10% of cycle)
            return phase < 0.1 ? 1.0 : 0.0
        }
    }
}


// MARK: - Flash Mode View

struct FlashModeView: View {
    // Configuration
    let frequency: Double
    let intensity: Double
    let colorTemperature: Int
    let pattern: MindMachineModel.LightPattern
    
    @State private var controller: FlashController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    init(frequency: Double, intensity: Double, colorTemperature: Int, pattern: MindMachineModel.LightPattern) {
        self.frequency = frequency
        self.intensity = intensity
        self.colorTemperature = colorTemperature
        self.pattern = pattern
        _controller = State(initialValue: FlashController(frequency: frequency, intensity: intensity, pattern: pattern))
    }
    
    var body: some View {
        ZStack {
            // Flash Background
            flashGrid
            
            // Controls Overlay
            controlsView
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            if !reduceMotion {
                controller.start()
            }
        }
        .onDisappear {
            controller.stop()
        }
        // Safety Warning
        .alert("Photosensitive Warning", isPresented: .constant(!UserDefaults.standard.bool(forKey: "hasSeenFlashWarning"))) {
            Button("I Understand") {
                UserDefaults.standard.set(true, forKey: "hasSeenFlashWarning")
                if !reduceMotion {
                    controller.start()
                }
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("This mode contains rapid flashing lights. Do not use if you suffer from photosensitive epilepsy or other light-sensitive conditions.")
        }
    }
    
    // MARK: - Flash Visuals
    
    private var flashGrid: some View {
        let baseColor = Color.fromKelvin(colorTemperature)
        
        return HStack(spacing: 0) {
            // Left Eye
            Rectangle()
                .fill(baseColor)
                .opacity(controller.leftOpacity)
                .ignoresSafeArea()
            
            // Right Eye
            if controller.bilateralMode {
                Rectangle()
                    .fill(baseColor)
                    .opacity(controller.rightOpacity)
                    .ignoresSafeArea()
            }
        }
    }
    
    // MARK: - HUD Controls
    
    private var controlsView: some View {
        VStack {
            // Top HUD
            HStack {
                Button(action: {
                    controller.stop()
                    dismiss()
                }) {
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
            
            Spacer()
            
            // Bottom Controls
            VStack(spacing: 24) {
                if controller.bilateralMode {
                    bilateralSlider
                }
                
                HStack(spacing: 40) {
                    // Bilateral Toggle
                    Button(action: {
                        controller.bilateralMode.toggle()
                        TranceHaptics.shared.medium()
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: controller.bilateralMode ? "eyes.inverse" : "eye")
                                .font(.system(size: 28, weight: .light))
                            Text(controller.bilateralMode ? "Bilateral" : "Unified")
                                .font(TranceTypography.caption)
                        }
                        .foregroundColor(controller.bilateralMode ? .roseGold : .white.opacity(0.8))
                    }
                    
                    // Play/Pause
                    Button(action: {
                        if controller.isFlashing {
                            controller.stop()
                        } else {
                            controller.start()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: controller.isFlashing ? "pause.fill" : "play.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 32)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
    
    private var bilateralSlider: some View {
        VStack(spacing: 12) {
            Text("Bilateral Drift: \(controller.bilateralDrift, specifier: "%+.2f")")
                .font(TranceTypography.caption)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                Text("L")
                    .font(TranceTypography.caption)
                    .foregroundColor(.white.opacity(0.7))
                
                Slider(value: $controller.bilateralDrift, in: -1...1)
                    .accentColor(.roseGold)
                
                Text("R")
                    .font(TranceTypography.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    FlashModeView(
        frequency: 10.0,
        intensity: 0.75,
        colorTemperature: 3000,
        pattern: .sine
    )
}