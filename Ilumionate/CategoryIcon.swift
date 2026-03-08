//
//  CategoryIcon.swift
//  Ilumionate
//
//  Circular category icons with halo glow effects
//

import SwiftUI

struct CategoryIcon: View {
    let emoji: String
    let label: String
    let haloColor: Color

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            TranceHaptics.shared.selection()
        }) {
            VStack(spacing: TranceSpacing.icon) {
                Text(emoji)
                    .font(.system(size: 22))
                    .frame(width: 52, height: 52)
                    .background(Color.bgCard)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.glassBorder, lineWidth: 1))
                    .shadow(
                        color: haloColor.opacity(isPressed ? 0.5 : 0.3),
                        radius: isPressed ? 14 : 10
                    )
                    .scaleEffect(isPressed ? 1.1 : 1.0)

                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: TranceSpacing.content) {
        CategoryIcon(
            emoji: "🌙",
            label: "Sleep",
            haloColor: .bwDelta
        )

        CategoryIcon(
            emoji: "🎯",
            label: "Focus",
            haloColor: .bwAlpha
        )

        CategoryIcon(
            emoji: "⚡",
            label: "Energy",
            haloColor: .bwBeta
        )

        CategoryIcon(
            emoji: "🧘",
            label: "Relax",
            haloColor: .bwTheta
        )

        CategoryIcon(
            emoji: "🌀",
            label: "Trance",
            haloColor: .bwGamma
        )
    }
    .padding(TranceSpacing.screen)
    .background(Color.bgPrimary)
}