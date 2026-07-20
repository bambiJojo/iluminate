//
//  ReaderQuickStartCard.swift
//  Ilumionate
//

import SwiftUI

struct ReaderQuickStartCard: View {
    let plan: ReaderQuickStartPlan
    let onStart: (ReaderQuickStartPlan) -> Void

    var body: some View {
        Button {
            TranceHaptics.shared.medium()
            onStart(plan)
        } label: {
            LiminalCard {
                HStack(spacing: TranceSpacing.content) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(plan.script.theme.accent.opacity(0.18))
                        .frame(width: 58, height: 58)
                        .overlay {
                            Image(systemName: plan.startType == .resumed
                                  ? "play.circle.fill"
                                  : "text.line.first.and.arrowtriangle.forward")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(plan.script.theme.accent)
                        }

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(plan.startType == .resumed ? "Continue now" : "Start reading now")
                            .font(TranceTypography.caption.weight(.semibold))
                            .foregroundStyle(Color.roseGold)

                        Text(plan.script.title)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        Text(plan.startType == .resumed
                             ? "Pick up where you stopped — no setup needed."
                             : "Use your saved reading preferences — no setup needed.")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.bgDeep)
                        .frame(width: 40, height: 40)
                        .background(Color.roseGold, in: .circle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(plan.startType == .resumed ? "Continue" : "Start") \(plan.script.title)"
        )
        .accessibilityHint("Begins reading immediately with saved preferences")
    }
}
