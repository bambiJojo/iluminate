//
//  ProfileView.swift
//  Ilumionate
//
//  User profile with listening stats, weekly activity, and session history.
//

import SwiftUI

@MainActor
struct ProfileView: View {

    @Environment(\.dismiss) private var dismiss
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("profileGoal") private var profileGoal = ""
    @State private var showingSettings = false
    @State private var animateContent = false

    private let history = SessionHistoryManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TranceSpacing.content) {
                    avatarHeader
                    statsRow
                    weeklyActivityCard
                    recentSessionsCard
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.bottom, TranceSpacing.tabBarClearance)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.roseGold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        TranceHaptics.shared.light()
                        showingSettings = true
                    }
                    .foregroundStyle(Color.roseGold)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.large)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                animateContent = true
            }
        }
    }

    // MARK: - Avatar Header

    private var avatarHeader: some View {
        VStack(spacing: TranceSpacing.small) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.roseGold, .blush],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Text(profileInitial)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .shadow(color: .roseGold.opacity(0.35), radius: 16, x: 0, y: 8)

            if profileName.isEmpty {
                Text("Your Profile")
                    .font(TranceTypography.greetingAccent)
                    .foregroundStyle(Color.textPrimary)
            } else {
                Text(profileName)
                    .font(TranceTypography.greetingAccent)
                    .foregroundStyle(Color.textPrimary)
            }

            if !profileGoal.isEmpty {
                Text(profileGoal)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TranceSpacing.statusBar)
        .opacity(animateContent ? 1 : 0)
        .offset(y: animateContent ? 0 : 12)
    }

    private var profileInitial: String {
        profileName.first.map(String.init) ?? "?"
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: TranceSpacing.small) {
            statCard(
                value: history.totalSessionsCompleted.formatted(),
                label: "Completed",
                color: .roseGold
            )
            statCard(
                value: formatTotalTime(history.totalListeningTime),
                label: "Total Time",
                color: .bwAlpha
            )
            statCard(
                value: history.currentStreak.formatted(),
                label: "Day Streak",
                color: .bwTheta
            )
        }
        .opacity(animateContent ? 1 : 0)
        .offset(y: animateContent ? 0 : 16)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: animateContent)
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        GlassCard {
            VStack(spacing: TranceSpacing.micro) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Weekly Activity Card

    private var weeklyActivityCard: some View {
        GlassCard(label: "This Week") {
            VStack(alignment: .leading, spacing: TranceSpacing.small) {
                weeklyBarChart

                let count = history.thisWeekSessionCount
                Text("\(count) session\(count == 1 ? "" : "s") this week")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .opacity(animateContent ? 1 : 0)
        .offset(y: animateContent ? 0 : 16)
        .animation(.easeOut(duration: 0.5).delay(0.2), value: animateContent)
    }

    private var weeklyBarChart: some View {
        let activity = history.weeklyActivity()
        let maxCount = max(1, activity.max() ?? 1)
        let calendar = Calendar.current
        let today = Date()

        return HStack(alignment: .bottom, spacing: TranceSpacing.inner) {
            ForEach(0..<activity.count, id: \.self) { index in
                let count = activity[index]
                let daysAgo = 6 - index
                let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
                let isToday = daysAgo == 0
                let dayLabel = String(date.formatted(.dateTime.weekday(.abbreviated)).prefix(2))
                let barHeight = CGFloat(count) / CGFloat(maxCount) * 60 + 4

                VStack(spacing: TranceSpacing.micro) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            isToday
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [.roseGold, .roseDeep],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                : AnyShapeStyle(Color.roseGold.opacity(count > 0 ? 0.55 : 0.15))
                        )
                        .frame(height: animateContent ? barHeight : 4)
                        .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.06 + 0.3), value: animateContent)

                    Text(dayLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isToday ? Color.roseGold : Color.textLight)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 80, alignment: .bottom)
    }

    // MARK: - Recent Sessions Card

    private var recentSessionsCard: some View {
        GlassCard(label: "Recent Sessions") {
            if history.entries.isEmpty {
                emptyHistoryPlaceholder
            } else {
                VStack(spacing: TranceSpacing.list) {
                    let recent = Array(history.entries.prefix(10))
                    ForEach(recent.indices, id: \.self) { index in
                        sessionRow(recent[index])
                        if index < recent.count - 1 {
                            Divider()
                                .background(Color.glassBorder)
                        }
                    }
                }
            }
        }
        .opacity(animateContent ? 1 : 0)
        .offset(y: animateContent ? 0 : 16)
        .animation(.easeOut(duration: 0.5).delay(0.3), value: animateContent)
    }

    private var emptyHistoryPlaceholder: some View {
        VStack(spacing: TranceSpacing.small) {
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundStyle(Color.roseGold.opacity(0.4))
            Text("No sessions yet")
                .font(TranceTypography.body)
                .foregroundStyle(Color.textSecondary)
            Text("Play a session to start tracking your progress")
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textLight)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TranceSpacing.content)
    }

    private func sessionRow(_ entry: SessionHistoryEntry) -> some View {
        HStack(spacing: TranceSpacing.list) {
            Circle()
                .fill(categoryColor(for: entry.category))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.sessionName)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatListenTime(entry.durationListened))
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                if entry.completed {
                    Text("Completed")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.roseGold)
                }
            }
        }
    }

    // MARK: - Helpers

    private func categoryColor(for category: String) -> Color {
        switch category {
        case "Sleep":  return .bwDelta
        case "Relax":  return .bwTheta
        case "Focus":  return .bwAlpha
        case "Energy": return .bwBeta
        case "Trance": return .bwGamma
        default:       return .roseGold
        }
    }

    private func formatTotalTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatListenTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes > 0 { return "\(minutes)m" }
        return "\(Int(interval))s"
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
}
