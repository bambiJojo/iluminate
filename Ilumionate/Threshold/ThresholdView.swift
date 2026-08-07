//
//  ThresholdView.swift
//  Ilumionate
//
//  The launch threshold. Void, a breathing orb, and a vignette that closes and
//  releases — then the app is simply there.
//
//  The aurora drawn here is deliberately the same field Home draws, at the same
//  mood and the same phase: `AuroraBackground` animates off the absolute clock,
//  so two instances mounted seconds apart are pixel-identical. That is what
//  makes the exit seamless without any geometry matching.
//

import SwiftUI

struct ThresholdView: View {
    /// Plain `let` is correct here — `@Observable` tracks reads without
    /// `@Bindable`, and nothing in this view needs a two-way binding.
    let controller: ThresholdController

    /// Same call Home makes, so the two fields agree on colour as well as phase.
    private var mood: BrainwaveCategory {
        PortalRecommender.category(forHour: Calendar.current.component(.hour, from: .now))
    }

    var body: some View {
        TimelineView(.animation) { context in
            let frame = controller.frame(at: context.date)

            ZStack {
                Color.bgDeep
                    .ignoresSafeArea()

                AuroraBackground(mood: mood)
                    .opacity(frame.auroraOpacity)

                LumeOrb(size: .hero)
                    .scaleEffect(frame.orbScale)
                    .opacity(frame.orbOpacity)

                ThresholdVignette(closure: frame.vignetteClosure)

                Button {
                    controller.skip(now: .now)
                } label: {
                    Color.clear.contentShape(.rect)
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()
                .accessibilityLabel("Skip the opening")
            }
            .onChange(of: controller.hasElapsed(at: context.date)) { _, hasElapsed in
                if hasElapsed { controller.finish() }
            }
        }
        .task {
            controller.begin(at: .now)
        }
    }
}

#Preview("Full motion") {
    ThresholdView(controller: ThresholdController(isSuppressed: false, motion: .full))
}
#Preview("Reduced motion") {
    ThresholdView(controller: ThresholdController(isSuppressed: false, motion: .reduced))
}
