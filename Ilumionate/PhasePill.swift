//
//  PhasePill.swift
//  Ilumionate
//
//  Capsule labels for hypnosis phases
//

import SwiftUI

struct PhasePill: View {
    let phase: String   // e.g. "Deepener Phase"

    var body: some View {
        Text(phase)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.roseDeep)
            .padding(.horizontal, TranceSpacing.card)
            .padding(.vertical, 5)
            .background(
                LinearGradient(colors: [.blush, Color.roseGold.opacity(0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: TranceSpacing.list) {
        PhasePill(phase: "Intro Phase")
        PhasePill(phase: "Induction Phase")
        PhasePill(phase: "Deepener Phase")
        PhasePill(phase: "Fractionation Phase")
        PhasePill(phase: "Suggestion Phase")
        PhasePill(phase: "Awakening Phase")
    }
    .padding(TranceSpacing.screen)
    .background(Color.bgPrimary)
}