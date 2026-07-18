//
//  AuroraBackground.swift
//  Ilumionate
//
//  The signature Liminal surface: a void radial gradient with 2–3 large
//  blurred aurora blobs drifting at Breath tempo. Mood tints the aurora
//  toward a brainwave zone. Freezes under Reduce Motion. Pauses when an
//  active light session owns the screen. In light mode the void becomes
//  the Pink Aurora dawn wash with softer blobs.
//

import SwiftUI

struct AuroraBackground: View {
    /// Optional zone tint. nil = neutral teal/blue/violet mix.
    var mood: BrainwaveCategory? = nil
    /// When true, ambient drift halts (e.g. during an active flash session).
    var isPaused: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Void base (dark) / dawn wash (light) via adaptive tokens
            RadialGradient(
                colors: [Color.bgPrimary, Color.bgDeep],
                center: .init(x: 0.5, y: 1.15),
                startRadius: 0, endRadius: 700
            )
            .ignoresSafeArea()

            if reduceMotion || isPaused {
                staticBlobs
            } else {
                animatedBlobs
            }
        }
        .background(Color.bgDeep.ignoresSafeArea())
        .accessibilityHidden(true)
    }

    private var blobColors: [Color] {
        if let mood {
            return [mood.haloColor, .roseDeep, mood.haloColor.opacity(0.7)]
        }
        return [.roseDeep, .lavender, .roseGold]
    }

    /// Aurora blobs read heavier on the blush dawn wash; back them off in light mode.
    private var blobOpacity: Double {
        colorScheme == .light ? 0.18 : 0.35
    }

    private var staticBlobs: some View {
        ZStack {
            blob(blobColors[0]).offset(x: -120, y: -200)
            blob(blobColors[1]).offset(x: 130, y: 240)
            blob(blobColors[2]).opacity(0.5).offset(x: 60, y: 40)
        }
        .ignoresSafeArea()
    }

    private var animatedBlobs: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = t * (2 * .pi / LiminalMotion.breathDuration)
            ZStack {
                blob(blobColors[0])
                    .offset(x: -120 + CGFloat(sin(phase) * 40),
                            y: -200 + CGFloat(cos(phase * 0.8) * 30))
                blob(blobColors[1])
                    .offset(x: 130 + CGFloat(cos(phase) * 35),
                            y: 240 + CGFloat(sin(phase * 0.9) * 30))
                blob(blobColors[2])
                    .opacity(0.5)
                    .offset(x: 60 + CGFloat(sin(phase * 1.1) * 30),
                            y: 40 + CGFloat(cos(phase) * 40))
            }
            .ignoresSafeArea()
        }
    }

    private func blob(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 420, height: 420)
            .blur(radius: 90)
            .opacity(blobOpacity)
    }
}

#Preview("Neutral") { AuroraBackground() }
#Preview("Sleep mood") { AuroraBackground(mood: .sleep) }
#Preview("Light") { AuroraBackground().environment(\.colorScheme, .light) }
