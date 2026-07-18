//
//  PlaylistArtwork.swift
//  Ilumionate
//
//  Shared generated artwork for playlists: derives the distinct content types
//  in a playlist and renders them as a 1/2/4-region aurora gradient mosaic.
//

import SwiftUI

enum PlaylistArtwork {

    /// Distinct, ordered content types for artwork generation.
    /// Drops nil / .unknown, deduplicates preserving first-seen order, caps at 4.
    static func distinctTypes(from types: [AudioContentType?]) -> [AudioContentType] {
        var seen = Set<AudioContentType>()
        var result: [AudioContentType] = []
        for case let type? in types where type != .unknown {
            if seen.insert(type).inserted {
                result.append(type)
                if result.count == 4 { break }
            }
        }
        return result
    }

    /// The color used for shadows/washes behind the artwork.
    static func dominantColor(for types: [AudioContentType]) -> Color {
        ContentTypeStyle.color(for: types.first)
    }

    static func gradient(for type: AudioContentType?) -> LinearGradient {
        let color = ContentTypeStyle.color(for: type)
        return LinearGradient(
            colors: [color, color.opacity(0.65)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

/// Gradient mosaic artwork for a playlist. Layout is constraint-based
/// (no GeometryReader/.position), so it can never overlap surrounding views.
struct PlaylistArtworkView: View {
    let types: [AudioContentType]
    var cornerRadius: CGFloat = TranceRadius.thumbnail
    var iconSize: CGFloat? = nil

    var body: some View {
        ZStack {
            switch types.count {
            case 0:
                PlaylistArtwork.gradient(for: nil)
                icon("music.note.list")
            case 1:
                PlaylistArtwork.gradient(for: types[0])
                icon(ContentTypeStyle.icon(for: types[0]))
            default:
                quadrants
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    // 2 types → 2 columns; 3-4 types → 2x2 grid (3rd type fills the bottom row).
    private var quadrants: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                PlaylistArtwork.gradient(for: types[0])
                PlaylistArtwork.gradient(for: types[1])
            }
            if types.count >= 3 {
                HStack(spacing: 0) {
                    PlaylistArtwork.gradient(for: types[2])
                    PlaylistArtwork.gradient(for: types.count >= 4 ? types[3] : types[2])
                }
            }
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: iconSize ?? 32, weight: .ultraLight))
            .foregroundStyle(.white.opacity(0.7))
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        VStack(spacing: TranceSpacing.card) {
            PlaylistArtworkView(types: [], cornerRadius: 24)
                .frame(width: 120, height: 120)
            HStack(spacing: TranceSpacing.card) {
                PlaylistArtworkView(types: [.hypnosis])
                    .frame(width: 80, height: 80)
                PlaylistArtworkView(types: [.hypnosis, .music])
                    .frame(width: 80, height: 80)
                PlaylistArtworkView(types: [.hypnosis, .music, .meditation, .asmr])
                    .frame(width: 80, height: 80)
            }
        }
    }
}
