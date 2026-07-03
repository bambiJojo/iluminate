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
            .buttonStyle(PlayerButtonStyle())
    }
}

/// Solid accent circular action button — play/pause in the player, pause/resume
/// in the reader. Clean filled circle + subtle glow (no heavy gradient).
struct ClusterPlayButton: View {
    let label: String
    let systemImage: String
    var size: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(Color.voidDeep)
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
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.body)
            .foregroundStyle(Color.textSecondary)
            .frame(width: size, height: size)
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
