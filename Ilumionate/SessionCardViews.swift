//
//  SessionCardViews.swift
//  Ilumionate
//
//  Reusable session card components used by the home featured carousel and
//  the Mind Machine sessions browser.
//

import SwiftUI

// MARK: - Featured Session Card (Home Carousel)

/// Large gradient card used in the horizontal home carousel.
struct FeaturedSessionCard: View {
    let session: LightSession
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Gradient background
                RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                    .fill(
                        LinearGradient(
                            colors: session.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        // Subtle noise texture overlay
                        RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                            .fill(.white.opacity(0.05))
                    )

                // Content
                VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                    // Category badge
                    HStack(spacing: 5) {
                        Image(systemName: session.categoryIcon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(session.brainwaveCategory.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, TranceSpacing.inner)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.18))
                    .clipShape(Capsule())

                    Spacer()

                    // Session name
                    Text(session.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Tagline
                    Text(session.tagline)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)

                    // Duration + play row
                    HStack {
                        Label(session.durationFormatted, systemImage: "clock")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))

                        Spacer()

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                    }
                }
                .padding(TranceSpacing.list)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 195, height: 160)
    }
}

// MARK: - Compact Session Row (Mind Machine / Lists)

/// Compact row card for the Mind Machine sessions browser.
struct CompactSessionRow: View {
    let session: LightSession
    let index: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TranceSpacing.list) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                        .fill(
                            LinearGradient(
                                colors: session.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    Image(systemName: session.categoryIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.displayName)
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: TranceSpacing.small) {
                        Text(session.tagline)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)

                        Text("·")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textLight)

                        Text(session.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(session.accentColor)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Count Badge

struct SessionCountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count) session\(count == 1 ? "" : "s")")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, TranceSpacing.inner)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
