//
//  WaveformShape.swift
//  Ilumionate
//
//  Pure waveform sampler + a Shape that traces one glowing cycle. Used by the
//  Create tab's waveform picker so each pattern shows its real shape (spec §4).
//

import SwiftUI

/// Normalized waveform sampler. `phase` 0...1 maps one full cycle to amplitude 0...1
/// (0.5 = baseline for sine; shapes are framed for legible picker thumbnails, not DSP).
enum WaveformSample {
    static func value(_ pattern: MindMachineModel.LightPattern, phase: Double) -> Double {
        let p = phase - phase.rounded(.down) // wrap into 0..<1
        switch pattern {
        case .sine:
            return 0.5 + 0.5 * sin(p * 2 * .pi)
        case .square:
            return p < 0.5 ? 1.0 : 0.0
        case .triangle:
            return p < 0.5 ? (p / 0.5) : (1.0 - (p - 0.5) / 0.5)
        case .sawtooth:
            return p
        case .pulse:
            return p < 0.05 ? 1.0 : 0.0
        }
    }
}

/// Traces one cycle of `pattern` across the rect, y inverted so amplitude 1 is the top.
struct WaveformShape: Shape {
    let pattern: MindMachineModel.LightPattern
    var samples: Int = 64

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0...samples {
            let phase = Double(i) / Double(samples)
            let amp = WaveformSample.value(pattern, phase: phase)
            let x = rect.minX + CGFloat(phase) * rect.width
            let y = rect.maxY - CGFloat(amp) * rect.height
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

#Preview {
    ZStack {
        Color.voidPrimary.ignoresSafeArea()
        VStack(spacing: TranceSpacing.cardMargin) {
            ForEach(MindMachineModel.LightPattern.allCases, id: \.rawValue) { pattern in
                WaveformShape(pattern: pattern)
                    .stroke(
                        LinearGradient(colors: [.auroraTeal, .auroraBlue],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .frame(height: 44)
                    .shadow(color: .auroraTeal.opacity(0.5), radius: 8)
                    .padding(.horizontal, TranceSpacing.screen)
            }
        }
    }
}
