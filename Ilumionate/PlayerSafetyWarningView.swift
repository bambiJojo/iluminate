//
//  PlayerSafetyWarningView.swift
//  Ilumionate
//
//  Photosensitive safety warning shown before flash/color pulse modes.
//

import SwiftUI

struct PlayerSafetyWarningView: View {
    let mode: PlayerMode
    let onAcknowledge: () -> Void
    let onCancel: () -> Void

    private var warningText: String {
        switch mode {
        case .colorPulse:
            return "Color pulse mode uses rapidly changing colored light. " +
                   "Do not use if you have photosensitive epilepsy or are " +
                   "sensitive to flashing or strobing lights."
        default:
            return "This mode contains rapid flashing lights. " +
                   "Do not use if you suffer from photosensitive epilepsy " +
                   "or other light-sensitive conditions."
        }
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: TranceSpacing.content) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.roseGold)

                Text("Safety Warning")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(Color.textPrimary)

                Text(warningText)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TranceSpacing.content)

                Button(action: onAcknowledge) {
                    Text("I Understand, Continue")
                        .font(TranceTypography.body)
                        .bold()
                        .foregroundStyle(.white)
                        .padding(.vertical, TranceSpacing.list)
                        .padding(.horizontal, TranceSpacing.content)
                        .background(
                            LinearGradient(
                                colors: [.roseGold, .roseDeep],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(.rect(cornerRadius: TranceRadius.button))
                }

                Button("Cancel", action: onCancel)
                    .foregroundStyle(Color.textSecondary)
                    .font(TranceTypography.body)
            }
            .padding(TranceSpacing.screen)
        }
    }
}
