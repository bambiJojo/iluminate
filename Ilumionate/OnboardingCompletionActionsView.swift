//
//  OnboardingCompletionActionsView.swift
//  Ilumionate
//

import SwiftUI

struct OnboardingCompletionActionsView: View {
    let canStartSession: Bool
    let onStartSession: () -> Void
    let onExploreApp: () -> Void

    var body: some View {
        VStack(spacing: TranceSpacing.list) {
            if canStartSession {
                Button(action: onStartSession) {
                    Label("Start your 3-min session", systemImage: "sparkles")
                        .font(TranceTypography.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.roseGold)
                        .clipShape(.capsule)
                        .shadow(color: Color.roseGold.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Begins the guided welcome session immediately")
            }

            Button(action: onExploreApp) {
                Text(canStartSession ? "Explore LumeSync instead" : "Explore LumeSync")
                    .font(TranceTypography.body.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Finishes onboarding and opens the Home screen")
        }
    }
}
