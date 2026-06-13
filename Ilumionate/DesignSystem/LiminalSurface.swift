//
//  LiminalSurface.swift
//  Ilumionate
//
//  The Liminal glass surface: ultraThinMaterial over the void with a
//  hairline aurora border and an aurora GLOW (not a dark drop shadow).
//

import SwiftUI

/// Applies the Liminal glass treatment to any view.
struct LiminalSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat = TranceRadius.glassCard
    var glow: Bool = true

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.voidElevated.opacity(0.6))
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
            .shadow(color: glow ? Color.auroraBlue.opacity(0.12) : .clear,
                    radius: 18, x: 0, y: 0)
    }
}

extension View {
    func liminalSurface(cornerRadius: CGFloat = TranceRadius.glassCard, glow: Bool = true) -> some View {
        modifier(LiminalSurfaceModifier(cornerRadius: cornerRadius, glow: glow))
    }
}

/// A labeled glass card built on the Liminal surface — drop-in companion to GlassCard.
struct LiminalCard<Content: View>: View {
    let label: String?
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
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.textGhost)
            }
            content()
        }
        .padding(TranceSpacing.card)
        .liminalSurface()
    }
}

#Preview {
    ZStack {
        Color.voidPrimary.ignoresSafeArea()
        VStack(spacing: TranceSpacing.cardMargin) {
            LiminalCard(label: "Tonight") {
                Text("Hypnagogic Drift · 30 min")
                    .font(TranceTypography.body)
                    .foregroundStyle(.textBright)
            }
            LiminalCard {
                Text("No label")
                    .font(TranceTypography.body)
                    .foregroundStyle(.textDim)
            }
        }
        .padding(TranceSpacing.screen)
    }
}
