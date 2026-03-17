//
//  PlayerCountdownOverlay.swift
//  Ilumionate
//
//  Configurable countdown overlay shown before session playback begins.
//

import SwiftUI

struct PlayerCountdownOverlay: View {
    let count: Int

    var body: some View {
        ZStack {
            Color.bgPrimary.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: TranceSpacing.content) {
                Text("\(count)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.roseGold, .roseDeep],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.roseGold.opacity(0.4), radius: 20, x: 0, y: 8)
                    .id(count)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.4).combined(with: .opacity),
                        removal: .scale(scale: 0.6).combined(with: .opacity)
                    ))

                Text("Get ready\u{2026}")
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textSecondary)
            }
            .animation(.easeInOut(duration: 0.35), value: count)
        }
    }
}
