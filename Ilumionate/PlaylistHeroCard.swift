//
//  PlaylistHeroCard.swift
//  Ilumionate
//
//  Featured playlist card for the bento layout: full-width gradient wash
//  derived from the playlist's content types, bottom scrim, aurora play button.
//

import SwiftUI

struct PlaylistHeroCard: View {
    let playlist: Playlist
    let types: [AudioContentType]
    var onPlay: () -> Void
    var onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            ZStack(alignment: .bottomLeading) {
                PlaylistArtworkView(types: types, cornerRadius: TranceRadius.glassCard)

                LinearGradient(
                    colors: [Color.voidPrimary.opacity(0.85), .clear],
                    startPoint: .bottom, endPoint: .center
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("FEATURED")
                        .font(TranceTypography.cardLabel)
                        .tracking(1.4)
                        .foregroundStyle(.textLight)

                    Text(playlist.name)
                        .font(TranceTypography.screenTitle)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: TranceSpacing.inner) {
                        Text("\(playlist.itemCount) tracks · \(playlist.totalDurationFormatted)")
                            .font(TranceTypography.caption)
                            .foregroundStyle(.textSecondary)

                        if playlist.smartTransitions {
                            CrossfadeChip()
                        }
                    }
                }
                .padding(TranceSpacing.card)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
            .overlay(
                RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                    .strokeBorder(Color.glassBorder, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                PlaylistPlayButton(size: 44, action: onPlay)
                    .padding(TranceSpacing.list)
            }
            .shadow(color: PlaylistArtwork.dominantColor(for: types).opacity(0.3),
                    radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

/// Aurora gradient circular play button shared by hero and grid tiles.
struct PlaylistPlayButton: View {
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button("Play", systemImage: "play.fill", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(Color.voidPrimary)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [.roseGold, .roseDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(.circle)
            .shadow(color: Color.roseGold.opacity(0.4), radius: 8, x: 0, y: 3)
    }
}

/// Small aurora chip indicating smart transitions are on.
struct CrossfadeChip: View {
    var body: some View {
        Label("Crossfade", systemImage: "arrow.trianglehead.merge")
            .font(TranceTypography.cardLabel)
            .foregroundStyle(.roseGold)
            .padding(.horizontal, TranceSpacing.inner)
            .padding(.vertical, 3)
            .background(Color.roseGold.opacity(0.14))
            .clipShape(.capsule)
    }
}

#Preview {
    ZStack {
        Color.voidPrimary.ignoresSafeArea()
        PlaylistHeroCard(
            playlist: Playlist(name: "Evening Descent",
                               items: [PlaylistItem(audioFileId: UUID(), filename: "drift.mp3", duration: 760)]),
            types: [.hypnosis, .meditation, .music],
            onPlay: {}, onEdit: {}
        )
        .padding(TranceSpacing.screen)
    }
}
