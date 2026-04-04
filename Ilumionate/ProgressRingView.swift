//
//  ProgressRingView.swift
//  Ilumionate
//
//  Circular progress indicators with rose-gold styling
//

import SwiftUI

struct ProgressRingView: View {
    let progress: Double  // 0.0–1.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.glassBorder, lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.roseGold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.roseGold)
        }
        .frame(width: 44, height: 44)
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: TranceSpacing.content) {
        ProgressRingView(progress: 0.0)
        ProgressRingView(progress: 0.3)
        ProgressRingView(progress: 0.6)
        ProgressRingView(progress: 0.9)
        ProgressRingView(progress: 1.0)
    }
    .padding(TranceSpacing.screen)
    .background(Color.bgPrimary)
}