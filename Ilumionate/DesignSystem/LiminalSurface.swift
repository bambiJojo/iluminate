//
//  LiminalSurface.swift
//  Ilumionate
//
//  The Liminal glass surface: ultraThinMaterial over the void with a
//  hairline aurora border and an aurora GLOW (not a dark drop shadow).
//

import SwiftUI

// MARK: - Canonical Liminal Glass

/// The clip shape a Liminal glass surface is cut to.
///
/// Surfaces are either fully rounded capsules (the floating tab bar) or
/// rounded rectangles with an explicit corner radius (cards, the mini player).
enum LiminalGlassShape {
    case capsule
    case roundedRect(cornerRadius: CGFloat)

    /// Type-erased `Shape` used for the fill, clip, and stroke passes so a
    /// single recipe can serve both the capsule and rounded-rect cases.
    var shape: AnyShape {
        switch self {
        case .capsule:                       AnyShape(.capsule)
        case .roundedRect(let cornerRadius): AnyShape(.rect(cornerRadius: cornerRadius))
        }
    }
}

/// The ONE canonical Liminal "void-glass" treatment.
///
/// Layering (back to front): a tinted `bgSecondary` plate establishes the
/// dark void, `.ultraThinMaterial` sits in *front* of it so its blur stays
/// visible, a hairline aurora border traces the edge, and a centered
/// aurora-blue glow blooms outward (an atmospheric halo, not a dark drop
/// shadow). Every Liminal surface — cards, the tab bar, the mini player —
/// is expressed through this single modifier, parameterized only by clip
/// shape and tint strength.
struct LiminalGlassModifier: ViewModifier {
    var glassShape: LiminalGlassShape
    var tintOpacity: Double = 0.7
    var glow: Bool = true

    func body(content: Content) -> some View {
        let shape = glassShape.shape
        let surface = content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .background(shape.fill(Color.bgSecondary.opacity(tintOpacity)))
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(Color.glassBorder, lineWidth: 1)
            }

        // A `.shadow` with a clear colour still costs its offscreen pass, so the
        // glow-less variants have to skip the modifier rather than clear it.
        if glow {
            surface.shadow(color: Color.roseDeep.opacity(0.15), radius: 16, x: 0, y: 0)
        } else {
            surface
        }
    }
}

extension View {
    /// Applies the canonical Liminal glass treatment cut to `shape`.
    func liminalGlass(
        _ shape: LiminalGlassShape,
        tintOpacity: Double = 0.7,
        glow: Bool = true
    ) -> some View {
        modifier(LiminalGlassModifier(glassShape: shape, tintOpacity: tintOpacity, glow: glow))
    }

    /// Convenience for the common rounded-rectangle card surface.
    func liminalSurface(cornerRadius: CGFloat = TranceRadius.glassCard, glow: Bool = true) -> some View {
        liminalGlass(.roundedRect(cornerRadius: cornerRadius), glow: glow)
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
                    .foregroundStyle(.textLight)
            }
            content()
        }
        .padding(TranceSpacing.card)
        .liminalSurface()
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        VStack(spacing: TranceSpacing.cardMargin) {
            LiminalCard(label: "Tonight") {
                Text("Hypnagogic Drift · 30 min")
                    .font(TranceTypography.body)
                    .foregroundStyle(.textPrimary)
            }
            LiminalCard {
                Text("No label")
                    .font(TranceTypography.body)
                    .foregroundStyle(.textSecondary)
            }
        }
        .padding(TranceSpacing.screen)
    }
}
