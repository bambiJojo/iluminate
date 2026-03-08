//
//  PulseOrb.swift
//  Ilumionate
//
//  Breathing animation orb component for light visualization
//

import SwiftUI

struct PulseOrb: View {
    let frequency: Double
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.6

    private var animationDuration: Double {
        1.0 / frequency
    }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.flashOn.opacity(0.8),
                        Color.roseGold.opacity(0.6),
                        Color.roseDeep.opacity(0.3)
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: 100
                )
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                startPulsing()
            }
            .onChange(of: frequency) { _, _ in
                startPulsing()
            }
    }

    private func startPulsing() {
        withAnimation(
            .easeInOut(duration: animationDuration)
            .repeatForever(autoreverses: true)
        ) {
            scale = 1.2
            opacity = 0.9
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.bgPrimary
            .ignoresSafeArea()

        VStack(spacing: 40) {
            Text("Alpha (10 Hz)")
                .font(TranceTypography.sectionTitle)
                .foregroundColor(.textPrimary)

            PulseOrb(frequency: 10.0)
                .frame(width: 200, height: 200)

            Text("Theta (6 Hz)")
                .font(TranceTypography.sectionTitle)
                .foregroundColor(.textPrimary)

            PulseOrb(frequency: 6.0)
                .frame(width: 200, height: 200)
        }
    }
}