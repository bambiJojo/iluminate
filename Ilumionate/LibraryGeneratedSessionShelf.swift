//
//  LibraryGeneratedSessionShelf.swift
//  Ilumionate
//
//  Horizontal shelf of light scores the user generated from their own audio.
//  Card visuals mirror the Built-in Sessions shelf; tapping a card plays the
//  paired audio file, which auto-loads its generated light score.
//

import SwiftUI

struct LibraryGeneratedSessionShelf: View {
    let items: [GeneratedSessionItem]
    let onPlay: (AudioFile) -> Void

    var body: some View {
        CarouselRow(items: items, cardWidthFraction: LibraryShelfMetrics.cardWidthFraction) { item in
            Button {
                onPlay(item.audioFile)
            } label: {
                GeneratedSessionShelfCard(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct GeneratedSessionShelfCard: View {
    let item: GeneratedSessionItem

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.inner) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.bwGamma.opacity(0.18))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.bwGamma)
                }

            Text(item.session.displayName)
                .font(TranceTypography.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            Text(item.session.durationFormatted)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(TranceSpacing.list)
        .frame(height: LibraryShelfMetrics.audioCardHeight)
        .liminalSurface(glow: false)
    }
}
