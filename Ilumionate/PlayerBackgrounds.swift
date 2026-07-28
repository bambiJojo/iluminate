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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let baseColor = Color.fromKelvin(colorTemperature)
        // Reduce Motion: render a steady "on" field instead of the strobing
        // left/right opacities so motion-sensitive users never see a flash.
        let leftOpacity = reduceMotion ? controller.intensity : controller.leftOpacity
        let rightOpacity = reduceMotion ? controller.intensity : controller.rightOpacity
        HStack(spacing: 0) {
            Rectangle()
                .fill(baseColor)
                .opacity(leftOpacity)
                .ignoresSafeArea()
            if controller.bilateralMode {
                Rectangle()
                    .fill(baseColor)
                    .opacity(rightOpacity)
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
/// The entrainment backdrop: the driven light field when lights are running,
/// a flat surface when they are not. Shared by every mode that can run
/// audio without lights.
struct EntrainmentBackground: View {
    let engine: LightEngine
    let isActive: Bool

    var body: some View {
        if isActive {
            SessionView(engine: engine)
        } else {
            Color.bgPrimary.ignoresSafeArea()
        }
    }
}
