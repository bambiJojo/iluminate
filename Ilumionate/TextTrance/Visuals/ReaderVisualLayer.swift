//  ReaderVisualLayer.swift
//  Ilumionate
//
//  Feeds a ReaderVisual's shader with the current modulation. Renders nothing
//  for `.none` and `.breath` — `.breath` is the RadialGradient that already
//  lives in TextTrancePlayerView.

import SwiftUI

struct ReaderVisualLayer: View {
    let visual: ReaderVisual
    let modulation: ReaderVisualModulation
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
                            // the photosensitivity ceiling is testable.
                            .float(Float(visual.motionRate))
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
