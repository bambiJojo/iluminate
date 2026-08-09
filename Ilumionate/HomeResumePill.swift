//
//  HomeResumePill.swift
//  Ilumionate
//
//  Pick up where you left off.
//
//  Subordinate to the doors on purpose: making resume the hero would quietly
//  bias every launch toward repeating the last session, which is the opposite
//  of letting someone find the part of the app they like.
//

import SwiftUI

struct HomeResumePill: View {
    let state: HomeResumeState
    let action: () -> Void

    private var remainingText: String {
        Duration.seconds(state.remaining).formatted(.time(pattern: .minuteSecond))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.roseGold)

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(state.title)
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text("\(remainingText) remaining")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 0)

                ProgressRingView(progress: state.progress)
            }
            .padding(TranceSpacing.card)
            .liminalGlass(.roundedRect(cornerRadius: TranceRadius.glassCard))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resume \(state.title)")
        .accessibilityValue("\(remainingText) remaining")
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        HomeResumePill(
            state: HomeResumeState(
                snapshot: PlaybackProgressSnapshot(
                    contentID: "preview",
                    kind: .session,
                    title: "Hypnagogic Drift",
                    progress: 0.42,
                    duration: 1800,
                    updatedAt: .now
                )
            )!,
            action: {}
        )
        .padding(TranceSpacing.screen)
    }
}
