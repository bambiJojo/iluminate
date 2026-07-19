//
//  PlayerInterruptionBanner.swift
//  Ilumionate
//

import SwiftUI

struct PlayerInterruptionBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            Label(message, systemImage: "pause.circle.fill")
                .font(.callout)
                .foregroundStyle(.white)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: TranceRadius.thumbnail))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Dismiss message")
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.statusBar)
    }
}
