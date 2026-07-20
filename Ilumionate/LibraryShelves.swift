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
                    .foregroundStyle(Color.roseGold)
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
                    .foregroundStyle(Color.roseGold)
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

/// Horizontal shelf of audio-file cards; tapping a card plays it with lights,
/// while the info control opens the file's detail screen.
struct LibraryAudioShelf: View {
    let files: [AudioFile]
    var showsHeart = false
    var showsAnalyzedSeal = false
    let onPlay: (AudioFile) -> Void
    var onOpenInfo: ((AudioFile) -> Void)? = nil

    var body: some View {
        CarouselRow(items: files) { file in
            // The info control is a sibling of the play button, not nested in
            // its label — a button inside another button's label won't receive taps.
            ZStack(alignment: .bottomTrailing) {
                Button {
                    onPlay(file)
                } label: {
                    AudioShelfCard(file: file, showsHeart: showsHeart, showsAnalyzedSeal: showsAnalyzedSeal)
                }
                .buttonStyle(.plain)

                if let onOpenInfo {
                    Button {
                        TranceHaptics.shared.light()
                        onOpenInfo(file)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.textSecondary)
                            .padding(TranceSpacing.list)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About \(file.displayName)")
                }
            }
        }
    }
}

private struct AudioShelfCard: View {
    let file: AudioFile
    var showsHeart = false
    var showsAnalyzedSeal = false

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

                    if showsAnalyzedSeal {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.roseGold)
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

/// Horizontal shelf of playlist cards, led by a create card; tapping a
/// playlist plays it, tapping the create card opens the new-playlist editor.
struct LibraryPlaylistShelf: View {
    let playlists: [Playlist]
    let onPlay: (Playlist) -> Void
    let onCreate: () -> Void
    let onOpenLibrary: () -> Void

    private var items: [PlaylistShelfItem] {
        [.create] + playlists.map(PlaylistShelfItem.playlist)
    }

    var body: some View {
        CarouselRow(items: items) { item in
            switch item {
            case .create:
                Button {
                    TranceHaptics.shared.light()
                    onCreate()
                } label: {
                    NewPlaylistCard()
                }
                .buttonStyle(.plain)
            case .playlist(let playlist):
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
}

private enum PlaylistShelfItem: Identifiable {
    case create
    case playlist(Playlist)

    var id: String {
        switch self {
        case .create: return "create-playlist"
        case .playlist(let playlist): return playlist.id.uuidString
        }
    }
}

/// Dashed "New Playlist" affordance leading the playlists shelf.
private struct NewPlaylistCard: View {
    var body: some View {
        VStack(spacing: TranceSpacing.list) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.roseGold)
            Text("New Playlist")
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 128)
        .background(Color.glassBorder.opacity(0.10),
                    in: .rect(cornerRadius: TranceRadius.glassCard))
        .overlay {
            RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                .strokeBorder(Color.roseGold.opacity(0.5),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
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

// MARK: - Artists Shelf

/// Horizontal shelf of creator cards; tapping opens that artist's sessions.
struct LibraryArtistShelf: View {
    let artists: [LibraryArtist]
    let onOpen: (LibraryArtist) -> Void

    var body: some View {
        CarouselRow(items: artists) { artist in
            Button {
                TranceHaptics.shared.light()
                onOpen(artist)
            } label: {
                ArtistShelfCard(artist: artist)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ArtistShelfCard: View {
    let artist: LibraryArtist

    var body: some View {
        LiminalCard {
            HStack(spacing: TranceSpacing.list) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.roseDeep.opacity(0.18))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "music.mic")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.roseDeep)
                    }

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(artist.name)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(artist.fileCount) sessions")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 88)
    }
}

// MARK: - Empty Library

/// Shown under the header when no audio files exist at all.
struct LibraryEmptyCard: View {
    var body: some View {
        GlassCard {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(Color.roseGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No sessions yet")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Tap  +  to add your first session")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared Pill

/// Gradient "Play" pill shared by all shelf cards (mirrors the reader's
/// Resume pill on Continue Reading cards).
private struct ShelfPlayPill: View {
    var body: some View {
        Label("Play", systemImage: "play.fill")
            .font(TranceTypography.caption.weight(.semibold))
            .foregroundStyle(Color.bgDeep)
            .padding(.horizontal, TranceSpacing.list)
            .padding(.vertical, TranceSpacing.icon)
            .background(
                LinearGradient(colors: [.roseGold, .roseDeep],
                               startPoint: .leading, endPoint: .trailing),
                in: .capsule
            )
    }
}
