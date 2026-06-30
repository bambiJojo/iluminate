//
//  PhaseTimeline.swift
//  Ilumionate
//
//  Slim glowing segmented strip across the canonical session arc. The active
//  stage glows brighter and pulses at Breath tempo (frozen under Reduce Motion).
//  Self-contained Stage enum — decoupled from the analysis model (spec §3/§4).
//

import SwiftUI

struct PhaseTimeline: View {
    /// The canonical session arc shown as a glowing strip.
    enum Stage: String, CaseIterable, Identifiable {
        case intro, induction, deepener, suggestion, awakening
        var id: String { rawValue }
    }

    /// The stage currently highlighted, or nil for a neutral preview (all dim).
    var current: Stage? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || current == nil {
                strip(pulse: 1.0)
            } else {
                TimelineView(.animation) { context in
                    strip(pulse: pulseOpacity(at: context.date))
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private func strip(pulse: Double) -> some View {
        HStack(spacing: TranceSpacing.micro) {
            ForEach(Stage.allCases) { stage in
                let isActive = stage == current
                Capsule()
                    .fill(isActive ? Color.auroraTeal : Color.auroraBlue.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .opacity(isActive ? pulse : 1.0)
                    .shadow(color: isActive ? Color.auroraTeal.opacity(0.6 * pulse) : .clear, radius: 6)
            }
        }
    }

    private func pulseOpacity(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let phase = t * (2 * .pi / LiminalMotion.breathDuration)
        return 0.7 + 0.3 * (0.5 + 0.5 * sin(phase))
    }
}

#Preview {
    ZStack {
        Color.voidPrimary.ignoresSafeArea()
        VStack(spacing: TranceSpacing.cardMargin) {
            PhaseTimeline(current: .deepener)
            PhaseTimeline(current: nil)
        }
        .padding(TranceSpacing.screen)
    }
}
