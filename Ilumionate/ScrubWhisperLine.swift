//
//  ScrubWhisperLine.swift
//  Ilumionate
//
//  A whisper-thin progress line pinned to a screen's bottom edge that becomes
//  a full-width scrubber under touch: whisper (2pt, faint) → prominent
//  (brighter while controls are visible) → scrubbing (6pt + floating overlay).
//

import SwiftUI

struct ScrubWhisperLine<Overlay: View>: View {
    let fraction: Double
    var tint: Color = .roseGold
    var prominent = false
    var interactive = true
    /// Continuous during drag, with the scrubbed fraction (0…1).
    var onScrub: (Double) -> Void = { _ in }
    /// Fired once on release with the final fraction.
    var onScrubEnd: (Double) -> Void = { _ in }
    /// Step applied by the VoiceOver adjustable action (fraction units).
    var accessibilityStep: Double = 0.05
    /// Floating readout rendered above the line while scrubbing.
    @ViewBuilder let overlay: (Double) -> Overlay

    @State private var scrubFraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isScrubbing: Bool { scrubFraction != nil }

    var body: some View {
        GeometryReader { geo in
            let displayed = scrubFraction ?? min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.textGhost.opacity(isScrubbing ? 0.30 : prominent ? 0.22 : 0.12))
                Capsule()
                    .fill(tint.opacity(isScrubbing ? 1 : prominent ? 0.9 : 0.5))
                    .frame(width: max(0, geo.size.width * displayed))
            }
            .frame(height: isScrubbing ? 6 : 2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(.rect)                       // 24pt hit target
            .gesture(interactive ? dragGesture(width: geo.size.width) : nil)
            .overlay(alignment: .bottom) {
                if let scrubFraction {
                    overlay(scrubFraction)
                        .padding(.bottom, 18)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 24)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isScrubbing)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: prominent)
        .animation(.linear(duration: 0.3), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment
                ? min(1, fraction + accessibilityStep)
                : max(0, fraction - accessibilityStep)
            onScrubEnd(next)
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let f = min(1, max(0, value.location.x / max(width, 1)))
                scrubFraction = f
                onScrub(f)
            }
            .onEnded { value in
                let f = min(1, max(0, value.location.x / max(width, 1)))
                scrubFraction = nil
                onScrubEnd(f)
            }
    }
}
