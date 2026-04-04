//
//  ProfileSettingsView+Helpers.swift
//  Ilumionate
//
//  Shared helper views, profile editor sheet, about sheet, and utility
//  methods for ProfileSettingsView.
//

import SwiftUI

extension ProfileSettingsView {

    // MARK: - Reusable Setting Rows

    func settingsToggle(
        title: String,
        binding: Binding<Bool>,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title)
                .font(TranceTypography.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Toggle("", isOn: binding)
                .toggleStyle(RoseToggleStyle())
                .labelsHidden()
        }
    }

    func settingsSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: (Double) -> String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: TranceSpacing.micro) {
            HStack {
                Text(title)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            CustomSlider(
                value: value,
                range: range,
                trackColor: .glassBorder,
                thumbColor: color,
                activeColor: color
            )
        }
    }

    func settingsButton(
        title: String,
        icon: String,
        color: Color = .textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(title)
                    .font(TranceTypography.body)
                    .foregroundStyle(color == .textSecondary ? Color.textPrimary : color)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textLight)
            }
        }
        .buttonStyle(.plain)
    }

    func analysisPickerRow<T: CaseIterable & Hashable & RawRepresentable>(
        label: String,
        description: String,
        selection: Binding<T>
    ) -> some View where T.AllCases: RandomAccessCollection, T.RawValue == String {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                Text(description)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Picker(label, selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { value in
                    Text(value.rawValue.capitalized).tag(value)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.roseGold)
            .labelsHidden()
        }
    }

    // MARK: - Stat Card

    func statCard(value: String, label: String, color: Color) -> some View {
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

    // MARK: - Weekly Bar Chart

    var weeklyBarChart: some View {
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
                let dayLabel = String(
                    date.formatted(.dateTime.weekday(.abbreviated)).prefix(2)
                )
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
                                : AnyShapeStyle(
                                    Color.roseGold.opacity(count > 0 ? 0.55 : 0.15)
                                )
                        )
                        .frame(height: animateContent ? barHeight : 4)
                        .animation(
                            .easeOut(duration: 0.4).delay(Double(index) * 0.06 + 0.3),
                            value: animateContent
                        )

                    Text(dayLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isToday ? Color.roseGold : Color.textLight)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 80, alignment: .bottom)
    }

    // MARK: - Session Row

    func sessionRow(_ entry: SessionHistoryEntry) -> some View {
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

    // MARK: - Empty History

    var emptyHistoryPlaceholder: some View {
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

    // MARK: - Profile Editor Sheet

    var profileEditor: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                VStack(spacing: TranceSpacing.cardMargin) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.roseGold, .bwTheta],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 90, height: 90)

                        let preview: String = {
                            let words = draftName.split(separator: " ").prefix(2)
                            let result = words.map {
                                String($0.prefix(1)).uppercased()
                            }.joined()
                            return result.isEmpty ? "?" : result
                        }()
                        Text(preview)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, TranceSpacing.content)

                    GlassCard(label: "Your Info") {
                        VStack(spacing: TranceSpacing.list) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.roseGold)
                                    .frame(width: 24)
                                TextField("Name", text: $draftName)
                                    .font(TranceTypography.body)
                                    .foregroundStyle(Color.textPrimary)
                            }
                            Divider().background(Color.glassBorder)
                            HStack(alignment: .top) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(Color.roseGold)
                                    .frame(width: 24)
                                    .padding(.top, 2)
                                TextField(
                                    "Wellness goal (e.g. reduce anxiety)",
                                    text: $draftGoal,
                                    axis: .vertical
                                )
                                .font(TranceTypography.body)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(3)
                            }
                        }
                    }
                    .padding(.horizontal, TranceSpacing.screen)

                    Spacer()
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditingProfile = false }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        TranceHaptics.shared.medium()
                        profileName = draftName
                        profileGoal = draftGoal
                        isEditingProfile = false
                    }
                    .foregroundStyle(Color.roseGold)
                    .bold()
                }
            }
        }
    }

    // MARK: - About Sheet

    var aboutSheet: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: TranceSpacing.content) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [.roseGold, .bwTheta],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 90, height: 90)
                            Image(systemName: "waveform.and.magnifyingglass")
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, TranceSpacing.content)

                        Text("LumeSync")
                            .font(TranceTypography.screenTitle)
                            .foregroundStyle(Color.textPrimary)

                        Text("v\(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textLight)

                        GlassCard(label: "About") {
                            Text(
                                "LumeSync is a personal hypnosis audio player and mind machine " +
                                "designed to help you achieve deep relaxation and transformative " +
                                "trance states using light and sound. Created with love for " +
                                "wellness explorers."
                            )
                            .font(TranceTypography.body)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, TranceSpacing.screen)
                    }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showAbout = false }
                        .foregroundStyle(Color.roseGold)
                }
            }
        }
    }

    // MARK: - Utility Methods

    func categoryColor(for category: String) -> Color {
        switch category {
        case "Sleep":  .bwDelta
        case "Relax":  .bwTheta
        case "Focus":  .bwAlpha
        case "Energy": .bwBeta
        case "Trance": .bwGamma
        default:       .roseGold
        }
    }

    func formatTotalTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    func formatListenTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes > 0 { return "\(minutes)m" }
        return "\(Int(interval))s"
    }

    func exportSessionData() {
        do {
            let exportURL = try AppSettingsManager.exportSnapshot()
            presentShareSheet(items: [exportURL])
        } catch {
            print("Failed to export settings snapshot: \(error)")
        }
    }

    func clearAllData() {
        do {
            try AppSettingsManager.clearAllData()
            showClearDataDone = true
        } catch {
            print("Failed to clear all app data: \(error)")
        }
    }

    func resetPreferences() {
        AppSettingsManager.resetPreferences()
    }

    private func presentShareSheet(items: [Any]) {
        let activityVC = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootVC = windowScene.windows.first?.rootViewController
        else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }
        topVC.present(activityVC, animated: true)
    }
}
