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
        CarouselRow(items: files, cardWidthFraction: LibraryShelfMetrics.cardWidthFraction) { file in
            Button {
                onPlay(file)
            } label: {
                AudioShelfCard(
                    file: file,
                    showsHeart: showsHeart,
                    showsAnalyzedSeal: showsAnalyzedSeal,
                    reservesInfoSlot: onOpenInfo != nil
                )
            }
            .buttonStyle(.plain)
            // Layered outside the play button rather than inside its label, so
            // the info control wins the tap instead of the card behind it.
            .overlay(alignment: .bottomTrailing) {
                if let onOpenInfo {
                    ShelfInfoButton { onOpenInfo(file) }
                        .accessibilityLabel("About \(file.displayName)")
                }
            }
            // Long press keeps the same destination for anyone already used to it.
            .contextMenu {
                Button("Play", systemImage: "play.fill") { onPlay(file) }
                if let onOpenInfo {
                    Button("Session Info", systemImage: "info.circle") { onOpenInfo(file) }
                }
            }
        }
    }
}

// MARK: - Shelf Info Button

/// Trailing "about this card" control shared by the audio and playlist shelves.
/// Sits in the card's bottom-right corner, opposite the badges, where neither
/// the wrapped title nor the meta line reaches it.
private struct ShelfInfoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundStyle(Color.textLight)
                .frame(width: 32, height: 32)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .padding(.trailing, TranceSpacing.icon)
        .padding(.bottom, TranceSpacing.micro)
    }
}

/// Shared sizing for the Library shelves. Cards are deliberately narrow enough
/// that a second card and a peek of a third are always visible — a full-width
/// card turns a 144-file library into a one-item-at-a-time carousel.
enum LibraryShelfMetrics {
    static let cardWidthFraction: CGFloat = 0.46
    /// Tall enough for a two-line title plus a meta line — at a narrow width most
    /// session names wrap, and truncating them defeats the point of the shelf.
    static let audioCardHeight: CGFloat = 118
    static let artistCardHeight: CGFloat = 72
    /// Trailing room a card's meta line gives up to `ShelfInfoButton`.
    static let infoSlotWidth: CGFloat = 30
}

private struct AudioShelfCard: View {
    let file: AudioFile
    var showsHeart = false
    var showsAnalyzedSeal = false
    var reservesInfoSlot = false

    /// Creator carries more signal than duration when scanning a shelf, so it
    /// leads the meta line and duration follows.
    private var metaLine: String {
        guard let creator = file.creatorDisplayName else { return file.durationFormatted }
        return "\(creator) · \(file.durationFormatted)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.inner) {
            HStack(spacing: TranceSpacing.icon) {
                SessionGlowDot(contentType: file.analysisResult?.contentType, size: 26)

                Spacer(minLength: 0)

                if showsHeart || file.favorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "E85D75"))
                }

                if showsAnalyzedSeal || file.isAnalyzed {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.roseGold)
                }
            }

            Text(file.displayName)
                .font(TranceTypography.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            Text(metaLine)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .padding(.trailing, reservesInfoSlot ? LibraryShelfMetrics.infoSlotWidth : 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(TranceSpacing.list)
        .frame(height: LibraryShelfMetrics.audioCardHeight)
        .liminalSurface()
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
    /// Opens the playlist's own detail screen — tracks, transitions, artwork.
    var onOpenInfo: ((Playlist) -> Void)? = nil

    /// The create card trails the shelf so real playlists occupy the first
    /// slots — leading with it hid every playlist behind a swipe.
    private var items: [PlaylistShelfItem] {
        playlists.map(PlaylistShelfItem.playlist) + [.create]
    }

    var body: some View {
        CarouselRow(items: items, cardWidthFraction: LibraryShelfMetrics.cardWidthFraction) { item in
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
                    PlaylistShelfCard(playlist: playlist, reservesInfoSlot: onOpenInfo != nil)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottomTrailing) {
                    if let onOpenInfo {
                        ShelfInfoButton { onOpenInfo(playlist) }
                            .accessibilityLabel("About \(playlist.name)")
                    }
                }
                .contextMenu {
                    Button("Play", systemImage: "play.fill") {
                        onPlay(playlist)
                    }
                    if let onOpenInfo {
                        Button("Playlist Details", systemImage: "info.circle") {
                            onOpenInfo(playlist)
                        }
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
        VStack(spacing: TranceSpacing.inner) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.roseGold)
            Text("New Playlist")
                .font(TranceTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: LibraryShelfMetrics.audioCardHeight)
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
    var reservesInfoSlot = false

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.inner) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.roseGold.opacity(0.18))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.roseGold)
                }

            Text(playlist.name)
                .font(TranceTypography.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            Text(playlist.isEmpty
                 ? "Empty"
                 : "\(playlist.itemCount) tracks · \(playlist.totalDurationFormatted)")
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .padding(.trailing, reservesInfoSlot ? LibraryShelfMetrics.infoSlotWidth : 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(TranceSpacing.list)
        .frame(height: LibraryShelfMetrics.audioCardHeight)
        .liminalSurface()
    }
}

