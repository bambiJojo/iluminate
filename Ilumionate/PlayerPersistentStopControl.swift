//
//  PlayerPersistentStopControl.swift
//  Ilumionate
//
//  One-tap escape hatch that remains visible after the player controls hide.
//

import SwiftUI

struct PlayerPersistentStopControl: View {
    let revealProgress: Double
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: TranceSpacing.small) {
            Text("Swipe up to show controls")
                .font(TranceTypography.caption)
                .foregroundStyle(.white.opacity(0.65 * (1 - revealProgress)))

            Button("Stop session", systemImage: "stop.fill", action: onStop)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, TranceSpacing.content)
                .frame(minHeight: 44)
                .background(.black.opacity(0.68), in: .capsule)
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ends the session immediately")
        }
        .padding(.bottom, TranceSpacing.statusBar)
    }
}

#Preview {
    ZStack {
        Color.pink
        PlayerPersistentStopControl(revealProgress: 0, onStop: {})
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
    .ignoresSafeArea()
}
