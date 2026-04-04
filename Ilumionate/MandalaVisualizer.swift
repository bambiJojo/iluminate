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
    @State private var animationScale: CGFloat = 1.0
    @State private var isVisible = true

    let size: CGFloat
    let brightness: Double // 0.0-1.0 from light engine
    var isPlaying: Bool

    init(size: CGFloat = 200, brightness: Double = 0.5, isPlaying: Bool = true) {
        self.size = size
        self.brightness = brightness
        self.isPlaying = isPlaying
    }

    var body: some View {
        // Evaluate once per body call instead of on every sub-expression
        let shouldReduceAnimations = brightness < 0.1
        let animationDuration: Double = shouldReduceAnimations ? 6.0 : 3.0
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

            // Middle rings - optimized for performance
            if !shouldReduceAnimations {
                ForEach(0..<3, id: \.self) { index in
                    let ringSize = size * (0.8 - Double(index) * 0.2)
                    let opacity = 0.2 + Double(index) * 0.1

                    Circle()
                        .stroke(
                            Color.roseGold.opacity(opacity * brightness),
                            lineWidth: 1.5
                        )
                        .frame(width: ringSize, height: ringSize)
                        .scaleEffect(animationScale)
                        .opacity(isAnimating ? 0.8 : 0.4)
                        .animation(
                            .easeInOut(duration: animationDuration)
                            .delay(Double(index) * 0.3)
                            .repeatForever(autoreverses: true),
                            value: isAnimating
                        )
                }
            }

            // Central core with mandala pattern
            ZStack {
                // Core gradient - adaptive complexity
                Circle()
                    .fill(
                        shouldReduceAnimations
                        ? AnyShapeStyle(Color.roseGold.opacity(brightness * 0.6))
                        : AnyShapeStyle(RadialGradient(
                            colors: [
                                Color.roseGold.opacity(brightness * 0.8),
                                Color.blush.opacity(brightness * 0.4),
                                Color.lavender.opacity(brightness * 0.2),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.25
                        ))
                    )
                    .frame(width: size * 0.5, height: size * 0.5)
                    .scaleEffect(animationScale)

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
        .opacity(isPlaying ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.6), value: isPlaying)
        .onAppear {
            isVisible = true
            if isPlaying {
                startAnimations(reduced: brightness < 0.1)
            }
        }
        .onDisappear {
            isVisible = false
        }
        .onChange(of: brightness) { oldValue, newValue in
            // Restart animations only when performance tier changes
            if (oldValue < 0.1) != (newValue < 0.1), isPlaying {
                startAnimations(reduced: newValue < 0.1)
            }
        }
        .onChange(of: isPlaying) { _, newValue in
            if newValue {
                startAnimations(reduced: brightness < 0.1)
            } else {
                settleAnimations()
            }
        }
    }

    private func startAnimations(reduced: Bool) {
        guard isVisible else { return }
        let duration: Double = reduced ? 6.0 : 3.0

        withAnimation(
            .easeInOut(duration: duration)
            .repeatForever(autoreverses: true)
        ) {
            isAnimating = true
            animationScale = reduced ? 1.02 : 1.1
        }

        let rotationDuration = reduced ? 40.0 : 20.0
        withAnimation(
            .linear(duration: rotationDuration)
            .repeatForever(autoreverses: false)
        ) {
            rotationAngle += 360
        }
    }

    /// Smoothly settle animations to a resting state when playback pauses.
    private func settleAnimations() {
        withAnimation(.easeOut(duration: 0.8)) {
            isAnimating = false
            animationScale = 1.0
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
