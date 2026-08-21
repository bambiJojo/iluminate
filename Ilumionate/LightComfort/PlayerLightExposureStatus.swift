//
//  PlayerLightExposureStatus.swift
//  Ilumionate
//
//  Quiet, controls-only feedback for the current light-time budget.
//

import SwiftUI

struct PlayerLightExposureStatus: View {
    let text: String
    let limitReached: Bool

    var body: some View {
        Label(text, systemImage: limitReached ? "moon.zzz" : "hourglass")
            .font(TranceTypography.caption)
            .foregroundStyle(Color.white.opacity(0.75))
            .accessibilityLabel(text)
    }
}
