//
//  PlayerPauseOverlay.swift
//  Ilumionate
//
//  Pause overlay shown when the session is paused.
//

import SwiftUI

struct PlayerPauseOverlay: View {
    let onTap: () -> Void

    var body: some View {
        ZStack {
            Color.bgPrimary.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: TranceSpacing.content) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.roseGold)

                Text("Session Paused")
                    .font(TranceTypography.trackTitle)
                    .foregroundStyle(Color.textPrimary)

                Text("Tap play to continue")
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .onTapGesture(perform: onTap)
    }
}
