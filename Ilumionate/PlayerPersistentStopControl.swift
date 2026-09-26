//
//  PlayerPersistentStopControl.swift
//  Ilumionate
//
//  One-tap escape hatch that remains visible after the player controls hide.
//  After a quiet spell it shrinks to an icon so it does not sit over the
//  session like a banner, but it stays on screen with a full touch target.
//

import SwiftUI

struct PlayerPersistentStopControl: View {
    let revealProgress: Double
    let showsSwipeHint: Bool
    let isCompact: Bool
    let onStop: () -> Void

    /// Apple's minimum comfortable touch target. The compact icon keeps it,
    /// so shrinking the button never makes the exit harder to hit.
    private static let minimumTouchTarget: CGFloat = 44

    var body: some View {
        VStack(spacing: TranceSpacing.small) {
            if showsSwipeHint {
                // Backed like the button: white text alone vanished on a
                // bright flash field, which is exactly when it is needed.
                Text("Swipe up to show controls")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, TranceSpacing.small)
                    .padding(.vertical, TranceSpacing.micro)
                    .background(.black.opacity(0.45), in: .capsule)
                    .opacity(1 - revealProgress)
                    .transition(.opacity)
            }

            Button(action: onStop) {
                // Styling lives inside the label so the whole capsule or
                // circle takes the tap, not just the text and glyph.
                if isCompact {
                    Image(systemName: "stop.fill")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: Self.minimumTouchTarget, height: Self.minimumTouchTarget)
                        .background(.black.opacity(0.45), in: .circle)
                        .overlay {
                            Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
                        }
                        .contentShape(.circle)
                } else {
                    Label("Stop session", systemImage: "stop.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, TranceSpacing.content)
                        .frame(minHeight: Self.minimumTouchTarget)
                        .background(.black.opacity(0.68), in: .capsule)
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        }
                        .contentShape(.capsule)
                }
            }
            .buttonStyle(.plain)
            // Same name in both forms, so VoiceOver never sees a nameless glyph.
            .accessibilityLabel("Stop session")
            .accessibilityHint("Ends the session immediately")
        }
        .padding(.bottom, TranceSpacing.statusBar)
    }
}

#Preview {
    ZStack {
        Color.pink
        PlayerPersistentStopControl(revealProgress: 0, showsSwipeHint: true, isCompact: false, onStop: {})
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
    .ignoresSafeArea()
}
