//
//  ContinueAudioCard.swift
//  Ilumionate
//

import SwiftUI

struct ContinueAudioCard: View {
    let audioFile: AudioFile
    let progress: Double
    let onContinue: () -> Void

    var body: some View {
        GlassCard(label: "Continue Listening") {
            Button(action: onContinue) {
                HStack(spacing: TranceSpacing.list) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.roseGold)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(audioFile.displayName)
                            .font(TranceTypography.body)
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1)

                        Text("\(remainingDuration.formatted(.time(pattern: .minuteSecond))) remaining")
                            .font(TranceTypography.caption)
                            .foregroundStyle(.textSecondary)
                    }

                    Spacer()

                    ProgressRingView(progress: progress)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue (audioFile.displayName)")
            .accessibilityValue("(Int(progress * 100)) percent complete")
        }
    }

    private var remainingDuration: Duration {
        .seconds(max(0, audioFile.duration * (1 - progress)))
    }
}
