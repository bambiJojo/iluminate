//
//  LocalAudioMatchPickerRow.swift
//  Ilumionate
//

import SwiftUI

struct LocalAudioMatchPickerRow: View {
    let audioFile: AudioFile
    let isSuggested: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "waveform")
                .foregroundStyle(isSelected ? Color.green : Color.roseGold)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                Text(audioFile.displayName)
                    .font(TranceTypography.body)
                    .foregroundStyle(.textPrimary)

                HStack(spacing: TranceSpacing.inner) {
                    Text(audioFile.durationFormatted)
                    if isSuggested {
                        Label("Suggested", systemImage: "sparkles")
                    }
                }
                .font(TranceTypography.caption)
                .foregroundStyle(.textSecondary)
            }

            Spacer()
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}
