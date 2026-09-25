//
//  PlayerPersistentStopControl.swift
//  Ilumionate
//
//  One-tap escape hatch that remains visible after the player controls hide.
//  After a quiet spell it fades to a resting glyph so it does not sit over
//  the session like a banner, but it stays on screen and tappable throughout.
//

import SwiftUI

struct PlayerPersistentStopControl: View {
    let revealProgress: Double
    let showsSwipeHint: Bool
    let isDimmed: Bool
    let onStop: () -> Void

    /// Faint enough to disappear into a session, still findable by touch.
    private static let dimmedOpacity = 0.22

    var body: some View {
        VStack(spacing: TranceSpacing.small) {
            if showsSwipeHint {
                Text("Swipe up to show controls")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.white.opacity(0.65 * (1 - revealProgress)))
            }

            Button("Stop session", systemImage: "stop.fill", action: onStop)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, TranceSpacing.content)
                .frame(minHeight: 44)
                .background(.black.opacity(0.68), in: .capsule)
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ends the session immediately")
        }
        .padding(.bottom, TranceSpacing.statusBar)
        // Opacity rather than removal: a dimmed button must still take the tap.
        .opacity(isDimmed ? Self.dimmedOpacity : 1)
    }
}

#Preview {
    ZStack {
        Color.pink
        PlayerPersistentStopControl(revealProgress: 0, showsSwipeHint: true, isDimmed: false, onStop: {})
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
    .ignoresSafeArea()
}
