//
//  GlassCard.swift
//  Ilumionate
//
//  Primary container component with glass morphism effect
//

import SwiftUI

struct GlassCard<Content: View>: View {
    let label: String?       // uppercase label, nil to hide
    @ViewBuilder let content: () -> Content

    init(label: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.small) {
            if let label {
                Text(label)
                    .font(TranceTypography.cardLabel)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundColor(.textLight)
            }
            content()
        }
        .padding(TranceSpacing.card)
        .modifier(GlassBackground())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: TranceSpacing.cardMargin) {
        GlassCard(label: "Continue Session") {
            HStack(spacing: TranceSpacing.list) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.roseGold.opacity(0.3))
                    .frame(width: 120, height: 30)

                VStack(alignment: .leading) {
                    Text("Deep Sleep Induction")
                        .font(TranceTypography.body)
                        .foregroundColor(.textPrimary)
                    Text("18:24 remaining")
                        .font(TranceTypography.caption)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                Circle()
                    .stroke(Color.glassBorder, lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text("60%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.roseGold)
                    )
            }
        }

        GlassCard {
            Text("Card without label")
                .font(TranceTypography.body)
                .foregroundColor(.textPrimary)
        }
    }
    .padding(TranceSpacing.screen)
    .background(Color.bgPrimary)
}