//  CreateFieldPreview.swift
//  Ilumionate
//
//  What the configured session will actually look like, rendered with the same
//  shader and the same modulation the session will run — not an illustration of
//  it. This replaces PhoneScreenOrb, which drew a picture of a phone.
//
//  Two constraints. It renders at the configured strength, so what you see is
//  what you get. And it obeys the same flicker budget as the session, because a
//  preview is a small light flashing at you for as long as you sit on this
//  screen — VisualFieldSettings.modulation is the only path in, so it cannot
//  exceed the bands.

import SwiftUI

struct CreateFieldPreview: View {
    let kind: CreateSessionKind
    let visual: VisualFieldSettings
    let light: MindMachineModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 200

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                .fill(Color.bgSecondary.opacity(0.55))

            content
                .clipShape(.rect(cornerRadius: TranceRadius.glassCard))

            RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                .stroke(Color.glassBorder, lineWidth: 1)
        }
        .frame(height: Self.height)
        .overlay(alignment: .bottomLeading) { caption }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview")
        .accessibilityValue(captionText)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .visualField:
            // focus: 0 — there is no word to protect, and the compressed centre
            // is the whole point of an inward effect.
            VisualFieldLayer(
                visual: visual.visual,
                modulation: visual.modulation(reduceMotion: reduceMotion),
                opacity: visual.clampedOpacity,
                focus: 0
            )
        case .flash, .bilateral, .colourPulse:
            // LumeOrb takes only size and pulse — it derives its own breath
            // period from the frequency and clamps it to a calm range, which is
            // the behaviour a preview wants. Intensity and warmth are carried by
            // the gradient behind it.
            LumeOrb(size: .medium, pulse: light.frequency)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RadialGradient(
                        colors: [
                            Color.fromKelvin(light.colorTemperature)
                                .opacity(0.35 * light.intensity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: Self.height * 0.7
                    )
                }
        }
    }

    private var caption: some View {
        Text(captionText)
            .font(TranceTypography.caption)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, TranceSpacing.inner)
            .padding(.vertical, TranceSpacing.micro)
            .background(.ultraThinMaterial, in: .capsule)
            .padding(TranceSpacing.inner)
    }

    private var captionText: String {
        switch kind {
        case .visualField:
            let strength = visual.clampedOpacity
                .formatted(.percent.precision(.fractionLength(0)))
            return "\(visual.visual.displayName) · \(visual.direction.displayName) · \(strength)"
        case .flash, .bilateral, .colourPulse:
            let hertz = light.frequency.formatted(.number.precision(.fractionLength(1)))
            return "\(light.brainwaveZone) · \(hertz) Hz"
        }
    }
}
