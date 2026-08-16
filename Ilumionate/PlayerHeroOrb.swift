//
//  PlayerHeroOrb.swift
//  Ilumionate
//
//  The "now playing" centerpiece for finite-duration player modes: the Liminal
//  aurora orb, wrapped in a halo that swells with live light output. Falls back
//  to a calm static orb under reduce-motion.
//

import SwiftUI

struct PlayerHeroOrb: View {
    let engine: LightEngine
    let isPlaying: Bool
    /// Optional entrainment frequency driving the orb's breath rate.
    var pulse: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Brightness-reactive halo — reflects the actual light output so the
            // orb feels connected to the session's light.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.auroraTeal.opacity(0.30 * engine.brightness + 0.05), .clear],
                        center: .center, startRadius: 0, endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .scaleEffect(reduceMotion ? 1 : 0.9 + 0.2 * engine.brightness)
                .animation(.easeOut(duration: 0.2), value: engine.brightness)

            LumeOrb(
                size: .medium,
                pulse: isPlaying ? pulse : nil,
                isPaused: !isPlaying
            )
                .opacity(isPlaying ? 1 : 0.85)
        }
        .frame(width: 240, height: 240)
        .accessibilityHidden(true)
    }
}