// MARK: - Built-in Sessions Shelf

/// Horizontal shelf of bundled light-session cards; tapping plays the session.
struct LibraryBuiltInSessionShelf: View {
    let sessions: [LightSession]
    let onPlay: (LightSession) -> Void

    var body: some View {
        CarouselRow(items: sessions, cardWidthFraction: LibraryShelfMetrics.cardWidthFraction) { session in
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
        VStack(alignment: .leading, spacing: TranceSpacing.inner) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.bwGamma.opacity(0.18))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.bwGamma)
                }

            Text(session.displayName)
                .font(TranceTypography.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            Text(session.durationFormatted)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(TranceSpacing.list)
        .frame(height: LibraryShelfMetrics.audioCardHeight)
        .liminalSurface()
    }
}

// MARK: - Artists Shelf

/// Horizontal shelf of creator cards; tapping opens that artist's sessions.
struct LibraryArtistShelf: View {
    let artists: [LibraryArtist]
    let onOpen: (LibraryArtist) -> Void

    var body: some View {
        CarouselRow(items: artists, cardWidthFraction: LibraryShelfMetrics.cardWidthFraction) { artist in
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
        HStack(spacing: TranceSpacing.inner) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.roseDeep.opacity(0.18))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "music.mic")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.roseDeep)
                }

            // No chevron: at this width it stole the room full creator names need,
            // and the card's only action is already to open that creator.
            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                Text(artist.name)
                    .font(TranceTypography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(artist.fileCount) sessions")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TranceSpacing.list)
        .frame(height: LibraryShelfMetrics.artistCardHeight)
        .liminalSurface()
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

// MARK: - Playlist Result Row

/// Dense playlist row used in search results, where a 2-up artwork grid would
/// bury the handful of actual matches.
struct LibraryPlaylistResultRow: View {
    let playlist: Playlist
    let onPlay: () -> Void
    var onOpenInfo: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: TranceSpacing.inner) {
            playButton

            if let onOpenInfo {
                Button(action: onOpenInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.textLight)
                        .frame(width: 32, height: 32)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(playlist.name)")
            }
        }
    }

    private var playButton: some View {
        Button(action: onPlay) {
            HStack(spacing: TranceSpacing.list) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.roseGold.opacity(0.18))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.roseGold)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    // Two lines: several playlists here share a long prefix, and
                    // one truncated line makes them impossible to tell apart.
                    Text(playlist.name)
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(playlist.isEmpty
                         ? "Empty"
                         : "\(playlist.itemCount) tracks · \(playlist.totalDurationFormatted)")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 0)

                if playlist.isEmpty == false {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.roseGold)
                }
            }
            .padding(.vertical, TranceSpacing.inner)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(playlist.isEmpty)
    }
}
