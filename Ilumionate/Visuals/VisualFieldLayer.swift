//  VisualFieldLayer.swift
//  Ilumionate
//
//  Feeds a TranceVisual's shader with the current modulation. Renders nothing
//  for `.none` and `.breath` — `.breath` is the RadialGradient that already
//  lives in TextTrancePlayerView.
//
//  Shared by both surfaces: the reader draws this behind its words, and the
//  Create tab's Visual Field draws it as the whole screen.

import SwiftUI

struct VisualFieldLayer: View {
    let visual: TranceVisual
    let modulation: VisualModulation
    let opacity: Double

    var body: some View {
        if let shaderName = visual.shaderName {
            // paused: stops the schedule entirely when Reduce Motion pinned
            // speed to zero, so the shader is evaluated once and never again.
            TimelineView(.animation(paused: modulation.speed == 0)) { timeline in
                Rectangle()
                    .foregroundStyle(.black)
                    .colorEffect(
                        ShaderLibrary[dynamicMember: shaderName](
                            // boundingRect, not a GeometryReader: inside the
                            // reader's macOS window-filling cover a proxy size
                            // never resolves and the effect renders nothing.
                            .boundingRect,
                            .float(Self.shaderTime(timeline.date)),
                            .color(modulation.tint),
                            .float(Float(modulation.speed)),
                            .float(Float(modulation.amplitude)),
                            // Sourced from Swift, not hardcoded in Metal, so
                            // the photosensitivity ceiling is testable. The SIGN
                            // carries direction; the magnitude is what the
                            // ceiling test measures, so reversing travel cannot
                            // smuggle an effect past the budget.
                            .float(Float(visual.motionRate * modulation.direction.sign))
                        )
                    )
            }
            .opacity(opacity)
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }

    /// Seconds, wrapped hourly. An unwrapped absolute timestamp loses float
    /// precision and the motion visibly stutters after a while.
    private static func shaderTime(_ date: Date) -> Float {
        Float(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3_600))
    }
}
