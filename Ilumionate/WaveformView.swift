//
//  WaveformView.swift
//  Ilumionate
//
//  Audio waveform visualization with smooth curves
//

import SwiftUI

struct WaveformView: View {
    let samples: [CGFloat]  // normalized 0–1
    let color: Color
    let strokeWidth: CGFloat

    init(samples: [CGFloat], color: Color = .roseGold, strokeWidth: CGFloat = 2) {
        self.samples = samples
        self.color = color
        self.strokeWidth = strokeWidth
    }

    var body: some View {
        GeometryReader { geometry in
            if samples.isEmpty {
                // Fallback for empty samples
                Rectangle()
                    .fill(color.opacity(0.3))
                    .frame(height: 2)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            } else {
                Path { path in
                    let width = geometry.size.width / CGFloat(max(samples.count - 1, 1))
                    let height = geometry.size.height

                    if samples.count == 1 {
                        // Single sample - draw a line
                        let y = height * (1 - samples[0])
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    } else {
                        // Multiple samples - draw smooth curve
                        path.move(to: CGPoint(x: 0, y: height * (1 - samples[0])))

                        for i in 1..<samples.count {
                            let x = CGFloat(i) * width
                            let y = height * (1 - samples[i])
                            let previousX = CGFloat(i - 1) * width
                            let previousY = height * (1 - samples[i - 1])

                            // Control point for smooth curve
                            let controlPoint = CGPoint(x: previousX + width / 2, y: previousY)
                            path.addQuadCurve(to: CGPoint(x: x, y: y), control: controlPoint)
                        }
                    }
                }
                .stroke(color, lineWidth: strokeWidth)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: TranceSpacing.cardMargin) {
        // Sample waveform data
        let sampleData1: [CGFloat] = [0.1, 0.3, 0.8, 0.4, 0.6, 0.9, 0.2, 0.7, 0.3, 0.5, 0.8, 0.1, 0.4, 0.9, 0.2, 0.6]
        let sampleData2: [CGFloat] = [0.5, 0.7, 0.3, 0.8, 0.2, 0.6, 0.9, 0.4, 0.1, 0.7, 0.5, 0.8, 0.3, 0.6, 0.2, 0.9]

        GlassCard(label: "Audio Waveform") {
            VStack(spacing: TranceSpacing.inner) {
                WaveformView(samples: sampleData1)
                    .frame(height: 60)

                Text("Deep Sleep Induction - Dr. Sarah Mitchell")
                    .font(TranceTypography.body)
                    .foregroundStyle(.textPrimary)
            }
        }

        GlassCard(label: "Small Waveform") {
            WaveformView(samples: sampleData2, color: .bwAlpha)
                .frame(height: 30)
        }

        GlassCard(label: "Empty Waveform") {
            WaveformView(samples: [])
                .frame(height: 30)
        }
    }
    .padding(TranceSpacing.screen)
    .background(Color.bgPrimary)
}