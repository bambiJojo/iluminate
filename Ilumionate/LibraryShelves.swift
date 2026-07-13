//
//  LibraryShelves.swift
//  Ilumionate
//
//  Shelf-first components for the Library tab: reader-style header, shelf
//  section headers, carousel shelves for recents/favorites/playlists/built-in
//  sessions, and the analysis-queue status card. Pure presentation — all
//  state and actions stay in LibraryView.
//

import SwiftUI

// MARK: - Header

/// "Library" title with a circular + button, matching the reader's header.
struct LibraryHubHeader: View {
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Text("Library")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.auroraTeal)
                    .frame(width: 36, height: 36)
                    .background(Color.glassBorder.opacity(0.14), in: .circle)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.glassBorder.opacity(0.35), lineWidth: 1)
                    }
            }
            .accessibilityLabel("Add sessions")
        }
    }
}

// MARK: - Section Header

/// Shelf title with an optional trailing "See all" action.
struct LibraryShelfSectionHeader: View {
    let title: String
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TranceTypography.sectionTitle)
                .fontWeight(.bold)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            if let onSeeAll {
                Button("See all", action: onSeeAll)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.auroraTeal)
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, TranceSpacing.micro)
    }
}

// MARK: - Analysis Queue Status

/// Compact status row shown only while analyses are queued or running.
struct AnalysisQueueStatusCard: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GlassCard {
                HStack(spacing: TranceSpacing.list) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.roseGold.opacity(0.18))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "waveform")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.roseGold)
                        }

                    Text("Analysis Queue")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)

                    Spacer()

                    Text("\(count)")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textLight)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textLight)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Audio Shelf (Recently Played / Favorites)

/// Horizontal shelf of audio-file cards; tapping a card plays it with lights.
struct LibraryAudioShelf: View {
    let files: [AudioFile]
    var showsHeart = false
    let onPlay: (AudioFile) -> Void

    var body: some View {
        CarouselRow(items: files) { file in
            Button {
                onPlay(file)
            } label: {
                AudioShelfCard(file: file, showsHeart: showsHeart)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AudioShelfCard: View {
    let file: AudioFile
    var showsHeart = false

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.list) {
                    SessionGlowDot(contentType: file.analysisResult?.contentType, size: 40)

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(file.displayName)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(file.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if showsHeart {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "E85D75"))
                    }
                }

                ShelfPlayPill()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 128)
    }
}

// MARK: - Playlists Shelf

/// Horizontal shelf of playlist cards; tapping plays the playlist.
struct LibraryPlaylistShelf: View {
    let playlists: [Playlist]
    let onPlay: (Playlist) -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        CarouselRow(items: playlists) { playlist in
            Button {
                onPlay(playlist)
            } label: {
                PlaylistShelfCard(playlist: playlist)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Play", systemImage: "play.fill") {
                    onPlay(playlist)
                }
                Button("Open Playlists", systemImage: "music.note.list") {
                    onOpenLibrary()
                }
            }
        }
    }
}

private struct PlaylistShelfCard: View {
    let playlist: Playlist

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.list) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.roseGold.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.roseGold)
                        }

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(playlist.name)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text("\(playlist.itemCount) tracks · \(playlist.totalDurationFormatted)")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                ShelfPlayPill()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 128)
    }
}

// MARK: - Built-in Sessions Shelf

/// Horizontal shelf of bundled light-session cards; tapping plays the session.
struct LibraryBuiltInSessionShelf: View {
    let sessions: [LightSession]
    let onPlay: (LightSession) -> Void

    var body: some View {
        CarouselRow(items: sessions) { session in
            Button {
                onPlay(session)
            } label: {
                BuiltInSessionShelfCard(session: session)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct BuiltInSessionShelfCard: View {
    let session: LightSession

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.list) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.bwGamma.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.bwGamma)
                        }

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(session.displayName)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(session.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                ShelfPlayPill()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 128)
    }
}

// MARK: - Shared Pill

/// Gradient "Play" pill shared by all shelf cards (mirrors the reader's
/// Resume pill on Continue Reading cards).
private struct ShelfPlayPill: View {
    var body: some View {
        Label("Play", systemImage: "play.fill")
            .font(TranceTypography.caption.weight(.semibold))
            .foregroundStyle(Color.voidDeep)
            .padding(.horizontal, TranceSpacing.list)
            .padding(.vertical, TranceSpacing.icon)
            .background(
                LinearGradient(colors: [.auroraTeal, .auroraBlue],
                               startPoint: .leading, endPoint: .trailing),
                in: .capsule
            )
    }
}
