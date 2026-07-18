//
//  PlaylistGridTile.swift
//  Ilumionate
//
//  2-up glass grid tile for the bento playlist layout.
//

import SwiftUI

struct PlaylistGridTile: View {
    let playlist: Playlist
    let types: [AudioContentType]
    var onPlay: () -> Void
    var onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                PlaylistArtworkView(types: types, iconSize: 22)
                    .frame(height: 84)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottomTrailing) {
                        if !playlist.isEmpty {
                            PlaylistPlayButton(size: 30, action: onPlay)
                                .padding(TranceSpacing.inner)
                        }
                    }

                Text(playlist.name)
                    .font(TranceTypography.body)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: TranceSpacing.inner) {
                    Text("\(playlist.itemCount) tracks · \(playlist.totalDurationFormatted)")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)

                    if playlist.smartTransitions {
                        Image(systemName: "arrow.trianglehead.merge")
                            .font(TranceTypography.cardLabel)
                            .foregroundStyle(.roseGold)
                    }
                }
            }
            .padding(TranceSpacing.list)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
            .overlay(
                RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                    .strokeBorder(Color.glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        HStack(spacing: TranceSpacing.list) {
            PlaylistGridTile(
                playlist: Playlist(name: "Focus Deep Work",
                                   items: [PlaylistItem(audioFileId: UUID(), filename: "focus.mp3", duration: 3300)]),
                types: [.brainwave],
                onPlay: {}, onEdit: {}
            )
            PlaylistGridTile(
                playlist: Playlist(name: "Morning Reset"),
                types: [.meditation, .affirmations],
                onPlay: {}, onEdit: {}
            )
        }
        .padding(TranceSpacing.screen)
    }
}
