//
//  SessionView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/7/26.
//

import SwiftUI

/// Full-screen view that modulates brightness based on LightEngine output.
/// This is the primary visual entrainment surface.
///
/// In standard mode: full screen brightness driven by `engine.brightness`.
/// In bilateral mode: screen splits into left/right halves, each driven by
/// their respective phase-offset brightness values.
///
/// Brightness is driven by Color value directly rather than opacity to avoid
/// an extra compositing pass and keep the luminance curve linear.
struct SessionView: View {

    var engine: LightEngine

    var body: some View {
        ZStack {
            Group {
                if engine.bilateralMode {
                    bilateralView
                } else {
                    monoView
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            print("👁 SessionView appeared")
            print("  Initial brightness: \(engine.brightness)")
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            print("👁 SessionView disappeared")
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Mono

    private var monoView: some View {
        Color(white: engine.brightness)
            .colorMultiply(colorForTemperature(engine.colorTemperature))
            .ignoresSafeArea()
    }

    // MARK: - Bilateral

    private var bilateralView: some View {
        HStack(spacing: 0) {
            Color(white: engine.brightnessLeft)
                .colorMultiply(colorForTemperature(engine.colorTemperature))
            Color(white: engine.brightnessRight)
                .colorMultiply(colorForTemperature(engine.colorTemperature))
        }
        .ignoresSafeArea()
    }

    // MARK: - Color Temperature

    /// Pre-computed color temperature lookup table for performance
    /// Eliminates expensive pow() and log() operations during real-time rendering
    private static let colorTemperatureLUT: [Int: Color] = {
        var table: [Int: Color] = [:]

        // Pre-compute colors for temperature range in 50K increments
        for kelvin in stride(from: 2000, through: 6500, by: 50) {
            let temp = Double(kelvin) / 100.0

            let red: Double
            let green: Double
            let blue: Double

            // Red calculation
            if temp <= 66 {
                red = 1.0
            } else {
                red = min(1.0, max(0.0, (1.292936186 * pow(temp - 60, -0.1332047592))))
            }

            // Green calculation
            if temp <= 66 {
                green = min(1.0, max(0.0, (0.390081579 * log(temp)) - 0.631841444))
            } else {
                green = min(1.0, max(0.0, (1.129890861 * pow(temp - 60, -0.0755148492))))
            }

            // Blue calculation
            if temp >= 66 {
                blue = 1.0
            } else if temp <= 19 {
                blue = 0.0
            } else {
                blue = min(1.0, max(0.0, (0.543206789 * log(temp - 10)) - 1.196254089))
            }

            table[kelvin] = Color(red: red, green: green, blue: blue)
        }

        return table
    }()

    /// Convert Kelvin temperature to a color tint using pre-computed lookup table
    /// 2000K = warm amber, 3500K = neutral white, 6500K = cool blue-white
    /// Performance optimized: O(1) lookup vs expensive math operations
    private func colorForTemperature(_ kelvin: Double?) -> Color {
        guard let kelvin = kelvin else {
            return .white // Neutral white if no temperature specified
        }

        // Clamp to valid range and round to nearest 50K increment
        let k = max(2000, min(kelvin, 6500))
        let rounded = Int(round(k / 50) * 50)

        // Fast O(1) lookup instead of expensive calculations
        return Self.colorTemperatureLUT[rounded] ?? .white
    }
}

#Preview("Mono") {
    SessionView(engine: {
        let e = LightEngine()
        e.targetFrequency = 10.0
        e.waveform = .sine
        return e
    }())
}

#Preview("Bilateral") {
    SessionView(engine: {
        let e = LightEngine()
        e.targetFrequency = 10.0
        e.waveform = .sine
        e.bilateralMode = true
        e.bilateralPhaseOffset = 0.5
        return e
    }())
}
