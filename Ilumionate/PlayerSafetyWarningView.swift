//
//  PlayerSafetyWarningView.swift
//  Ilumionate
//
//  Photosensitivity warning shown before any player mode that drives the
//  flashing-light engine.
//

import SwiftUI

struct PlayerSafetyWarningView: View {
    let mode: PlayerMode
    let onAcknowledge: () -> Void
    let onCancel: () -> Void

    private var modeDescription: String {
        switch mode {
        case .colorPulse:
            return "Colour Pulse uses rapidly changing coloured light."
        default:
            return "This mode can display rapid flashing or brightness changes."
        }
    }

    private let warnings = [
        "Do not continue if you have photosensitivity, epilepsy or a history of seizures, light-triggered migraines, or another light-sensitive condition.",
        "Stop immediately if you experience discomfort, dizziness, nausea, headache, visual disturbance, confusion, or any unusual symptom.",
        "Do not use while driving, operating machinery, or anywhere you cannot stop immediately."
    ]

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

                Text(modeDescription)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TranceSpacing.content)

                VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                    ForEach(warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: TranceSpacing.inner) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(Color.roseGold)
                            Text(warning)
                                .font(TranceTypography.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.content)

                Button(action: onAcknowledge) {
                    Text("I Understand the Risks, Continue")
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
