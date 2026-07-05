//
//  HomeStreakPill.swift
//  Ilumionate
//
//  Momentum indicator for the Home dashboard. Surfaces the listening streak
//  the app already computes (goal-gradient effect: never show a blank zero —
//  the pill only appears once the user has real momentum to protect).
//

import SwiftUI

struct HomeStreakPill: View {
    @AppStorage("listeningHistoryEnabled") private var historyEnabled = true

    private let history = SessionHistoryManager.shared

    var body: some View {
        if historyEnabled, hasMomentum {
            HStack(spacing: TranceSpacing.inner) {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.roseGold, .warmAccent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(TranceTypography.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(TranceTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                weekTrack
            }
            .padding(.horizontal, TranceSpacing.content)
            .padding(.vertical, TranceSpacing.inner)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: TranceRadius.glassCard))
            .overlay(
                RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                    .stroke(Color.roseGold.opacity(0.25), lineWidth: 1)
            )
        }
    }

    // MARK: - Content

    private var hasMomentum: Bool {
        history.currentStreak >= 1
            || history.streakAtRisk >= 1
            || history.thisWeekSessionCount >= 1
    }

    /// True when a real streak (ending yesterday) will break unless the user
    /// listens today — the moment loss aversion has the most to work with.
    private var isAtRisk: Bool {
        history.streakAtRisk >= 1
    }

    private var headline: String {
        if isAtRisk {
            return "Keep your \(history.streakAtRisk)-day streak"
        }
        let streak = history.currentStreak
        if streak >= 1 {
            return "\(streak)-day streak"
        }
        return "You're getting started"
    }

    private var subtitle: String {
        if isAtRisk {
            return "One session today keeps it alive"
        }
        let count = history.thisWeekSessionCount
        let noun = count == 1 ? "session" : "sessions"
        return "\(count) \(noun) this week"
    }

    /// Seven dots, one per day, brightest for days with a completed session.
    private var weekTrack: some View {
        HStack(spacing: 4) {
            ForEach(history.weeklyActivity().enumerated(), id: \.offset) { _, count in
                Circle()
                    .fill(count > 0 ? Color.roseGold : Color.textGhost.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
