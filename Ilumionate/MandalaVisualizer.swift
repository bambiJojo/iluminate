//
//  MandalaVisualizer.swift
//  Ilumionate
//
//  Concentric pulsing rings for session visualization
//

import SwiftUI

struct MandalaVisualizer: View {
    @State private var isAnimating = false
    @State private var rotationAngle: Double = 0

    let size: CGFloat
    let brightness: Double // 0.0-1.0 from light engine

    init(size: CGFloat = 200, brightness: Double = 0.5) {
        self.size = size
        self.brightness = brightness
    }

    var body: some View {
        ZStack {
            // Outer ring with rotation
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.roseGold.opacity(0.3), Color.lavender.opacity(0.2), Color.blush.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotationAngle))
                .overlay(
                    // Marker dots on outer ring
                    ForEach(0..<8, id: \.self) { index in
                        Circle()
                            .fill(Color.roseGold.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .offset(y: -size / 2)
                            .rotationEffect(.degrees(Double(index) * 45))
                    }
                )

            // Middle rings
            ForEach(0..<3, id: \.self) { index in
                let ringSize = size * (0.8 - Double(index) * 0.2)
                let opacity = 0.2 + Double(index) * 0.1

                Circle()
                    .stroke(
                        Color.roseGold.opacity(opacity * brightness),
                        lineWidth: 1.5
                    )
                    .frame(width: ringSize, height: ringSize)
                    .scaleEffect(isAnimating ? 1.05 : 0.95)
                    .opacity(isAnimating ? 0.8 : 0.4)
                    .animation(
                        .easeInOut(duration: 3.0)
                        .delay(Double(index) * 0.3)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }

            // Central core with mandala pattern
            ZStack {
                // Core gradient
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.roseGold.opacity(brightness * 0.8),
                                Color.blush.opacity(brightness * 0.4),
                                Color.lavender.opacity(brightness * 0.2),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.25
                        )
                    )
                    .frame(width: size * 0.5, height: size * 0.5)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)

                // Inner mandala petals
                ForEach(0..<12, id: \.self) { index in
                    Capsule()
                        .fill(Color.roseGold.opacity(0.3))
                        .frame(width: 2, height: size * 0.15)
                        .offset(y: -size * 0.075)
                        .rotationEffect(.degrees(Double(index) * 30))
                }

                // Center dot
                Circle()
                    .fill(Color.roseGold)
                    .frame(width: 6, height: 6)
                    .opacity(brightness)
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // Breathing animation
        withAnimation(
            .easeInOut(duration: 3.0)
            .repeatForever(autoreverses: true)
        ) {
            isAnimating = true
        }

        // Rotation animation
        withAnimation(
            .linear(duration: 20.0)
            .repeatForever(autoreverses: false)
        ) {
            rotationAngle = 360
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: TranceSpacing.cardMargin) {
        MandalaVisualizer(size: 200, brightness: 0.3)
        MandalaVisualizer(size: 120, brightness: 0.7)
        MandalaVisualizer(size: 80, brightness: 1.0)
    }
    .padding(TranceSpacing.screen)
    .background(Color.bgPrimary)
}