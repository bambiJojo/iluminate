//
//  PlaylistArtworkStyle.swift
//  Ilumionate
//
//  Selectable artwork for a playlist: a trance/hypnosis motif plus a colorway.
//  Everything is drawn in code, so artwork stays crisp at any size and adapts
//  to light/dark automatically via the semantic palette.
//

import SwiftUI

/// The drawn motif behind a playlist's artwork.
enum PlaylistArtworkMotif: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Derives a gradient mosaic from the playlist's content types.
    case auto
    case spiral
    case rings
    case pendulum
    case waves

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .spiral: return "Spiral"
        case .rings: return "Ripple"
        case .pendulum: return "Pendulum"
        case .waves: return "Drift"
        }
    }
}

/// Colorway applied to a motif. Values resolve through the semantic palette so
/// each one has a light-mode and dark-mode form.
enum PlaylistArtworkPalette: String, Codable, CaseIterable, Identifiable, Sendable {
    case aurora
    case rose
    case ember
    case abyss

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aurora: return "Aurora"
        case .rose: return "Rose"
        case .ember: return "Ember"
        case .abyss: return "Abyss"
        }
    }

    /// Ink colors for the motif's strokes, ordered along the gradient.
    var colors: [Color] {
        switch self {
        case .aurora: return [.roseGold, .roseDeep, .lavender]
        case .rose: return [.blush, .lavender, .roseDeep]
        case .ember: return [.warmAccent, .blush, .lavender]
        case .abyss: return [.lavender, .roseDeep, .roseGold]
        }
    }

    var inkGradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Soft wash behind the motif — a tint of the colorway over the card surface.
    var backdrop: LinearGradient {
        LinearGradient(
            colors: [colors[0].opacity(0.22), colors[min(1, colors.count - 1)].opacity(0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Color used for shadows/glows cast by artwork in this colorway.
    var glow: Color { colors[0] }
}

/// A playlist's chosen artwork. `.automatic` keeps the legacy content-derived mosaic.
struct PlaylistArtworkStyle: Codable, Equatable, Sendable, Identifiable {
    var motif: PlaylistArtworkMotif
    var palette: PlaylistArtworkPalette

    init(motif: PlaylistArtworkMotif = .auto, palette: PlaylistArtworkPalette = .aurora) {
        self.motif = motif
        self.palette = palette
    }

    static let automatic = PlaylistArtworkStyle()

    var id: String { "\(motif.rawValue)-\(palette.rawValue)" }

    var displayName: String {
        motif == .auto ? motif.displayName : "\(motif.displayName) · \(palette.displayName)"
    }

    /// Everything the picker offers: Auto first, then every motif in every colorway.
    static var gallery: [PlaylistArtworkStyle] {
        let motifs = PlaylistArtworkMotif.allCases.filter { $0 != .auto }
        return [.automatic] + motifs.flatMap { motif in
            PlaylistArtworkPalette.allCases.map {
                PlaylistArtworkStyle(motif: motif, palette: $0)
            }
        }
    }
}
