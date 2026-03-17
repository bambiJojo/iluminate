//
//  PlayerBackgrounds.swift
//  Ilumionate
//
//  Background visual layers for each unified player mode.
//

import SwiftUI

// MARK: - Session Background

/// Rose-gold ambient light background for bundled session mode.
struct SessionPlayerBackground: View {
    let engine: LightEngine

    var body: some View {
        ZStack {
            Color.bgPrimary
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.roseGold.opacity(engine.brightness * 0.4),
                    Color.blush.opacity(engine.brightness * 0.2),
                    .clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 400
            )
            .ignoresSafeArea()
            .blendMode(.softLight)
        }
    }
}

// MARK: - Flash Grid Background

/// Full-screen flash grid with left/right opacity for flash mode.
struct FlashGridBackground: View {
    let controller: FlashController
    let colorTemperature: Int

    var body: some View {
        let baseColor = Color.fromKelvin(colorTemperature)
        HStack(spacing: 0) {
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
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Color Pulse Background

/// Hue-cycling brightness pulse background for color pulse mode.
struct ColorPulseBackground: View {
    let frequency: Double
    let intensity: Double
    let isPaused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let hue = (elapsed * 0.05).truncatingRemainder(dividingBy: 1.0)
            let raw = (sin(elapsed * frequency * 2 * .pi) + 1) / 2
            let pulseBrightness = isPaused ? 0.0 : raw * intensity

            Color(hue: hue, saturation: 0.85, brightness: pulseBrightness)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Audio Light Background

/// Switches between bgPrimary and SessionView based on light sync state.
struct AudioLightBackground: View {
    let engine: LightEngine
    let lightSyncEnabled: Bool

    var body: some View {
        if lightSyncEnabled {
            SessionView(engine: engine)
        } else {
            Color.bgPrimary.ignoresSafeArea()
        }
    }
}
