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

    /// Drives the drift. Flipped once on appear; the repeating animations below
    /// carry it from there.
    @State private var drifting = false

    /// The drift used to run through `TimelineView(.animation)`, which re-evaluated
    /// the whole stack every display frame — up to 120 times a second on ProMotion.
    /// Since only the offsets changed, that re-rendered three identical blurs per
    /// frame for nothing, and forced every `.ultraThinMaterial` surface above to
    /// re-sample its backdrop just as often.
    ///
    /// Now the offsets are driven by repeating implicit animations, so the blobs
    /// rasterize once and the compositor only moves them. Periods are mutually
    /// prime-ish so the three never fall into lockstep.
    private var animatedBlobs: some View {
        ZStack {
            blob(blobColors[0])
                .offset(x: drifting ? -80 : -160, y: drifting ? -170 : -230)
                .animation(breath(LiminalMotion.breathDuration), value: drifting)

            blob(blobColors[1])
                .offset(x: drifting ? 165 : 95, y: drifting ? 270 : 210)
                .animation(breath(LiminalMotion.breathDuration * 1.27), value: drifting)

            blob(blobColors[2])
                .opacity(0.5)
                .offset(x: drifting ? 90 : 30, y: drifting ? 80 : 0)
                .animation(breath(LiminalMotion.breathDuration * 1.63), value: drifting)
        }
        .ignoresSafeArea()
        .onAppear { drifting = true }
    }

    private func breath(_ duration: Double) -> Animation {
        .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }

    /// A radial gradient rather than a solid circle behind `.blur(radius: 90)`.
    /// The blur was an offscreen Gaussian pass per blob per frame; the gradient
    /// is the same soft falloff drawn directly, with no extra pass.
    private func blob(_ color: Color) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(blobOpacity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 210
                )
            )
            .frame(width: 420, height: 420)
    }
}

#Preview("Neutral") { AuroraBackground() }
#Preview("Sleep mood") { AuroraBackground(mood: .sleep) }
#Preview("Light") { AuroraBackground().environment(\.colorScheme, .light) }
