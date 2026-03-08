//
//  IntensityDial.swift
//  Ilumionate
//
//  Circular intensity control with gesture handling
//

import SwiftUI

struct IntensityDial: View {
    @Binding var intensity: Double // 0.0 to 1.0
    @State private var isDragging = false
    @State private var lastAngle: Double = 0

    private let minAngle: Double = -135 // degrees
    private let maxAngle: Double = 135  // degrees
    private let dialRadius: CGFloat = 80

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.glassBorder, lineWidth: 4)
                .frame(width: dialRadius * 2, height: dialRadius * 2)

            // Active track
            Circle()
                .trim(from: 0, to: CGFloat(intensity))
                .stroke(
                    AngularGradient(
                        colors: [Color.roseGold, Color.roseDeep, Color.warmAccent],
                        center: .center,
                        startAngle: .degrees(minAngle),
                        endAngle: .degrees(maxAngle)
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: dialRadius * 2, height: dialRadius * 2)
                .rotationEffect(.degrees(-90))

            // Center button with intensity display
            ZStack {
                Circle()
                    .fill(Color.bgCard)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .stroke(Color.glassBorder, lineWidth: 1)
                    )

                VStack(spacing: 2) {
                    Text("\(Int(intensity * 100))")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("%")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.textSecondary)
                }
            }

            // Drag handle
            Circle()
                .fill(isDragging ? Color.roseDeep : Color.roseGold)
                .frame(width: 16, height: 16)
                .position(handlePosition)
                .scaleEffect(isDragging ? 1.2 : 1.0)
                .shadow(
                    color: Color.roseGold.opacity(0.3),
                    radius: isDragging ? 8 : 4,
                    x: 0, y: 2
                )
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        TranceHaptics.shared.selection()
                    }

                    let angle = angleFromPosition(value.location)
                    let normalizedAngle = normalizeAngle(angle)
                    intensity = max(0.0, min(1.0, normalizedAngle))
                }
                .onEnded { _ in
                    isDragging = false
                    TranceHaptics.shared.light()
                }
        )
    }

    private var handlePosition: CGPoint {
        let angle = minAngle + (intensity * (maxAngle - minAngle))
        let radian = angle * .pi / 180
        let x = dialRadius + dialRadius * cos(radian)
        let y = dialRadius + dialRadius * sin(radian)
        return CGPoint(x: x, y: y)
    }

    private func angleFromPosition(_ position: CGPoint) -> Double {
        let center = CGPoint(x: dialRadius, y: dialRadius)
        let dx = position.x - center.x
        let dy = position.y - center.y
        let angle = atan2(dy, dx) * 180 / .pi
        return angle
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        let normalizedAngle = angle < 0 ? angle + 360 : angle
        let adjustedAngle = normalizedAngle - 90 // Adjust for 12 o'clock start

        if adjustedAngle >= minAngle && adjustedAngle <= maxAngle {
            return (adjustedAngle - minAngle) / (maxAngle - minAngle)
        }

        return intensity // Return current value if outside range
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        Text("Intensity Control")
            .font(TranceTypography.sectionTitle)
            .foregroundColor(.textPrimary)

        IntensityDial(intensity: .constant(0.7))

        Text("Drag the handle around the dial")
            .font(TranceTypography.caption)
            .foregroundColor(.textSecondary)
    }
    .padding(TranceSpacing.screen)
    .background(Color.bgPrimary)
}