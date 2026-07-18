//
//  GlowButton.swift
//  Ilumionate
//
//  Liminal call-to-action button. Press = scale + glow bloom (never opacity dim).
//

import SwiftUI

struct GlowButton: View {
    enum Kind { case primary, secondary }

    let title: String
    var systemImage: String? = nil
    var kind: Kind = .primary
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            TranceHaptics.shared.medium()
            action()
        } label: {
            label
                .frame(maxWidth: .infinity)
                .padding(.vertical, TranceSpacing.card)
                .background(background)
                .clipShape(.rect(cornerRadius: TranceRadius.button))
                .overlay(
                    RoundedRectangle(cornerRadius: TranceRadius.button)
                        .stroke(kind == .secondary ? Color.glassBorder : .clear, lineWidth: 1)
                )
                .shadow(color: glowColor.opacity(isPressed ? 0.55 : 0.3),
                        radius: isPressed ? 26 : 18, x: 0, y: 6)
                .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(LiminalMotion.touch) { isPressed = pressing }
        }, perform: {})
    }

    @ViewBuilder
    private var label: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.headline)
        .foregroundStyle(kind == .primary ? Color.bgDeep : Color.textPrimary)
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            LinearGradient(colors: [.roseGold, .roseDeep],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .secondary:
            Color.bgSecondary.opacity(0.6)
        }
    }

    private var glowColor: Color { kind == .primary ? .roseGold : .roseDeep }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        VStack(spacing: TranceSpacing.cardMargin) {
            GlowButton(title: "Begin", systemImage: "play.fill") {}
            GlowButton(title: "Browse Library", kind: .secondary) {}
        }
        .padding(TranceSpacing.screen)
    }
}
