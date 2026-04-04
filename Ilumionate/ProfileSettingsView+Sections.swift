//
//  ProfileSettingsView+Sections.swift
//  Ilumionate
//
//  All content sections for the unified ProfileSettingsView.
//

import SwiftUI
import StoreKit

extension ProfileSettingsView {

    // MARK: - Avatar Header

    var avatarHeader: some View {
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

            Button("Edit Profile", systemImage: "pencil.circle") {
                TranceHaptics.shared.light()
                draftName = profileName
                draftGoal = profileGoal
                isEditingProfile = true
            }
            .font(TranceTypography.caption)
            .foregroundStyle(Color.roseGold)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TranceSpacing.small)
        .opacity(animateContent ? 1 : 0)
        .offset(y: animateContent ? 0 : 12)
    }

    var profileInitial: String {
        profileName.first.map(String.init) ?? "?"
    }

    // MARK: - Stats Row

    var statsRow: some View {
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

    // MARK: - Weekly Activity

    var weeklyActivityCard: some View {
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

    // MARK: - Appearance

    var appearanceSection: some View {
        GlassCard(label: "Appearance") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.roseGold)
                    Text("Color Mode")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                }
                Picker("Appearance", selection: appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.roseGold)
            }
        }
    }

    // MARK: - Core Settings

    var coreSettingsSection: some View {
        GlassCard(label: "Core Settings") {
            VStack(spacing: TranceSpacing.list) {
                settingsToggle(
                    title: "Haptic Feedback",
                    binding: $hapticFeedbackEnabled,
                    icon: "iphone.radiowaves.left.and.right",
                    color: .roseGold
                )
                settingsToggle(
                    title: "Keep Screen Awake During Sessions",
                    binding: $autoLockEnabled,
                    icon: "lock.open.display",
                    color: .bwTheta
                )
            }
        }
    }

    // MARK: - Session Defaults

    var sessionDefaultsSection: some View {
        GlassCard(label: "Session Defaults") {
            VStack(spacing: TranceSpacing.list) {
                settingsSlider(
                    title: "Frequency Scale",
                    value: $userFrequencyMultiplier,
                    range: 0.5...2.0,
                    format: {
                        $0.formatted(.number.precision(.fractionLength(1))) + "×"
                    },
                    color: .roseGold
                )
                HStack(spacing: TranceSpacing.list) {
                    Image(systemName: "timer")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.bwAlpha)
                        .frame(width: 24)
                    Text("Countdown Timer")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Picker("Countdown", selection: $countdownDuration) {
                        Text("3s").tag(3)
                        Text("7s").tag(7)
                        Text("10s").tag(10)
                    }
                    .tint(.textSecondary)
                }
            }
        }
    }

    // MARK: - Light Sync Preferences (from Analyzer)

    var lightSyncPreferencesSection: some View {
        GlassCard(label: "Light Sync AI") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(Color.roseGold)
                    Text("AI Analysis")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                }

                Picker("Content Hint", selection: $prefs.contentHint) {
                    ForEach(ContentHint.allCases, id: \.self) { hint in
                        Label(hint.displayName, systemImage: hint.sfSymbol).tag(hint)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.roseGold)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Content Hint")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                    Text("Tells the AI what kind of content to expect")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text("Custom Instructions")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                    Text("Optional guidance appended to the AI prompt for future analyses.")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)

                    TextField(
                        "Example: prefer warmer palettes and slower ramps for hypnosis content.",
                        text: $prefs.customInstructions,
                        axis: .vertical
                    )
                    .lineLimit(3...5)
                    .textFieldStyle(.roundedBorder)
                }

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.subheadline)
                        .foregroundStyle(Color.roseGold)
                    Text("Session Generation")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Intensity")
                            .font(TranceTypography.body)
                            .foregroundStyle(Color.textPrimary)
                        Text("Brightness and strength of light patterns")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Text("\(Int(prefs.intensityMultiplier * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.roseGold)
                        .frame(width: 40, alignment: .trailing)
                }
                Slider(value: $prefs.intensityMultiplier, in: 0.3...1.5)
                    .tint(Color.roseGold)

                Divider()

                analysisPickerRow(
                    label: "Frequency Range",
                    description: "Hz range for light moments",
                    selection: $prefs.frequencyProfile
                )
                Divider()
                analysisPickerRow(
                    label: "Transitions",
                    description: "How smoothly patterns change",
                    selection: $prefs.transitionStyle
                )
                Divider()
                analysisPickerRow(
                    label: "Color Temperature",
                    description: "Warmth or coolness of light",
                    selection: $prefs.colorTempMode
                )
                Divider()

                Toggle(isOn: $prefs.bilateralMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bilateral Mode")
                            .font(TranceTypography.body)
                            .foregroundStyle(Color.textPrimary)
                        Text("Alternate left/right visual field stimulation")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .tint(Color.roseGold)

                Divider()

                Toggle(isOn: $prefs.autoAnalyzeOnImport) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Analyze on Import")
                            .font(TranceTypography.body)
                            .foregroundStyle(Color.textPrimary)
                        Text("Queue new files for AI analysis automatically")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .tint(Color.roseGold)
            }
        }
    }

    // MARK: - Privacy & Data

    var privacyDataSection: some View {
        GlassCard(label: "Privacy & Data") {
            VStack(spacing: TranceSpacing.list) {
                settingsToggle(
                    title: "Track Session History",
                    binding: $listeningHistoryEnabled,
                    icon: "clock.badge.checkmark",
                    color: .bwAlpha
                )
                settingsButton(
                    title: "Export Session Data",
                    icon: "square.and.arrow.up.circle"
                ) {
                    TranceHaptics.shared.light()
                    exportSessionData()
                }
                settingsButton(
                    title: "Clear All Data",
                    icon: "trash.circle",
                    color: .roseDeep
                ) {
                    TranceHaptics.shared.heavy()
                    showClearDataAlert = true
                }
            }
        }
    }

    // MARK: - Recent Sessions

    var recentSessionsCard: some View {
        GlassCard(label: "Recent Sessions") {
            if history.entries.isEmpty {
                emptyHistoryPlaceholder
            } else {
                VStack(spacing: TranceSpacing.list) {
                    let recent = Array(history.entries.prefix(10))
                    ForEach(recent.indices, id: \.self) { index in
                        sessionRow(recent[index])
                        if index < recent.count - 1 {
                            Divider().background(Color.glassBorder)
                        }
                    }
                }
            }
        }
        .opacity(animateContent ? 1 : 0)
        .offset(y: animateContent ? 0 : 16)
        .animation(.easeOut(duration: 0.5).delay(0.3), value: animateContent)
    }

    // MARK: - Support & About

    var supportAboutSection: some View {
        GlassCard(label: "Support") {
            VStack(spacing: TranceSpacing.list) {
                settingsButton(
                    title: "Help & Support",
                    icon: "questionmark.circle"
                ) {
                    TranceHaptics.shared.light()
                    if let url = URL(string: "mailto:support@ilumionate.app") {
                        openURL(url)
                    }
                }
                settingsButton(title: "Rate on App Store", icon: "star.circle") {
                    TranceHaptics.shared.light()
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        SKStoreReviewController.requestReview(in: scene)
                    }
                }
                settingsButton(title: "About LumeSync", icon: "heart.circle") {
                    TranceHaptics.shared.light()
                    showAbout = true
                }
                // Hidden dev toggle — tap 5× on the last row
                Color.clear
                    .frame(height: 1)
                    .onTapGesture(count: 5) {
                        showDeveloperOptions.toggle()
                        TranceHaptics.shared.heavy()
                    }
            }
        }
    }

    // MARK: - Developer Options

    var developerOptionsSection: some View {
        GlassCard(label: "Developer Settings") {
            VStack(spacing: TranceSpacing.list) {
                settingsButton(
                    title: "Print Engine Diagnostics",
                    icon: "cpu",
                    color: .roseDeep
                ) {
                    TranceHaptics.shared.light()
                    print("=== ENGINE DIAGNOSTICS ===")
                    print("Profile: \(profileName) | Goal: \(profileGoal)")
                    print("Haptics: \(hapticFeedbackEnabled) | Keep Awake: \(autoLockEnabled)")
                    print("Freq Scale: \(userFrequencyMultiplier) | Countdown: \(countdownDuration)")
                    print("History: \(listeningHistoryEnabled)")
                    print("AI Prefs: \(prefs.snapshot)")
                    print("==========================")
                }
                settingsButton(
                    title: "Reset Preferences",
                    icon: "arrow.clockwise.circle",
                    color: .roseDeep
                ) {
                    TranceHaptics.shared.heavy()
                    resetPreferences()
                }
                settingsButton(
                    title: "Reset Onboarding",
                    icon: "arrow.uturn.backward.circle",
                    color: .roseDeep
                ) {
                    TranceHaptics.shared.heavy()
                    UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
                }
            }
        }
    }
}
