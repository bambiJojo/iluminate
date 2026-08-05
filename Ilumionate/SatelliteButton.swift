//
//  SatelliteButton.swift
//  Ilumionate
//
//  The shared "orbital" control grammar: icon-only satellite buttons, the
//  solid-accent circular action button, and ghost ring buttons used by both
//  the unified player and the Text Trance reader.
//

import SwiftUI

/// Icon-only ghost-circle control for satellite rows.
struct SatelliteButton: View {
    let label: String
    let systemImage: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.subheadline)
            .foregroundStyle(active ? Color.roseGold : Color.textSecondary)
            .frame(width: 36, height: 36)
            .background(active ? Color.roseGold.opacity(0.12) : Color.glassFill)
            .overlay(Circle().strokeBorder(
                active ? Color.roseGold.opacity(0.5) : Color.glassBorder, lineWidth: 1))
            .clipShape(.circle)
            // Keep the 36pt visual but meet the 44pt minimum touch target.
            .frame(width: 44, height: 44)
            .contentShape(.circle)
            .buttonStyle(PlayerButtonStyle())
    }
}

/// Solid accent circular action button — play/pause in the player, pause/resume
/// in the reader. Clean filled circle + subtle glow (no heavy gradient).
struct ClusterPlayButton: View {
    let label: String
    let systemImage: String
    var size: CGFloat = 64
    /// Overrides the glyph size when the button is scaled up. Nil keeps the
    /// original `.title2`, so existing callers render exactly as before.
    var symbolSize: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(symbolSize.map { .system(size: $0, weight: .semibold) } ?? .title2)
            .foregroundStyle(Color.bgDeep)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.roseGold))
            .shadow(color: Color.roseGold.opacity(0.35), radius: 14)
            .buttonStyle(PlayPauseButtonStyle())
    }
}

/// Ghost ring button flanking the action button (skip, end, settings).
struct ClusterGhostButton: View {
    let label: String
    let systemImage: String
    var size: CGFloat = 44
    /// Overrides the glyph size when the button is scaled up. Nil keeps the
    /// original `.body`, so existing callers render exactly as before.
    var symbolSize: CGFloat?
    /// Fills the ring with the glass surface used by control tiles, so a
    /// transport row can sit in the same visual family as a tile tray.
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(symbolSize.map { .system(size: $0, weight: .medium) } ?? .body)
            .foregroundStyle(Color.textSecondary)
            .frame(width: size, height: size)
            .background(Circle().fill(filled ? Color.glassFill : .clear))
            .overlay(Circle().strokeBorder(Color.glassBorder, lineWidth: 1))
            .contentShape(.circle)
            .buttonStyle(PlayerButtonStyle())
    }
}

/// Spring-bounce press effect for the solid action button.
/// (Moved from PlayerTransportSection.swift so the reader can share it.)
struct PlayPauseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}
