//
//  HomeCoreActionsView.swift
//  Ilumionate
//

import SwiftUI

struct HomeCoreActionsView: View {
    let onOpenAudioLibrary: () -> Void
    let onOpenReader: () -> Void

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text("Choose your path")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Go straight to the experiences people use most.")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                HStack(spacing: TranceSpacing.list) {
                    CoreActionButton(
                        title: "Audio",
                        subtitle: "Listen & analyze",
                        systemImage: "waveform",
                        tint: .bwAlpha,
                        action: onOpenAudioLibrary
                    )
                    CoreActionButton(
                        title: "Reader",
                        subtitle: "Start in one tap",
                        systemImage: "text.line.first.and.arrowtriangle.forward",
                        tint: .roseGold,
                        action: onOpenReader
                    )
                }
            }
        }
    }
}

private struct CoreActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(TranceTypography.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TranceSpacing.list)
            .background(tint.opacity(0.10), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title)")
    }
}
