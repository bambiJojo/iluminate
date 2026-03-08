//
//  CTAButton.swift
//  Ilumionate
//
//  Call-to-action button with gradient and press animations
//

import SwiftUI

struct CTAButton: View {
    let title: String
    let gradient: [Color]
    let action: () -> Void

    init(_ title: String,
         gradient: [Color] = [.roseGold, .roseDeep],
         action: @escaping () -> Void) {
        self.title = title
        self.gradient = gradient
        self.action = action
    }

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            TranceHaptics.shared.medium()
            action()
        }) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, TranceSpacing.card)
                .background(
                    LinearGradient(colors: gradient,
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                .shadow(
                    color: TranceShadow.button.color,
                    radius: TranceShadow.button.radius,
                    x: TranceShadow.button.x,
                    y: TranceShadow.button.y
                )
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .offset(y: isPressed ? 2 : 0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.15)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: TranceSpacing.cardMargin) {
        CTAButton("Start Session") {
            print("Start Session tapped")
        }

        CTAButton("Generate Light Script ✦",
                  gradient: [.phaseDeepener, .roseGold]) {
            print("Generate tapped")
        }

        CTAButton("Continue",
                  gradient: [.phaseInduction, .phaseDeepener]) {
            print("Continue tapped")
        }
    }
    .padding(TranceSpacing.screen)
    .background(Color.bgPrimary)
}