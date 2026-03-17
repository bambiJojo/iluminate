//
//  SettingsView+Sections.swift
//  LumeSync
//
//  All content sections and sheet views for SettingsView.
//

import SwiftUI

extension SettingsView {

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
                    title: "Session Lock",
                    binding: $autoLockEnabled,
                    icon: "lock.circle",
                    color: .bwTheta
                )
                settingsToggle(
                    title: "Notifications",
                    binding: $sessionNotifications,
                    icon: "bell.circle",
                    color: .bwAlpha
                )
                settingsToggle(
                    title: "Breathing Guidance",
                    binding: $breathingGuidanceEnabled,
                    icon: "wind.circle",
                    color: .bwDelta
                )
            }
        }
    }

    // MARK: - Session Defaults

    var sessionDefaultsSection: some View {
        GlassCard(label: "Session Defaults") {
            VStack(spacing: TranceSpacing.list) {
                settingsSlider(
                    title: "Default Intensity",
                    value: $defaultIntensity,
                    range: 0.1...1.0,
                    format: { String(format: "%.0f%%", $0 * 100) },
                    color: .bwBeta
                )
                settingsSlider(
                    title: "Preferred Duration",
                    value: $preferredSessionDuration,
                    range: 5...60,
                    format: { String(format: "%.0f min", $0) },
                    color: .bwDelta
                )
                settingsSlider(
                    title: "Frequency Scale",
                    value: $userFrequencyMultiplier,
                    range: 0.5...2.0,
                    format: { String(format: "%.1f×", $0) },
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
                        Text("1s").tag(1)
                        Text("3s").tag(3)
                        Text("10s").tag(10)
                    }
                    .tint(.textSecondary)
                }
                settingsToggle(
                    title: "Bilateral Mode Default",
                    binding: $bilateralModeDefault,
                    icon: "brain.head.profile",
                    color: .bwGamma
                )
            }
        }
    }

    // MARK: - Audio & Display

    var audioDisplaySection: some View {
        GlassCard(label: "Audio & Display") {
            VStack(spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.list) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.bwGamma)
                        .frame(width: 24)
                    Text("Audio Quality")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Picker("Audio Quality", selection: audioQualityMode) {
                        ForEach(AudioQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    .tint(.textSecondary)
                }
                settingsSlider(
                    title: "Display Brightness",
                    value: $displayBrightness,
                    range: 0.1...1.0,
                    format: { String(format: "%.0f%%", $0 * 100) },
                    color: .bwTheta
                )
                settingsToggle(
                    title: "Keep Screen On",
                    binding: $keepScreenOn,
                    icon: "sun.max.circle",
                    color: .bwAlpha
                )
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
                settingsToggle(
                    title: "Anonymous Analytics",
                    binding: $analyticsEnabled,
                    icon: "chart.bar",
                    color: .textSecondary
                )
                settingsButton(title: "Export Session Data", icon: "square.and.arrow.up.circle") {
                    TranceHaptics.shared.light()
                    exportSessionData()
                }
                settingsButton(title: "Privacy Policy", icon: "hand.raised.circle") {
                    TranceHaptics.shared.light()
                    if let url = URL(string: "https://www.apple.com/legal/privacy/") {
                        UIApplication.shared.open(url)
                    }
                }
                settingsButton(title: "Clear All Data", icon: "trash.circle", color: .roseDeep) {
                    TranceHaptics.shared.heavy()
                    showClearDataAlert = true
                }
            }
        }
    }

    // MARK: - Support & About

    var supportAboutSection: some View {
        GlassCard(label: "Support") {
            VStack(spacing: TranceSpacing.list) {
                settingsButton(title: "Help & Support", icon: "questionmark.circle") {
                    TranceHaptics.shared.light()
                    if let url = URL(string: "mailto:support@ilumionate.app") {
                        UIApplication.shared.open(url)
                    }
                }
                settingsButton(title: "Rate on App Store", icon: "star.circle") {
                    TranceHaptics.shared.light()
                    if let url = URL(string: "https://apps.apple.com") {
                        UIApplication.shared.open(url)
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
                    print("Haptics: \(hapticFeedbackEnabled) | Lock: \(autoLockEnabled)")
                    print("Intensity: \(defaultIntensity) | Duration: \(preferredSessionDuration)")
                    print("Freq Scale: \(userFrequencyMultiplier) | History: \(listeningHistoryEnabled)")
                    print("Quality: \(audioQualityRaw) | Brightness: \(displayBrightness)")
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
}
