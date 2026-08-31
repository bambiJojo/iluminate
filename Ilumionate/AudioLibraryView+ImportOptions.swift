// AudioLibraryView+ImportOptions.swift
// Ilumionate

import SwiftUI

extension AudioLibraryView {
    var importOptionsSection: some View {
        GlassCard(label: "Add Audio") {
            Button {
                acquisition.importFromFiles()
            } label: {
                HStack(spacing: TranceSpacing.list) {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .frame(width: 28)
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Files")
                            .font(TranceTypography.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)

                        Text("Choose audio you have permission to use")
                            .font(TranceTypography.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, TranceSpacing.card)
                .padding(.vertical, TranceSpacing.card)
                .background(
                    LinearGradient(
                        colors: [.roseGold, .roseDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                .shadow(color: Color.roseGold.opacity(0.30), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.cardMargin)
    }
}
