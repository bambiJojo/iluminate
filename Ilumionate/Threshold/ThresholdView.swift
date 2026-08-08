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

    /// The instruction held beneath the orb — "Close your eyes and relax".
    ///
    /// The arc is wordless; the screen is not. Whether the user's eyes are
    /// closed changes what a photoentrainment session does, so this is
    /// functional copy rather than decoration.
    var message: String?

    /// Called when the user taps to skip. The arc eases out over
    /// `ThresholdChoreography.skipDuration` regardless; this tells the owner
    /// to bring the session forward to meet it.
    var onSkip: (() -> Void)?

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

                if let message {
                    Text(message)
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TranceSpacing.content)
                        // Tracks the aurora, not the orb: it arrives with the
                        // field during Bloom and stays up through Opening and
                        // any held line afterwards, rather than dissolving
                        // with the orb while it is still being read.
                        .opacity(frame.auroraOpacity)
                        .offset(y: LumeOrb.Size.hero.diameter * 0.85)
                        .id(message)
                        // Sequenced, not crossfaded. Both lines share a
                        // position and a font now that no numeral separates
                        // them, so overlapping them mid-swap renders as one
                        // illegible smear rather than a transition.
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeIn(duration: 0.28).delay(0.3)),
                            removal: .opacity.animation(.easeOut(duration: 0.28))
                        ))
                }

                Button {
                    controller.skip(now: .now)
                    onSkip?()
                } label: {
                    Color.clear.contentShape(.rect)
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()
                .accessibilityLabel("Begin the session now")
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
