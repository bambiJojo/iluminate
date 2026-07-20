//
//  AnalysisReadySessionsCard.swift
//  Ilumionate
//

import SwiftUI

struct AnalysisReadySessionsCard: View {
    let files: [AudioFile]
    let onPlay: (AudioFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            Label("Ready to Play", systemImage: "sparkles")
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.textPrimary)

            GlassCard {
                VStack(spacing: TranceSpacing.list) {
                    ForEach(Array(files.prefix(3).enumerated()), id: \.element.id) { index, file in
                        if index > 0 {
                            Divider()
                        }

                        HStack(spacing: TranceSpacing.list) {
                            Image(systemName: "waveform.badge.checkmark")
                                .font(.title3)
                                .foregroundStyle(Color.bwGamma)
                                .frame(width: 34, height: 34)

                            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                                Text(file.displayName)
                                    .font(TranceTypography.body)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Text("Analysis complete · Light Sync ready")
                                    .font(TranceTypography.caption)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: TranceSpacing.inner)

                            Button("Play", systemImage: "play.fill") {
                                onPlay(file)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.roseGold)
                            .accessibilityHint("Starts the generated Light Sync session")
                        }
                    }
                }
            }
        }
    }
}
