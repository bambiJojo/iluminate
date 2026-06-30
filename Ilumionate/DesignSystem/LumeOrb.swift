//
//  LumeOrb.swift
//  Ilumionate
//
//  The Liminal centerpiece: a conic aurora ring slowly rotating around a
//  void core, with a breathing outer glow. Sizes: hero / medium / mini.
//  Optional `pulse` frequency drives the breath rate (target Hz preview).
//

import SwiftUI

struct LumeOrb: View {
    enum Size { case hero, medium, mini
        var diameter: CGFloat { switch self { case .hero: 200; case .medium: 120; case .mini: 40 } }
        var ringInset: CGFloat { switch self { case .hero: 7; case .medium: 5; case .mini: 2 } }
        var glowRadius: CGFloat { switch self { case .hero: 40; case .medium: 22; case .mini: 8 } }
    }

    var size: Size = .hero
    /// Optional target frequency (Hz). When set, breath period = 1/pulse, clamped to a calm range.
    var pulse: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var breathPeriod: Double {
        guard let pulse, pulse > 0 else { return LiminalMotion.breathDuration }
        // Map entrainment Hz to a visible-but-calm breath (never seizure-fast).
        return min(6.0, max(2.0, 1.0 / pulse * 4.0))
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let spin = reduceMotion ? 0 : (t / LiminalMotion.orbSpinDuration)
                .truncatingRemainder(dividingBy: 1) * 360
            let breath = reduceMotion ? 0.0 : sin(t * (2 * .pi / breathPeriod))
            let glowScale = 1.0 + 0.10 * breath
            let glowOpacity = 0.6 + 0.25 * breath

            ZStack {
                // Outer breathing glow
                Circle()
                    .fill(RadialGradient(colors: [Color.auroraBlue.opacity(0.4), .clear],
                                         center: .center, startRadius: 0,
                                         endRadius: size.diameter * 0.9))
                    .scaleEffect(glowScale)
                    .opacity(glowOpacity)

                // Conic aurora ring
                Circle()
                    .fill(AngularGradient(colors: [.auroraTeal, .auroraBlue, .auroraViolet, .auroraPink, .auroraTeal],
                                          center: .center))
                    .rotationEffect(.degrees(spin))

                // Void core
                Circle()
                    .fill(Color.voidPrimary)
                    .padding(size.ringInset)
            }
            .frame(width: size.diameter, height: size.diameter)
            .shadow(color: .auroraBlue.opacity(0.4), radius: size.glowRadius)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Hero") {
    ZStack { Color.voidPrimary.ignoresSafeArea(); LumeOrb(size: .hero) }
}
#Preview("Mini") {
    ZStack { Color.voidPrimary.ignoresSafeArea(); LumeOrb(size: .mini) }
}
